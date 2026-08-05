import Foundation

/// Per-message reasoning expand/collapse rules, extracted so every transition
/// is testable without SwiftUI or the view hierarchy.
struct ReasoningToggleState: Equatable {
    private(set) var isExpanded = false
    private(set) var isPinned = false
    private var previousSnapshot: Snapshot?

    /// Reconciles the latest complete message snapshot. On first observation,
    /// a live reasoning-only response is expanded; restored history follows
    /// `prefersExpanded`. Later snapshots detect content transitions regardless
    /// of how many fields changed in the same render pass.
    mutating func reconcile(message: ChatMessage, prefersExpanded: Bool = false) {
        let snapshot = Snapshot(message: message)
        defer { previousSnapshot = snapshot }

        guard let previousSnapshot else {
            if snapshot.isStreaming, snapshot.hasReasoning, !snapshot.hasAnswer {
                isExpanded = true
            } else if prefersExpanded, snapshot.hasReasoning {
                isExpanded = true
            }
            return
        }

        // Reaching any terminal state closes reasoning unless the user asked
        // for thinking to stay expanded by default. A manual pin still wins.
        if snapshot.isTerminal {
            guard prefersExpanded, snapshot.hasReasoning else {
                isExpanded = false
                return
            }
            if isPinned { return }
            isExpanded = true
            return
        }

        guard !isPinned else { return }

        if !previousSnapshot.hasAnswer, snapshot.hasAnswer {
            if !prefersExpanded {
                isExpanded = false
            }
        } else if !previousSnapshot.hasReasoning,
                  snapshot.hasReasoning,
                  snapshot.isStreaming,
                  !snapshot.hasAnswer {
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

    func state(for messageID: UUID) -> ReasoningToggleState {
        states[messageID] ?? ReasoningToggleState()
    }

    mutating func toggleByUser(messageID: UUID) {
        var state = states[messageID] ?? ReasoningToggleState()
        state.toggleByUser()
        states[messageID] = state
    }
}
