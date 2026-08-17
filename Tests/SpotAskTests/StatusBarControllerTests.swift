import AppKit
import XCTest
@testable import SpotAsk

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testRebuildingTheStatusMenuDoesNotCrashWhenReusableItemsAreAlreadyAttached() {
        let suite = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let controller = StatusBarController(settings: AppSettings(defaults: defaults))
        controller.rebuildMenu()
        controller.rebuildMenu()
        NotificationCenter.default.post(name: .spotAskLanguageChanged, object: nil)
    }

    func testApplyingABackupDoesNotCrashTheStatusMenuLanguageObserver() throws {
        let sourceSuite = "StatusBarControllerBackupSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "StatusBarControllerBackupDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        source.language = .english
        source.proxyEnabled = true
        source.proxyHost = "127.0.0.1"
        source.proxyPort = 7890
        let backup = try source.makeConfigurationBackup()

        let destination = AppSettings(defaults: destinationDefaults)
        destination.language = .simplifiedChinese
        _ = StatusBarController(settings: destination)

        try destination.applyConfigurationBackup(backup)

        XCTAssertEqual(destination.language, .english)
        XCTAssertTrue(destination.proxyEnabled)
        XCTAssertEqual(destination.proxyHost, "127.0.0.1")
        XCTAssertEqual(destination.proxyPort, 7890)
    }
}
