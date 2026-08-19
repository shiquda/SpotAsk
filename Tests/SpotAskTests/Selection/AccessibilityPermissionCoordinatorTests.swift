import Foundation
import Testing
@testable import SpotAsk

@Suite("Accessibility permission coordinator")
@MainActor
struct AccessibilityPermissionCoordinatorTests {
    @Test("Initial detection checks permission without a system prompt")
    func initialDetectionIsSilent() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = makeCoordinator(checker: checker)

        #expect(coordinator.status == .notAllowed)
        #expect(checker.requests == [false])
    }

    @Test("Settings authorization always makes an explicit request")
    func settingsAuthorizationCanBeRetried() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = makeCoordinator(checker: checker)

        coordinator.requestPermissionFromSettings()
        coordinator.requestPermissionFromSettings()

        #expect(coordinator.status == .notAllowed)
        #expect(checker.requests == [false, false, true, false, true])
    }

    @Test("The selection assistant requests authorization only once per run")
    func selectionAssistantDoesNotRepeatAuthorizationPrompt() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = makeCoordinator(checker: checker)

        coordinator.requestPermissionForSelectionAssistant()
        coordinator.requestPermissionForSelectionAssistant()

        #expect(coordinator.status == .notAllowed)
        #expect(checker.requests == [false, false, false, true, false])
    }

    @Test("Refreshing after returning to the app updates the observable status")
    func refreshUpdatesStatusAfterPermissionChanges() {
        let checker = StubPermissionChecker(isTrusted: false)
        let coordinator = makeCoordinator(checker: checker)
        checker.isTrusted = true

        coordinator.refresh()

        #expect(coordinator.status == .allowed)
        #expect(checker.requests == [false, false])
    }

    @Test("A signing change with a previous grant clears the stale Accessibility row")
    func signingChangeClearsStaleGrant() {
        let checker = StubPermissionChecker(isTrusted: false)
        let resetter = StubGrantResetter()
        let store = MemoryGrantIdentityStore(lastTrustedIdentity: "old-hash")
        let coordinator = makeCoordinator(
            checker: checker,
            resetter: resetter,
            identity: "new-hash",
            store: store,
            featureEnabled: false
        )

        #expect(resetter.resetBundleIDs == ["com.spotask.app.test"])
        #expect(coordinator.status == .needsReauthorization)
        #expect(coordinator.clearedStaleGrant)
        #expect(store.lastTrustedIdentity == nil)
        #expect(store.lastResetIdentity == "new-hash")
    }

    @Test("The same unsigned-in grant is not reset twice")
    func alreadyResetIdentityIsNotResetAgain() {
        let checker = StubPermissionChecker(isTrusted: false)
        let resetter = StubGrantResetter()
        let store = MemoryGrantIdentityStore(
            lastTrustedIdentity: "old-hash",
            lastResetIdentity: "new-hash"
        )
        let coordinator = makeCoordinator(
            checker: checker,
            resetter: resetter,
            identity: "new-hash",
            store: store
        )

        coordinator.refresh()

        #expect(resetter.resetBundleIDs.isEmpty)
        #expect(coordinator.status == .needsReauthorization)
        #expect(!coordinator.clearedStaleGrant)
    }

    @Test("An enabled selection assistant without a recorded grant clears a leftover row once")
    func enabledFeatureClearsUnknownLeftoverGrant() {
        let checker = StubPermissionChecker(isTrusted: false)
        let resetter = StubGrantResetter()
        let store = MemoryGrantIdentityStore()
        let coordinator = makeCoordinator(
            checker: checker,
            resetter: resetter,
            identity: "fresh-hash",
            store: store,
            featureEnabled: true
        )

        #expect(resetter.resetBundleIDs == ["com.spotask.app.test"])
        #expect(coordinator.status == .needsReauthorization)
        coordinator.refresh()
        #expect(resetter.resetBundleIDs == ["com.spotask.app.test"])
    }


    @Test("A previous reset of this install keeps the reauthorization status")
    func previousResetKeepsReauthorizationWithoutResettingAgain() {
        let checker = StubPermissionChecker(isTrusted: false)
        let resetter = StubGrantResetter()
        let store = MemoryGrantIdentityStore(lastResetIdentity: "fresh-hash")
        let coordinator = makeCoordinator(
            checker: checker,
            resetter: resetter,
            identity: "fresh-hash",
            store: store,
            featureEnabled: true
        )

        #expect(resetter.resetBundleIDs.isEmpty)
        #expect(coordinator.status == .needsReauthorization)
        #expect(!coordinator.clearedStaleGrant)
    }

    @Test("An unused feature does not clear Accessibility on first launch")
    func unusedFeatureDoesNotResetUnknownIdentity() {
        let checker = StubPermissionChecker(isTrusted: false)
        let resetter = StubGrantResetter()
        let coordinator = makeCoordinator(
            checker: checker,
            resetter: resetter,
            identity: "fresh-hash",
            store: MemoryGrantIdentityStore(),
            featureEnabled: false
        )

        #expect(resetter.resetBundleIDs.isEmpty)
        #expect(coordinator.status == .notAllowed)
        #expect(!coordinator.clearedStaleGrant)
    }
    @Test("A successful reauthorization records the current install identity")
    func successfulPromptRecordsCurrentIdentity() {
        let checker = StubPermissionChecker(isTrusted: false)
        let store = MemoryGrantIdentityStore(lastTrustedIdentity: "old-hash")
        let coordinator = makeCoordinator(
            checker: checker,
            identity: "new-hash",
            store: store
        )
        checker.isTrusted = true

        coordinator.requestPermissionFromSettings()

        #expect(coordinator.status == .allowed)
        #expect(store.lastTrustedIdentity == "new-hash")
        #expect(!coordinator.clearedStaleGrant)
    }
}

@MainActor
private func makeCoordinator(
    checker: StubPermissionChecker,
    resetter: StubGrantResetter = StubGrantResetter(),
    identity: String? = "test-hash",
    store: MemoryGrantIdentityStore = MemoryGrantIdentityStore(),
    featureEnabled: Bool = false
) -> AccessibilityPermissionCoordinator {
    AccessibilityPermissionCoordinator(
        permissionChecker: checker,
        grantResetter: resetter,
        identityProvider: StubIdentityProvider(identity: identity),
        identityStore: store,
        featureEnabled: { featureEnabled },
        bundleIdentifier: "com.spotask.app.test"
    )
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

private final class StubGrantResetter: AccessibilityGrantResetting, @unchecked Sendable {
    private(set) var resetBundleIDs: [String] = []

    func resetGrant(for bundleIdentifier: String) -> Bool {
        resetBundleIDs.append(bundleIdentifier)
        return true
    }
}

private struct StubIdentityProvider: CodeSigningIdentityProviding {
    let identity: String?

    func currentIdentity() -> String? { identity }
}

private final class MemoryGrantIdentityStore: AccessibilityGrantIdentityStoring {
    var lastTrustedIdentity: String?
    var lastResetIdentity: String?

    init(lastTrustedIdentity: String? = nil, lastResetIdentity: String? = nil) {
        self.lastTrustedIdentity = lastTrustedIdentity
        self.lastResetIdentity = lastResetIdentity
    }
}
