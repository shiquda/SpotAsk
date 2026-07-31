import Foundation
import XCTest
@testable import SpotAsk

final class LocalAPIKeyStoreTests: XCTestCase {
    func testRoundTripUsesCurrentUserOnlyPermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = LocalAPIKeyStore(fileURL: fileURL)
        try store.saveAPIKey("local-test-key")

        XCTAssertEqual(try LocalAPIKeyStore(fileURL: fileURL).readAPIKey(), "local-test-key")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o600)

        try store.deleteAPIKey()
        XCTAssertNil(try LocalAPIKeyStore(fileURL: fileURL).readAPIKey())
    }
}
