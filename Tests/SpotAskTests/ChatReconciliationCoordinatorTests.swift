import Observation
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
    func testStreamingReconcileSkipsAdditionalReasoningChunksAndCollapsesWhenAnswerStarts() {
        let coordinator = ChatReconciliationCoordinator()
        let id = UUID()
        let initialReasoning = ChatMessage(id: id, role: .assistant, content: "", reasoningContent: "Step 1", state: .streaming)
        let grownReasoning = ChatMessage(id: id, role: .assistant, content: "", reasoningContent: "Step 1\nStep 2", state: .streaming)
        let answerStarted = ChatMessage(id: id, role: .assistant, content: "Answer", reasoningContent: "Step 1\nStep 2", state: .streaming)
        let answerContinued = ChatMessage(id: id, role: .assistant, content: "Answer more", reasoningContent: "Step 1\nStep 2", state: .streaming)

        XCTAssertTrue(coordinator.reconcileStreamingMessage(initialReasoning, prefersExpanded: true))
        XCTAssertTrue(coordinator.reasoningToggle.state(for: id).isExpanded)

        XCTAssertFalse(coordinator.reconcileStreamingMessage(grownReasoning, prefersExpanded: true))
        XCTAssertTrue(coordinator.reasoningToggle.state(for: id).isExpanded)

        XCTAssertTrue(coordinator.reconcileStreamingMessage(answerStarted, prefersExpanded: true))
        XCTAssertFalse(coordinator.reasoningToggle.state(for: id).isExpanded)

        XCTAssertFalse(coordinator.reconcileStreamingMessage(answerContinued, prefersExpanded: true))
    }

    func testObservationNotifiesImmediatelyOnUserQuestionAndReasoningToggles() {
        final class Flag: @unchecked Sendable {
            var value = false
        }

        let coordinator = ChatReconciliationCoordinator()
        let userMessage = ChatMessage(role: .user, content: "Long question")
        let assistantMessage = assistant(reasoning: "Thinking...", state: .streaming)
        coordinator.reconcile(messages: [userMessage, assistantMessage], prefersExpanded: false)

        let didInvalidateUserExpansion = Flag()
        withObservationTracking {
            _ = coordinator.userMessageExpansionState.isExpanded(messageID: userMessage.id)
        } onChange: {
            didInvalidateUserExpansion.value = true
        }
        coordinator.userMessageExpansionState.toggle(messageID: userMessage.id)
        XCTAssertTrue(didInvalidateUserExpansion.value)
        XCTAssertTrue(coordinator.userMessageExpansionState.isExpanded(messageID: userMessage.id))

        let didInvalidateReasoning = Flag()
        withObservationTracking {
            _ = coordinator.reasoningToggle.state(for: assistantMessage.id)
        } onChange: {
            didInvalidateReasoning.value = true
        }
        coordinator.reasoningToggle.toggleByUser(messageID: assistantMessage.id)
        XCTAssertTrue(didInvalidateReasoning.value)
        XCTAssertTrue(coordinator.reasoningToggle.state(for: assistantMessage.id).isExpanded)
        XCTAssertTrue(coordinator.reasoningToggle.state(for: assistantMessage.id).isPinned)

        let didInvalidateAssistantExpansion = Flag()
        withObservationTracking {
            _ = coordinator.assistantMessageExpansionState.isExpanded(messageID: assistantMessage.id)
        } onChange: {
            didInvalidateAssistantExpansion.value = true
        }
        coordinator.assistantMessageExpansionState.toggle(messageID: assistantMessage.id)
        XCTAssertTrue(didInvalidateAssistantExpansion.value)
        XCTAssertFalse(coordinator.assistantMessageExpansionState.isExpanded(messageID: assistantMessage.id))
    }

    func testManualReasoningPinBeforeFirstReconcileSurvivesReconcile() {
        let coordinator = ChatReconciliationCoordinator()
        let message = assistant(reasoning: "Thinking...", state: .streaming)

        coordinator.reasoningToggle.toggleByUser(messageID: message.id)
        XCTAssertTrue(coordinator.reasoningToggle.state(for: message.id).isExpanded)

        coordinator.reconcile(messages: [message], prefersExpanded: false)
        XCTAssertTrue(coordinator.reasoningToggle.state(for: message.id).isExpanded)
        XCTAssertTrue(coordinator.reasoningToggle.state(for: message.id).isPinned)
    }

    private func assistant(
        content: String = "",
        reasoning: String? = nil,
        state: MessageState
    ) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, reasoningContent: reasoning, state: state)
    }
}
