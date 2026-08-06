import Foundation

struct URLNormalizer {
    static func endpoint(
        from rawValue: String,
        useFullEndpoint: Bool,
        format: ProviderFormat = .openAICompatible
    ) throws -> URL {
        var components = try validatedComponents(from: rawValue)
        switch format {
        case .anthropic:
            return try anthropicEndpoint(from: components, useFullEndpoint: useFullEndpoint)
        case .openAICompatible:
            break
        }
        let endpointPath = "/chat/completions"
        let currentPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if useFullEndpoint {
            guard currentPath.hasSuffix(endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { throw ChatError.invalidURL }
        } else if !currentPath.hasSuffix(endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
            components.path = currentPath.isEmpty ? endpointPath : "/" + currentPath + endpointPath
        }
        guard let url = components.url else { throw ChatError.invalidURL }
        return url
    }

    static func modelsEndpoint(
        from rawValue: String,
        format: ProviderFormat = .openAICompatible
    ) throws -> URL {
        var components = try validatedComponents(from: rawValue)
        if format == .anthropic {
            var currentPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if currentPath.hasSuffix("messages") {
                currentPath = String(currentPath.dropLast("messages".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if currentPath == "v1" || currentPath.isEmpty {
                components.path = "/v1/models"
            } else {
                components.path = "/" + currentPath + "/v1/models"
            }
            guard let url = components.url else { throw ChatError.invalidURL }
            return url
        }

        let chatPath = "chat/completions"
        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(chatPath) {
            path.removeLast(chatPath.count)
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        components.path = path.isEmpty ? "/models" : "/" + path + "/models"
        guard let url = components.url else { throw ChatError.invalidURL }
        return url
    }

    private static func anthropicEndpoint(
        from components: URLComponents,
        useFullEndpoint: Bool
    ) throws -> URL {
        guard useFullEndpoint else {
            var endpoint = components
            let currentPath = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if currentPath == "v1" || currentPath.isEmpty {
                endpoint.path = "/v1/messages"
            } else if currentPath.hasSuffix("messages") {
                endpoint.path = "/" + currentPath
            } else {
                endpoint.path = "/" + currentPath + "/v1/messages"
            }
            guard let url = endpoint.url else { throw ChatError.invalidURL }
            return url
        }
        guard let url = components.url else { throw ChatError.invalidURL }
        return url
    }

    private static func validatedComponents(from rawValue: String) throws -> URLComponents {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let components = URLComponents(string: cleaned),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty
        else {
            throw ChatError.invalidURL
        }
        let localHosts = ["localhost", "127.0.0.1", "::1"]
        if scheme == "http", let host = components.host?.lowercased(), !localHosts.contains(host) {
            throw ChatError.invalidURL
        }
        return components
    }
}
