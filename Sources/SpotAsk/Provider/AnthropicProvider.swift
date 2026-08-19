import Foundation

/// Official Anthropic Messages API provider.
struct AnthropicProvider: ChatProvider {
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
            compatibilityProfile: RequestCompatibilityProfile = .anthropic,
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

    private static let apiVersion = "2023-06-01"
    private static let maxTokens = 8_192

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
                try JSONDecoder().decode(AnthropicNonStreamingResponse.self, from: data).events
            },
            decodePayload: makeStreamEvents,
            mapUnexpectedError: { _ in ChatError.decodingFailed }
        )
    }

    func testConnection() async throws {
        let request = ChatRequest(model: configuration.model, messages: [ChatMessage(role: .user, content: "ping")], stream: false)
        let urlRequest = try makeURLRequest(for: request, stream: false)
        _ = try await transport.data(for: urlRequest)
    }

    private func nonStreaming(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(for: request, stream: false)
                    let data = try await transport.data(for: urlRequest)
                    let completion = try JSONDecoder().decode(AnthropicNonStreamingResponse.self, from: data)
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

    private func makeURLRequest(for request: ChatRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let system = request.messages
            .filter { $0.role == .system }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        urlRequest.httpBody = try makeRequestBody(
            for: request,
            system: system,
            stream: stream
        )
        return urlRequest
    }

    private func makeRequestBody(for request: ChatRequest, system: String, stream: Bool) throws -> Data {
        let conversation = try request.messages
            .filter { $0.role != .system }
            .map { message in
                try ModelJSONValue.object([
                    "role": .string(message.role.rawValue),
                    "content": .wrapping(Self.anthropicContent(for: message))
                ])
            }
        var body: [String: ModelJSONValue] = [
            "model": .string(request.model),
            "max_tokens": .number(Double(Self.maxTokens)),
            "messages": .array(conversation),
            "stream": .bool(stream)
        ]
        if !system.isEmpty {
            body["system"] = .string(system)
        }
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

    /// Text-only messages keep the historical `content: "string"` shape. Only
    /// messages with attachments become an array of content blocks.
    private static func anthropicContent(for message: ChatMessage) -> AnthropicMessageContent {
        guard !message.attachments.isEmpty else { return .text(message.content) }
        var blocks: [AnthropicContentBlock] = []
        for attachment in message.attachments {
            switch attachment.payload {
            case let .image(data):
                blocks.append(
                    AnthropicContentBlock(
                        type: "image",
                        text: nil,
                        source: AnthropicImageSource(
                            type: "base64",
                            mediaType: attachment.mimeType,
                            data: data.base64EncodedString()
                        )
                    )
                )
            case let .text(text, _):
                blocks.append(
                    AnthropicContentBlock(
                        type: "text",
                        text: "<attachment name=\"\(attachment.filename)\">\n\(text)\n</attachment>",
                        source: nil
                    )
                )
            }
        }
        if !message.content.isEmpty {
            blocks.append(AnthropicContentBlock(type: "text", text: message.content, source: nil))
        }
        return .blocks(blocks)
    }

    private func makeStreamEvents(from payload: String) throws -> [ChatStreamEvent] {
        guard let data = payload.data(using: .utf8) else { throw ChatError.decodingFailed }
        if payload == "[DONE]" { return [.completed] }
        let response: AnthropicStreamPayload
        do {
            response = try JSONDecoder().decode(AnthropicStreamPayload.self, from: data)
        } catch {
            throw ChatError.decodingFailed
        }
        if let error = response.error {
            throw ChatError.serverError(status: 0, message: error.message)
        }
        var events: [ChatStreamEvent] = []
        if let block = response.contentBlock {
            if block.type == "thinking", let thinking = block.thinking, !thinking.isEmpty {
                events.append(.reasoningDelta(thinking))
            }
            if block.type == "text", let text = block.text, !text.isEmpty {
                events.append(.answerDelta(text))
            }
        }
        if let delta = response.delta {
            if let reasoning = delta.thinking, !reasoning.isEmpty {
                events.append(.reasoningDelta(reasoning))
            }
            if let text = delta.text, !text.isEmpty {
                events.append(.answerDelta(text))
            }
        }
        if let usage = response.usage {
            events.append(.usage(.init(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens)))
        }
        if response.type == "message_stop" {
            events.append(.completed)
        }
        return events
    }
}

/// Single-value encoding preserves the plain-string content for text-only
/// requests; multimodal messages use an explicit block array.
private enum AnthropicMessageContent: Encodable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text): try container.encode(text)
        case let .blocks(blocks): try container.encode(blocks)
        }
    }
}

private struct AnthropicContentBlock: Encodable {
    let type: String
    let text: String?
    let source: AnthropicImageSource?
}

private struct AnthropicImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct AnthropicStreamPayload: Decodable {
    struct Delta: Decodable {
        let text: String?
        let thinking: String?
    }
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
        let thinking: String?
    }
    struct Error: Decodable {
        let message: String?
    }
    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    let type: String
    let contentBlock: ContentBlock?
    let delta: Delta?
    let error: Error?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case type
        case contentBlock = "content_block"
        case delta
        case error
        case usage
    }
}

private struct AnthropicNonStreamingResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
        let thinking: String?
    }

    let content: [ContentBlock]

    var events: [ChatStreamEvent] {
        content.compactMap { block -> ChatStreamEvent? in
            if block.type == "thinking", let thinking = block.thinking, !thinking.isEmpty {
                return .reasoningDelta(thinking)
            }
            if block.type == "text", let text = block.text, !text.isEmpty {
                return .answerDelta(text)
            }
            return nil
        }
    }
}

