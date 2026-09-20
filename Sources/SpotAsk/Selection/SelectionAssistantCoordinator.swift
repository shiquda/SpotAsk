import AppKit
import Foundation

@MainActor
final class SelectionAssistantCoordinator {
    private let settings: AppSettings
    private let reader: any SelectedTextReading
    private let applicationProvider: any ForegroundSelectionApplicationProviding
    private let permissionCoordinator: AccessibilityPermissionCoordinator
    private let settingsOpener: any AccessibilityPermissionSettingsOpening
    private let commandCenter: SpotAskCommandCenter
    private let overlay: any SelectionOverlayControlling
    private let executor: any QuickActionExecuting
    private let clipboardAssistedPolicy: ClipboardAssistedSelectionPolicy
    private let deferredTextReader: (any DeferredSelectionTextReading)?
    private var triggerToken = 0
    private var snapshot: SelectedTextSnapshot?
    private var hasShownPermissionRecovery = false
    private var automaticTriggerTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        reader: (any SelectedTextReading)? = nil,
        applicationProvider: any ForegroundSelectionApplicationProviding = MacOSForegroundSelectionApplicationProvider(),
        permissionCoordinator: AccessibilityPermissionCoordinator,
        settingsOpener: any AccessibilityPermissionSettingsOpening = MacOSAccessibilityPermissionSettingsOpener(),
        commandCenter: SpotAskCommandCenter = .shared,
        overlay: any SelectionOverlayControlling,
        executor: any QuickActionExecuting = DefaultQuickActionExecutor()
    ) {
        // The reader works on its own queue, so it cannot read main-actor
        // settings mid-read. Keep a mirror of the clipboard preferences and
        // refresh it whenever the selection settings change.
        let clipboardAssistedPolicy = ClipboardAssistedSelectionPolicy()
        clipboardAssistedPolicy.update(
            enabled: settings.clipboardAssistedSelectionEnabled,
            identifiers: settings.clipboardAssistedSelectionAppIdentifiers
        )
        self.clipboardAssistedPolicy = clipboardAssistedPolicy
        self.settings = settings
        let reader = reader ?? AccessibilitySelectedTextReader(clipboardAssistedPolicy: clipboardAssistedPolicy)
        self.reader = reader
        // A reader that can find a selection without reading it hands the copy
        // to the moment an action runs: `readDeferredSelectionText`.
        deferredTextReader = reader as? any DeferredSelectionTextReading
        self.applicationProvider = applicationProvider
        self.permissionCoordinator = permissionCoordinator
        self.settingsOpener = settingsOpener
        self.commandCenter = commandCenter
        self.overlay = overlay
        self.executor = executor
    }

    func trigger() {
        trigger(showsFeedback: true)
    }

    func scheduleAutomaticTrigger() {
        automaticTriggerTask?.cancel()
        guard settings.selectionAssistantEnabled,
              settings.selectionAssistantMode == .actionBar,
              settings.selectionAutoInvokeEnabled else { return }
        automaticTriggerTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(settings.selectionAutoInvokeDelay))
            guard !Task.isCancelled else { return }
            guard settings.allowsAutomaticInvoke(from: applicationProvider.frontmostApplication()) else { return }
            trigger(showsFeedback: false, requiresConfirmedSelection: true)
        }
    }

    func cancelAutomaticTrigger() {
        automaticTriggerTask?.cancel()
        automaticTriggerTask = nil
        // AX reads can outlive the delay task. Invalidate an in-flight result so
        // a click that clears the visual selection cannot revive stale text.
        triggerToken += 1
    }

    private func trigger(showsFeedback: Bool, requiresConfirmedSelection: Bool = false) {
        guard settings.selectionAssistantEnabled else {
            cancelInFlightAndDiscardPresentedSelection()
            return
        }
        guard permissionCoordinator.requestPermissionForSelectionAssistant() == .allowed else {
            discardPresentedSelection()
            guard showsFeedback, !hasShownPermissionRecovery else { return }
            hasShownPermissionRecovery = true
            overlay.showPermissionDenied { [weak self] in
                self?.settingsOpener.openAccessibilitySettings()
            }
            return
        }
        hasShownPermissionRecovery = false
        triggerToken += 1
        let token = triggerToken
        Task { [weak self] in
            guard let self else { return }
            do {
                let current = try await reader.readSelection(promptForPermission: false)
                guard token == triggerToken else { return }
                // An empty or whitespace-only selection must not wake the
                // assistant. A clipboard-assisted selection is confirmed by its
                // presence alone: its text is only read once an action runs.
                guard current.hasUsableSelection else {
                    discardPresentedSelection()
                    return
                }
                guard !requiresConfirmedSelection || current.isConfirmedSelection else {
                    discardPresentedSelection()
                    return
                }
                snapshot = current
                if settings.selectionAssistantMode == .direct {
                    let preset = settings.selectionPromptPreset()
                    let resolved = await resolveText(of: current)
                    guard token == triggerToken else { return }
                    guard let resolved else {
                        discardPresentedSelection()
                        if showsFeedback { overlay.showMessage(.noSelection) }
                        return
                    }
                    snapshot = resolved
                    if let preset { commandCenter.ask(resolved.text, promptPreset: preset, selectionSnapshot: resolved) }
                    else { commandCenter.compose(resolved.text) }
                } else {
                    let showsChat = settings.selectionActionBarShowsChatAction
                    let presets = selectionActionBarPresets
                    let externalAsks = selectionActionBarExternalAsks
                    guard showsChat || !presets.isEmpty || !externalAsks.isEmpty else {
                        discardPresentedSelection()
                        return
                    }
                    overlay.showActions(
                        snapshot: current,
                        showsChat: showsChat,
                        presets: presets,
                        externalAsks: externalAsks,
                        showsLabels: settings.selectionActionBarShowsLabels,
                        shortcutForChat: nil,
                        shortcutForPreset: { [settings] preset in
                            settings.shortcut(for: .promptPreset(preset.id))
                        },
                        shortcutForExternalAsk: { [settings] action in
                            settings.shortcut(for: .quickAction(action.id))
                        },
                        onSelectChat: { [weak self] in
                            self?.addToChat()
                        },
                        onSelectPreset: { [weak self] preset in
                            self?.apply(preset: preset)
                        },
                        onSelectExternalAsk: { [weak self] action in
                            self?.performExternalAsk(action)
                        }
                    )
                }
            } catch let error as SelectionReadingError {
                guard token == triggerToken else { return }
                snapshot = nil
                overlay.hide()
                if showsFeedback { overlay.showMessage(error.feedbackMessage) }
            } catch {
                guard token == triggerToken else { return }
                snapshot = nil
                overlay.hide()
                if showsFeedback { overlay.showMessage(.temporaryFailure) }
            }
        }
    }

    func handleSettingsChanged() {
        clipboardAssistedPolicy.update(
            enabled: settings.clipboardAssistedSelectionEnabled,
            identifiers: settings.clipboardAssistedSelectionAppIdentifiers
        )
        guard settings.selectionAssistantEnabled else {
            cancelInFlightAndDiscardPresentedSelection()
            return
        }
    }

    private func cancelInFlightAndDiscardPresentedSelection() {
        triggerToken += 1
        automaticTriggerTask?.cancel()
        automaticTriggerTask = nil
        discardPresentedSelection()
    }

    private func discardPresentedSelection() {
        snapshot = nil
        overlay.hide()
    }

    /// Hides the action bar and hands the selection over, so an action that
    /// needs the text can read it without the overlay lingering.
    private func takePresentedSelection() -> SelectedTextSnapshot? {
        guard let snapshot else { return nil }
        overlay.hide()
        self.snapshot = nil
        return snapshot
    }

    /// The selection an action should act on, with its text in hand.
    ///
    /// Clipboard-assisted selections arrive without text: the host app is asked
    /// to copy it now, at the moment an action runs. What it copies is the text
    /// the action uses, which is the whole point of that mode — anything the
    /// app misreports through Accessibility never becomes an answer or a prompt.
    private func resolveText(of presented: SelectedTextSnapshot) async -> SelectedTextSnapshot? {
        guard presented.textOrigin == .deferredToPasteboard else { return presented }
        let text = await deferredTextReader?.readDeferredSelectionText(for: presented) ?? presented.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return presented.resolvingText(text)
    }

    private func apply(preset: PromptPreset) {
        guard let presented = takePresentedSelection() else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let resolved = await resolveText(of: presented) else {
                overlay.showMessage(.noSelection)
                return
            }
            commandCenter.ask(
                resolved.text,
                promptPreset: settings.enabledPromptPreset(id: preset.id),
                selectionSnapshot: resolved
            )
        }
    }

    private func addToChat() {
        guard let presented = takePresentedSelection() else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let resolved = await resolveText(of: presented) else {
                overlay.showMessage(.noSelection)
                return
            }
            commandCenter.addToChat(resolved.text)
        }
    }

    private var selectionActionBarPresets: [PromptPreset] {
        guard settings.selectionActionBarShowsPrompts else { return [] }
        return Array(settings.enabledPromptPresets.prefix(SelectionActionBarLayout.maxTotalActions))
    }

    private var selectionActionBarExternalAsks: [QuickAction] {
        guard settings.externalAskEnabled,
              settings.selectionActionBarShowsExternalAsk
        else { return [] }
        let remaining = max(0, SelectionActionBarLayout.maxTotalActions - selectionActionBarPresets.count)
        return Array(settings.enabledQuickActions.prefix(remaining))
    }

    private func performExternalAsk(_ action: QuickAction) {
        guard let presented = takePresentedSelection() else { return }
        guard settings.externalAskEnabled,
              settings.selectionActionBarShowsExternalAsk,
              let currentAction = settings.enabledQuickAction(id: action.id)
        else {
            overlay.showMessage(.temporaryFailure)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard let resolved = await resolveText(of: presented) else {
                overlay.showMessage(.noSelection)
                return
            }
            if !QuickActionLaunch.perform(currentAction, query: resolved.text, executor: executor) {
                overlay.showMessage(.temporaryFailure)
            }
        }
    }
}

