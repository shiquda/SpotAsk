import XCTest
@testable import SpotAsk

final class ReasoningToggleStateTests: XCTestCase {
    func testReasoningTextUpdateAppendsOnlyTheNewSuffix() {
        XCTAssertEqual(
            ReasoningTextUpdate.change(from: "first", to: "first second"),
            .append(" second")
        )
    }

    func testReasoningTextUpdateReplacesWhenContentIsRewritten() {
        XCTAssertEqual(
            ReasoningTextUpdate.change(from: "draft", to: "revised"),
            .replace("revised")
        )
    }

    func testReasoningTextUpdateSkipsUnchangedContent() {
        XCTAssertEqual(
            ReasoningTextUpdate.change(from: "same", to: "same"),
            .unchanged
        )
    }

    func testInitialHistoricalReasoningIsCollapsed() {
        let message = assistant(reasoning: "Earlier work", state: .complete)
        var store = ReasoningToggleStateStore()

        store.reconcile(messages: [message])

        XCTAssertFalse(store.state(for: message.id).isExpanded)
    }

    func testInitialStreamingReasoningExpandsOnlyWhenDefaultEnabled() {
        let message = assistant(reasoning: "Working", state: .streaming)
        var store = ReasoningToggleStateStore()

        store.reconcile(messages: [message])
        XCTAssertFalse(store.state(for: message.id).isExpanded)

        store.reconcile(messages: [message], prefersExpanded: true)
        XCTAssertTrue(store.state(for: message.id).isExpanded)
    }

    func testStreamingReasoningStaysCollapsedWhenDefaultDisabled() {
        let message = assistant(reasoning: "Working", state: .streaming)
        var store = ReasoningToggleStateStore()

        store.reconcile(messages: [message])

        XCTAssertFalse(store.state(for: message.id).isExpanded)
    }

    func testDefaultEnabledCollapsesReasoningWhenAnswerStarts() {
        var message = assistant(reasoning: "Working", state: .streaming)
        var store = ReasoningToggleStateStore()
        store.reconcile(messages: [message], prefersExpanded: true)
        XCTAssertTrue(store.state(for: message.id).isExpanded)

        message.content = "Partial answer"
        store.reconcile(messages: [message], prefersExpanded: true)

        XCTAssertFalse(store.state(for: message.id).isExpanded)
    }

    func testAnswerBeforeReasoningDoesNotReopen() {
        var message = assistant(content: "Answer", state: .streaming)
        var store = ReasoningToggleStateStore()
        store.reconcile(messages: [message])

        message.reasoningContent = "Late reasoning"
        store.reconcile(messages: [message])

        XCTAssertFalse(store.state(for: message.id).isExpanded)
    }

    func testTerminalStatesPreservePreviouslyUserExpandedReasoning() {
        for terminalState in [MessageState.complete, .cancelled, .failed] {
            var message = assistant(reasoning: "Working", state: .streaming)
            var store = ReasoningToggleStateStore()
            store.reconcile(messages: [message], prefersExpanded: true)
            store.toggleByUser(messageID: message.id)
            store.toggleByUser(messageID: message.id)
            XCTAssertTrue(store.state(for: message.id).isExpanded)

            message.state = terminalState
            store.reconcile(messages: [message])

            XCTAssertTrue(store.state(for: message.id).isExpanded, "\(terminalState) should preserve user-expanded reasoning")
            XCTAssertTrue(store.state(for: message.id).isPinned)
        }
    }

    func testTerminalStatePreservesPreviouslyUserExpandedReasoning() {
        var message = assistant(reasoning: "Working", state: .streaming)
        var store = ReasoningToggleStateStore()
        store.reconcile(messages: [message], prefersExpanded: true)
        store.toggleByUser(messageID: message.id)
        store.toggleByUser(messageID: message.id)
        XCTAssertTrue(store.state(for: message.id).isExpanded)

        message.content = "Answer"
        message.state = .complete
        store.reconcile(messages: [message])

        XCTAssertTrue(store.state(for: message.id).isExpanded)
        XCTAssertTrue(store.state(for: message.id).isPinned)
    }

    func testReconcileRemovesStateForDeletedMessageOnly() {
        let retained = assistant(reasoning: "Retained", state: .streaming)
        let removed = assistant(reasoning: "Removed", state: .streaming)
        var store = ReasoningToggleStateStore()
        store.reconcile(messages: [retained, removed], prefersExpanded: true)

        store.reconcile(messages: [retained], prefersExpanded: true)

        XCTAssertEqual(store.states.count, 1)
        XCTAssertTrue(store.states[retained.id]?.isExpanded == true)
        XCTAssertNil(store.states[removed.id])
    }

    func testDefaultExpandedCollapsesHistoricalReasoning() {
        let message = assistant(reasoning: "Earlier work", state: .complete)
        var store = ReasoningToggleStateStore()

        store.reconcile(messages: [message], prefersExpanded: true)

        XCTAssertFalse(store.state(for: message.id).isExpanded)
    }

    func testDefaultExpandedCollapsesReasoningAfterCompletion() {
        var message = assistant(reasoning: "Working", state: .streaming)
        var store = ReasoningToggleStateStore()
        store.reconcile(messages: [message], prefersExpanded: true)
        XCTAssertTrue(store.state(for: message.id).isExpanded)

        message.content = "Final answer"
        message.state = .complete
        store.reconcile(messages: [message], prefersExpanded: true)

        XCTAssertFalse(store.state(for: message.id).isExpanded)
    }

    func testDefaultExpandedDoesNotOverrideManualCollapse() {
        var message = assistant(reasoning: "Working", state: .streaming)
        var store = ReasoningToggleStateStore()
        store.reconcile(messages: [message], prefersExpanded: true)
        store.toggleByUser(messageID: message.id)

        message.state = .complete
        store.reconcile(messages: [message], prefersExpanded: true)

        XCTAssertFalse(store.state(for: message.id).isExpanded)
        XCTAssertTrue(store.state(for: message.id).isPinned)
    }

    private func assistant(
        content: String = "",
        reasoning: String? = nil,
        state: MessageState
    ) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, reasoningContent: reasoning, state: state)
    }
}
