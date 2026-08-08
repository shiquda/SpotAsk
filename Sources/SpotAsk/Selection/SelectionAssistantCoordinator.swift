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
        overlay: any SelectionOverlayControlling
    ) {
        self.settings = settings
        self.reader = reader
        self.applicationProvider = applicationProvider
        self.permissionCoordinator = permissionCoordinator
        self.settingsOpener = settingsOpener
        self.commandCenter = commandCenter
        self.overlay = overlay
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
            trigger(showsFeedback: false)
        }
    }

    func cancelAutomaticTrigger() {
        automaticTriggerTask?.cancel()
        automaticTriggerTask = nil
    }

    private func trigger(showsFeedback: Bool) {
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
                snapshot = current
                if settings.selectionAssistantMode == .direct {
                    let preset = settings.selectionPromptPreset()
                    if let preset { commandCenter.ask(current.text, promptPreset: preset, selectionSnapshot: current) }
                    else { commandCenter.compose(current.text) }
                } else {
                    overlay.showActions(
                        snapshot: current,
                        presets: Array(settings.enabledPromptPresets.prefix(4)),
                        showsLabels: settings.selectionActionBarShowsLabels
                    ) { [weak self] preset in
                        self?.apply(preset: preset)
                    }
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
        showsLabels: Bool,
        onSelect: @escaping (PromptPreset) -> Void
    )
    func showMessage(_ message: SelectionFeedback)
    func showPermissionDenied(openSettings: @escaping () -> Void)
    func hide()
}
