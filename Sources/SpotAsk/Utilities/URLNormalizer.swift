import Foundation

struct URLNormalizer {
    static func endpoint(from rawValue: String, useFullEndpoint: Bool) throws -> URL {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: cleaned),
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
        let endpointPath = "/chat/completions"
        let currentPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if useFullEndpoint {
            guard currentPath.hasSuffix(endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { throw ChatError.invalidURL }
        } else if !currentPath.hasSuffix(endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
            components.path = "/" + currentPath + endpointPath
        }
        guard let url = components.url else { throw ChatError.invalidURL }
        return url
    }
}
