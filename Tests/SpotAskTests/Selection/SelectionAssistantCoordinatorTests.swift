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

    @Test("Manual trigger skips empty selection text")
    func manualTriggerSkipsEmptySelectionText() async {
        let overlay = SelectionOverlayStub()
        let reader = SelectionReaderStub(snapshot: makeSnapshot(text: " \n\t "))
        let coordinator = makeCoordinator(settings: makeSettings(), reader: reader, overlay: overlay)

        coordinator.trigger()
        for _ in 0 ..< 20 where reader.promptRequests.isEmpty {
            await Task.yield()
        }

        #expect(reader.promptRequests == [false])
        #expect(!overlay.hasActionHandler)
    }

    @Test("Action bar includes enabled External Ask actions")
    func actionBarIncludesEnabledExternalAsks() async {
        let settings = makeSettings()
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.shownExternalAsks.map(\.id) == [QuickAction.BuiltInID.chatGPT])
        #expect(!overlay.shownPresets.isEmpty)
    }

    @Test("Action bar hides External Ask when the selection switch is off")
    func actionBarHidesExternalAskWhenSelectionSwitchOff() async {
        let settings = makeSettings()
        settings.selectionActionBarShowsExternalAsk = false
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.shownExternalAsks.isEmpty)
        #expect(!overlay.shownPresets.isEmpty)
    }

    @Test("Action bar hides External Ask when the master switch is off")
    func actionBarHidesExternalAskWhenMasterSwitchOff() async {
        let settings = makeSettings()
        settings.externalAskEnabled = false
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.shownExternalAsks.isEmpty)
    }

    @Test("Action bar shows at most three External Ask actions")
    func actionBarCapsExternalAsksAtThree() async {
        let settings = makeSettings()
        settings.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: true)
        #expect(settings.saveCustomQuickAction(QuickAction(
            name: "Perplexity",
            kind: .web(urlTemplate: "https://www.perplexity.ai/search?q={query}")
        )))
        #expect(settings.saveCustomQuickAction(QuickAction(
            name: "Phind",
            kind: .web(urlTemplate: "https://www.phind.com/search?q={query}")
        )))
        let overlay = SelectionOverlayStub()
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }

        #expect(overlay.shownExternalAsks.count == 3)
        #expect(overlay.shownExternalAsks.map(\.id) == Array(settings.enabledQuickActions.prefix(3).map(\.id)))
    }

    @Test("Choosing External Ask substitutes the captured query and hides the overlay")
    func choosingExternalAskSubstitutesQuery() async {
        let overlay = SelectionOverlayStub()
        let executor = RecordingQuickActionExecutor()
        let snapshot = makeSnapshot(text: "hello 世界 & =\n")
        let coordinator = makeCoordinator(
            settings: makeSettings(),
            reader: SelectionReaderStub(snapshot: snapshot),
            overlay: overlay,
            executor: executor
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }
        overlay.chooseFirstExternalAsk()

        #expect(overlay.hideCount == 1)
        #expect(overlay.messages.isEmpty)
        #expect(executor.performed == [
            .url(URL(string: "https://chatgpt.com/?q=hello%20%E4%B8%96%E7%95%8C%20%26%20%3D")!)
        ])
    }

    @Test("Choosing a terminal External Ask shell-escapes the captured query")
    func choosingTerminalExternalAskEscapesQuery() async {
        let settings = makeSettings()
        let terminal = QuickAction(
            name: "OMP",
            kind: .terminal(commandTemplate: "omp {query}")
        )
        #expect(settings.saveCustomQuickAction(terminal))
        settings.setQuickActionEnabled(id: QuickAction.BuiltInID.chatGPT, isEnabled: false)
        let overlay = SelectionOverlayStub()
        let executor = RecordingQuickActionExecutor()
        let coordinator = makeCoordinator(
            settings: settings,
            reader: SelectionReaderStub(snapshot: makeSnapshot(text: "don't fail")),
            overlay: overlay,
            executor: executor
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }
        overlay.chooseFirstExternalAsk()

        #expect(executor.performed == [.terminalCommand("omp 'don'\\''t fail'")])
        #expect(overlay.hideCount == 1)
    }

    @Test("A failed External Ask shows a temporary failure after closing the bar")
    func failedExternalAskShowsTemporaryFailure() async {
        let overlay = SelectionOverlayStub()
        let executor = RecordingQuickActionExecutor()
        executor.result = false
        let coordinator = makeCoordinator(
            settings: makeSettings(),
            reader: SelectionReaderStub(snapshot: sampleSnapshot),
            overlay: overlay,
            executor: executor
        )

        coordinator.trigger()
        for _ in 0 ..< 20 where !overlay.hasActionHandler {
            await Task.yield()
        }
        overlay.chooseFirstExternalAsk()

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
        executor: any QuickActionExecuting = RecordingQuickActionExecutor()
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
    private(set) var shownPresets: [PromptPreset] = []
    private(set) var shownExternalAsks: [QuickAction] = []
    private var presetHandler: ((PromptPreset) -> Void)?
    private var externalAskHandler: ((QuickAction) -> Void)?

    var hasActionHandler: Bool { presetHandler != nil || externalAskHandler != nil }

    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        shownPresets = presets
        shownExternalAsks = externalAsks
        presetHandler = onSelectPreset
        externalAskHandler = onSelectExternalAsk
    }
    func showMessage(_ message: SelectionFeedback) { messages.append(message) }
    func showPermissionDenied(openSettings: @escaping () -> Void) { permissionDeniedCount += 1 }
    func hide() { hideCount += 1 }

    func chooseFirstAction() {
        guard let preset = shownPresets.first else { return }
        presetHandler?(preset)
    }

    func chooseFirstExternalAsk() {
        guard let action = shownExternalAsks.first else { return }
        externalAskHandler?(action)
    }
}

@MainActor
private final class RecordingQuickActionExecutor: QuickActionExecuting, @unchecked Sendable {
    var result = true
    private(set) var performed: [ResolvedQuickAction] = []

    func perform(_ resolved: ResolvedQuickAction) -> Bool {
        performed.append(resolved)
        return result
    }
}

@MainActor
private struct SelectionSettingsOpenerStub: AccessibilityPermissionSettingsOpening {
    func openAccessibilitySettings() -> Bool { true }
}
