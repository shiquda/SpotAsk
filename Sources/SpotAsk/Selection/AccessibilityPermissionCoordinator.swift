import AppKit
import Foundation
import Observation
import Security

enum AccessibilityPermissionStatus: Equatable, Sendable {
    case allowed
    case notAllowed
    case needsReauthorization
}

@MainActor
protocol AccessibilityPermissionSettingsOpening {
    @discardableResult
    func openAccessibilitySettings() -> Bool
}

@MainActor
struct MacOSAccessibilityPermissionSettingsOpener: AccessibilityPermissionSettingsOpening {
    @discardableResult
    func openAccessibilitySettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}

protocol AccessibilityGrantResetting: Sendable {
    func resetGrant(for bundleIdentifier: String) -> Bool
}

struct MacOSAccessibilityGrantResetter: AccessibilityGrantResetting {
    func resetGrant(for bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct NoOpAccessibilityGrantResetter: AccessibilityGrantResetting {
    func resetGrant(for bundleIdentifier: String) -> Bool { false }
}

protocol CodeSigningIdentityProviding: Sendable {
    func currentIdentity() -> String?
}

struct MacOSCodeSigningIdentityProvider: CodeSigningIdentityProviding {
    func currentIdentity() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else {
            return nil
        }
        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            return unique.base64EncodedString()
        }
        if let hashes = info[kSecCodeInfoCdHashes as String] as? [Data], let first = hashes.first {
            return first.base64EncodedString()
        }
        return nil
    }
}

protocol AccessibilityGrantIdentityStoring: AnyObject {
    var lastTrustedIdentity: String? { get set }
    var lastResetIdentity: String? { get set }
}

final class UserDefaultsAccessibilityGrantIdentityStore: AccessibilityGrantIdentityStoring {
    private enum Key {
        static let lastTrustedIdentity = "spotask.accessibility.lastTrustedIdentity"
        static let lastResetIdentity = "spotask.accessibility.lastResetIdentity"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastTrustedIdentity: String? {
        get { defaults.string(forKey: Key.lastTrustedIdentity) }
        set { defaults.set(newValue, forKey: Key.lastTrustedIdentity) }
    }

    var lastResetIdentity: String? {
        get { defaults.string(forKey: Key.lastResetIdentity) }
        set { defaults.set(newValue, forKey: Key.lastResetIdentity) }
    }
}

@MainActor
@Observable
final class AccessibilityPermissionCoordinator {
    private let permissionChecker: any AccessibilityPermissionChecking
    private let grantResetter: any AccessibilityGrantResetting
    private let identityProvider: any CodeSigningIdentityProviding
    private let identityStore: any AccessibilityGrantIdentityStoring
    private let featureEnabled: () -> Bool
    private let bundleIdentifier: String
    private var hasRequestedPermissionForSelectionAssistant = false

    private(set) var status: AccessibilityPermissionStatus
    private(set) var clearedStaleGrant = false

    init(
        permissionChecker: any AccessibilityPermissionChecking = MacOSAccessibilityPermissionChecker(),
        grantResetter: any AccessibilityGrantResetting = NoOpAccessibilityGrantResetter(),
        identityProvider: any CodeSigningIdentityProviding = MacOSCodeSigningIdentityProvider(),
        identityStore: any AccessibilityGrantIdentityStoring = UserDefaultsAccessibilityGrantIdentityStore(),
        featureEnabled: @escaping () -> Bool = { false },
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.spotask.app"
    ) {
        self.permissionChecker = permissionChecker
        self.grantResetter = grantResetter
        self.identityProvider = identityProvider
        self.identityStore = identityStore
        self.featureEnabled = featureEnabled
        self.bundleIdentifier = bundleIdentifier
        status = .notAllowed
        reconcile(prompt: false)
    }

    @discardableResult
    func refresh() -> AccessibilityPermissionStatus {
        reconcile(prompt: false)
        return status
    }

    @discardableResult
    func requestPermissionFromSettings() -> AccessibilityPermissionStatus {
        reconcile(prompt: true)
        return status
    }

    @discardableResult
    func requestPermissionForSelectionAssistant() -> AccessibilityPermissionStatus {
        reconcile(prompt: false)
        guard status != .allowed,
              !hasRequestedPermissionForSelectionAssistant else {
            return status
        }

        hasRequestedPermissionForSelectionAssistant = true
        reconcile(prompt: true)
        return status
    }

    @discardableResult
    private func reconcile(prompt: Bool) -> AccessibilityPermissionStatus {
        let currentIdentity = identityProvider.currentIdentity()
        if permissionChecker.isTrusted(prompt: false) {
            recordTrustedIdentity(currentIdentity)
            clearedStaleGrant = false
            status = .allowed
            return finish(prompt: prompt, currentIdentity: currentIdentity)
        }

        if shouldResetStaleGrant(currentIdentity: currentIdentity),
           grantResetter.resetGrant(for: bundleIdentifier) {
            identityStore.lastResetIdentity = currentIdentity
            identityStore.lastTrustedIdentity = nil
            clearedStaleGrant = true
            if permissionChecker.isTrusted(prompt: false) {
                recordTrustedIdentity(currentIdentity)
                clearedStaleGrant = false
                status = .allowed
                return finish(prompt: prompt, currentIdentity: currentIdentity)
            }
        }

        status = shouldPresentReauthorization(currentIdentity: currentIdentity) ? .needsReauthorization : .notAllowed
        return finish(prompt: prompt, currentIdentity: currentIdentity)
    }

    @discardableResult
    private func finish(prompt: Bool, currentIdentity: String?) -> AccessibilityPermissionStatus {
        guard prompt else { return status }
        if permissionChecker.isTrusted(prompt: true) {
            recordTrustedIdentity(identityProvider.currentIdentity() ?? currentIdentity)
            clearedStaleGrant = false
            status = .allowed
            return status
        }
        status = shouldPresentReauthorization(currentIdentity: currentIdentity) ? .needsReauthorization : .notAllowed
        return status
    }

    private func recordTrustedIdentity(_ identity: String?) {
        identityStore.lastTrustedIdentity = identity
    }

    private func shouldResetStaleGrant(currentIdentity: String?) -> Bool {
        guard let currentIdentity else { return false }
        if identityStore.lastResetIdentity == currentIdentity { return false }
        if let lastTrustedIdentity = identityStore.lastTrustedIdentity, lastTrustedIdentity != currentIdentity {
            return true
        }
        return featureEnabled() && identityStore.lastTrustedIdentity == nil
    }

    private func shouldPresentReauthorization(currentIdentity: String?) -> Bool {
        if clearedStaleGrant { return true }
        guard let currentIdentity else { return false }
        return identityStore.lastResetIdentity == currentIdentity
            && identityStore.lastTrustedIdentity != currentIdentity
    }
}
