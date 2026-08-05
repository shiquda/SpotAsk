import AppKit
import Foundation

@MainActor
final class SelectionAssistantCoordinator {
    private let settings: AppSettings
    private let reader: any SelectedTextReading
    private let commandCenter: SpotAskCommandCenter
    private let overlay: any SelectionOverlayControlling
    private var triggerToken = 0
    private var snapshot: SelectedTextSnapshot?

    init(
        settings: AppSettings,
        reader: any SelectedTextReading = AccessibilitySelectedTextReader(),
        commandCenter: SpotAskCommandCenter = .shared,
        overlay: any SelectionOverlayControlling
    ) {
        self.settings = settings
        self.reader = reader
        self.commandCenter = commandCenter
        self.overlay = overlay
    }

    func trigger() {
        guard settings.selectionAssistantEnabled else { return }
        triggerToken += 1
        let token = triggerToken
        Task { [weak self] in
            guard let self else { return }
            do {
                let current = try await reader.readSelection(promptForPermission: true)
                guard token == triggerToken else { return }
                snapshot = current
                if settings.selectionAssistantMode == .direct {
                    let preset = settings.selectionPromptPreset()
                    if let preset { commandCenter.ask(current.text, promptPreset: preset) }
                    else { commandCenter.compose(current.text) }
                } else {
                    overlay.showActions(snapshot: current, presets: Array(settings.enabledPromptPresets.prefix(4))) { [weak self] preset in
                        self?.apply(preset: preset)
                    }
                }
            } catch let error as SelectionReadingError {
                guard token == triggerToken else { return }
                overlay.showMessage(error.feedbackMessage)
            } catch {
                guard token == triggerToken else { return }
                overlay.showMessage(.temporaryFailure)
            }
        }
    }

    private func apply(preset: PromptPreset) {
        guard let initial = snapshot else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let current = try await reader.readSelection(promptForPermission: false)
                guard current == initial else {
                    overlay.showMessage(.selectionChanged)
                    return
                }
                overlay.hide()
                commandCenter.ask(current.text, promptPreset: settings.enabledPromptPreset(id: preset.id))
            } catch {
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
    func showActions(snapshot: SelectedTextSnapshot, presets: [PromptPreset], onSelect: @escaping (PromptPreset) -> Void)
    func showMessage(_ message: SelectionFeedback)
    func hide()
}
