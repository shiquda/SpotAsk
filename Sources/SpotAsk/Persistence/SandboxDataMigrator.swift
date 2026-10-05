import Foundation

struct SandboxDataMigrationResult: Equatable, Sendable {
    let didMigrate: Bool
    let migratedPreferencesCount: Int
    let migratedCredentials: Bool
    let migratedSession: Bool
    let migratedDiagnostics: Bool
}

struct SandboxDataMigrator {
    private let fileManager: FileManager
    private let bundleIdentifier: String
    private let containerBaseURL: URL
    private let applicationSupportURL: URL
    private let defaults: UserDefaults

    init(
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.spotask.app",
        containerBaseURL: URL? = nil,
        applicationSupportURL: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.bundleIdentifier = bundleIdentifier

        let homeURL = fileManager.homeDirectoryForCurrentUser
        self.containerBaseURL = containerBaseURL ?? homeURL
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library", isDirectory: true)

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? homeURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.applicationSupportURL = applicationSupportURL ?? appSupport
        self.defaults = defaults
    }

    private var markerFileURL: URL {
        applicationSupportURL
            .appendingPathComponent("SpotAsk", isDirectory: true)
            .appendingPathComponent(".sandbox-migration-completed", isDirectory: false)
    }

    private var migrationHistoryDirectoryURL: URL {
        applicationSupportURL
            .appendingPathComponent("SpotAsk/migration-history", isDirectory: true)
    }

    @discardableResult
    func migrateIfNeeded() -> SandboxDataMigrationResult {
        // Idempotency: check if migration was already performed
        guard !fileManager.fileExists(atPath: markerFileURL.path) else {
            return SandboxDataMigrationResult(
                didMigrate: false,
                migratedPreferencesCount: 0,
                migratedCredentials: false,
                migratedSession: false,
                migratedDiagnostics: false
            )
        }

        // Check if the old sandbox container exists
        guard fileManager.fileExists(atPath: containerBaseURL.path) else {
            return SandboxDataMigrationResult(
                didMigrate: false,
                migratedPreferencesCount: 0,
                migratedCredentials: false,
                migratedSession: false,
                migratedDiagnostics: false
            )
        }

        var migratedPrefsCount = 0
        var migratedCredentials = false
        var migratedSession = false
        var migratedDiagnostics = false

        // 1. Preferences migration: ~/Library/Containers/.../Data/Library/Preferences/<bundleID>.plist
        let containerPrefsURL = containerBaseURL
            .appendingPathComponent("Preferences/\(bundleIdentifier).plist", isDirectory: false)
        if fileManager.fileExists(atPath: containerPrefsURL.path),
           let plistData = try? Data(contentsOf: containerPrefsURL),
           let plistDict = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
            for (key, value) in plistDict {
                // Non-destructive: only migrate keys not already present in defaults
                if defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                    migratedPrefsCount += 1
                }
            }
        }

        // 2. Credentials migration: ~/Library/Containers/.../Data/Library/Application Support/SpotAsk/credentials.json
        let containerCredentialsURL = containerBaseURL
            .appendingPathComponent("Application Support/SpotAsk/credentials.json", isDirectory: false)
        let destSpotAskDir = applicationSupportURL.appendingPathComponent("SpotAsk", isDirectory: true)
        let destCredentialsURL = destSpotAskDir.appendingPathComponent("credentials.json", isDirectory: false)

        if fileManager.fileExists(atPath: containerCredentialsURL.path) {
            try? fileManager.createDirectory(at: destSpotAskDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !fileManager.fileExists(atPath: destCredentialsURL.path) {
                if (try? fileManager.copyItem(at: containerCredentialsURL, to: destCredentialsURL)) != nil {
                    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destCredentialsURL.path)
                    migratedCredentials = true
                }
            }
        }

        // 3. Session migration: ~/Library/Containers/.../Data/Library/Application Support/<bundleID>/current-session.json
        // or ~/Library/Containers/.../Data/Library/Application Support/SpotAsk/current-session.json
        let destSessionDir = applicationSupportURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let destSessionURL = destSessionDir.appendingPathComponent("current-session.json", isDirectory: false)

        let candidateSessionURLs = [
            containerBaseURL.appendingPathComponent("Application Support/\(bundleIdentifier)/current-session.json", isDirectory: false),
            containerBaseURL.appendingPathComponent("Application Support/SpotAsk/current-session.json", isDirectory: false)
        ]

        if !fileManager.fileExists(atPath: destSessionURL.path) {
            for candidateURL in candidateSessionURLs {
                if fileManager.fileExists(atPath: candidateURL.path) {
                    try? fileManager.createDirectory(at: destSessionDir, withIntermediateDirectories: true)
                    if (try? fileManager.copyItem(at: candidateURL, to: destSessionURL)) != nil {
                        migratedSession = true
                        break
                    }
                }
            }
        }

        // 4. Diagnostics migration: ~/Library/Containers/.../Data/Library/Application Support/SpotAsk/Diagnostics/diagnostics.json
        let containerDiagnosticsURL = containerBaseURL
            .appendingPathComponent("Application Support/SpotAsk/Diagnostics/diagnostics.json", isDirectory: false)
        let destDiagnosticsDir = destSpotAskDir.appendingPathComponent("Diagnostics", isDirectory: true)
        let destDiagnosticsURL = destDiagnosticsDir.appendingPathComponent("diagnostics.json", isDirectory: false)

        if fileManager.fileExists(atPath: containerDiagnosticsURL.path) && !fileManager.fileExists(atPath: destDiagnosticsURL.path) {
            try? fileManager.createDirectory(at: destDiagnosticsDir, withIntermediateDirectories: true)
            if (try? fileManager.copyItem(at: containerDiagnosticsURL, to: destDiagnosticsURL)) != nil {
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destDiagnosticsURL.path)
                migratedDiagnostics = true
            }
        }

        // 5. Write migration record & marker (non-destructive, keeps original container intact!)
        try? fileManager.createDirectory(at: destSpotAskDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fileManager.createDirectory(at: migrationHistoryDirectoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let record = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sourceContainer": containerBaseURL.path,
            "migratedPreferencesCount": "\(migratedPrefsCount)",
            "migratedCredentials": "\(migratedCredentials)",
            "migratedSession": "\(migratedSession)",
            "migratedDiagnostics": "\(migratedDiagnostics)"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted]) {
            let recordURL = migrationHistoryDirectoryURL.appendingPathComponent("sandbox-v0.1-migration.json")
            try? data.write(to: recordURL, options: .atomic)
            try? data.write(to: markerFileURL, options: .atomic)
        }

        return SandboxDataMigrationResult(
            didMigrate: true,
            migratedPreferencesCount: migratedPrefsCount,
            migratedCredentials: migratedCredentials,
            migratedSession: migratedSession,
            migratedDiagnostics: migratedDiagnostics
        )
    }

    static func migrateIfNeeded() {
        let migrator = SandboxDataMigrator()
        migrator.migrateIfNeeded()
    }
}
