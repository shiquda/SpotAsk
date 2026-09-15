import XCTest
import Sparkle
@testable import SpotAsk

@MainActor
final class FakeUpdateDriver: UpdateDriver {
    var automaticallyChecksForUpdates = true
    private(set) var startCount = 0
    private(set) var checkCount = 0
    private(set) var requestedSources: [UpdateDownloadSource] = []

    func start() {
        startCount += 1
    }

    func checkForUpdates() {
        checkCount += 1
        requestedSources.append(.official)
    }

    func checkForUpdates(using source: UpdateDownloadSource) {
        checkCount += 1
        requestedSources.append(source)
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

    func testAppcastAbortOnOfficialSourceMarksUnavailableWhenDirectOfficialSelected() {
        let settings = makeSettings()
        settings.updateDownloadSource = .official
        let coordinator = makeCoordinator(settings: settings)
        coordinator.checkForUpdates()

        coordinator.handleAbort(sparkleError(code: 1002))

        XCTAssertEqual(coordinator.status, .unavailable)
        XCTAssertFalse(coordinator.isChecking)
    }

    func testAutomaticModeFallsBackToAcceleratedOnNetworkTimeout() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        coordinator.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)
        XCTAssertEqual(driver.requestedSources, [.official])
        XCTAssertEqual(coordinator.currentAttemptSource, .official)
        XCTAssertTrue(coordinator.isChecking)

        // First check encounters timeout error
        let timeoutError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        coordinator.handleAbort(timeoutError)

        // Seamlessly retries accelerated mirror
        XCTAssertEqual(driver.checkCount, 2)
        XCTAssertEqual(driver.requestedSources, [.official, .accelerated])
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertEqual(coordinator.activeDownloadSource, .accelerated)
        XCTAssertTrue(coordinator.isChecking)

