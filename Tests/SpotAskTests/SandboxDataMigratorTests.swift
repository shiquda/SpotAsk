import XCTest
@testable import SpotAsk

final class SandboxDataMigratorTests: XCTestCase {
    private var tempDirectory: URL!
    private var containerURL: URL!
    private var appSupportURL: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SandboxMigratorTest-\(UUID().uuidString)")
        containerURL = tempDirectory.appendingPathComponent("Container/Data/Library", isDirectory: true)
        appSupportURL = tempDirectory.appendingPathComponent("ApplicationSupport", isDirectory: true)

        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        suiteName = "SandboxMigratorTest.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testSandboxDataMigratorMigratesPreferencesCredentialsSessionDiagnostics() throws {
        let bundleID = "com.spotask.app"

        // 1. Populate old sandbox preferences plist
        let prefsDir = containerURL.appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        let prefsPlistURL = prefsDir.appendingPathComponent("\(bundleID).plist")
        let prefsData: [String: Any] = [
            "systemPrompt": "Migrated System Prompt",
            "contextLimit": 35,
            "renderMath": false
        ]
        let plistBytes = try PropertyListSerialization.data(fromPropertyList: prefsData, format: .xml, options: 0)
        try plistBytes.write(to: prefsPlistURL)

        // 2. Populate old sandbox credentials.json
        let credsDir = containerURL.appendingPathComponent("Application Support/SpotAsk", isDirectory: true)
        try FileManager.default.createDirectory(at: credsDir, withIntermediateDirectories: true)
        let credsURL = credsDir.appendingPathComponent("credentials.json")
        let credsData = "{\"api-key-1\": \"secret-value\"}".data(using: .utf8)!
        try credsData.write(to: credsURL)

