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

    func testDraftIsKeptOnCloseByDefaultAndOptOutPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).clearInputOnClose, "The draft should survive closing the window unless the user opts out")

        let settings = AppSettings(defaults: defaults)
        settings.clearInputOnClose = true
        XCTAssertTrue(AppSettings(defaults: defaults).clearInputOnClose)
    }

    func testPanelOriginPersistsAndClears() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(AppSettings(defaults: defaults).panelOrigin)

        let settings = AppSettings(defaults: defaults)
        settings.panelOrigin = CGPoint(x: 120, y: 340)
        XCTAssertEqual(AppSettings(defaults: defaults).panelOrigin, CGPoint(x: 120, y: 340))

        settings.panelOrigin = nil
        XCTAssertNil(AppSettings(defaults: defaults).panelOrigin)
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

    func testSimplifiedChineseUsesTheSwiftPMPackagedLocalizationDirectory() {
        let bundle = L10n.localizedBundle(for: .simplifiedChinese)

        XCTAssertEqual(bundle.bundleURL.lastPathComponent, "zh-hans.lproj")
        XCTAssertEqual(bundle.localizedString(forKey: "settings.title", value: nil, table: "Localizable"), "设置")
    }
}
