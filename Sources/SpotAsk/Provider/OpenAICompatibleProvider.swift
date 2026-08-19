import Foundation

struct OpenAICompatibleProvider: ChatProvider {
    struct Configuration: Sendable {
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
            compatibilityProfile: RequestCompatibilityProfile = .genericOpenAI,
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
                var urlRequest = try makeURLRequest(for: request)
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                return urlRequest
            },
            decodeNonStreaming: { data in
                try JSONDecoder().decode(NonStreamingResponse.self, from: data).events
            },
            decodePayload: SSEParser.parsePayload,
            mapUnexpectedError: { $0 }
        )
    }

    func testConnection() async throws {
        let request = ChatRequest(model: configuration.model, messages: [ChatMessage(role: .user, content: "ping")], stream: false)
        let urlRequest = try makeURLRequest(for: request)
        _ = try await transport.data(for: urlRequest)
    }

    private func nonStreaming(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                    let data = try await transport.data(for: urlRequest)
                    let completion = try JSONDecoder().decode(NonStreamingResponse.self, from: data)
                    for event in completion.events { continuation.yield(event) }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatError.cancelled)
                } catch let error as ChatError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: ChatHTTP.mapURLError(error))
                } catch {
                    continuation.finish(throwing: ChatError.decodingFailed)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeURLRequest(for request: ChatRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try makeRequestBody(for: request)
        return urlRequest
    }

    private func makeRequestBody(for request: ChatRequest) throws -> Data {
        let messages = try request.messages.map { message in
            try ModelJSONValue.object([
                "role": .string(message.role.rawValue),
                "content": .wrapping(Self.openAIContent(for: message))
            ])
        }
        var body: [String: ModelJSONValue] = [
            "model": .string(request.model),
            "messages": .array(messages),
            "stream": .bool(request.stream)
        ]
        let automatic = configuration.compatibilityProfile.automaticReasoningParameters(for: configuration.thinkingMode)
        let extras = configuration.extraRequestParameters ?? [:]
        if extras.keys.contains(where: { RequestCompatibilityProfile.reasoningControlKeys.contains($0) }) {
            for key in automatic.keys { body.removeValue(forKey: key) }
        } else {
            for (key, value) in automatic {
                body[key] = value
            }
        }
        if extras.keys.contains(where: { RequestCompatibilityProfile.protectedStructuralKeys.contains($0) }) {
            throw ChatError.invalidConfiguration
        }
        body.mergeModelJSON(extras)
        return try JSONEncoder().encode(body)
    }

    /// Text-only requests keep the historical `content: "string"` wire format.
    /// Only messages with attachments switch to the multimodal content array.
    private static func openAIContent(for message: ChatMessage) -> OpenAIMessageContent {
        guard !message.attachments.isEmpty else { return .text(message.content) }
        var parts: [OpenAIContentPart] = []
        for attachment in message.attachments {
            switch attachment.payload {
            case let .image(data):
                parts.append(
                    OpenAIContentPart(
                        type: "image_url",
                        text: nil,
                        imageURL: .init(url: "data:\(attachment.mimeType);base64,\(data.base64EncodedString())")
                    )
                )
            case let .text(text, _):
                parts.append(
                    OpenAIContentPart(
                        type: "text",
                        text: "[Attached file: \(attachment.filename)]\n\(text)",
                        imageURL: nil
                    )
                )
            }
        }
        if !message.content.isEmpty {
            parts.append(OpenAIContentPart(type: "text", text: message.content, imageURL: nil))
        }
        return .parts(parts)
    }
}

/// One user message's content. Encoding a single value keeps text-only requests
/// byte-for-byte compatible with the previous `content: String` schema.
enum OpenAIMessageContent: Encodable {
    case text(String)
    case parts([OpenAIContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text): try container.encode(text)
        case let .parts(parts): try container.encode(parts)
        }
    }
}

struct OpenAIContentPart: Encodable, Equatable {
    let type: String
    let text: String?
    let imageURL: OpenAIImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

struct OpenAIImageURL: Encodable, Equatable {
    let url: String
}

struct NonStreamingResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let message: Message
    }
    let choices: [Choice]

    var events: [ChatStreamEvent] {
        guard let message = choices.first?.message else { return [] }
        var events: [ChatStreamEvent] = []
        if let reasoning = message.reasoningContent, !reasoning.isEmpty { events.append(.reasoningDelta(reasoning)) }
        if let answer = message.content, !answer.isEmpty { events.append(.answerDelta(answer)) }
        return events
    }
}
