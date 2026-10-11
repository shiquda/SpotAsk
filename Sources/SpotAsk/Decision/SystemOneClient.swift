import Foundation

protocol SystemOneTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionSystemOneTransport: SystemOneTransport {
    var session: URLSession

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SystemOneClientError.invalidResponse
        }
        return (data, http)
    }
}

/// One evaluation request. The caller owns the deadline; this client does not retry.
struct SystemOneClient: Sendable {
    var transport: any SystemOneTransport
    var sleep: @Sendable (Duration) async throws -> Void

    func evaluate(
        question: String,
        model: String,
        criteria: [String: String],
        url: URL,
        apiKey: String?,
        timeout: TimeInterval
    ) async throws -> SystemOneChoiceAnswer {
        let body = try SystemOneRequestBuilder.body(model: model, state: question, criteria: criteria)
        let request = SystemOneRequestBuilder.request(
            url: url,
            apiKey: apiKey,
            timeout: timeout,
            body: body
        )
        let allowed = Set(criteria.keys)
        return try await withThrowingTaskGroup(of: SystemOneChoiceAnswer.self) { group in
            group.addTask {
                let (data, http) = try await transport.data(for: request)
                guard (200...299).contains(http.statusCode) else {
                    throw SystemOneClientError.httpStatus(http.statusCode)
                }
                return try SystemOneResponseParser.parse(data, allowedChoices: allowed)
            }
            group.addTask {
                try await sleep(.milliseconds(max(1, Int(timeout * 1000))))
                throw SystemOneClientError.timedOut
            }
            do {
                guard let first = try await group.next() else {
                    group.cancelAll()
                    throw SystemOneClientError.timedOut
                }
                group.cancelAll()
                return first
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    static func isTimeout(_ error: Error) -> Bool {
        if let clientError = error as? SystemOneClientError, clientError == .timedOut {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return true
        }
        return false
    }
}
