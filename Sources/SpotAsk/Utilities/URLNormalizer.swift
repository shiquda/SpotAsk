import Foundation

struct URLNormalizer {
    static func endpoint(from rawValue: String, useFullEndpoint: Bool) throws -> URL {
        var components = try validatedComponents(from: rawValue)
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

    static func modelsEndpoint(from rawValue: String) throws -> URL {
        var components = try validatedComponents(from: rawValue)

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
