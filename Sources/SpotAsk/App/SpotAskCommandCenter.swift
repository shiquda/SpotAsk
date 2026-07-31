import SwiftUI

@MainActor
final class SpotAskCommandCenter {
    static let shared = SpotAskCommandCenter()

    private enum DeferredAction {
        case open
        case prepare(PromptPreset)
        case newConversation
        case ask(String, PromptPreset?)
        case showSettings
    }

    private var panelController: SpotAskPanelController?
    private var deferredAction: DeferredAction?

    private init() {}

    func configure(panelController: SpotAskPanelController) {
        self.panelController = panelController
        if let deferredAction {
            self.deferredAction = nil
            perform(deferredAction)
        }
    }

    func setPanelContent(@ViewBuilder _ content: @escaping () -> some View) {
        panelController?.setContent(content)
    }

    func open() {
        guard let panelController else {
            deferredAction = .open
            return
        }
        panelController.show()
    }

    func prepare(promptPreset: PromptPreset) {
        guard panelController != nil else {
            deferredAction = .prepare(promptPreset)
            return
        }
        perform(.prepare(promptPreset))
    }

    func toggle() {
        guard let panelController else {
            deferredAction = .open
            return
        }
        panelController.toggle()
    }

    func close() {
        panelController?.hide()
    }

    func toggleWindowOnTop() {
        panelController?.toggleWindowOnTop()
    }

    func startNewConversation() {
        guard panelController != nil else {
            deferredAction = .newConversation
            return
        }
        perform(.newConversation)
    }

    func ask(_ question: String?, promptPreset: PromptPreset? = nil) {
        let trimmedQuestion = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedQuestion.isEmpty else {
            open()
            return
        }
        guard panelController != nil else {
            deferredAction = .ask(trimmedQuestion, promptPreset)
            return
        }
        perform(.ask(trimmedQuestion, promptPreset))
    }

    func showSettings() {
        guard panelController != nil else {
            deferredAction = .showSettings
            return
        }
        perform(.showSettings)
    }

    private func perform(_ action: DeferredAction) {
        switch action {
        case .open:
            panelController?.show()
        case let .prepare(promptPreset):
            panelController?.show()
            NotificationCenter.default.post(.spotAskSelectPromptPreset(promptPreset))
        case .newConversation:
            panelController?.show()
            NotificationCenter.default.post(name: .spotAskNewConversation, object: nil)
            NotificationCenter.default.post(name: .spotAskFocusInput, object: nil)
        case let .ask(question, promptPreset):
            panelController?.show()
            NotificationCenter.default.post(.spotAskAskQuestion(question, promptPreset: promptPreset))
        case .showSettings:
            panelController?.show()
            NotificationCenter.default.post(name: .spotAskShowSettings, object: nil)
        }
    }
}
