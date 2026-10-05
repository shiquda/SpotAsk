import Foundation

@MainActor
final class ChatReconciliationCoordinator {
    var reasoningToggle = ReasoningToggleStateStore()
    var userMessageExpansionState = UserMessageExpansionState()
    var assistantMessageExpansionState = MessageExpansionState()

    private(set) var lastReconciledMessageCount = -1
    private(set) var lastReconciledTailID: UUID?
    private(set) var lastReconciledTailState: MessageState?
    private(set) var lastPrefersExpanded: Bool?
    private(set) var lastStreamingReasoningCount = -1

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

        reasoningToggle.reconcile(messages: messages, prefersExpanded: prefersExpanded)
        userMessageExpansionState.reconcile(messages: messages, role: .user)
        assistantMessageExpansionState.reconcile(messages: messages, role: .assistant)
        return true
    }

    /// Reconciles reasoning state for an active streaming message only when reasoning content grows.
    @discardableResult
    func reconcileStreamingMessage(_ message: ChatMessage, prefersExpanded: Bool) -> Bool {
        guard message.state == .streaming, let reasoning = message.reasoningContent, !reasoning.isEmpty else { return false }
        if reasoning.count == lastStreamingReasoningCount { return false }
        lastStreamingReasoningCount = reasoning.count
        reasoningToggle.reconcile(message: message, prefersExpanded: prefersExpanded)
        return true
    }
}
