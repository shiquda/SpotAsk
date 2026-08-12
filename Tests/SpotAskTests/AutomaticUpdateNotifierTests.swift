import XCTest
@testable import SpotAsk

@MainActor
final class AutomaticUpdateNotifierTests: XCTestCase {
    func testChecksOnceWhenEnabledAndNotifiesWithTheLatestRelease() async {
        let suite = "AutomaticUpdateNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.automaticUpdateCheckEnabled = true

        let update = AvailableAppUpdate(version: AppVersion(string: "0.2.0")!)
        let checker = StubUpdateChecker(result: update)
        let notifier = AutomaticUpdateNotifier(settings: settings, checker: checker)
        var shownUpdates: [AvailableAppUpdate] = []

        await notifier.checkAtLaunchIfEnabled { shownUpdates.append($0) }
        await notifier.checkAtLaunchIfEnabled { shownUpdates.append($0) }

        XCTAssertEqual(shownUpdates, [update])
        let checkCount = await checker.checkCount
        XCTAssertEqual(checkCount, 1)
    }

    func testSkipsCheckWhenDisabled() async {
        let suite = "AutomaticUpdateNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.automaticUpdateCheckEnabled = false

        let checker = StubUpdateChecker(result: AvailableAppUpdate(version: AppVersion(string: "0.2.0")!))
        let notifier = AutomaticUpdateNotifier(settings: settings, checker: checker)
        var didNotify = false

        await notifier.checkAtLaunchIfEnabled { _ in didNotify = true }

        XCTAssertFalse(didNotify)
        let checkCount = await checker.checkCount
        XCTAssertEqual(checkCount, 0)
    }
}

private actor StubUpdateChecker: AppUpdateChecking {
    let result: AvailableAppUpdate?
    private(set) var checkCount = 0

    init(result: AvailableAppUpdate?) {
        self.result = result
    }

    func check(for currentVersion: AppVersion) async throws -> AvailableAppUpdate? {
        checkCount += 1
        return result
    }
}
