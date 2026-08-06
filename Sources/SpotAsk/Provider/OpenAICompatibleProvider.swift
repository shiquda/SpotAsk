import Foundation

struct OpenAICompatibleProvider: ChatProvider {
    struct Configuration: Sendable {
        let endpoint: URL
        let apiKey: String
        let model: String
        let timeout: TimeInterval
    }

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
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, httpResponse) = try await transport.streamingResponse(for: urlRequest)
                    if !(httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") ?? false) {
                        let data = try await ChatHTTP.collect(bytes)
                        let completion = try JSONDecoder().decode(NonStreamingResponse.self, from: data)
                        for event in completion.events { continuation.yield(event) }
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }
                    var parser = SSEParser()
                    var receivedCompletion = false
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for event in try parser.feed(Data([byte])) {
                            if case .completed = event { receivedCompletion = true }
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() {
                        if case .completed = event { receivedCompletion = true }
                        continuation.yield(event)
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
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func testConnection() async throws {
        let request = ChatRequest(model: configuration.model, messages: [ChatMessage(role: .user, content: "ping")], stream: false)
        var urlRequest = try makeURLRequest(for: request)
        urlRequest.httpBody = try JSONEncoder().encode(OpenAIRequest(model: configuration.model, messages: [.init(role: "user", content: "ping")], stream: false, maxTokens: 1))
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
        let messages = request.messages.map { OpenAIRequest.Message(role: $0.role.rawValue, content: $0.content) }
        urlRequest.httpBody = try JSONEncoder().encode(OpenAIRequest(model: request.model, messages: messages, stream: request.stream, maxTokens: nil))
        return urlRequest
    }

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

private struct OpenAIRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream: Bool
    let maxTokens: Int?
    enum CodingKeys: String, CodingKey { case model, messages, stream; case maxTokens = "max_tokens" }
}