        // 3. Populate old sandbox current-session.json
        let sessionDir = containerURL.appendingPathComponent("Application Support/\(bundleID)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let sessionURL = sessionDir.appendingPathComponent("current-session.json")
        let sessionData = "{\"messages\": []}".data(using: .utf8)!
        try sessionData.write(to: sessionURL)

        // 4. Populate old sandbox diagnostics.json
        let diagDir = containerURL.appendingPathComponent("Application Support/SpotAsk/Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)
        let diagURL = diagDir.appendingPathComponent("diagnostics.json")
        let diagData = "[{\"message\": \"sandbox-log\"}]".data(using: .utf8)!
        try diagData.write(to: diagURL)

        let migrator = SandboxDataMigrator(
            bundleIdentifier: bundleID,
            containerBaseURL: containerURL,
            applicationSupportURL: appSupportURL,
            defaults: defaults
        )

        let result = migrator.migrateIfNeeded()

        XCTAssertTrue(result.didMigrate)
        XCTAssertEqual(result.migratedPreferencesCount, 3)
        XCTAssertTrue(result.migratedCredentials)
        XCTAssertTrue(result.migratedSession)
        XCTAssertTrue(result.migratedDiagnostics)

        // Verify preferences in defaults
        XCTAssertEqual(defaults.string(forKey: "systemPrompt"), "Migrated System Prompt")
        XCTAssertEqual(defaults.integer(forKey: "contextLimit"), 35)
        XCTAssertEqual(defaults.bool(forKey: "renderMath"), false)

        // Verify credentials copied to unsandboxed destination
        let destCredsURL = appSupportURL.appendingPathComponent("SpotAsk/credentials.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destCredsURL.path))
        XCTAssertEqual(try Data(contentsOf: destCredsURL), credsData)

        // Verify session copied
        let destSessionURL = appSupportURL.appendingPathComponent("\(bundleID)/current-session.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destSessionURL.path))
        XCTAssertEqual(try Data(contentsOf: destSessionURL), sessionData)

        // Verify diagnostics copied
        let destDiagURL = appSupportURL.appendingPathComponent("SpotAsk/Diagnostics/diagnostics.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDiagURL.path))
        XCTAssertEqual(try Data(contentsOf: destDiagURL), diagData)

        // Verify non-destructive: original container files still exist!
        XCTAssertTrue(FileManager.default.fileExists(atPath: credsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: diagURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefsPlistURL.path))

        // Verify idempotency on second run
        let secondResult = migrator.migrateIfNeeded()
        XCTAssertFalse(secondResult.didMigrate)
    }

    func testSandboxDataMigratorDoesNotOverwriteExistingData() throws {
        let bundleID = "com.spotask.app"

        // Set up existing unsandboxed data
        defaults.set("Existing User Prompt", forKey: "systemPrompt")

        let destCredsDir = appSupportURL.appendingPathComponent("SpotAsk", isDirectory: true)
        try FileManager.default.createDirectory(at: destCredsDir, withIntermediateDirectories: true)
        let destCredsURL = destCredsDir.appendingPathComponent("credentials.json")
        let existingCreds = "{\"existing\": \"key\"}".data(using: .utf8)!
        try existingCreds.write(to: destCredsURL)

        // Old container has older data
        let credsDir = containerURL.appendingPathComponent("Application Support/SpotAsk", isDirectory: true)
        try FileManager.default.createDirectory(at: credsDir, withIntermediateDirectories: true)
        let oldCredsURL = credsDir.appendingPathComponent("credentials.json")
        try "{\"old\": \"key\"}".data(using: .utf8)!.write(to: oldCredsURL)

        let prefsDir = containerURL.appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        let prefsPlistURL = prefsDir.appendingPathComponent("\(bundleID).plist")
        let prefsData = ["systemPrompt": "Old Sandbox Prompt", "newKey": "New Value"]
        let plistBytes = try PropertyListSerialization.data(fromPropertyList: prefsData, format: .xml, options: 0)
        try plistBytes.write(to: prefsPlistURL)

        let migrator = SandboxDataMigrator(
            bundleIdentifier: bundleID,
            containerBaseURL: containerURL,
            applicationSupportURL: appSupportURL,
            defaults: defaults
        )

        let result = migrator.migrateIfNeeded()
        XCTAssertTrue(result.didMigrate)
        // Existing systemPrompt was preserved
        XCTAssertEqual(defaults.string(forKey: "systemPrompt"), "Existing User Prompt")
        // Non-conflicting key was migrated
        XCTAssertEqual(defaults.string(forKey: "newKey"), "New Value")
        // Existing credentials were preserved
        XCTAssertEqual(try Data(contentsOf: destCredsURL), existingCreds)
    }
    func testSandboxDataMigratorFailureDoesNotWriteMarkerAndAllowsRetry() throws {
        let bundleID = "com.spotask.app"

        // Old container has credentials
        let credsDir = containerURL.appendingPathComponent("Application Support/SpotAsk", isDirectory: true)
        try FileManager.default.createDirectory(at: credsDir, withIntermediateDirectories: true)
        let oldCredsURL = credsDir.appendingPathComponent("credentials.json")
        try "{\"secret\": \"token\"}".data(using: .utf8)!.write(to: oldCredsURL)

        // Simulate failure by making destSpotAskDir read-only so copyItem fails
        let destSpotAskDir = appSupportURL.appendingPathComponent("SpotAsk", isDirectory: true)
        try FileManager.default.createDirectory(at: destSpotAskDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o500])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destSpotAskDir.path)
        }

        let migrator = SandboxDataMigrator(
            bundleIdentifier: bundleID,
            containerBaseURL: containerURL,
            applicationSupportURL: appSupportURL,
            defaults: defaults
        )

        // Attempt 1: copy fails due to permissions
        let result1 = migrator.migrateIfNeeded()
        XCTAssertFalse(result1.didMigrate)
        XCTAssertFalse(result1.migratedCredentials)

        // Marker file must NOT exist!
        let markerFile = appSupportURL.appendingPathComponent("SpotAsk/.sandbox-migration-completed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerFile.path))

        // Restore write permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destSpotAskDir.path)

        // Attempt 2: retry should now succeed!
        let result2 = migrator.migrateIfNeeded()
        XCTAssertTrue(result2.didMigrate)
        XCTAssertTrue(result2.migratedCredentials)

        // Marker file now exists!
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerFile.path))

        // Destination credentials exist!
        let destCredsURL = destSpotAskDir.appendingPathComponent("credentials.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destCredsURL.path))
    }
}
