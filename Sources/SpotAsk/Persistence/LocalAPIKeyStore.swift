import Foundation

protocol APIKeyStoring: Sendable {
    func readAPIKey(for providerID: UUID) throws -> String?
    func saveAPIKey(_ key: String, for providerID: UUID) throws
    func deleteAPIKey(for providerID: UUID) throws
    func deleteAllAPIKeys() throws
}

protocol LegacyAPIKeyMigrating: APIKeyStoring {
    func migrateLegacyAPIKey(to providerID: UUID) throws
}

/// Reserved credential slot for the global proxy password. Reuses the same
/// local credential store so the password never lands in plain preference data.
enum ProxyCredentialSlot {
    static let providerID = UUID(uuidString: "A1B2C3D4-0000-4000-8000-00000000A10B")!
}

/// Stores API keys in Application Support while a stable Keychain signing
/// identity is unavailable. Each Provider receives an independent key slot.
final class LocalAPIKeyStore: LegacyAPIKeyMigrating, @unchecked Sendable {
    private struct Credentials: Codable {
        var apiKeys: [String: String]
        var legacyAPIKey: String?

        init(apiKeys: [String: String] = [:], legacyAPIKey: String? = nil) {
            self.apiKeys = apiKeys
            self.legacyAPIKey = legacyAPIKey
        }

        private enum CodingKeys: String, CodingKey {
            case apiKeys
            case apiKey
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            apiKeys = try container.decodeIfPresent([String: String].self, forKey: .apiKeys) ?? [:]
            legacyAPIKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(apiKeys, forKey: .apiKeys)
            try container.encodeIfPresent(legacyAPIKey, forKey: .apiKey)
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(
            fileManager: fileManager,
            bundleIdentifier: bundleIdentifier
        )
    }

    func readAPIKey(for providerID: UUID) throws -> String? {
        try withCredentials { $0.apiKeys[providerID.uuidString] }
    }

    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        try mutateCredentials { $0.apiKeys[providerID.uuidString] = key }
    }

    func deleteAPIKey(for providerID: UUID) throws {
        try mutateCredentials { $0.apiKeys.removeValue(forKey: providerID.uuidString) }
    }

    func deleteAllAPIKeys() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    /// Moves the pre-catalog single credential into the migrated Provider once.
    func migrateLegacyAPIKey(to providerID: UUID) throws {
        try mutateCredentials { credentials in
            guard let legacy = credentials.legacyAPIKey else { return }
            if credentials.apiKeys[providerID.uuidString] == nil {
                credentials.apiKeys[providerID.uuidString] = legacy
            }
            credentials.legacyAPIKey = nil
        }
    }

    private func withCredentials<T>(_ body: (Credentials) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(try loadCredentials())
    }

    private func mutateCredentials(_ mutation: (inout Credentials) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var credentials = try loadCredentials()
        try mutation(&credentials)
        try save(credentials)
    }

    private func loadCredentials() throws -> Credentials {
        guard fileManager.fileExists(atPath: fileURL.path) else { return Credentials() }
        return try JSONDecoder().decode(Credentials.self, from: Data(contentsOf: fileURL))
    }

    private func save(_ credentials: Credentials) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(credentials).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func defaultFileURL(fileManager: FileManager, bundleIdentifier: String?) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryName = bundleIdentifier == "com.spotask.app.debug"
            ? "com.spotask.app.debug"
            : "SpotAsk"
        return applicationSupportURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
    }
}
