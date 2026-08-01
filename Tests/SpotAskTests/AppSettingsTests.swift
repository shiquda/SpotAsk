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

    func testMenuBarIconDefaultsToVisibleAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.showsMenuBarIcon)

        settings.showsMenuBarIcon = false
        XCTAssertFalse(AppSettings(defaults: defaults).showsMenuBarIcon)
    }

    func testChangingMenuBarIconPreferenceNotifiesTheRunningApplication() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let expectation = expectation(forNotification: .spotAskMenuBarIconVisibilityChanged, object: settings)

        settings.showsMenuBarIcon = false

        wait(for: [expectation], timeout: 0)
    }

    func testMenuBarAndDockPresentationsUseOppositeRecoveryEntrances() {
        let menuBar = AppEntryPresentation(showsMenuBarIcon: true)
        XCTAssertTrue(menuBar.showsStatusItem)
        XCTAssertEqual(menuBar.activationPolicy, .accessory)

        let dock = AppEntryPresentation(showsMenuBarIcon: false)
        XCTAssertFalse(dock.showsStatusItem)
        XCTAssertEqual(dock.activationPolicy, .regular)
    }

    func testEntryPresentationCoordinatorAppliesInitialAndLivePreference() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var statusItemVisibility: [Bool] = []
        var activationPolicies: [NSApplication.ActivationPolicy] = []

        let coordinator = AppEntryPresentationCoordinator(
            settings: settings,
            setStatusItemVisible: { statusItemVisibility.append($0) },
            setActivationPolicy: { activationPolicies.append($0) }
        )
        XCTAssertNotNil(coordinator)
        XCTAssertEqual(statusItemVisibility, [true])
        XCTAssertEqual(activationPolicies, [.accessory])

        settings.showsMenuBarIcon = false
        XCTAssertEqual(statusItemVisibility, [true, false])
        XCTAssertEqual(activationPolicies, [.accessory, .regular])

        settings.showsMenuBarIcon = true
        XCTAssertEqual(statusItemVisibility, [true, false, true])
        XCTAssertEqual(activationPolicies, [.accessory, .regular, .accessory])
    }

    func testDockReopenRequestsThePanelOnlyWhenNoWindowIsVisible() {
        var openRequests = 0

        XCTAssertTrue(handleDockReopen(hasVisibleWindows: false) { openRequests += 1 })
        XCTAssertEqual(openRequests, 1)

        XCTAssertTrue(handleDockReopen(hasVisibleWindows: true) { openRequests += 1 })
        XCTAssertEqual(openRequests, 1)
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
