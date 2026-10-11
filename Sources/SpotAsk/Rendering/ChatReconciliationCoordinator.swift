import Foundation
import Observation

@MainActor
@Observable
final class ChatReconciliationCoordinator {
    var reasoningToggle = ReasoningToggleStateStore()
    var userMessageExpansionState = UserMessageExpansionState()
    var assistantMessageExpansionState = MessageExpansionState()

    @ObservationIgnored private(set) var lastReconciledMessageCount = -1
    @ObservationIgnored private(set) var lastReconciledTailID: UUID?
    @ObservationIgnored private(set) var lastReconciledTailState: MessageState?
    @ObservationIgnored private(set) var lastPrefersExpanded: Bool?

    init() {}

    /// Idempotently reconciles the expansion states for all messages.
    /// Skips duplicate runs when message count, tail message identity/state, and
    /// reasoning expansion preference are unchanged.
    @discardableResult
    func reconcile(messages: [ChatMessage], prefersExpanded: Bool, force: Bool = false) -> Bool {
        let tailMessage = messages.last
        if !force,
           messages.count == lastReconciledMessageCount,
           tailMessage?.id == lastReconciledTailID,
           tailMessage?.state == lastReconciledTailState,
           prefersExpanded == lastPrefersExpanded {
            return false
        }

        lastReconciledMessageCount = messages.count
        lastReconciledTailID = tailMessage?.id
        lastReconciledTailState = tailMessage?.state
        lastPrefersExpanded = prefersExpanded

        var updatedReasoning = reasoningToggle
        updatedReasoning.reconcile(messages: messages, prefersExpanded: prefersExpanded)
        if updatedReasoning != reasoningToggle {
            reasoningToggle = updatedReasoning
        }

        var updatedUserExpansion = userMessageExpansionState
        updatedUserExpansion.reconcile(messages: messages, role: .user)
        if updatedUserExpansion != userMessageExpansionState {
            userMessageExpansionState = updatedUserExpansion
        }

        var updatedAssistantExpansion = assistantMessageExpansionState
        updatedAssistantExpansion.reconcile(messages: messages, role: .assistant)
        if updatedAssistantExpansion != assistantMessageExpansionState {
            assistantMessageExpansionState = updatedAssistantExpansion
        }
        return true
    }

    /// Reconciles reasoning state for an active streaming message when its
    /// reasoning/answer phase changes (e.g. reasoning starts or answer starts).
    @discardableResult
    func reconcileStreamingMessage(_ message: ChatMessage, prefersExpanded: Bool) -> Bool {
        guard message.state == .streaming, let reasoning = message.reasoningContent, !reasoning.isEmpty else { return false }
        var updated = reasoningToggle
        updated.reconcile(message: message, prefersExpanded: prefersExpanded)
        guard updated != reasoningToggle else { return false }
        reasoningToggle = updated
        return true
    }
}
