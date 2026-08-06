import Foundation
import Testing
@testable import SpotAsk

@Suite("Accessibility permission coordinator")
@MainActor
struct AccessibilityPermissionCoordinatorTests {
    @Test("Initial detection checks permission without a system prompt")
    func initialDetectionIsSilent() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)

        #expect(coordinator.status == .notAllowed)
        #expect(checker.requests == [false])
    }

    @Test("Settings authorization always makes an explicit request")
    func settingsAuthorizationCanBeRetried() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)

        coordinator.requestPermissionFromSettings()
        coordinator.requestPermissionFromSettings()

        #expect(coordinator.status == .notAllowed)
        #expect(checker.requests == [false, true, true])
    }

    @Test("The selection assistant requests authorization only once per run")
    func selectionAssistantDoesNotRepeatAuthorizationPrompt() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)

        coordinator.requestPermissionForSelectionAssistant()
        coordinator.requestPermissionForSelectionAssistant()

        #expect(coordinator.status == .notAllowed)
        #expect(checker.requests == [false, false, true, false])
    }

    @Test("Refreshing after returning to the app updates the observable status")
    func refreshUpdatesStatusAfterPermissionChanges() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)
        checker.isTrusted = true

        coordinator.refresh()

        #expect(coordinator.status == .allowed)
        #expect(checker.requests == [false, false])
    }
}

private final class StubPermissionChecker: AccessibilityPermissionChecking, @unchecked Sendable {
    var isTrusted: Bool
    private(set) var requests: [Bool] = []

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        requests.append(prompt)
        return isTrusted
    }
}
