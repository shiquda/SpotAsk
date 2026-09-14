import XCTest
@testable import SpotAsk

@MainActor
final class FakeUpdateDriver: UpdateDriver {
    var automaticallyChecksForUpdates = true
    private(set) var startCount = 0
    private(set) var checkCount = 0

    func start() {
        startCount += 1
    }

    func checkForUpdates() {
        checkCount += 1
    }
}

final class MemorySkippedVersionStore: SkippedVersionStoring {
    var skippedVersion: String?
}

@MainActor
final class UpdateCoordinatorTests: XCTestCase {
    func testStartAppliesAutomaticCheckSetting() {
        let settings = makeSettings()
        settings.automaticUpdateCheckEnabled = false
        let driver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(
            driver: driver,
            skippedStore: MemorySkippedVersionStore(),
            settings: settings,
            openURL: { _ in }
        )

        coordinator.start()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        XCTAssertEqual(coordinator.status, .idle)
    }

    func testCheckForUpdatesIsIdempotentWhileChecking() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        coordinator.checkForUpdates()
        coordinator.checkForUpdates()

        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(driver.checkCount, 1)
        XCTAssertTrue(coordinator.isChecking)
    }

    func testRestoreRemindersClearsSkippedVersionAndChecksAgain() {
        let driver = FakeUpdateDriver()
        let store = MemorySkippedVersionStore()
        store.skippedVersion = "1.4.0"
        let coordinator = makeCoordinator(driver: driver, store: store)
        coordinator.refreshSkippedVersion()
        XCTAssertEqual(coordinator.skippedVersion, "1.4.0")

        coordinator.restoreReminders()

        XCTAssertNil(store.skippedVersion)
        XCTAssertNil(coordinator.skippedVersion)
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(driver.checkCount, 1)
    }

    func testNoUpdateAndUserCancelAbortStayIdle() {
        let coordinator = makeCoordinator()

        coordinator.handleAbort(sparkleError(code: 1001))
        XCTAssertEqual(coordinator.status, .idle)

        coordinator.status = .checking
        coordinator.handleAbort(sparkleError(code: 4007))
        XCTAssertEqual(coordinator.status, .idle)

        coordinator.status = .checking
        coordinator.handleAbort(sparkleError(code: 4008))
        XCTAssertEqual(coordinator.status, .idle)
    }

    func testAppcastAbortMarksUnavailable() {
        let coordinator = makeCoordinator()

        coordinator.handleAbort(sparkleError(code: 1002))

        XCTAssertEqual(coordinator.status, .unavailable)
        XCTAssertFalse(coordinator.isChecking)
    }

    func testGitHubReleaseFallbackOpensNamedBrowserURL() {
        var opened: [URL] = []
        let coordinator = makeCoordinator(openURL: { opened.append($0) })

        coordinator.openGitHubReleaseFallback()

        XCTAssertEqual(opened, [UpdateFeed.githubReleasesURL])
    }

    func testUserDefaultsSkippedVersionStoreUsesSparkleKey() {
        let suite = "SkippedVersionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var store = UserDefaultsSkippedVersionStore(defaults: defaults)
        store.skippedVersion = "1.2.3"
        XCTAssertEqual(defaults.string(forKey: "SUSkippedVersion"), "1.2.3")

        store.skippedVersion = ""
        XCTAssertNil(defaults.object(forKey: "SUSkippedVersion"))
        XCTAssertNil(store.skippedVersion)
    }

    private func makeCoordinator(
        driver: FakeUpdateDriver = FakeUpdateDriver(),
        store: MemorySkippedVersionStore = MemorySkippedVersionStore(),
        openURL: @escaping (URL) -> Void = { _ in }
    ) -> UpdateCoordinator {
        UpdateCoordinator(
            driver: driver,
            skippedStore: store,
            settings: makeSettings(),
            openURL: openURL
        )
    }

    private func makeSettings() -> AppSettings {
        let suite = "UpdateCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }
    private func sparkleError(code: Int) -> NSError {
        NSError(domain: "SUSparkleErrorDomain", code: code)
    }
}
