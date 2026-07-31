import Foundation

protocol APIKeyStoring: Sendable {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

/// Stores an API key in a current-user file when a stable Keychain signing identity is unavailable.
final class LocalAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private struct Credentials: Codable {
        let apiKey: String
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cachedKey: String??

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func readAPIKey() throws -> String? {
        lock.lock()
        if let cachedKey {
            lock.unlock()
            return cachedKey
        }
        lock.unlock()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            cache(nil)
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        cache(credentials.apiKey)
        return credentials.apiKey
    }

    func saveAPIKey(_ key: String) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let data = try JSONEncoder().encode(Credentials(apiKey: key))
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        cache(key)
    }

    func deleteAPIKey() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        cache(nil)
    }

    private func cache(_ key: String?) {
        lock.lock()
        cachedKey = key
        lock.unlock()
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupportURL
            .appendingPathComponent("SpotAsk", isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
    }
}
