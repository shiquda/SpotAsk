import AppKit
import Foundation
import Observation
import Sparkle

@MainActor
final class SpotAskUserDriver: SPUStandardUserDriver {
    weak var coordinator: UpdateCoordinator?

    @objc(showUpdateNotFoundWithError:acknowledgement:)
    func showUpdateNotFound(withError error: NSError, acknowledgement: @escaping () -> Void) {
        dismissUpdateInstallation()
        acknowledgement()
        coordinator?.handleNoUpdateFound()
    }
}
protocol SkippedVersionStoring {
    var skippedVersion: String? { get set }
}

struct UserDefaultsSkippedVersionStore: SkippedVersionStoring {
    static let key = "SUSkippedVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var skippedVersion: String? {
        get {
            let value = defaults.string(forKey: Self.key)
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}

@MainActor
protocol UpdateDriver: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    func start()
    func checkForUpdates()
    func checkForUpdates(using source: UpdateDownloadSource)
}

extension UpdateDriver {
    func checkForUpdates(using source: UpdateDownloadSource) {
        checkForUpdates()
    }
}

@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriver, SPUUpdaterDelegate {
    private var updater: SPUUpdater?
    private var userDriver: SpotAskUserDriver?
    private var pendingAutomaticChecks = true
    private(set) var currentSource: UpdateDownloadSource = .official
    weak var coordinator: UpdateCoordinator? {
        didSet {
            userDriver?.coordinator = coordinator
        }
    }

    var activeUpdater: SPUUpdater? {
        updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? pendingAutomaticChecks }
        set {
            pendingAutomaticChecks = newValue
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    private func isCurrentUpdater(_ updater: SPUUpdater) -> Bool {
        self.updater === updater
    }

    func start() {
        start(forceRestart: false)
    }

    func start(forceRestart: Bool) {
        if forceRestart || updater == nil {
            let hostBundle = Bundle.main
            let driver = SpotAskUserDriver(hostBundle: hostBundle, delegate: nil)
            driver.coordinator = coordinator
            let updater = SPUUpdater(
                hostBundle: hostBundle,
                applicationBundle: hostBundle,
                userDriver: driver,
                delegate: self
            )
            updater.automaticallyChecksForUpdates = pendingAutomaticChecks
            updater.automaticallyDownloadsUpdates = false
            self.userDriver = driver
            self.updater = updater
        }
        do {
            try updater?.start()
        } catch {
            // Sparkle start failure is handled gracefully
        }
    }

    func checkForUpdates() {
        checkForUpdates(using: coordinator?.currentAttemptSource ?? .official)
    }

    func checkForUpdates(using source: UpdateDownloadSource) {
        let isChangingSource = (updater != nil && source != currentSource)
        currentSource = source
        if updater == nil {
            start()
        } else if updater?.sessionInProgress == true || isChangingSource {
            start(forceRestart: true)
        }
        updater?.checkForUpdates()
    }
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard isCurrentUpdater(updater) else { return nil }
        if let currentAttempt = coordinator?.currentAttemptSource, coordinator?.hasFallenBackInCurrentCycle == false {
            currentSource = currentAttempt
        }
        return coordinator?.currentFeedURL() ?? UpdateFeed.appcastURL().absoluteString
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.willStartUpdateCycle()
        if let currentAttempt = coordinator?.currentAttemptSource {
            currentSource = currentAttempt
        }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.prepareDownloadRequest(request, for: item)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.handleDownloadFailure(item: item, error: error, from: currentSource)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.didFindValidUpdate(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.markIdle()
        if let currentAttempt = coordinator?.currentAttemptSource {
            currentSource = currentAttempt
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.handleAbort(error, from: currentSource)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard isCurrentUpdater(updater) else { return }
        coordinator?.didFinishUpdateCycle(error: error, from: currentSource)
        if let currentAttempt = coordinator?.currentAttemptSource {
            currentSource = currentAttempt
        }
    }
}

@MainActor
@Observable
final class UpdateCoordinator {
    enum Status: Equatable {
        case idle
        case checking
        case unavailable
    }

    static let shared = UpdateCoordinator()

    private let driver: any UpdateDriver
    private var skippedStore: any SkippedVersionStoring
    private let settings: AppSettings
    private let openURL: (URL) -> Void
    private let notifyUpToDate: () -> Void

    var status: Status = .idle
    var skippedVersion: String?

    var isChecking: Bool {
        status == .checking
    }

    private(set) var currentAttemptSource: UpdateDownloadSource = .official
    private(set) var activeDownloadSource: UpdateDownloadSource = .official
    private(set) var hasFallenBackInCurrentCycle = false
    private var didEnclosureFailOnOfficial = false
    private(set) var activeCycleID = UUID()

    var checkTimeoutInterval: TimeInterval = 10.0
    var downloadTimeoutInterval: TimeInterval = 10.0
    private var checkTimeoutTask: Task<Void, Never>?

    init(
        driver: (any UpdateDriver)? = nil,
        skippedStore: any SkippedVersionStoring = UserDefaultsSkippedVersionStore(),
        settings: AppSettings = .shared,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        notifyUpToDate: @escaping () -> Void = { StatusToastCenter.shared.show(L10n.string("settings.upToDate")) }
    ) {
        self.skippedStore = skippedStore
        self.settings = settings
        self.openURL = openURL
        self.notifyUpToDate = notifyUpToDate
        if let driver {
            self.driver = driver
        } else {
            let sparkleDriver = SparkleUpdateDriver()
            self.driver = sparkleDriver
            sparkleDriver.coordinator = self
        }
        skippedVersion = skippedStore.skippedVersion
    }

    func start() {
        driver.automaticallyChecksForUpdates = settings.automaticUpdateCheckEnabled
        driver.start()
        refreshSkippedVersion()
    }
    func willStartUpdateCycle() {
        if hasFallenBackInCurrentCycle && currentAttemptSource == .accelerated {
            return
        }
        prepareForNewCycle()
    }

    func prepareForNewCycle() {
        cancelTimeoutWatchdog()
        activeCycleID = UUID()
        status = .checking
        hasFallenBackInCurrentCycle = false
        didEnclosureFailOnOfficial = false

        if settings.updateDownloadSource == .automatic {
            currentAttemptSource = .official
            activeDownloadSource = .official
        } else {
            currentAttemptSource = settings.updateDownloadSource
            activeDownloadSource = settings.updateDownloadSource
        }

        startTimeoutWatchdogIfNeeded()
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        prepareForNewCycle()
        driver.checkForUpdates(using: currentAttemptSource)
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        driver.automaticallyChecksForUpdates = enabled
    }

    func restoreReminders() {
        skippedStore.skippedVersion = nil
        skippedVersion = nil
        checkForUpdates()
    }

    func openGitHubReleaseFallback() {
        openURL(UpdateFeed.githubReleasesURL)
    }

    func refreshSkippedVersion() {
        skippedVersion = skippedStore.skippedVersion
    }

    func didFindValidUpdate(_ item: SUAppcastItem) {
        cancelTimeoutWatchdog()
        status = .idle
        refreshSkippedVersion()
    }

    func markIdle() {
        cancelTimeoutWatchdog()
        status = .idle
        resetCycleState()
        refreshSkippedVersion()
    }
    func handleNoUpdateFound() {
        markIdle()
        notifyUpToDate()
    }


    func markUnavailable() {
        cancelTimeoutWatchdog()
        status = .unavailable
        resetCycleState()
        refreshSkippedVersion()
    }

    private func resetCycleState() {
        hasFallenBackInCurrentCycle = false
        didEnclosureFailOnOfficial = false
        if settings.updateDownloadSource == .automatic {
            currentAttemptSource = .official
            activeDownloadSource = .official
        } else {
            currentAttemptSource = settings.updateDownloadSource
            activeDownloadSource = settings.updateDownloadSource
        }
    }

    func currentFeedURL() -> String {
        let source: UpdateDownloadSource
        if settings.updateDownloadSource == .automatic {
            source = currentAttemptSource
        } else {
            source = settings.updateDownloadSource
        }
        return UpdateFeed.appcastURL(for: source).absoluteString
    }

    func prepareDownloadRequest(_ request: NSMutableURLRequest, for item: SUAppcastItem) {
        request.timeoutInterval = downloadTimeoutInterval
        let source = (settings.updateDownloadSource == .automatic) ? activeDownloadSource : settings.updateDownloadSource
        if source == .accelerated, let originalURL = request.url {
            request.url = UpdateFeed.acceleratedEnclosureURL(for: originalURL)
        }
    }

    func handleDownloadFailure(item: SUAppcastItem, error: Error, from source: UpdateDownloadSource? = nil) {
        if let source, source != currentAttemptSource {
            return
        }
        if Self.isNetworkOrTimeoutError(error),
           settings.updateDownloadSource == .automatic,
           activeDownloadSource == .official,
           !hasFallenBackInCurrentCycle {
            didEnclosureFailOnOfficial = true
            activeDownloadSource = .accelerated
        }
    }
    func handleAbort(_ error: Error, from source: UpdateDownloadSource? = nil) {
        if let source, source != currentAttemptSource {
            return
        }
        cancelTimeoutWatchdog()
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case Int(SUError.noUpdateError.rawValue),
                 Int(SUError.installationCanceledError.rawValue),
                 Int(SUError.installationAuthorizeLaterError.rawValue):
                markIdle()
                return
            case Int(SUError.signatureError.rawValue),
                 Int(SUError.validationError.rawValue):
                // Security invariance redline: fail closed on signature error
                markUnavailable()
                return
            default:
                break
            }
        }

        let isNetworkOrTimeout = Self.isNetworkOrTimeoutError(error)
        let canFallback = settings.updateDownloadSource == .automatic
            && !hasFallenBackInCurrentCycle
            && (currentAttemptSource == .official || activeDownloadSource == .official || didEnclosureFailOnOfficial)

        if isNetworkOrTimeout && canFallback {
            triggerFallbackToAccelerated()
            return
        }

        markUnavailable()
    }

    func didFinishUpdateCycle(error: (any Error)?, from source: UpdateDownloadSource? = nil) {
        if let source, source != currentAttemptSource {
            return
        }
        if hasFallenBackInCurrentCycle && currentAttemptSource == .accelerated && status == .checking {
            return
        }
        if let error {
            let nsError = error as NSError
            if nsError.domain == SUSparkleErrorDomain,
               (nsError.code == Int(SUError.noUpdateError.rawValue) ||
                nsError.code == Int(SUError.installationCanceledError.rawValue) ||
                nsError.code == Int(SUError.installationAuthorizeLaterError.rawValue)) {
                markIdle()
            } else {
                markUnavailable()
            }
        } else {
            markIdle()
        }
    }

    func handleCheckTimeout() {
        guard status == .checking,
              settings.updateDownloadSource == .automatic,
              currentAttemptSource == .official,
              !hasFallenBackInCurrentCycle else {
            return
        }
        triggerFallbackToAccelerated()
    }

    func triggerFallbackToAccelerated() {
        cancelTimeoutWatchdog()
        activeCycleID = UUID()
        didEnclosureFailOnOfficial = false
        hasFallenBackInCurrentCycle = true
        currentAttemptSource = .accelerated
        activeDownloadSource = .accelerated
        status = .checking
        driver.checkForUpdates(using: .accelerated)
    }

    private func startTimeoutWatchdogIfNeeded() {
        cancelTimeoutWatchdog()
        guard settings.updateDownloadSource == .automatic, currentAttemptSource == .official else {
            return
        }
        let timeout = checkTimeoutInterval
        let cycleID = activeCycleID
        let attemptSource = currentAttemptSource
        checkTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.status == .checking,
                  self.activeCycleID == cycleID,
                  self.currentAttemptSource == attemptSource else {
                return
            }
            self.handleCheckTimeout()
        }
    }

    private func cancelTimeoutWatchdog() {
        checkTimeoutTask?.cancel()
        checkTimeoutTask = nil
    }

    static func isNetworkOrTimeoutError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorBadServerResponse,
                 NSURLErrorResourceUnavailable,
                 NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired,
                 NSURLErrorCannotLoadFromNetwork,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorDataNotAllowed:
                return true
            default:
                return false
            }
        }

        if nsError.domain == SUSparkleErrorDomain {
            if nsError.code == Int(SUError.appcastError.rawValue) ||
               nsError.code == Int(SUError.downloadError.rawValue) {
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                    return isNetworkOrTimeoutError(underlying)
                }
                return true
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNetworkOrTimeoutError(underlying)
        }

        return false
    }
}
