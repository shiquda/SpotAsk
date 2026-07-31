import XCTest
@testable import SpotAsk

@MainActor
final class AppSettingsTests: XCTestCase {
    func testWindowOnTopDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.keepWindowOnTop)

        settings.keepWindowOnTop = true
        XCTAssertTrue(AppSettings(defaults: defaults).keepWindowOnTop)
    }
}
