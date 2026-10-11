import Foundation

protocol SystemOneTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Scoped to one evaluation: reject before URLSession sends the redirected body.
private final class SystemOneRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL?
    private let lock = NSLock()
    private var rejected = false

    init(url: URL?) {
        origin = url
    }

    var rejectedRedirect: Bool {
        lock.withLock { rejected }
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func effectivePort(_ url: URL) -> Int? {
            url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let origin, let destination = request.url,
              Self.sameOrigin(origin, destination) else {
            lock.withLock { rejected = true }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct URLSessionSystemOneTransport: SystemOneTransport {
    var session: URLSession

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let delegate = SystemOneRedirectDelegate(url: request.url)
        let (data, response) = try await session.data(for: request, delegate: delegate)
        if delegate.rejectedRedirect {
            throw SystemOneClientError.unsafeRedirect
        }
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
