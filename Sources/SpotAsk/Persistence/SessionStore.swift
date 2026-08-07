import Foundation

struct SessionStore {
    private let fileManager: FileManager
    private let bundleIdentifier: String

    init(fileManager: FileManager = .default, bundleIdentifier: String = "com.spotask.app") {
        self.fileManager = fileManager
        self.bundleIdentifier = bundleIdentifier
    }

    func save(_ messages: [ChatMessage]) throws {
        let directory = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Attachments are intentionally not persisted: the session file stays
        // small and a restart starts without binary context.
        let stripped = messages.map { message in
            var copy = message
            copy.attachments = []
            return copy
        }
        try JSONEncoder().encode(stripped).write(to: directory.appendingPathComponent("current-session.json"), options: .atomic)
    }

    func load() throws -> [ChatMessage] {
        let url = try applicationSupportDirectory().appendingPathComponent("current-session.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ChatMessage].self, from: Data(contentsOf: url))
    }

    func clear() throws {
        try? fileManager.removeItem(at: try applicationSupportDirectory().appendingPathComponent("current-session.json"))
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw ChatError.invalidConfiguration }
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }
}
