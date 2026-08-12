import Foundation
import XCTest
@testable import SpotAsk

final class LocalAPIKeyStoreTests: XCTestCase {
    func testDefaultCredentialLocationKeepsReleaseCompatibilityAndIsolatesDebug() {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        XCTAssertEqual(
            LocalAPIKeyStore.defaultFileURL(fileManager: fileManager, bundleIdentifier: "com.spotask.app"),
            applicationSupportURL
                .appendingPathComponent("SpotAsk", isDirectory: true)
                .appendingPathComponent("credentials.json")
        )
        XCTAssertEqual(
            LocalAPIKeyStore.defaultFileURL(fileManager: fileManager, bundleIdentifier: "com.spotask.app.debug"),
            applicationSupportURL
                .appendingPathComponent("com.spotask.app.debug", isDirectory: true)
                .appendingPathComponent("credentials.json")
        )
    }

    func testRoundTripUsesCurrentUserOnlyPermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = LocalAPIKeyStore(fileURL: fileURL)
        let providerID = UUID()
        try store.saveAPIKey("local-test-key", for: providerID)

        XCTAssertEqual(try LocalAPIKeyStore(fileURL: fileURL).readAPIKey(for: providerID), "local-test-key")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o600)

        try store.deleteAPIKey(for: providerID)
        XCTAssertNil(try LocalAPIKeyStore(fileURL: fileURL).readAPIKey(for: providerID))
    }

    func testProviderCredentialsAreIsolated() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let firstProvider = UUID()
        let secondProvider = UUID()
        let store = LocalAPIKeyStore(fileURL: fileURL)

        try store.saveAPIKey("first-key", for: firstProvider)
        try store.saveAPIKey("second-key", for: secondProvider)

        XCTAssertEqual(try store.readAPIKey(for: firstProvider), "first-key")
        XCTAssertEqual(try store.readAPIKey(for: secondProvider), "second-key")
        try store.deleteAPIKey(for: firstProvider)
        XCTAssertNil(try store.readAPIKey(for: firstProvider))
        XCTAssertEqual(try store.readAPIKey(for: secondProvider), "second-key")
    }

    func testLegacyCredentialMigratesWithoutOverwritingExistingProviderKey() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("{\"apiKey\":\"legacy-key\"}".utf8).write(to: fileURL)
        let providerID = UUID()
        let store = LocalAPIKeyStore(fileURL: fileURL)

        try store.migrateLegacyAPIKey(to: providerID)

        XCTAssertEqual(try store.readAPIKey(for: providerID), "legacy-key")
        try store.saveAPIKey("new-key", for: providerID)
        try store.migrateLegacyAPIKey(to: providerID)
        XCTAssertEqual(try store.readAPIKey(for: providerID), "new-key")
    }

    func testDeleteAllCredentialsRemovesEveryProviderKey() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = LocalAPIKeyStore(fileURL: fileURL)
        let firstProvider = UUID()
        let secondProvider = UUID()
        try store.saveAPIKey("first-key", for: firstProvider)
        try store.saveAPIKey("second-key", for: secondProvider)

        try store.deleteAllAPIKeys()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(try store.readAPIKey(for: firstProvider))
        XCTAssertNil(try store.readAPIKey(for: secondProvider))
    }
}
