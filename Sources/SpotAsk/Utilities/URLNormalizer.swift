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
        case .gemini:
            return try geminiEndpoint(from: components, useFullEndpoint: useFullEndpoint)
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
        if format == .gemini {
            return try geminiEndpoint(from: components, useFullEndpoint: false)
        }
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

    /// The Gemini API addresses a model inside the request path, so a Gemini
    /// address always resolves to the model collection root; the provider
    /// appends the model and the action (`:generateContent`) to it.
    private static func geminiEndpoint(
        from components: URLComponents,
        useFullEndpoint: Bool
    ) throws -> URL {
        var endpoint = components
        // The access key travels in the `x-goog-api-key` header, so an address
        // never needs to keep a query string.
        endpoint.query = nil
        endpoint.fragment = nil

        var segments = endpoint.path.split(separator: "/").map(String.init)
        if let modelsIndex = segments.firstIndex(of: "models") {
            // A pasted model or action address still resolves to the collection root.
            segments = Array(segments.prefix(modelsIndex + 1))
        } else if segments == ["v1beta"] {
            segments = []
        } else if useFullEndpoint {
            throw ChatError.invalidURL
        }
        if segments.last != "models" {
            segments.append(contentsOf: ["v1beta", "models"])
        }
        endpoint.path = "/" + segments.joined(separator: "/")

        guard let url = endpoint.url else { throw ChatError.invalidURL }
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
