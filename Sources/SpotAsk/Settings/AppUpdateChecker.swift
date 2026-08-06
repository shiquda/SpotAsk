import Foundation
import Observation

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

struct AvailableAppUpdate: Equatable, Sendable {
    let version: AppVersion
}

protocol AppUpdateChecking: Sendable {
    func check(for currentVersion: AppVersion) async throws -> AvailableAppUpdate?
}

struct AppUpdateChecker: AppUpdateChecking {
    static let sourceURL = URL(string: "https://github.com/shiquda/SpotAsk")!
    static let releasesURL = URL(string: "https://api.github.com/repos/shiquda/SpotAsk/releases/latest")!
    static let downloadURL = URL(string: "https://github.com/shiquda/SpotAsk/releases/latest")!

    private let session: URLSession

    init(session: URLSession = ChatNetworking.urlSession()) {
        self.session = session
    }

    func check(for currentVersion: AppVersion) async throws -> AvailableAppUpdate? {
        let (data, response) = try await session.data(from: Self.releasesURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateCheckError.invalidResponse
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        return Self.update(forReleaseTag: release.tagName, currentVersion: currentVersion)
    }

    static func update(forReleaseTag releaseTag: String, currentVersion: AppVersion) -> AvailableAppUpdate? {
        guard let releaseVersion = AppVersion(string: releaseTag), currentVersion < releaseVersion else {
            return nil
        }
        return AvailableAppUpdate(version: releaseVersion)
    }

    private struct Release: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    private enum UpdateCheckError: Error {
        case invalidResponse
    }
}

@MainActor
@Observable
final class AppUpdateState {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(AvailableAppUpdate)
        case unavailable
    }

    private let currentVersion: AppVersion
    private let checker: any AppUpdateChecking

    var status: Status = .idle

    init(
        currentVersion: AppVersion = .current,
        checker: any AppUpdateChecking = AppUpdateChecker()
    ) {
        self.currentVersion = currentVersion
        self.checker = checker
    }

    var isChecking: Bool {
        status == .checking
    }

    func checkForUpdate() {
        guard !isChecking else { return }
        status = .checking

        Task {
            do {
                status = try await checker.check(for: currentVersion)
                    .map(Status.updateAvailable) ?? .upToDate
            } catch {
                status = .unavailable
            }
        }
    }
}
