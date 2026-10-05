import XCTest
@testable import SpotAsk

@MainActor
final class ChatReconciliationCoordinatorTests: XCTestCase {
    func testReconcileSkipsDuplicateRunsForUnchangedInput() {
        let coordinator = ChatReconciliationCoordinator()
        let messages = [assistant(reasoning: "Working", state: .streaming)]

        XCTAssertTrue(coordinator.reconcile(messages: messages, prefersExpanded: false))
        XCTAssertFalse(coordinator.reconcile(messages: messages, prefersExpanded: false))
    }

    func testReconcileRunsAgainWhenPreferenceChanges() {
        let coordinator = ChatReconciliationCoordinator()
        let messages = [assistant(reasoning: "Working", state: .streaming)]

        XCTAssertTrue(coordinator.reconcile(messages: messages, prefersExpanded: false))
        XCTAssertTrue(coordinator.reconcile(messages: messages, prefersExpanded: true))
    }

    func testForceReconcileAlwaysRuns() {
        let coordinator = ChatReconciliationCoordinator()
        let messages = [assistant(reasoning: "Working", state: .streaming)]

        XCTAssertTrue(coordinator.reconcile(messages: messages, prefersExpanded: false))
        XCTAssertTrue(coordinator.reconcile(messages: messages, prefersExpanded: false, force: true))
    }

    func testReconcileRunsAgainWhenTailStateChanges() {
        let coordinator = ChatReconciliationCoordinator()
        var message = assistant(reasoning: "Working", state: .streaming)

        XCTAssertTrue(coordinator.reconcile(messages: [message], prefersExpanded: true))
        XCTAssertTrue(coordinator.reasoningToggle.state(for: message.id).isExpanded)

        message.state = .complete
        XCTAssertTrue(coordinator.reconcile(messages: [message], prefersExpanded: true))
        XCTAssertFalse(coordinator.reasoningToggle.state(for: message.id).isExpanded)
    }

    func testReconcileAppendsNewTailMessage() {
        let coordinator = ChatReconciliationCoordinator()
        let first = assistant(reasoning: "First", state: .complete)
        let second = assistant(reasoning: "Second", state: .streaming)

        XCTAssertTrue(coordinator.reconcile(messages: [first], prefersExpanded: false))
        XCTAssertTrue(coordinator.reconcile(messages: [first, second], prefersExpanded: false))
        XCTAssertEqual(coordinator.reasoningToggle.states.count, 2)
    }

    func testStreamingReconcileSkipsUnchangedReasoningLength() {
        let coordinator = ChatReconciliationCoordinator()
        let message = assistant(reasoning: "Working", state: .streaming)

        XCTAssertTrue(coordinator.reconcileStreamingMessage(message, prefersExpanded: false))
        XCTAssertFalse(coordinator.reconcileStreamingMessage(message, prefersExpanded: false))
    }

    func testStreamingReconcileIgnoresNonStreamingMessages() {
        let coordinator = ChatReconciliationCoordinator()
        let message = assistant(reasoning: "Done", state: .complete)

        XCTAssertFalse(coordinator.reconcileStreamingMessage(message, prefersExpanded: true))
    }

    func testStreamingReconcileExpandsReasoningWhenDefaultEnabled() {
        let coordinator = ChatReconciliationCoordinator()
        let message = assistant(reasoning: "Working", state: .streaming)

        XCTAssertTrue(coordinator.reconcileStreamingMessage(message, prefersExpanded: true))
        XCTAssertTrue(coordinator.reasoningToggle.state(for: message.id).isExpanded)
    }

    private func assistant(
        content: String = "",
        reasoning: String? = nil,
        state: MessageState
    ) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, reasoningContent: reasoning, state: state)
    }
}