        // If accelerated mirror also times out, marks unavailable without infinite loop
        coordinator.handleAbort(timeoutError)
        XCTAssertEqual(coordinator.status, .unavailable)
        XCTAssertFalse(coordinator.isChecking)
        XCTAssertEqual(driver.checkCount, 2)
    }

    func testAutomaticModeFallsBackToAcceleratedOnCannotConnectToHost() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        coordinator.checkForUpdates()
        let connectError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        coordinator.handleAbort(connectError)

        XCTAssertEqual(driver.checkCount, 2)
        XCTAssertEqual(driver.requestedSources, [.official, .accelerated])
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertTrue(coordinator.isChecking)
    }

    func testWatchdogTimeoutTriggersFallbackToAccelerated() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        coordinator.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)
        XCTAssertEqual(coordinator.currentAttemptSource, .official)

        coordinator.handleCheckTimeout()
        XCTAssertEqual(driver.checkCount, 2)
        XCTAssertEqual(driver.requestedSources, [.official, .accelerated])
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertTrue(coordinator.isChecking)
    }

    func testEnclosureDownloadFailureSwitchesToAccelerated() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        coordinator.checkForUpdates()
        XCTAssertEqual(coordinator.activeDownloadSource, .official)

        let downloadError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        coordinator.handleDownloadFailure(item: SUAppcastItem.empty(), error: downloadError)
        XCTAssertEqual(coordinator.activeDownloadSource, .accelerated)

        // Following abort triggers retry on accelerated source
        coordinator.handleAbort(downloadError)
        XCTAssertEqual(driver.checkCount, 2)
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
    }

    func testSignatureAndValidationErrorsDoNotFallback() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        coordinator.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)

        // SUSignatureError (3001) must fail closed and never fallback
        coordinator.handleAbort(sparkleError(code: 3001))
        XCTAssertEqual(coordinator.status, .unavailable)
        XCTAssertFalse(coordinator.isChecking)
        XCTAssertEqual(driver.checkCount, 1)

        // SUValidationError (3002) must also fail closed
        let driver2 = FakeUpdateDriver()
        let coordinator2 = makeCoordinator(driver: driver2)
        coordinator2.checkForUpdates()
        coordinator2.handleAbort(sparkleError(code: 3002))
        XCTAssertEqual(coordinator2.status, .unavailable)
        XCTAssertFalse(coordinator2.isChecking)
        XCTAssertEqual(driver2.checkCount, 1)
    }

    func testPrepareDownloadRequestSetsTimeoutAndAcceleratesURL() {
        let coordinator = makeCoordinator()
        coordinator.checkForUpdates()

        let dmgURL = URL(string: "https://github.com/shiquda/SpotAsk/releases/download/v1.0.0/SpotAsk-1.0.0-arm64.dmg")!
        let request = NSMutableURLRequest(url: dmgURL)

        // Initially on official source
        coordinator.prepareDownloadRequest(request, for: SUAppcastItem.empty())
        XCTAssertEqual(request.timeoutInterval, 10.0)
        XCTAssertEqual(request.url, dmgURL)

        // When fallback is triggered, accelerates the URL
        coordinator.triggerFallbackToAccelerated()
        coordinator.prepareDownloadRequest(request, for: SUAppcastItem.empty())
        XCTAssertEqual(request.timeoutInterval, 10.0)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://ghproxy.net/https://github.com/shiquda/SpotAsk/releases/download/v1.0.0/SpotAsk-1.0.0-arm64.dmg"
        )
    }

    func testForcedAcceleratedSourceDirectlyUsesMirror() {
        let settings = makeSettings()
        settings.updateDownloadSource = .accelerated
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver, settings: settings)

        coordinator.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)
        XCTAssertEqual(driver.requestedSources, [.accelerated])
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertEqual(coordinator.activeDownloadSource, .accelerated)
        XCTAssertEqual(
            coordinator.currentFeedURL(),
            UpdateFeed.acceleratedAppcastURL().absoluteString
        )
    }

    func testIsNetworkOrTimeoutError() {
        XCTAssertTrue(UpdateCoordinator.isNetworkOrTimeoutError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        XCTAssertTrue(UpdateCoordinator.isNetworkOrTimeoutError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)))
        XCTAssertTrue(UpdateCoordinator.isNetworkOrTimeoutError(NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed)))
        XCTAssertTrue(UpdateCoordinator.isNetworkOrTimeoutError(sparkleError(code: 1002))) // SUAppcastError
        XCTAssertTrue(UpdateCoordinator.isNetworkOrTimeoutError(sparkleError(code: 2001))) // SUDownloadError
        XCTAssertFalse(UpdateCoordinator.isNetworkOrTimeoutError(sparkleError(code: 3001))) // SUSignatureError
        XCTAssertFalse(UpdateCoordinator.isNetworkOrTimeoutError(sparkleError(code: 3002))) // SUValidationError
        XCTAssertFalse(UpdateCoordinator.isNetworkOrTimeoutError(sparkleError(code: 1001))) // SUNoUpdateError
    }

    func testAutomaticModeResetsToOfficialAcrossCyclesAndSchedulesWatchdog() async {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)
        coordinator.checkTimeoutInterval = 0.05

        // Cycle 1: Check updates on official, trigger fallback to accelerated, then finish cycle
        coordinator.checkForUpdates()
        XCTAssertEqual(coordinator.currentAttemptSource, .official)
        coordinator.handleCheckTimeout()
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertEqual(driver.checkCount, 2)
        XCTAssertTrue(coordinator.hasFallenBackInCurrentCycle)

        // Mark cycle complete
        coordinator.markIdle()
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertEqual(coordinator.currentAttemptSource, .official)
        XCTAssertFalse(coordinator.hasFallenBackInCurrentCycle)

        // Cycle 2: Sparkle background timer initiates check by calling willStartUpdateCycle / currentFeedURL
        coordinator.willStartUpdateCycle()
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(coordinator.currentAttemptSource, .official)
        XCTAssertEqual(
            coordinator.currentFeedURL(),
            UpdateFeed.officialAppcastURL().absoluteString
        )

        // Wait for watchdog to fire for this second cycle
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertEqual(
            coordinator.currentFeedURL(),
            UpdateFeed.acceleratedAppcastURL().absoluteString
        )
        XCTAssertEqual(driver.checkCount, 3)
    }

    func testLateAbortFromReplacedOfficialUpdaterCannotClobberAcceleratedAttempt() {
        let driver = FakeUpdateDriver()
        let coordinator = makeCoordinator(driver: driver)

        // Start check on official
        coordinator.checkForUpdates()
        XCTAssertEqual(coordinator.currentAttemptSource, .official)

        // Official times out, fallback triggered to accelerated
        coordinator.handleCheckTimeout()
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(driver.checkCount, 2)

        // Stale late abort arrives from replaced official updater
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        coordinator.handleAbort(networkError, from: .official)

        // Must still be checking on accelerated, not clobbered to unavailable
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(coordinator.currentAttemptSource, .accelerated)
        XCTAssertEqual(driver.checkCount, 2)

        // Abort from the active accelerated updater marks unavailable
        coordinator.handleAbort(networkError, from: .accelerated)
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
        settings: AppSettings? = nil,
        openURL: @escaping (URL) -> Void = { _ in }
    ) -> UpdateCoordinator {
        UpdateCoordinator(
            driver: driver,
            skippedStore: store,
            settings: settings ?? makeSettings(),
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
