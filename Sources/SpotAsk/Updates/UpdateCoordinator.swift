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
        if controller == nil {
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
        if controller == nil {
            start()
        }
        controller?.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateFeed.appcastURL().absoluteString
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
        driver.checkForUpdates()
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
        status = .idle
        refreshSkippedVersion()
    }

    func markUnavailable() {
        status = .unavailable
        refreshSkippedVersion()
    }

    func handleAbort(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case Int(SUError.noUpdateError.rawValue),
                 Int(SUError.installationCanceledError.rawValue),
                 Int(SUError.installationAuthorizeLaterError.rawValue):
                markIdle()
                return
            default:
                break
            }
        }
        markUnavailable()
    }
}
