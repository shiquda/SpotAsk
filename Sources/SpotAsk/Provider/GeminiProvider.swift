import Foundation

/// Official Google Gemini API provider (`generateContent` /
/// `streamGenerateContent`).
struct GeminiProvider: ChatProvider {
    struct Configuration: Sendable {
        /// The model collection root, e.g.
        /// `https://generativelanguage.googleapis.com/v1beta/models`.
        let endpoint: URL
        let apiKey: String
        let model: String
        let timeout: TimeInterval
        let compatibilityProfile: RequestCompatibilityProfile
        let thinkingMode: ModelThinkingMode
        let extraRequestParameters: [String: ModelJSONValue]?

        init(
            endpoint: URL,
            apiKey: String,
            model: String,
            timeout: TimeInterval,
            compatibilityProfile: RequestCompatibilityProfile = .gemini,
            thinkingMode: ModelThinkingMode = .providerDefault,
            extraRequestParameters: [String: ModelJSONValue]? = nil
        ) {
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.model = model
            self.timeout = timeout
            self.compatibilityProfile = compatibilityProfile
            self.thinkingMode = thinkingMode
            self.extraRequestParameters = extraRequestParameters
        }
    }

    let configuration: Configuration
    let urlSession: URLSession

    private var transport: HTTPChatTransport {
        HTTPChatTransport(urlSession: urlSession)
    }

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        guard request.stream else { return nonStreaming(request: request) }
        return ChatStreamingDriver.stream(
            transport: transport,
            makeRequest: {
                var urlRequest = try makeURLRequest(for: request, stream: true)
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                return urlRequest
            },
            decodeNonStreaming: { data in
                try Self.events(
                    from: JSONDecoder().decode(GeminiResponse.self, from: data),
                    includeCompletion: false
                )
            },
            decodePayload: { payload in
                try Self.events(
                    from: JSONDecoder().decode(GeminiResponse.self, from: Data(payload.utf8)),
                    includeCompletion: true
                )
            },
            mapUnexpectedError: { _ in ChatError.decodingFailed }
        )
    }

    func testConnection() async throws {
        let request = ChatRequest(model: configuration.model, messages: [ChatMessage(role: .user, content: "ping")], stream: false)
        try await ChatStreamingDriver.testConnection(transport: transport) {
            try makeURLRequest(for: request, stream: false)
        }
    }

    private func nonStreaming(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        ChatStreamingDriver.nonStreaming(
            transport: transport,
            makeRequest: { try makeURLRequest(for: request, stream: false) },
            decode: { data in
                try Self.events(
                    from: JSONDecoder().decode(GeminiResponse.self, from: data),
                    includeCompletion: false
                )
            }
        )
    }

    private func makeURLRequest(for request: ChatRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(
            url: try Self.actionURL(root: configuration.endpoint, model: request.model, stream: stream)
        )
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try makeRequestBody(for: request)
        return urlRequest
    }

    /// Gemini carries the model and the action in the path, so a request URL is
    /// built from the collection root: `.../models/<model>:generateContent`, or
    /// `.../models/<model>:streamGenerateContent?alt=sse` for a stream.
    static func actionURL(root: URL, model: String, stream: Bool) throws -> URL {
        let identifier = Self.modelIdentifier(from: model)
        guard !identifier.isEmpty,
              var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else {
            throw ChatError.invalidConfiguration
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/" + identifier + (stream ? ":streamGenerateContent" : ":generateContent")
        if stream {
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        }
        guard let url = components.url else { throw ChatError.invalidURL }
        return url
    }

    /// Accepts a model name with or without the `models/` prefix and with an
    /// action suffix, so a value copied from the API or the console works.
    static func modelIdentifier(from model: String) -> String {
        var identifier = model.trimmingCharacters(in: .whitespacesAndNewlines)
        while identifier.hasPrefix("models/") {
            identifier.removeFirst("models/".count)
        }
        if let action = identifier.firstIndex(of: ":") {
            identifier = String(identifier[..<action])
        }
        return identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeRequestBody(for request: ChatRequest) throws -> Data {
        let system = request.messages
            .filter { $0.role == .system }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        var contents: [ModelJSONValue] = []
        for message in request.messages where message.role != .system {
            let parts = Self.parts(for: message)
            // Gemini rejects a content entry without parts, so a message that
            // carries nothing is left out of the conversation.
            guard !parts.isEmpty else { continue }
            contents.append(
                .object([
                    "role": .string(message.role == .assistant ? "model" : "user"),
                    "parts": .array(parts)
                ])
            )
        }

        var body: [String: ModelJSONValue] = ["contents": .array(contents)]
        if !system.isEmpty {
            body["systemInstruction"] = .object([
                "parts": .array([.object(["text": .string(system)])])
            ])
        }
        return try ChatRequestBodyBuilder.buildJSONData(
            body: &body,
            compatibilityProfile: configuration.compatibilityProfile,
            thinkingMode: configuration.thinkingMode,
            extraParameters: configuration.extraRequestParameters
        )
    }

    private static func parts(for message: ChatMessage) -> [ModelJSONValue] {
        var parts: [ModelJSONValue] = []
        for attachment in message.attachments {
            switch attachment.payload {
            case let .image(data):
                parts.append(
                    .object([
                        "inlineData": .object([
                            "mimeType": .string(attachment.mimeType),
                            "data": .string(data.base64EncodedString())
                        ])
                    ])
                )
            case let .text(text, _):
                parts.append(.object(["text": .string("[Attached file: \(attachment.filename)]\n\(text)")]))
            }
        }
        if !message.content.isEmpty {
            parts.append(.object(["text": .string(message.content)]))
        }
        return parts
    }

    /// Text parts arrive as answer text; parts the model marked as `thought`
    /// arrive as reasoning text. `finishReason` closes the stream and
    /// `usageMetadata` reports the running token counts.
    ///
    /// A single response (`generateContent`) closes with the driver's own
    /// `.completed`, so only the streaming decode reports one.
    private static func events(from response: GeminiResponse, includeCompletion: Bool) throws -> [ChatStreamEvent] {
        if let error = response.error {
            throw ChatError.serverError(status: error.code ?? 0, message: error.message)
        }
        let candidate = response.candidates?.first
        if let blockReason = response.promptFeedback?.blockReason, !blockReason.isEmpty, candidate == nil {
            throw ChatError.serverError(status: 0, message: blockReason)
        }

        var events: [ChatStreamEvent] = []
        for part in candidate?.content?.parts ?? [] {
            guard let text = part.text, !text.isEmpty else { continue }
            if part.thought == true {
                events.append(.reasoningDelta(text))
            } else {
                events.append(.answerDelta(text))
            }
        }
        if let usage = response.usageMetadata {
            events.append(
                .usage(.init(inputTokens: usage.promptTokenCount, outputTokens: usage.candidatesTokenCount))
            )
        }
        if includeCompletion,
           let reason = candidate?.finishReason, !reason.isEmpty, reason != "FINISH_REASON_UNSPECIFIED" {
            events.append(.completed)
        }
        return events
    }
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
                let thought: Bool?
            }

            let parts: [Part]?
        }

        let content: Content?
        let finishReason: String?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }

    struct ErrorBody: Decodable {
        let code: Int?
        let message: String?
    }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let usageMetadata: UsageMetadata?
    let error: ErrorBody?
}
