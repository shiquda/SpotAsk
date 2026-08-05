import SwiftUI

enum SpotAskCommandAction: Equatable {
    case focusInput
    case compose(String, PromptPreset?)
    case prepare(PromptPreset)
    case newConversation
    case ask(String, PromptPreset?)
    case showSettings
}

@MainActor
final class SpotAskCommandCenter {
    static let shared = SpotAskCommandCenter()

    private var panelController: (any SpotAskPanelControlling)?
    private var hasPanelContent = false
    private var pendingActions: [SpotAskCommandAction] = []
    private var actionConsumer: ((SpotAskCommandAction) -> Void)?

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

    func ask(_ question: String?, promptPreset: PromptPreset? = nil) {
        let trimmedQuestion = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedQuestion.isEmpty else {
            open()
            return
        }
        enqueue(.ask(trimmedQuestion, promptPreset))
    }

    func showSettings() {
        enqueue(.showSettings)
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
