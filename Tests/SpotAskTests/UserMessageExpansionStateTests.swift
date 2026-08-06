import XCTest
@testable import SpotAsk

final class UserMessageExpansionStateTests: XCTestCase {
    func testShortMessageDoesNotCollapse() {
        XCTAssertFalse(UserMessageDisplayPolicy.shouldCollapse("A concise question."))
    }

    func testCharacterThresholdBoundary() {
        XCTAssertFalse(UserMessageDisplayPolicy.shouldCollapse(String(repeating: "a", count: 500)))
        XCTAssertTrue(UserMessageDisplayPolicy.shouldCollapse(String(repeating: "a", count: 501)))
    }

    func testCollapsedPreviewIsBoundedWithoutSplittingUnicodeCharacters() {
        let character = "👩🏽‍💻"
        let content = String(repeating: character, count: 501)

        let preview = UserMessageDisplayPolicy.collapsedPreview(for: content)

        XCTAssertEqual(preview, String(repeating: character, count: 500))
        XCTAssertEqual(preview?.count, UserMessageDisplayPolicy.characterThreshold)
    }

    func testExplicitLineThresholdBoundary() {
        XCTAssertFalse(UserMessageDisplayPolicy.shouldCollapse(Array(repeating: "line", count: 7).joined(separator: "\n")))
        XCTAssertTrue(UserMessageDisplayPolicy.shouldCollapse(Array(repeating: "line", count: 8).joined(separator: "\n")))
    }

    func testEightLinePreviewIncludesEighthLineWithoutTrailingEmptyLine() {
        let lines = (1...8).map { "line \($0)" }
        let content = lines.joined(separator: "\n")

        XCTAssertEqual(UserMessageDisplayPolicy.collapsedPreview(for: content), content)
    }

    func testNineLinePreviewContainsOnlyFirstEightLinesWithoutTrailingEmptyLine() {
        let lines = (1...9).map { "line \($0)" }
        let content = lines.joined(separator: "\n")

        XCTAssertEqual(
            UserMessageDisplayPolicy.collapsedPreview(for: content),
            lines.prefix(UserMessageDisplayPolicy.collapsedLineLimit).joined(separator: "\n")
        )
    }

    func testMessageStartsCollapsedAndCanToggleRepeatedly() {
        let message = userMessage(content: String(repeating: "a", count: 501))
        var state = UserMessageExpansionState()

        state.reconcile(messages: [message], role: .user)
        XCTAssertFalse(state.isExpanded(messageID: message.id))

        state.toggle(messageID: message.id)
        XCTAssertTrue(state.isExpanded(messageID: message.id))

        state.toggle(messageID: message.id)
        XCTAssertFalse(state.isExpanded(messageID: message.id))
    }

    func testReconcileRemovesExpansionForDeletedMessage() {
        let retained = userMessage(content: String(repeating: "a", count: 501))
        let removed = userMessage(content: String(repeating: "b", count: 501))
        var state = UserMessageExpansionState()

        state.toggle(messageID: retained.id)
        state.toggle(messageID: removed.id)
        state.reconcile(messages: [retained], role: .user)

        XCTAssertTrue(state.isExpanded(messageID: retained.id))
        XCTAssertFalse(state.isExpanded(messageID: removed.id))
    }

    func testExpansionStateDoesNotChangeMessageContent() {
        let content = String(repeating: "question ", count: 100)
        let message = userMessage(content: content)
        var state = UserMessageExpansionState()

        state.reconcile(messages: [message], role: .user)
        state.toggle(messageID: message.id)
        state.toggle(messageID: message.id)

        XCTAssertEqual(message.content, content)
    }

    func testRestoredMessageStartsCollapsedInNewExpansionState() {
        let message = userMessage(content: String(repeating: "a", count: 501))
        var previousState = UserMessageExpansionState()
        previousState.reconcile(messages: [message], role: .user)
        previousState.toggle(messageID: message.id)

        var restoredState = UserMessageExpansionState()
        restoredState.reconcile(messages: [message], role: .user)

        XCTAssertTrue(previousState.isExpanded(messageID: message.id))
        XCTAssertFalse(restoredState.isExpanded(messageID: message.id))
    }

    func testAssistantExpansionSurvivesUnrelatedMessageUpdatesAndCompletion() {
        var answer = ChatMessage(
            role: .assistant,
            content: String(repeating: "a", count: 4_001),
            state: .streaming
        )
        var state = MessageExpansionState()

        state.reconcile(messages: [answer], role: .assistant)
        XCTAssertTrue(state.isExpanded(messageID: answer.id))

        answer.state = .complete
        state.reconcile(messages: [answer], role: .assistant)
        XCTAssertTrue(state.isExpanded(messageID: answer.id))

        let followUp = ChatMessage(role: .user, content: "Next question")
        state.reconcile(messages: [answer, followUp], role: .assistant)
        XCTAssertTrue(state.isExpanded(messageID: answer.id))
    }

    func testRestoredLongAssistantAnswerStartsCollapsed() {
        let answer = ChatMessage(
            role: .assistant,
            content: String(repeating: "a", count: 4_001),
            state: .complete
        )
        var state = MessageExpansionState()

        state.reconcile(messages: [answer], role: .assistant)

        XCTAssertFalse(state.isExpanded(messageID: answer.id))
    }

    func testAssistantReconcileDoesNotRemoveUserExpansion() {
        let question = ChatMessage(role: .user, content: String(repeating: "q", count: 501))
        let answer = ChatMessage(role: .assistant, content: "Answer")
        var userState = UserMessageExpansionState()

        userState.toggle(messageID: question.id)
        userState.reconcile(messages: [question, answer], role: .user)

        XCTAssertTrue(userState.isExpanded(messageID: question.id))
        XCTAssertFalse(userState.isExpanded(messageID: answer.id))
    }

    private func userMessage(content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }
}
