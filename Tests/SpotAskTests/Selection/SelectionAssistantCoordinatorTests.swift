import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Selection assistant permission flow")
@MainActor
struct SelectionAssistantCoordinatorTests {
    @Test("A plain click gesture does not schedule automatic selection")
    func plainClickGestureDoesNotScheduleAutomaticSelection() {
        #expect(!SelectionAutoInvokeGesture.shouldTrigger(
            mouseDownLocation: CGPoint(x: 20, y: 20),
            mouseUpLocation: CGPoint(x: 21, y: 20),
            clickCount: 1,
            modifierFlags: []
        ))
    }

    @Test("Cancelling automatic selection discards an in-flight stale AX result")
    func cancellingAutomaticSelectionDiscardsInFlightResult() async {
        let settings = makeSettings()
        settings.selectionAutoInvokeEnabled = true
        settings.selectionAutoInvokeDelay = 0

        let overlay = SelectionOverlayStub()
        let reader = SuspendingSelectionReader()
        let coordinator = makeCoordinator(settings: settings, reader: reader, overlay: overlay)

        coordinator.scheduleAutomaticTrigger()
        for _ in 0 ..< 50 where !(await reader.hasStarted()) {
            await Task.yield()
        }
        #expect(await reader.hasStarted())

        coordinator.cancelAutomaticTrigger()
        await reader.finish(with: sampleSnapshot)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(!overlay.hasActionHandler)
    }

    @Test("Drag, multi-click, and Shift selection gestures can trigger automatic selection")
    func explicitSelectionGesturesCanScheduleAutomaticSelection() {
        #expect(SelectionAutoInvokeGesture.shouldTrigger(
            mouseDownLocation: CGPoint(x: 20, y: 20),
            mouseUpLocation: CGPoint(x: 30, y: 20),
            clickCount: 1,
            modifierFlags: []
        ))
        #expect(SelectionAutoInvokeGesture.shouldTrigger(
            mouseDownLocation: CGPoint(x: 20, y: 20),
            mouseUpLocation: CGPoint(x: 20, y: 20),
            clickCount: 2,
            modifierFlags: []
        ))
        #expect(SelectionAutoInvokeGesture.shouldTrigger(
            mouseDownLocation: CGPoint(x: 20, y: 20),
            mouseUpLocation: CGPoint(x: 20, y: 20),
            clickCount: 1,
            modifierFlags: .shift
        ))
    }

    @Test("A missing permission shows one recovery action without reading selected text")
    func missingPermissionDoesNotReadAndDoesNotRepeatRecovery() {
        let settings = makeSettings()
        let checker = SelectionPermissionChecker(isTrusted: false)
        let permissionCoordinator = makePermissionCoordinator(checker: checker)
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
        #expect(checker.requests == [false, false, false, true, false])
    }

    @Test("An allowed permission reads selected text without requesting another prompt")
    func allowedPermissionReadsSilently() async {
        let settings = makeSettings()
        let checker = SelectionPermissionChecker(isTrusted: true)
        let permissionCoordinator = makePermissionCoordinator(checker: checker)
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
        let permissionCoordinator = makePermissionCoordinator(checker: checker)
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

    @Test("Automatic trigger is skipped for a blacklisted source app")
    func automaticTriggerSkipsBlacklistedApp() async {
        let settings = makeSettings()
        settings.selectionAutoInvokeEnabled = true
        settings.selectionAutoInvokeDelay = 0
        settings.selectionAutoInvokeScope = .blacklist
        settings.selectionAutoInvokeBlacklist = ["com.example.Source"]

        let reader = SelectionReaderStub(snapshot: sampleSnapshot)
        let coordinator = makeCoordinator(settings: settings, reader: reader)

        coordinator.scheduleAutomaticTrigger()
        try? await Task.sleep(for: .seconds(0.02))

        #expect(reader.promptRequests.isEmpty)
    }

    @Test("Automatic trigger runs for an allowed whitelisted source app")
    func automaticTriggerRunsForWhitelistedApp() async {
        let settings = makeSettings()
        settings.selectionAutoInvokeEnabled = true
        settings.selectionAutoInvokeDelay = 0
        settings.selectionAutoInvokeScope = .whitelist
        settings.selectionAutoInvokeWhitelist = ["com.example.Source"]

        let reader = SelectionReaderStub(snapshot: sampleSnapshot)
        let coordinator = makeCoordinator(settings: settings, reader: reader)

        coordinator.scheduleAutomaticTrigger()
        for _ in 0 ..< 20 where reader.promptRequests.isEmpty {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
    }

    @Test("Automatic trigger does not show actions for empty selection text")
    func automaticTriggerSkipsEmptySelectionText() async {
        let settings = makeSettings()
        settings.selectionAutoInvokeEnabled = true
        settings.selectionAutoInvokeDelay = 0

        let overlay = SelectionOverlayStub()
        let reader = SelectionReaderStub(snapshot: makeSnapshot(text: " \n "))
        let coordinator = makeCoordinator(settings: settings, reader: reader, overlay: overlay)

        coordinator.scheduleAutomaticTrigger()
        for _ in 0 ..< 20 where reader.promptRequests.isEmpty {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
        #expect(!overlay.hasActionHandler)
    }

    @Test("Automatic trigger ignores a focused value without a real selection range")
    func automaticTriggerSkipsUnconfirmedFocusedValue() async {
        let settings = makeSettings()
        settings.selectionAutoInvokeEnabled = true
        settings.selectionAutoInvokeDelay = 0

        let overlay = SelectionOverlayStub()
        let reader = SelectionReaderStub(snapshot: SelectedTextSnapshot(
            text: "https://example.com/current-page",
            source: sampleSnapshot.source,
            selectedRange: nil,
            anchor: .pointer(CGPoint(x: 20, y: 20)),
            isConfirmedSelection: false
        ))
        let coordinator = makeCoordinator(settings: settings, reader: reader, overlay: overlay)

        coordinator.scheduleAutomaticTrigger()
        for _ in 0 ..< 20 where reader.promptRequests.isEmpty {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
        #expect(!overlay.hasActionHandler)
    }

    @Test("Automatic trigger accepts a genuinely selected URL")
    func automaticTriggerAcceptsSelectedURL() async {
        let settings = makeSettings()
        settings.selectionAutoInvokeEnabled = true
        settings.selectionAutoInvokeDelay = 0

        let overlay = SelectionOverlayStub()
        let reader = SelectionReaderStub(snapshot: makeSnapshot(text: "https://example.com/selected"))
        let coordinator = makeCoordinator(settings: settings, reader: reader, overlay: overlay)

        coordinator.scheduleAutomaticTrigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
        #expect(overlay.hasActionHandler)
    }

    @Test("Action bar receives enabled External Ask actions by default")
    func actionBarIncludesEnabledQuickActionsByDefault() async {
        let settings = makeSettings()
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(settings: settings, reader: SelectionReaderStub(snapshot: sampleSnapshot), overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where overlay.quickActions.isEmpty {
            await Task.yield()
        }

        #expect(overlay.quickActions.map(\.id) == settings.enabledQuickActions.map(\.id))
        #expect(!overlay.quickActions.isEmpty)
        #expect(!overlay.shownPresets.isEmpty)
    }

    @Test("Hiding External Ask in the action bar restores preset-only actions")
    func hidingExternalAskOmitsQuickActions() async {
        let settings = makeSettings()
        settings.selectionActionBarShowsExternalAsk = false
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(settings: settings, reader: SelectionReaderStub(snapshot: sampleSnapshot), overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.quickActions.isEmpty)
        #expect(overlay.hasActionHandler)
    }

    @Test("Hiding prompts in the action bar restores External Ask-only actions")
    func hidingPromptsOmitsPresetActions() async {
        let settings = makeSettings()
        settings.selectionActionBarShowsPrompts = false
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(settings: settings, reader: SelectionReaderStub(snapshot: sampleSnapshot), overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.shownPresets.isEmpty)
        #expect(!overlay.quickActions.isEmpty)
        #expect(overlay.hasActionHandler)
    }

    @Test("Hiding prompts and External Ask does not show the action bar")
    func hidingBothGroupsSkipsTheActionBar() async {
        let settings = makeSettings()
        settings.selectionActionBarShowsPrompts = false
        settings.selectionActionBarShowsExternalAsk = false
        let reader = SelectionReaderStub(snapshot: sampleSnapshot)
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(settings: settings, reader: reader, overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where reader.promptRequests.isEmpty {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
        #expect(!overlay.hasActionHandler)
        #expect(overlay.shownPresets.isEmpty)
        #expect(overlay.quickActions.isEmpty)
    }

    @Test("Action bar keeps prompts and folds trailing External Ask at a combined cap of 8")
    func actionBarCapsCombinedActionsAtEightPreferringPresets() async {
        let settings = makeSettings()
        #expect(settings.saveCustomPromptPreset(PromptPreset(title: "Custom A", instruction: "Do A")))
        #expect(settings.saveCustomPromptPreset(PromptPreset(title: "Custom B", instruction: "Do B")))
        #expect(settings.saveCustomPromptPreset(PromptPreset(title: "Custom C", instruction: "Do C")))
        #expect(settings.saveCustomPromptPreset(PromptPreset(title: "Custom D", instruction: "Do D")))
        settings.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: true)
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(settings: settings, reader: SelectionReaderStub(snapshot: sampleSnapshot), overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where overlay.shownPresets.count < 8 {
            await Task.yield()
        }

        #expect(overlay.shownPresets.count == 8)
        #expect(overlay.quickActions.isEmpty)
        #expect(overlay.shownPresets.map(\.id) == Array(settings.enabledPromptPresets.prefix(8)).map(\.id))
    }

    @Test("Disabling External Ask omits quick actions from the action bar")
    func disablingExternalAskOmitsQuickActions() async {
        let settings = makeSettings()
        settings.externalAskEnabled = false
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(settings: settings, reader: SelectionReaderStub(snapshot: sampleSnapshot), overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.quickActions.isEmpty)
    }

    @Test("Choosing an External Ask action injects selected text into the executor")
    func choosingQuickActionExecutesWithSelectedText() async {
        let settings = makeSettings()
        let overlay = SelectionOverlayStub()
        let executor = RecordingQuickActionExecutor()
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay,
            executor: executor
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where overlay.quickActions.isEmpty {
            await Task.yield()
        }
        overlay.chooseFirstQuickAction()

        #expect(overlay.hideCount == 1)
        #expect(executor.performed.count == 1)
        #expect(overlay.messages.isEmpty)
        guard case let .url(url) = executor.performed.first else {
            Issue.record("expected a URL quick action")
            return
        }
        #expect(url.absoluteString.contains("Selected%20text") || url.absoluteString.contains("Selected text"))
    }

    @Test("A failed External Ask action shows the temporary failure message")
    func failedQuickActionShowsTemporaryFailure() async {
        let settings = makeSettings()
        let overlay = SelectionOverlayStub()
        let executor = RecordingQuickActionExecutor(result: false)
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay,
            executor: executor
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where overlay.quickActions.isEmpty {
            await Task.yield()
        }
        overlay.chooseFirstQuickAction()

        #expect(overlay.hideCount == 1)
        #expect(overlay.messages == [.temporaryFailure])
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

    private func makeCoordinator(
        settings: AppSettings,
        reader: any SelectedTextReading,
        overlay: SelectionOverlayStub = SelectionOverlayStub(),
        executor: any QuickActionExecuting = DefaultQuickActionExecutor()
    ) -> SelectionAssistantCoordinator {
        SelectionAssistantCoordinator(
            settings: settings,
            reader: reader,
            applicationProvider: ForegroundSelectionApplicationStub(source: sampleSnapshot.source),
            permissionCoordinator: makePermissionCoordinator(
                checker: SelectionPermissionChecker(isTrusted: true)
            ),
            settingsOpener: SelectionSettingsOpenerStub(),
            commandCenter: SpotAskCommandCenter(),
            overlay: overlay,
            executor: executor
        )
    }

    private func makePermissionCoordinator(
        checker: SelectionPermissionChecker
    ) -> AccessibilityPermissionCoordinator {
        AccessibilityPermissionCoordinator(
            permissionChecker: checker,
            identityProvider: SelectionIdentityProvider(),
            identityStore: MemorySelectionGrantIdentityStore()
        )
    }

    private var sampleSnapshot: SelectedTextSnapshot {
        makeSnapshot()
    }

    private func makeSnapshot(text: String = "Selected text") -> SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: text,
            source: SelectionSourceApplication(processIdentifier: 42, bundleIdentifier: "com.example.Source", localizedName: "Source"),
            selectedRange: text.isEmpty ? nil : SelectionCharacterRange(location: 0, length: text.count),
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

private struct SelectionIdentityProvider: CodeSigningIdentityProviding {
    func currentIdentity() -> String? { "selection-test-hash" }
}

private final class MemorySelectionGrantIdentityStore: AccessibilityGrantIdentityStoring {
    var lastTrustedIdentity: String?
    var lastResetIdentity: String?
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

private actor SuspendingSelectionReader: SelectedTextReading {
    private var continuation: CheckedContinuation<SelectedTextSnapshot, any Error>?
    private var started = false

    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot {
        started = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func hasStarted() -> Bool {
        started
    }

    func finish(with snapshot: SelectedTextSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

private struct ForegroundSelectionApplicationStub: ForegroundSelectionApplicationProviding {
    let source: SelectionSourceApplication?

    func frontmostApplication() -> SelectionSourceApplication? {
        source
    }

    func currentProcessIdentifier() -> pid_t {
        -1
    }
}

@MainActor
private final class SelectionOverlayStub: SelectionOverlayControlling {
    private(set) var permissionDeniedCount = 0
    private(set) var hideCount = 0
    private(set) var messages: [SelectionFeedback] = []
    private(set) var quickActions: [QuickAction] = []
    private(set) var shownPresets: [PromptPreset] = []
    private var actionHandler: ((PromptPreset) -> Void)?
    private var quickActionHandler: ((QuickAction) -> Void)?

    var hasActionHandler: Bool { actionHandler != nil }

    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        shownPresets = presets
        self.quickActions = externalAsks
        actionHandler = onSelectPreset
        quickActionHandler = onSelectExternalAsk
    }
    func showMessage(_ message: SelectionFeedback) { messages.append(message) }
    func showPermissionDenied(openSettings: @escaping () -> Void) { permissionDeniedCount += 1 }
    func hide() { hideCount += 1 }

    func chooseFirstAction() {
        guard let preset = shownPresets.first else { return }
        actionHandler?(preset)
    }

    func chooseFirstQuickAction() {
        guard let action = quickActions.first else { return }
        quickActionHandler?(action)
    }
}

@MainActor
private final class RecordingQuickActionExecutor: QuickActionExecuting, @unchecked Sendable {
    var result: Bool
    private(set) var performed: [ResolvedQuickAction] = []

    init(result: Bool = true) {
        self.result = result
    }

    func perform(_ resolved: ResolvedQuickAction) -> Bool {
        performed.append(resolved)
        return result
    }
}

@MainActor
private struct SelectionSettingsOpenerStub: AccessibilityPermissionSettingsOpening {
    func openAccessibilitySettings() -> Bool { true }
}
