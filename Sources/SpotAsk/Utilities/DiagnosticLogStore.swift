import Foundation

struct DiagnosticLogEntry: Codable, Equatable, Sendable {
    let timestamp: Date
    let message: String
}

/// Rolling local diagnostic log. Writes only while diagnostics mode is
/// enabled, keeps the most recent entries, and never stores credentials.
final class DiagnosticLogStore: SelectionDiagnosticsSink, @unchecked Sendable {
    static let shared = DiagnosticLogStore()
    static let maximumEntryCount = 500
    static let maximumContentLength = 8_000

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var entries: [DiagnosticLogEntry]
    private var enabled = false

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.entries = Self.load(from: self.fileURL, fileManager: fileManager)
    }

    func setEnabled(_ isEnabled: Bool) {
        let wasEnabled: Bool
        lock.lock()
        wasEnabled = enabled
        enabled = isEnabled
        lock.unlock()
        if isEnabled, !wasEnabled {
            record("diagnostics-enabled")
        }
    }

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        entries.append(DiagnosticLogEntry(timestamp: .now, message: message))
        if entries.count > Self.maximumEntryCount {
            entries.removeFirst(entries.count - Self.maximumEntryCount)
        }
        try? persist()
    }

    func exportedText() -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        return entries.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }
            .joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        try? persist()
    }

    static func truncated(_ text: String, limit: Int = maximumContentLength) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    private func persist() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func load(from fileURL: URL, fileManager: FileManager) -> [DiagnosticLogEntry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DiagnosticLogEntry].self, from: data) else {
            return []
        }
        return Array(decoded.suffix(maximumEntryCount))
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupportURL
            .appendingPathComponent("SpotAsk", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("diagnostics.json", isDirectory: false)
    }
}
