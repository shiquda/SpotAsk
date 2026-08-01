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

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        guard request.stream else { return nonStreaming(request: request) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await urlSession.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
                    guard (200 ... 299).contains(httpResponse.statusCode) else {
                        throw try await error(from: httpResponse, bytes: bytes)
                    }
                    if !(httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") ?? false) {
                        let data = try await collect(bytes)
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
                    continuation.finish(throwing: mapURLError(error))
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
        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response: response, data: data)
    }

    private func nonStreaming(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await urlSession.data(for: urlRequest)
                    try validate(response: response, data: data)
                    let completion = try JSONDecoder().decode(NonStreamingResponse.self, from: data)
                    for event in completion.events { continuation.yield(event) }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatError.cancelled)
                } catch let error as ChatError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: mapURLError(error))
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

    private func validate(response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        switch http.statusCode {
        case 200 ... 299: return
        case 401, 403: throw ChatError.unauthorized
        case 429: throw ChatError.rateLimited
        default: throw ChatError.serverError(status: http.statusCode, message: apiMessage(from: data))
        }
    }

    private func error(from response: HTTPURLResponse, bytes: URLSession.AsyncBytes) async throws -> ChatError {
        let data = try await collect(bytes)
        switch response.statusCode {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .serverError(status: response.statusCode, message: apiMessage(from: data))
        }
    }

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if data.count < 65_536 { data.append(byte) }
        }
        return data
    }

    private func apiMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error?.message
    }

    private func mapURLError(_ error: URLError) -> ChatError {
        switch error.code {
        case .timedOut: .timeout
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost: .networkUnavailable
        default: .invalidResponse
        }
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
