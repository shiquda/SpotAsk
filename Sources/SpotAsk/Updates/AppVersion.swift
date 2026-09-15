import Foundation

struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmed.first == "v" || trimmed.first == "V" ? String(trimmed.dropFirst()) : trimmed
        let components = version.split(separator: ".", omittingEmptySubsequences: false)

        guard !components.isEmpty else { return nil }

        let parsedComponents = components.compactMap { Int($0) }
        guard parsedComponents.count == components.count else { return nil }

        let normalizedComponents = parsedComponents.reversed().drop { $0 == 0 }.reversed()
        self.components = normalizedComponents.isEmpty ? [0] : Array(normalizedComponents)
    }

    static var current: AppVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return AppVersion(string: version ?? "") ?? AppVersion(string: "0")!
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let lhsComponent = index < lhs.components.count ? lhs.components[index] : 0
            let rhsComponent = index < rhs.components.count ? rhs.components[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }
        return false
    }
}

enum UpdateFeed {
    static let sourceURL = URL(string: "https://github.com/shiquda/SpotAsk")!
    static let githubReleasesURL = URL(string: "https://github.com/shiquda/SpotAsk/releases/latest")!
    static let defaultMirrorPrefix = "https://ghproxy.net/"

    static func officialAppcastURL(architecture: String = currentArchitecture) -> URL {
        URL(string: "https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-\(architecture).xml")!
    }

    static func acceleratedAppcastURL(
        architecture: String = currentArchitecture,
        mirrorPrefix: String = defaultMirrorPrefix
    ) -> URL {
        let official = officialAppcastURL(architecture: architecture).absoluteString
        return URL(string: mirrorPrefix + official) ?? officialAppcastURL(architecture: architecture)
    }

    static func appcastURL(architecture: String = currentArchitecture) -> URL {
        officialAppcastURL(architecture: architecture)
    }

    static func appcastURL(
        for source: UpdateDownloadSource,
        architecture: String = currentArchitecture,
        mirrorPrefix: String = defaultMirrorPrefix
    ) -> URL {
        switch source {
        case .official:
            return officialAppcastURL(architecture: architecture)
        case .accelerated:
            return acceleratedAppcastURL(architecture: architecture, mirrorPrefix: mirrorPrefix)
        case .automatic:
            return officialAppcastURL(architecture: architecture)
        }
    }

    static func acceleratedEnclosureURL(
        for url: URL,
        mirrorPrefix: String = defaultMirrorPrefix
    ) -> URL {
        let urlString = url.absoluteString
        if urlString.hasPrefix(mirrorPrefix) {
            return url
        }
        if urlString.hasPrefix("https://github.com/") || urlString.hasPrefix("http://github.com/") {
            return URL(string: mirrorPrefix + urlString) ?? url
        }
        return url
    }

    static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
