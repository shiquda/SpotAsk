import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Selection assistant permission flow")
@MainActor
struct SelectionAssistantCoordinatorTests {
    @Test("A missing permission shows one recovery action without reading selected text")
    func missingPermissionDoesNotReadAndDoesNotRepeatRecovery() {
        let settings = makeSettings()
        let checker = SelectionPermissionChecker(isTrusted: false)
        let permissionCoordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)
        let reader = SelectionReaderStub()
        let overlay = SelectionOverlayStub()
        let coordinator = SelectionAssistantCoordinator(
            settings: settings,
            reader: reader,
            permissionCoordinator: permissionCoordinator,
            settingsOpener: SelectionSettingsOpenerStub(),
            commandCenter: SpotAskCommandCenter(),
            overlay: overlay
        )

        coordinator.trigger()
        coordinator.trigger()

        #expect(reader.promptRequests.isEmpty)
        #expect(overlay.permissionDeniedCount == 1)
        #expect(checker.requests == [false, false, true, false])
    }

    @Test("An allowed permission reads selected text without requesting another prompt")
    func allowedPermissionReadsSilently() async {
        let settings = makeSettings()
        let checker = SelectionPermissionChecker(isTrusted: true)
        let permissionCoordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)
        let reader = SelectionReaderStub(snapshot: sampleSnapshot)
        let overlay = SelectionOverlayStub()
        let coordinator = SelectionAssistantCoordinator(
            settings: settings,
            reader: reader,
            permissionCoordinator: permissionCoordinator,
            settingsOpener: SelectionSettingsOpenerStub(),
            commandCenter: SpotAskCommandCenter(),
            overlay: overlay
        )

        coordinator.trigger()
        for _ in 0 ..< 10 where reader.promptRequests.isEmpty {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
        #expect(checker.requests == [false, false])
        #expect(overlay.permissionDeniedCount == 0)
    }

    @Test("Choosing an action uses the captured selection without reading again")
    func choosingActionUsesCapturedSelection() async {
        let settings = makeSettings()
        let checker = SelectionPermissionChecker(isTrusted: true)
        let permissionCoordinator = AccessibilityPermissionCoordinator(permissionChecker: checker)
        let reader = SelectionReaderStub(snapshot: sampleSnapshot)
        let overlay = SelectionOverlayStub()
        let coordinator = SelectionAssistantCoordinator(
            settings: settings,
            reader: reader,
            permissionCoordinator: permissionCoordinator,
            settingsOpener: SelectionSettingsOpenerStub(),
            commandCenter: SpotAskCommandCenter(),
            overlay: overlay
        )

        coordinator.trigger()
        for _ in 0 ..< 10 where !overlay.hasActionHandler {
            await Task.yield()
        }
        overlay.chooseFirstAction()

        #expect(reader.promptRequests == [false])
        #expect(overlay.hideCount == 1)
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "SelectionAssistantCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.selectionAssistantEnabled = true
        settings.selectionAssistantMode = .actionBar
        return settings
    }

    private var sampleSnapshot: SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: "Selected text",
            source: SelectionSourceApplication(processIdentifier: 42, bundleIdentifier: "com.example.Source", localizedName: "Source"),
            selectedRange: SelectionCharacterRange(location: 0, length: 13),
            anchor: .pointer(CGPoint(x: 20, y: 20))
        )
    }
}

private final class SelectionPermissionChecker: AccessibilityPermissionChecking, @unchecked Sendable {
    let isTrusted: Bool
    private(set) var requests: [Bool] = []

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        requests.append(prompt)
        return isTrusted
    }
}

private final class SelectionReaderStub: SelectedTextReading, @unchecked Sendable {
    let snapshot: SelectedTextSnapshot
    private(set) var promptRequests: [Bool] = []

    init(snapshot: SelectedTextSnapshot = .init(
        text: "Selected text",
        source: SelectionSourceApplication(processIdentifier: 42, bundleIdentifier: "com.example.Source", localizedName: "Source"),
        selectedRange: SelectionCharacterRange(location: 0, length: 13),
        anchor: .pointer(CGPoint(x: 20, y: 20))
    )) {
        self.snapshot = snapshot
    }

    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot {
        promptRequests.append(promptForPermission)
        return snapshot
    }
}

@MainActor
private final class SelectionOverlayStub: SelectionOverlayControlling {
    private(set) var permissionDeniedCount = 0
    private(set) var hideCount = 0
    private var presets: [PromptPreset] = []
    private var actionHandler: ((PromptPreset) -> Void)?

    var hasActionHandler: Bool { actionHandler != nil }

    func showActions(snapshot: SelectedTextSnapshot, presets: [PromptPreset], onSelect: @escaping (PromptPreset) -> Void) {
        self.presets = presets
        actionHandler = onSelect
    }
    func showMessage(_ message: SelectionFeedback) {}
    func showPermissionDenied(openSettings: @escaping () -> Void) { permissionDeniedCount += 1 }
    func hide() { hideCount += 1 }

    func chooseFirstAction() {
        guard let preset = presets.first else { return }
        actionHandler?(preset)
    }
}

@MainActor
private struct SelectionSettingsOpenerStub: AccessibilityPermissionSettingsOpening {
    func openAccessibilitySettings() -> Bool { true }
}