enum SelectionFeedback: Equatable {
    case permissionDenied, noSelection, unsupported, temporaryFailure, selectionChanged, sensitiveField
}

extension SelectionReadingError {
    var feedbackMessage: SelectionFeedback {
        switch self {
        case .permissionDenied: .permissionDenied
        case .noSelection, .noExternalSelection: .noSelection
        case .sensitiveField: .sensitiveField
        case .unsupportedApplication, .accessibilityDisabled: .unsupported
        default: .temporaryFailure
        }
    }
}

@MainActor
protocol SelectionOverlayControlling: AnyObject {
    func showActions(
        snapshot: SelectedTextSnapshot,
        showsChat: Bool,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        shortcutForChat: InAppShortcut?,
        shortcutForPreset: ((PromptPreset) -> InAppShortcut?)?,
        shortcutForExternalAsk: ((QuickAction) -> InAppShortcut?)?,
        onSelectChat: @escaping () -> Void,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    )
    func showMessage(_ message: SelectionFeedback)
    func showPermissionDenied(openSettings: @escaping () -> Void)
    func hide()
}

extension SelectionOverlayControlling {

    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        showActions(
            snapshot: snapshot,
            showsChat: false,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            shortcutForChat: nil,
            shortcutForPreset: nil,
            shortcutForExternalAsk: nil,
            onSelectChat: {},
            onSelectPreset: onSelectPreset,
            onSelectExternalAsk: onSelectExternalAsk
        )
    }

    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        shortcutForPreset: ((PromptPreset) -> InAppShortcut?)?,
        shortcutForExternalAsk: ((QuickAction) -> InAppShortcut?)?,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        showActions(
            snapshot: snapshot,
            showsChat: false,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            shortcutForChat: nil,
            shortcutForPreset: shortcutForPreset,
            shortcutForExternalAsk: shortcutForExternalAsk,
            onSelectChat: {},
            onSelectPreset: onSelectPreset,
            onSelectExternalAsk: onSelectExternalAsk
        )
    }
}
