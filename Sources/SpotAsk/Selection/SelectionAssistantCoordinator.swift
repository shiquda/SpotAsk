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
    private var triggerToken = 0
    private var snapshot: SelectedTextSnapshot?
    private var hasShownPermissionRecovery = false
    private var automaticTriggerTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        reader: any SelectedTextReading = AccessibilitySelectedTextReader(),
        applicationProvider: any ForegroundSelectionApplicationProviding = MacOSForegroundSelectionApplicationProvider(),
        permissionCoordinator: AccessibilityPermissionCoordinator,
        settingsOpener: any AccessibilityPermissionSettingsOpening = MacOSAccessibilityPermissionSettingsOpener(),
        commandCenter: SpotAskCommandCenter = .shared,
        overlay: any SelectionOverlayControlling,
        executor: any QuickActionExecuting = DefaultQuickActionExecutor()
    ) {
        self.settings = settings
        self.reader = reader
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
        guard settings.selectionAssistantEnabled else { return }
        guard permissionCoordinator.requestPermissionForSelectionAssistant() == .allowed else {
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
                // An empty or whitespace-only selection must not wake the assistant.
                guard !current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard !requiresConfirmedSelection || current.isConfirmedSelection else { return }
                snapshot = current
                if settings.selectionAssistantMode == .direct {
                    let preset = settings.selectionPromptPreset()
                    if let preset { commandCenter.ask(current.text, promptPreset: preset, selectionSnapshot: current) }
                    else { commandCenter.compose(current.text) }
                } else {
                    let presets = selectionActionBarPresets
                    let externalAsks = selectionActionBarExternalAsks
                    guard !presets.isEmpty || !externalAsks.isEmpty else { return }
                    overlay.showActions(
                        snapshot: current,
                        presets: presets,
                        externalAsks: externalAsks,
                        showsLabels: settings.selectionActionBarShowsLabels,
                        shortcutForPreset: { [settings] preset in
                            settings.shortcut(for: .promptPreset(preset.id))
                        },
                        shortcutForExternalAsk: { [settings] action in
                            settings.shortcut(for: .quickAction(action.id))
                        },
                        onSelectPreset: { [weak self] preset in
                            self?.apply(preset: preset)
                        },
                        onSelectExternalAsk: { [weak self] action in
                            self?.performExternalAsk(action, snapshot: current)
                        }
                    )
                }
            } catch let error as SelectionReadingError {
                guard token == triggerToken else { return }
                if showsFeedback { overlay.showMessage(error.feedbackMessage) }
            } catch {
                guard token == triggerToken else { return }
                if showsFeedback { overlay.showMessage(.temporaryFailure) }
            }
        }
    }

    private func apply(preset: PromptPreset) {
        guard let snapshot else { return }
        overlay.hide()
        self.snapshot = nil
        commandCenter.ask(snapshot.text, promptPreset: settings.enabledPromptPreset(id: preset.id), selectionSnapshot: snapshot)
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

    private func performExternalAsk(_ action: QuickAction, snapshot: SelectedTextSnapshot) {
        overlay.hide()
        self.snapshot = nil
        guard settings.externalAskEnabled,
              settings.selectionActionBarShowsExternalAsk,
              let currentAction = settings.enabledQuickAction(id: action.id)
        else {
            overlay.showMessage(.temporaryFailure)
            return
        }
        let resolved: ResolvedQuickAction?
        switch currentAction.kind {
        case let .web(template), let .uriScheme(template):
            resolved = QuickActionBuilder.makeURL(template: template, query: snapshot.text).map { .url($0) }
        case let .terminal(template):
            resolved = QuickActionBuilder.makeTerminalCommand(template: template, query: snapshot.text).map { .terminalCommand($0) }
        }
        guard let resolved else {
            overlay.showMessage(.temporaryFailure)
            return
        }
        if !executor.perform(resolved) {
            overlay.showMessage(.temporaryFailure)
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
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    )
    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        shortcutForPreset: ((PromptPreset) -> InAppShortcut?)?,
        shortcutForExternalAsk: ((QuickAction) -> InAppShortcut?)?,
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
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            shortcutForPreset: nil,
            shortcutForExternalAsk: nil,
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
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            onSelectPreset: onSelectPreset,
            onSelectExternalAsk: onSelectExternalAsk
        )
    }
}
