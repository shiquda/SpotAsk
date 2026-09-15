import AppKit
import Foundation
import Observation
import Sparkle

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
    private var controller: SPUStandardUpdaterController?
    private var pendingAutomaticChecks = true
    weak var coordinator: UpdateCoordinator?

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? pendingAutomaticChecks }
        set {
            pendingAutomaticChecks = newValue
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func start() {
        start(forceRestart: false)
    }

    func start(forceRestart: Bool) {
        if forceRestart || controller == nil {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            controller.updater.automaticallyChecksForUpdates = pendingAutomaticChecks
            controller.updater.automaticallyDownloadsUpdates = false
            self.controller = controller
        }
        controller?.startUpdater()
    }

    func checkForUpdates() {
        checkForUpdates(using: coordinator?.currentAttemptSource ?? .official)
    }

    func checkForUpdates(using source: UpdateDownloadSource) {
        if controller == nil {
            start()
        } else if controller?.updater.sessionInProgress == true {
            start(forceRestart: true)
        }
        controller?.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        coordinator?.currentFeedURL() ?? UpdateFeed.appcastURL().absoluteString
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        coordinator?.prepareDownloadRequest(request, for: item)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        coordinator?.handleDownloadFailure(item: item, error: error)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        coordinator?.markIdle()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        coordinator?.markIdle()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        coordinator?.handleAbort(error)
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

    var status: Status = .idle
    var skippedVersion: String?

    var isChecking: Bool {
        status == .checking
    }

    private(set) var currentAttemptSource: UpdateDownloadSource = .official
    private(set) var activeDownloadSource: UpdateDownloadSource = .official
    private(set) var hasFallenBackInCurrentCycle = false
    private var didEnclosureFailOnOfficial = false

    var checkTimeoutInterval: TimeInterval = 10.0
    var downloadTimeoutInterval: TimeInterval = 10.0
    private var checkTimeoutTask: Task<Void, Never>?

    init(
        driver: (any UpdateDriver)? = nil,
        skippedStore: any SkippedVersionStoring = UserDefaultsSkippedVersionStore(),
        settings: AppSettings = .shared,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.skippedStore = skippedStore
        self.settings = settings
        self.openURL = openURL
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

    func checkForUpdates() {
        guard !isChecking else { return }
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

    func markIdle() {
        cancelTimeoutWatchdog()
        status = .idle
        refreshSkippedVersion()
    }

    func markUnavailable() {
        cancelTimeoutWatchdog()
        status = .unavailable
        refreshSkippedVersion()
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

    func handleDownloadFailure(item: SUAppcastItem, error: Error) {
        if Self.isNetworkOrTimeoutError(error),
           settings.updateDownloadSource == .automatic,
           activeDownloadSource == .official,
           !hasFallenBackInCurrentCycle {
            didEnclosureFailOnOfficial = true
            activeDownloadSource = .accelerated
            currentAttemptSource = .accelerated
        }
    }

    func handleAbort(_ error: Error) {
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
        checkTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.status == .checking, self.currentAttemptSource == .official else {
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
