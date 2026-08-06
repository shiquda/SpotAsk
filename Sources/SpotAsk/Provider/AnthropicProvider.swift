import Foundation

/// Official Anthropic Messages API provider.
struct AnthropicProvider: ChatProvider {
    struct Configuration: Sendable {
        let endpoint: URL
        let apiKey: String
        let model: String
        let timeout: TimeInterval
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
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try makeURLRequest(for: request, stream: true)
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, httpResponse) = try await transport.streamingResponse(for: urlRequest)
                    if !(httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") ?? false) {
                        let data = try await ChatHTTP.collect(bytes)
                        let completion = try JSONDecoder().decode(AnthropicNonStreamingResponse.self, from: data)
                        for event in completion.events { continuation.yield(event) }
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }
                    var parser = AnthropicSSEParser()
                    var receivedCompletion = false
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for payload in try parser.feed(Data([byte])) {
                            for event in try makeStreamEvents(from: payload) {
                                if case .completed = event { receivedCompletion = true }
                                continuation.yield(event)
                            }
                        }
                    }
                    for payload in try parser.finish() {
                        for event in try makeStreamEvents(from: payload) {
                            if case .completed = event { receivedCompletion = true }
                            continuation.yield(event)
                        }
                    }
                    if !receivedCompletion { continuation.yield(.completed) }
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
        let conversation = request.messages
            .filter { $0.role != .system }
            .map { AnthropicRequest.Message(role: $0.role.rawValue, content: $0.content) }
        urlRequest.httpBody = try JSONEncoder().encode(
            AnthropicRequest(
                model: request.model,
                maxTokens: Self.maxTokens,
                system: system.isEmpty ? nil : system,
                messages: conversation,
                stream: stream
            )
        )
        return urlRequest
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

private struct AnthropicRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
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

private struct AnthropicSSEParser: Sendable {
    private var pendingBytes = Data()

    mutating func feed(_ bytes: Data) throws -> [String] {
        pendingBytes.append(bytes)
        var payloads: [String] = []
        while let newline = pendingBytes.firstIndex(of: 0x0A) {
            var lineData = pendingBytes.prefix(upTo: newline)
            pendingBytes.removeSubrange(...newline)
            if lineData.last == 0x0D { lineData.removeLast() }
            guard !lineData.isEmpty else { continue }
            guard let line = String(data: lineData, encoding: .utf8) else { throw ChatError.decodingFailed }
            if line.hasPrefix(":") { continue }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if !payload.isEmpty { payloads.append(String(payload)) }
        }
        return payloads
    }

    mutating func finish() throws -> [String] {
        guard !pendingBytes.isEmpty else { return [] }
        pendingBytes.append(0x0A)
        return try feed(Data())
    }
}
