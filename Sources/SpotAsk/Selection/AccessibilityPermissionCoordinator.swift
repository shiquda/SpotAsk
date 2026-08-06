import AppKit
import Foundation
import Observation

enum AccessibilityPermissionStatus: Equatable, Sendable {
    case allowed
    case notAllowed
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

@MainActor
@Observable
final class AccessibilityPermissionCoordinator {
    private let permissionChecker: any AccessibilityPermissionChecking
    private var hasRequestedPermissionForSelectionAssistant = false

    private(set) var status: AccessibilityPermissionStatus

    init(permissionChecker: any AccessibilityPermissionChecking = MacOSAccessibilityPermissionChecker()) {
        self.permissionChecker = permissionChecker
        status = Self.status(for: permissionChecker.isTrusted(prompt: false))
    }

    @discardableResult
    func refresh() -> AccessibilityPermissionStatus {
        status = Self.status(for: permissionChecker.isTrusted(prompt: false))
        return status
    }

    @discardableResult
    func requestPermissionFromSettings() -> AccessibilityPermissionStatus {
        status = Self.status(for: permissionChecker.isTrusted(prompt: true))
        return status
    }

    @discardableResult
    func requestPermissionForSelectionAssistant() -> AccessibilityPermissionStatus {
        guard refresh() == .notAllowed,
              !hasRequestedPermissionForSelectionAssistant else {
            return status
        }

        hasRequestedPermissionForSelectionAssistant = true
        status = Self.status(for: permissionChecker.isTrusted(prompt: true))
        return status
    }

    private static func status(for isTrusted: Bool) -> AccessibilityPermissionStatus {
        isTrusted ? .allowed : .notAllowed
    }
}
