import Foundation

enum ReasoningTextUpdate: Equatable {
    case unchanged
    case append(String)
    case replace(String)

    static func change(from current: String, to updated: String) -> Self {
        guard current != updated else { return .unchanged }
        guard updated.hasPrefix(current) else { return .replace(updated) }
        return .append(String(updated.dropFirst(current.count)))
    }
}

/// Per-message reasoning expand/collapse rules, extracted so every transition
/// is testable without SwiftUI or the view hierarchy.
struct ReasoningToggleState: Equatable {
    private(set) var isExpanded = false
    private(set) var isPinned = false
    private var previousSnapshot: Snapshot?

    /// Reconciles the latest message snapshot. With `prefersExpanded` enabled,
    /// reasoning opens only while it is still streaming and collapses as soon
    /// as the answer starts or the message becomes terminal. Without it,
    /// reasoning never opens automatically; a manual pin always wins over
    /// automatic state changes.
    mutating func reconcile(message: ChatMessage, prefersExpanded: Bool = false) {
        let snapshot = Snapshot(message: message)
        defer { previousSnapshot = snapshot }

        guard previousSnapshot != nil else {
            isExpanded = snapshot.isStreaming && snapshot.hasReasoning && !snapshot.hasAnswer && prefersExpanded
            return
        }

        guard !isPinned else { return }

        // Reaching any terminal state closes only automatic reasoning; a
        // manual pin survives because collapsing it during a state transition
        // would otherwise move the conversation under the user.
        if snapshot.isTerminal {
            isExpanded = false
            return
        }

        if snapshot.hasAnswer {
            isExpanded = false
        } else if snapshot.hasReasoning, snapshot.isStreaming, prefersExpanded {
            isExpanded = true
        }
    }

    /// Manual expand / collapse gesture. Locks out all future automatisms.
    mutating func toggleByUser() {
        isExpanded.toggle()
        isPinned = true
    }

    private struct Snapshot: Equatable {
        let hasReasoning: Bool
        let hasAnswer: Bool
        let isStreaming: Bool
        let isTerminal: Bool

        init(message: ChatMessage) {
            hasReasoning = !(message.reasoningContent?.isEmpty ?? true)
            hasAnswer = !message.content.isEmpty
            isStreaming = message.state == .streaming
            isTerminal = message.state == .complete
                || message.state == .cancelled
                || message.state == .failed
        }
    }
}

/// Long-lived owner for every assistant message's toggle state. Keeping this
/// above the lazy row hierarchy means transitions are observed even when a row
/// is off-screen or several message fields change in one update.
struct ReasoningToggleStateStore: Equatable {
    private(set) var states: [UUID: ReasoningToggleState] = [:]

    mutating func reconcile(messages: [ChatMessage], prefersExpanded: Bool = false) {
        let assistantMessages = messages.filter { $0.role == .assistant }
        let currentIDs = Set(assistantMessages.map(\.id))
        states = states.filter { currentIDs.contains($0.key) }

        for message in assistantMessages {
            var state = states[message.id] ?? ReasoningToggleState()
            state.reconcile(message: message, prefersExpanded: prefersExpanded)
            states[message.id] = state
        }
    }

    /// Reconciles only one live streaming message. This is the hot path for
    /// token flushes, so it avoids rebuilding and scanning the full history.
    mutating func reconcile(message: ChatMessage, prefersExpanded: Bool = false) {
        var state = states[message.id] ?? ReasoningToggleState()
        state.reconcile(message: message, prefersExpanded: prefersExpanded)
        states[message.id] = state
    }

    func state(for messageID: UUID) -> ReasoningToggleState {
        states[messageID] ?? ReasoningToggleState()
    }

    mutating func toggleByUser(messageID: UUID) {
        var state = states[messageID] ?? ReasoningToggleState()
        state.toggleByUser()
        states[messageID] = state
    }
}
