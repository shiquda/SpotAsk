import SwiftUI

enum SpotAskCommandAction: Equatable {
    case focusInput
    case compose(String, PromptPreset?)
    case prepare(PromptPreset)
    case newConversation
    case ask(String, PromptPreset?, SelectedTextSnapshot? = nil)
    case addToChat(String)
}

@MainActor
final class SpotAskCommandCenter {
    static let shared = SpotAskCommandCenter()

    private var panelController: (any SpotAskPanelControlling)?
    private var hasPanelContent = false
    private var pendingActions: [SpotAskCommandAction] = []
    private var pendingSettingsRequests: [SettingsSection?] = []
    private var actionConsumer: ((SpotAskCommandAction) -> Void)?
    private var settingsPresenter: ((SettingsSection?) -> Void)?

    init() {}

    func configure(panelController: any SpotAskPanelControlling) {
        self.panelController = panelController
        showAndDeliverPendingActions()
    }

    func setPanelContent(@ViewBuilder _ content: @escaping () -> some View) {
        panelController?.setContent { AnyView(content()) }
        hasPanelContent = true
        showAndDeliverPendingActions()
    }

    /// The SwiftUI view calls this from `onAppear`, after its action handling
    /// closures are installed. Actions received before then stay buffered.
    func setActionConsumer(_ consumer: @escaping (SpotAskCommandAction) -> Void) {
        actionConsumer = consumer
        showAndDeliverPendingActions()
    }

    /// The presenter receives the requested settings page, or `nil` for plain
    /// Settings. Settings requests never enter the chat panel queue: they wait
    /// in their own queue and are delivered the moment a presenter exists, so a
    /// cold-start deep link neither needs the panel nor opens it.
    func setSettingsPresenter(_ presenter: @escaping (SettingsSection?) -> Void) {
        settingsPresenter = presenter
        deliverPendingSettingsRequests()
    }

    func open() {
        enqueue(.focusInput)
    }

    func compose(_ question: String, promptPreset: PromptPreset? = nil) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            open()
            return
        }
        enqueue(.compose(trimmedQuestion, promptPreset))
    }
    func addToChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            open()
            return
        }
        enqueue(.addToChat(trimmed))
    }


    func prepare(promptPreset: PromptPreset) {
        enqueue(.prepare(promptPreset))
    }

    func toggle() {
        guard let panelController else {
            enqueue(.focusInput)
            return
        }
        if panelController.isVisible {
            panelController.toggle()
        } else {
            enqueue(.focusInput)
        }
    }

    func close() {
        panelController?.hide()
    }

    func toggleWindowOnTop() {
        panelController?.toggleWindowOnTop()
    }

    func startNewConversation() {
        enqueue(.newConversation)
    }

    func ask(_ question: String?, promptPreset: PromptPreset? = nil, selectionSnapshot: SelectedTextSnapshot? = nil) {
        let trimmedQuestion = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedQuestion.isEmpty else {
            open()
            return
        }
        enqueue(.ask(trimmedQuestion, promptPreset, selectionSnapshot))
    }

    func showSettings(section: SettingsSection? = nil) {
        if let settingsPresenter {
            settingsPresenter(section)
        } else {
            pendingSettingsRequests.append(section)
        }
    }

    private func deliverPendingSettingsRequests() {
        guard let settingsPresenter, !pendingSettingsRequests.isEmpty else { return }
        let requests = pendingSettingsRequests
        pendingSettingsRequests.removeAll()
        requests.forEach(settingsPresenter)
    }

    private func enqueue(_ action: SpotAskCommandAction) {
        pendingActions.append(action)
        showAndDeliverPendingActions()
    }

    private func showAndDeliverPendingActions() {
        guard hasPanelContent, let panelController, !pendingActions.isEmpty else { return }
        panelController.show()
        guard let actionConsumer else { return }

        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach(actionConsumer)
    }
}
