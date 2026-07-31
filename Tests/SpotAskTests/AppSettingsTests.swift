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

    func testLanguageDefaultsToSystemAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).language, .system)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english
        XCTAssertEqual(AppSettings(defaults: defaults).language, .english)
    }

    func testLocalizationUsesExplicitLanguageSelection() {
        XCTAssertEqual(L10n.string("settings.title", language: .english), "Settings")
        XCTAssertEqual(L10n.string("settings.title", language: .simplifiedChinese), "设置")
    }
}
