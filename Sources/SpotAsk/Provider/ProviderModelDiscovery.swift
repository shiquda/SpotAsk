import Foundation

enum ModelRefreshStatus: Equatable, Sendable {
    case idle
    case loading
    case success(Int)
    case missingAccessKey
    case cancelled
    case failed
    case unavailable
}

enum ProviderModelDiscoveryError: Error, Equatable, Sendable {
    case unavailableForFullEndpoint
    case missingAPIKey
    case invalidResponse
    case unsuccessfulStatus(Int)
    case cancelled
    case networkUnavailable
    case timeout
}

protocol ProviderModelDiscovering: Sendable {
    func models(for provider: ProviderConfiguration, apiKey: String) async throws -> [String]
}

protocol ProviderModelDiscoveryTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionProviderModelDiscoveryTransport: ProviderModelDiscoveryTransport {
    let urlSession: URLSession

    init(urlSession: URLSession = ChatNetworking.urlSession()) {
        self.urlSession = urlSession
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await urlSession.data(for: request)
    }
}

struct OpenAICompatibleModelDiscovery: ProviderModelDiscovering {
    private struct Response: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private let transport: any ProviderModelDiscoveryTransport

    init(transport: any ProviderModelDiscoveryTransport = URLSessionProviderModelDiscoveryTransport()) {
        self.transport = transport
    }

    func models(for provider: ProviderConfiguration, apiKey: String) async throws -> [String] {
        guard provider.addressMode == .baseURL else {
            throw ProviderModelDiscoveryError.unavailableForFullEndpoint
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ProviderModelDiscoveryError.missingAPIKey }

        var request = URLRequest(url: try URLNormalizer.modelsEndpoint(from: provider.address))
        request.httpMethod = "GET"
        request.timeoutInterval = provider.timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (responseData, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderModelDiscoveryError.invalidResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw ProviderModelDiscoveryError.unsuccessfulStatus(httpResponse.statusCode)
            }
            let decoded = try JSONDecoder().decode(Response.self, from: responseData)
            return Set(
                decoded.data
                    .map(\.id)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            ).sorted()
        } catch is CancellationError {
            throw ProviderModelDiscoveryError.cancelled
        } catch let error as ProviderModelDiscoveryError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw ProviderModelDiscoveryError.cancelled
            case .timedOut: throw ProviderModelDiscoveryError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                throw ProviderModelDiscoveryError.networkUnavailable
            default: throw ProviderModelDiscoveryError.invalidResponse
            }
        } catch {
            throw ProviderModelDiscoveryError.invalidResponse
        }
    }
}
