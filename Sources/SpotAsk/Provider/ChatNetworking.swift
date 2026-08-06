import Foundation

enum ChatNetworking {
    static func urlSession(proxyConfiguration: [String: Any]? = nil) -> URLSession {
        guard let proxyConfiguration else { return .shared }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = proxyConfiguration
        return URLSession(configuration: configuration)
    }
}

enum ChatHTTP {
    static let maxErrorBodyBytes = 65_536

    static func collect(_ bytes: URLSession.AsyncBytes, limit: Int = maxErrorBodyBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if data.count < limit { data.append(byte) }
        }
        return data
    }

    static func chatError(statusCode: Int, data: Data) -> ChatError {
        let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error?.message
        switch statusCode {
        case 401, 403: return .unauthorized(message: message)
        case 429: return .rateLimited(message: message)
        default: return .serverError(status: statusCode, message: message)
        }
    }

    static func mapURLError(_ error: URLError) -> ChatError {
        switch error.code {
        case .timedOut: .timeout
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost: .networkUnavailable
        default: .invalidResponse
        }
    }
}

struct HTTPChatTransport: Sendable {
    let urlSession: URLSession

    func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await urlSession.data(for: request)
            try validate(response: response, data: data)
            return data
        } catch is CancellationError {
            throw ChatError.cancelled
        } catch let error as ChatError {
            throw error
        } catch let error as URLError {
            throw ChatHTTP.mapURLError(error)
        }
    }

    func streamingResponse(for request: URLRequest) async throws -> (bytes: URLSession.AsyncBytes, httpResponse: HTTPURLResponse) {
        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let data = try await ChatHTTP.collect(bytes)
                throw ChatHTTP.chatError(statusCode: httpResponse.statusCode, data: data)
            }
            return (bytes, httpResponse)
        } catch is CancellationError {
            throw ChatError.cancelled
        } catch let error as ChatError {
            throw error
        } catch let error as URLError {
            throw ChatHTTP.mapURLError(error)
        }
    }

    private func validate(response: URLResponse, data: Data = Data()) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw ChatHTTP.chatError(statusCode: httpResponse.statusCode, data: data)
        }
    }
}
