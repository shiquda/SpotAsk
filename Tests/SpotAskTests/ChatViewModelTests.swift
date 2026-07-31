import XCTest
@testable import SpotAsk

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testSendAndFollowUpIncludeConversationContext() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("first answer")], [.text("second answer")]])

        viewModel.input = "first question"
        viewModel.send()
        await waitForIdle(viewModel)
        viewModel.input = "follow up"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(recorder.requests[1].messages.map(\.role), [.system, .user, .assistant, .user])
    }

    func testDuplicateSendDoesNotCreateAnotherRequest() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.pending]])

        viewModel.input = "only once"
        viewModel.send()
        viewModel.send()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(recorder.requests.count, 1)
        viewModel.cancel()
    }

    func testCancelPreservesPartialResponse() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("partial"), .pending]])

        viewModel.input = "question"
        viewModel.send()
        try? await Task.sleep(for: .milliseconds(20))
        viewModel.cancel()

        XCTAssertEqual(viewModel.generationState, .cancelled)
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "partial")
        XCTAssertEqual(viewModel.lastAssistantMessage?.state, .cancelled)
    }

    func testRetryDoesNotDuplicateUserMessage() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.failure(.rateLimited)], [.text("recovered")]])

        viewModel.input = "retry me"
        viewModel.send()
        await waitForState(viewModel, .failed)
        viewModel.retry()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "recovered")
        XCTAssertEqual(recorder.requests.count, 2)
    }

    func testNewConversationClearsMessages() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("answer")]])
        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        viewModel.newConversation()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.generationState, .idle)
    }

    func testContextLimitKeepsMostRecentMessages() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("a1")], [.text("a2")], [.text("a3")]], contextLimit: 2)
        for question in ["q1", "q2", "q3"] {
            viewModel.input = question
            viewModel.send()
            await waitForIdle(viewModel)
        }

        XCTAssertEqual(recorder.requests[2].messages.map(\.content), ["You are a helpful assistant.", "a2", "q3"])
    }

    // MARK: - Stale session choice

    func testStaleSessionOffersChoiceAndBlocksSendUntilResolved() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("new answer")]])
        seedConversation(viewModel, lastActivity: Date(timeIntervalSinceNow: -30 * 60))

        viewModel.offerSessionChoiceIfNeeded()

        XCTAssertTrue(viewModel.isSessionChoicePending)
        viewModel.input = "new question"
        viewModel.send()
        XCTAssertEqual(viewModel.messages.filter { $0.role == .user }.count, 1, "The new question must not be appended before the user chooses")
        XCTAssertTrue(recorder.requests.isEmpty)

        viewModel.continueSession()
        XCTAssertFalse(viewModel.isSessionChoicePending)
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].messages.map(\.role), [.system, .user, .assistant, .user])
    }

    func testRecentSessionDoesNotOfferChoice() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])
        seedConversation(viewModel, lastActivity: Date(timeIntervalSinceNow: -5 * 60))

        viewModel.offerSessionChoiceIfNeeded()

        XCTAssertFalse(viewModel.isSessionChoicePending)
    }

    func testEmptySessionDoesNotOfferChoice() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])

        viewModel.offerSessionChoiceIfNeeded()

        XCTAssertFalse(viewModel.isSessionChoicePending)
    }

    func testStartFreshSessionClearsConversationButKeepsDraft() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])
        seedConversation(viewModel, lastActivity: Date(timeIntervalSinceNow: -30 * 60))
        viewModel.offerSessionChoiceIfNeeded()
        viewModel.input = "typed draft"

        viewModel.startFreshSession()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isSessionChoicePending)
        XCTAssertEqual(viewModel.input, "typed draft")
    }

    // MARK: - Recall last question

    func testRecallLastQuestionFillsEmptyInputWithoutTouchingMessages() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("answer")]])
        viewModel.input = "first question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertTrue(viewModel.recallLastQuestion())
        XCTAssertEqual(viewModel.input, "first question")
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])

        XCTAssertFalse(viewModel.recallLastQuestion(), "Recall must not run while the input has content")
        XCTAssertEqual(viewModel.input, "first question")
    }

    func testRecallLastQuestionWithEmptyConversationDoesNothing() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])

        XCTAssertFalse(viewModel.recallLastQuestion())
        XCTAssertEqual(viewModel.input, "")
    }

    // MARK: - Regenerate

    func testRegenerateReplacesLatestAnswerWithoutDuplicatingQuestion() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("first answer")], [.text("second answer")]])
        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertTrue(viewModel.canRegenerate)
        viewModel.regenerate()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "second answer")
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(recorder.requests[1].messages.map(\.role), [.system, .user])
    }

    func testRegenerateReusesOneShotPromptFromCurrentSession() async {
        let recorder = RequestRecorder()
        let preset = PromptPreset(title: "Custom Polish", instruction: "Polish with extra care")
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("a1")], [.text("a2")]]) { settings in
            settings.saveCustomPromptPreset(preset)
        }
        viewModel.selectedPromptPreset = preset
        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        viewModel.regenerate()
        await waitForIdle(viewModel)

        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(recorder.requests[1].messages.first?.content, "You are a helpful assistant.\n\nPolish with extra care")
    }

    func testRegenerateLooksUpOneShotPromptByTitleForRestoredSession() async {
        let recorder = RequestRecorder()
        let preset = PromptPreset(title: "Custom Polish", instruction: "Polish with extra care")
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.text("regenerated")]]) { settings in
            settings.saveCustomPromptPreset(preset)
        }
        // Simulates a session restored from disk: only the preset title survived.
        viewModel.messages = [
            ChatMessage(role: .user, content: "restored question", appliedPresetTitle: preset.title),
            ChatMessage(role: .assistant, content: "previous answer")
        ]

        XCTAssertTrue(viewModel.canRegenerate)
        viewModel.regenerate()
        await waitForIdle(viewModel)

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].messages.map(\.role), [.system, .user])
        XCTAssertEqual(recorder.requests[0].messages.first?.content, "You are a helpful assistant.\n\nPolish with extra care")
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "regenerated")
    }

    func testRegenerateUnavailableWithoutCompletedLatestAnswer() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.failure(.timeout)]])
        viewModel.input = "question"
        viewModel.send()
        await waitForState(viewModel, .failed)

        XCTAssertFalse(viewModel.canRegenerate, "Failed answers keep the existing retry path")

        viewModel.messages = [ChatMessage(role: .user, content: "only a question")]
        XCTAssertFalse(viewModel.canRegenerate, "Nothing to regenerate before an answer exists")
    }

    private func seedConversation(_ viewModel: ChatViewModel, lastActivity: Date) {
        viewModel.messages = [
            ChatMessage(role: .user, content: "old question", createdAt: lastActivity.addingTimeInterval(-30)),
            ChatMessage(role: .assistant, content: "old answer", createdAt: lastActivity)
        ]
    }

    private func makeViewModel(
        recorder: RequestRecorder,
        scripts: [[MockStep]],
        contextLimit: Int = 20,
        configure: ((AppSettings) -> Void)? = nil
    ) -> ChatViewModel {
        let suiteName = "SpotAskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.contextLimit = contextLimit
        configure?(settings)
        let factory = MockFactory(recorder: recorder, scripts: scripts)
        return ChatViewModel(settings: settings, providerFactory: factory, sessionStore: SessionStore(bundleIdentifier: suiteName))
    }

    private func waitForIdle(_ viewModel: ChatViewModel) async {
        await waitForState(viewModel, .idle)
    }

    private func waitForState(_ viewModel: ChatViewModel, _ state: GenerationState) async {
        for _ in 0 ..< 100 {
            if viewModel.generationState == state { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(state)")
    }
}

private final class RequestRecorder: @unchecked Sendable {
    var requests: [ChatRequest] = []
    var invocation = 0
}

@MainActor
private struct MockFactory: ChatProviderFactory {
    let recorder: RequestRecorder
    let scripts: [[MockStep]]

    func makeProvider() throws -> any ChatProvider {
        let index = recorder.invocation
        recorder.invocation += 1
        return MockProvider(recorder: recorder, steps: scripts.indices.contains(index) ? scripts[index] : [])
    }
}

private enum MockStep: Sendable {
    case text(String)
    case failure(ChatError)
    case pending
}

private struct MockProvider: ChatProvider {
    let recorder: RequestRecorder
    let steps: [MockStep]

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        recorder.requests.append(request)
        return AsyncThrowingStream { continuation in
            for step in steps {
                switch step {
                case let .text(value): continuation.yield(.textDelta(value))
                case let .failure(error): continuation.finish(throwing: error); return
                case .pending:
                    let task = Task {
                        try? await Task.sleep(for: .seconds(30))
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                    return
                }
            }
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}
