import XCTest
@testable import SpotAsk

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testFocusedComposerPreservesDraftOnlyDuringGeneration() {
        XCTAssertTrue(ChatInputSynchronization.shouldPreserveFocusedDraft(isGenerating: true, isFirstResponder: true))
        XCTAssertFalse(ChatInputSynchronization.shouldPreserveFocusedDraft(isGenerating: true, isFirstResponder: false))
        XCTAssertFalse(ChatInputSynchronization.shouldPreserveFocusedDraft(isGenerating: false, isFirstResponder: true))
        XCTAssertFalse(ChatInputSynchronization.shouldPreserveFocusedDraft(
            isGenerating: true,
            isFirstResponder: true,
            isModelTextEmpty: true
        ))
    }

    func testSendAndFollowUpIncludeConversationContext() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("first answer")], [.answer("second answer")]])

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
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.reasoning("partial reasoning"), .answer("partial"), .pending]])

        viewModel.input = "question"
        viewModel.send()
        try? await Task.sleep(for: .milliseconds(20))
        viewModel.cancel()

        XCTAssertEqual(viewModel.generationState, .cancelled)
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "partial")
        XCTAssertEqual(viewModel.lastAssistantMessage?.reasoningContent, "partial reasoning")
        XCTAssertEqual(viewModel.lastAssistantMessage?.state, .cancelled)
    }

    func testStreamingDeltasDoNotRewriteMessagesArray() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.reasoning("partial reasoning"), .answer("partial"), .pending]])

        viewModel.input = "question"
        viewModel.send()
        for _ in 0 ..< 100 {
            if viewModel.lastAssistantMessage?.content == "partial" { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.streamingContent, "partial")
        XCTAssertEqual(viewModel.streamingReasoning, "partial reasoning")
        XCTAssertEqual(viewModel.streamingAnswerChunks, ["partial"])
        XCTAssertEqual(viewModel.messages.last?.content, "")
        XCTAssertNil(viewModel.messages.last?.reasoningContent)
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "partial")

        viewModel.cancel()

        XCTAssertEqual(viewModel.messages.last?.content, "partial")
        XCTAssertEqual(viewModel.messages.last?.reasoningContent, "partial reasoning")
        XCTAssertNil(viewModel.activeStreamingAssistantID)
    }

    func testStreamingChunksRemainAvailableToRendererAfterCompletion() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("final answer")]])

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.streamingAnswerChunks, ["final answer"])
        XCTAssertEqual(viewModel.messages.last?.content, "final answer")
    }

    func testCompletedAnswerCommitsStreamingContentOnce() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("final answer")]])

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.messages.last?.content, "final answer")
        XCTAssertEqual(viewModel.streamingContent, "")
        XCTAssertNil(viewModel.activeStreamingAssistantID)
    }

    func testFailurePreservesPartialReasoningAndAnswer() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.reasoning("partial reasoning"), .answer("partial answer"), .failure(.timeout)]])

        viewModel.input = "question"
        viewModel.send()
        await waitForState(viewModel, .failed)

        XCTAssertEqual(viewModel.lastAssistantMessage?.reasoningContent, "partial reasoning")
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "partial answer")
        XCTAssertEqual(viewModel.lastAssistantMessage?.state, .failed)
    }

    func testRetryDoesNotDuplicateUserMessage() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.failure(.rateLimited(message: nil))], [.answer("recovered")]])

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
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])
        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        viewModel.newConversation()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.generationState, .idle)
    }

    func testContextLimitKeepsMostRecentMessages() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("a1")], [.answer("a2")], [.answer("a3")]], contextLimit: 2)
        for question in ["q1", "q2", "q3"] {
            viewModel.input = question
            viewModel.send()
            await waitForIdle(viewModel)
        }

        XCTAssertEqual(recorder.requests[2].messages.map(\.content), ["You are a helpful assistant.", "a2", "q3"])
    }

    func testFollowUpRequestExcludesAssistantReasoning() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.reasoning("private chain"), .answer("first answer")], [.answer("second answer")]])

        viewModel.input = "first question"
        viewModel.send()
        await waitForIdle(viewModel)
        viewModel.input = "follow up"
        viewModel.send()
        await waitForIdle(viewModel)

        let assistant = recorder.requests[1].messages.first { $0.role == .assistant }
        XCTAssertEqual(assistant?.content, "first answer")
        XCTAssertNil(assistant?.reasoningContent)
    }

    func testSessionStorePersistsReasoningContent() throws {
        let bundleIdentifier = "SpotAskTests.\(UUID().uuidString)"
        let store = SessionStore(bundleIdentifier: bundleIdentifier)
        defer { try? store.clear() }
        let message = ChatMessage(
            role: .assistant,
            content: "answer",
            reasoningContent: "reasoning",
            reasoningCompletedAt: .now.addingTimeInterval(-1),
            modelDisplayName: "GPT-5 mini",
            completedAt: .now
        )

        try store.save([message])

        XCTAssertEqual(try store.load(), [message])
    }

    func testReasoningTimestampStopsAtFirstAnswerDelta() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.reasoning("plan"), .answer("partial"), .pending]])

        viewModel.input = "question"
        viewModel.send()
        for _ in 0 ..< 100 {
            if viewModel.lastAssistantMessage?.content == "partial" { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "partial")
        XCTAssertNotNil(viewModel.lastAssistantMessage?.reasoningCompletedAt)
        XCTAssertNotNil(viewModel.lastAssistantMessage?.reasoningDuration)
        viewModel.cancel()
        XCTAssertEqual(viewModel.lastAssistantMessage?.state, .cancelled)
    }

    func testReasoningTimestampStopsAtTerminalStateWithoutAnswer() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.reasoning("plan"), .failure(.timeout)]])

        viewModel.input = "question"
        viewModel.send()
        await waitForState(viewModel, .failed)

        XCTAssertNotNil(viewModel.lastAssistantMessage?.reasoningCompletedAt)
        XCTAssertNotNil(viewModel.lastAssistantMessage?.reasoningDuration)
    }

    func testCompletedAnswerCapturesModelNameAndDuration() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.lastAssistantMessage?.modelDisplayName, "GPT-5 mini")
        XCTAssertNotNil(viewModel.lastAssistantMessage?.completedAt)
        XCTAssertNotNil(viewModel.lastAssistantMessage?.responseDuration)
    }

    func testSessionStorePersistsAppliedPromptIconSnapshot() throws {
        let bundleIdentifier = "SpotAskTests.\(UUID().uuidString)"
        let store = SessionStore(bundleIdentifier: bundleIdentifier)
        defer { try? store.clear() }
        let message = ChatMessage(
            role: .user,
            content: "question",
            appliedPresetTitle: "Translate",
            appliedPresetSymbolName: "character.bubble"
        )

        try store.save([message])

        XCTAssertEqual(try store.load(), [message])
    }

    func testSendSnapshotsAppliedPromptIcon() async {
        let recorder = RequestRecorder()
        let preset = PromptPreset.builtIn[0]
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])
        viewModel.selectedPromptPreset = preset
        viewModel.input = "question"

        viewModel.send()
        await waitForIdle(viewModel)

        let question = viewModel.messages.first { $0.role == .user }
        XCTAssertEqual(question?.appliedPresetTitle, preset.title)
        XCTAssertEqual(question?.appliedPresetSymbolName, "character.bubble")
        XCTAssertEqual(question?.appliedPresetIcon, "character.bubble")
    }

    // MARK: - Stale session recovery

    func testStaleSessionStartsFreshAndDiscardsPreviousSessionWhenSent() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("new answer")]])
        seedConversation(viewModel, lastActivity: Date(timeIntervalSinceNow: -30 * 60))

        viewModel.prepareNewConversationAfterInactivity()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.canRestorePreviousSession)
        viewModel.input = "new question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertFalse(viewModel.canRestorePreviousSession)
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].messages.map(\.role), [.system, .user])
    }

    func testRestoreSessionPreservesPreviousConversationContext() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("new answer")]])
        seedConversation(viewModel, lastActivity: Date(timeIntervalSinceNow: -30 * 60))

        viewModel.prepareNewConversationAfterInactivity()
        viewModel.restoreSession()
        viewModel.prepareNewConversationAfterInactivity()
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
        viewModel.input = "follow up"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertFalse(viewModel.canRestorePreviousSession)
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].messages.map(\.role), [.system, .user, .assistant, .user])
    }

    func testRecentSessionDoesNotStartFresh() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])
        seedConversation(viewModel, lastActivity: Date(timeIntervalSinceNow: -5 * 60))

        viewModel.prepareNewConversationAfterInactivity()

        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.canRestorePreviousSession)
    }

    func testEmptySessionDoesNotOfferRestore() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])

        viewModel.prepareNewConversationAfterInactivity()

        XCTAssertFalse(viewModel.canRestorePreviousSession)
    }

    // MARK: - Recall last question

    func testRecallLastQuestionFillsEmptyInputWithoutTouchingMessages() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])
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
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("first answer")], [.answer("second answer")]])
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
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("a1")], [.answer("a2")]]) { settings in
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

    func testRegenerateDoesNotReuseDisabledOneShotPrompt() async {
        let suiteName = "SpotAskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let preset = PromptPreset(title: "Custom Polish", instruction: "Polish with extra care")
        XCTAssertTrue(settings.saveCustomPromptPreset(preset))
        let recorder = RequestRecorder()
        let viewModel = ChatViewModel(
            settings: settings,
            providerFactory: MockFactory(recorder: recorder, scripts: [[.answer("a1")], [.answer("a2")]]),
            sessionStore: SessionStore(bundleIdentifier: suiteName)
        )

        viewModel.selectedPromptPreset = preset
        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)
        settings.setPromptPresetEnabled(id: preset.id, isEnabled: false)

        viewModel.regenerate()
        await waitForIdle(viewModel)

        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(recorder.requests[1].messages.first?.content, "You are a helpful assistant.")
        XCTAssertFalse(recorder.requests[1].messages.contains { $0.content.contains(preset.instruction) })
    }

    func testRegenerateLooksUpOneShotPromptByTitleForRestoredSession() async {
        let recorder = RequestRecorder()
        let preset = PromptPreset(title: "Custom Polish", instruction: "Polish with extra care")
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("regenerated")]]) { settings in
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

    func testRequestUsesImmutableTargetSnapshotWhenSelectionChangesDuringStartup() async throws {
        let suiteName = "SpotAskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let registry = settings.providerRegistry
        let originalCatalog = try XCTUnwrap(registry.catalog)
        let originalProvider = try XCTUnwrap(originalCatalog.providers.first)
        let originalModel = try XCTUnwrap(originalCatalog.models.first)
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 20)
        )
        let secondModel = try registry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second-upstream", providerID: secondProvider.id, isStreamingEnabled: false)
        )
        let snapshot = ProviderTargetSnapshot(
            modelID: originalModel.id,
            providerID: originalProvider.id,
            endpoint: URL(string: "https://original.example/v1/chat/completions")!,
            apiKey: "old-key",
            displayName: originalModel.displayName,
            upstreamModelID: originalModel.upstreamModelID,
            isStreamingEnabled: true,
            timeout: 60
        )
        let factory = SnapshotFactory(
            snapshot: snapshot,
            onSnapshot: { try registry.selectModel(id: secondModel.id) }
        )
        let viewModel = ChatViewModel(settings: settings, providerFactory: factory, sessionStore: SessionStore(bundleIdentifier: suiteName))

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(factory.receivedTargets.count, 1)
        XCTAssertEqual(registry.catalog?.selectedModelID, secondModel.id)
        guard let receivedTarget = factory.receivedTargets.first,
              let request = factory.requests.first else { return XCTFail("Expected a request built from the target snapshot") }
        XCTAssertEqual(receivedTarget.providerID, originalProvider.id)
        XCTAssertEqual(receivedTarget.upstreamModelID, originalModel.upstreamModelID)
        XCTAssertEqual(receivedTarget.apiKey, "old-key")
        XCTAssertEqual(request.model, originalModel.upstreamModelID)
        XCTAssertTrue(request.stream)
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
        snapshots: [UUID: ProviderTargetSnapshot] = [:],
        configure: ((AppSettings) -> Void)? = nil
    ) -> ChatViewModel {
        makeViewModelWithSettings(
            recorder: recorder,
            scripts: scripts,
            contextLimit: contextLimit,
            snapshots: snapshots,
            configure: configure
        ).0
    }

    private func makeViewModelWithSettings(
        recorder: RequestRecorder,
        scripts: [[MockStep]],
        contextLimit: Int = 20,
        snapshots: [UUID: ProviderTargetSnapshot] = [:],
        configure: ((AppSettings) -> Void)? = nil
    ) -> (ChatViewModel, AppSettings) {
        let suiteName = "SpotAskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.contextLimit = contextLimit
        configure?(settings)
        let factory = MockFactory(recorder: recorder, scripts: scripts, snapshotsByModelID: snapshots)
        let viewModel = ChatViewModel(settings: settings, providerFactory: factory, sessionStore: SessionStore(bundleIdentifier: suiteName))
        return (viewModel, settings)
    }

    private func waitForIdle(_ viewModel: ChatViewModel) async {
        await waitForState(viewModel, .idle)
    }

    // MARK: - Quick Model Switch

    func testDefaultModelUsedWhenNoSessionOverride() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(recorder.modelIDs.count, 1)
    }

    func testSessionModelOverrideUsedForRequest() async {
        let recorder = RequestRecorder()
        let modelB = UUID()
        let snapshotB = ProviderTargetSnapshot.testValue(
            modelID: modelB,
            displayName: "Model B",
            upstreamModelID: "model-b"
        )
        let (viewModel, settings) = makeViewModelWithSettings(
            recorder: recorder,
            scripts: [[.answer("answer")]],
            snapshots: [modelB: snapshotB]
        ) { settings in
            guard let catalog = settings.providerRegistry.catalog,
                  let providerID = catalog.providers.first?.id else { return }
            _ = try? settings.providerRegistry.saveModel(
                ModelConfiguration(
                    id: modelB,
                    displayName: "Model B",
                    upstreamModelID: "model-b",
                    providerID: providerID,
                    isStreamingEnabled: true
                )
            )
        }

        viewModel.selectSessionModel(id: modelB)
        XCTAssertEqual(viewModel.effectiveModelID, modelB)
        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(recorder.modelIDs, [modelB])
        XCTAssertEqual(viewModel.lastAssistantMessage?.modelDisplayName, "Model B")
    }

    func testNewConversationResetsSessionModel() async {
        let recorder = RequestRecorder()
        let modelB = UUID()
        let (viewModel, settings) = makeViewModelWithSettings(
            recorder: recorder,
            scripts: [[.answer("answer")]],
            snapshots: [modelB: ProviderTargetSnapshot.testValue(modelID: modelB)]
        ) { settings in
            guard let catalog = settings.providerRegistry.catalog,
                  let providerID = catalog.providers.first?.id else { return }
            _ = try? settings.providerRegistry.saveModel(
                ModelConfiguration(
                    id: modelB,
                    displayName: "Model B",
                    upstreamModelID: "model-b",
                    providerID: providerID,
                    isStreamingEnabled: true
                )
            )
        }

        viewModel.selectSessionModel(id: modelB)
        XCTAssertEqual(viewModel.effectiveModelID, modelB)
        XCTAssertNotNil(viewModel.sessionModelID)

        viewModel.newConversation()

        XCTAssertNil(viewModel.sessionModelID)
        XCTAssertNotEqual(viewModel.effectiveModelID, modelB)
    }

    func testDeletedSessionModelFallsBackToDefault() async {
        let recorder = RequestRecorder()
        let (viewModel, settings) = makeViewModelWithSettings(
            recorder: recorder,
            scripts: [[.answer("answer")]]
        ) { settings in
            guard let catalog = settings.providerRegistry.catalog,
                  let providerID = catalog.providers.first?.id else { return }
            _ = try? settings.providerRegistry.saveModel(
                ModelConfiguration(
                    displayName: "Model B",
                    upstreamModelID: "model-b",
                    providerID: providerID,
                    isStreamingEnabled: true
                )
            )
        }
        guard let catalog = settings.providerRegistry.catalog,
              let modelB = catalog.models.first(where: { $0.upstreamModelID == "model-b" }) else {
            XCTFail("Catalog setup failed")
            return
        }
        let defaultID = catalog.selectedModelID

        // Override to model B, then delete it from Settings.
        viewModel.selectSessionModel(id: modelB.id)
        XCTAssertEqual(viewModel.effectiveModelID, modelB.id)
        try? settings.providerRegistry.deleteModel(id: modelB.id)

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertNil(viewModel.sessionModelID)
        XCTAssertEqual(viewModel.effectiveModelID, defaultID)
        XCTAssertEqual(recorder.modelIDs.first, defaultID)
    }

    func testSelectSessionModelDoesNotChangeCatalogSelection() async {
        let recorder = RequestRecorder()
        let (viewModel, settings) = makeViewModelWithSettings(
            recorder: recorder,
            scripts: [[.answer("answer")]]
        ) { settings in
            guard let catalog = settings.providerRegistry.catalog,
                  let providerID = catalog.providers.first?.id else { return }
            _ = try? settings.providerRegistry.saveModel(
                ModelConfiguration(
                    displayName: "Model B",
                    upstreamModelID: "model-b",
                    providerID: providerID,
                    isStreamingEnabled: true
                )
            )
        }
        let selectedBefore = settings.providerRegistry.catalog?.selectedModelID
        guard let modelB = settings.providerRegistry.catalog?.models.first(where: { $0.upstreamModelID == "model-b" }) else {
            XCTFail("Model B not found")
            return
        }

        viewModel.selectSessionModel(id: modelB.id)

        XCTAssertEqual(viewModel.effectiveModelID, modelB.id)
        XCTAssertEqual(settings.providerRegistry.catalog?.selectedModelID, selectedBefore)
    }

    func testRegenerateWithSelectedModelUsesSessionOverride() async {
        let recorder = RequestRecorder()
        let modelB = UUID()
        let snapshotB = ProviderTargetSnapshot.testValue(
            modelID: modelB,
            displayName: "Model B",
            upstreamModelID: "model-b"
        )
        let (viewModel, settings) = makeViewModelWithSettings(
            recorder: recorder,
            scripts: [[.answer("first answer")], [.answer("second answer")]],
            snapshots: [modelB: snapshotB]
        ) { settings in
            guard let catalog = settings.providerRegistry.catalog,
                  let providerID = catalog.providers.first?.id else { return }
            _ = try? settings.providerRegistry.saveModel(
                ModelConfiguration(
                    id: modelB,
                    displayName: "Model B",
                    upstreamModelID: "model-b",
                    providerID: providerID,
                    isStreamingEnabled: true
                )
            )
        }

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertTrue(viewModel.regenerate(withModelID: modelB))
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.sessionModelID, modelB)
        XCTAssertEqual(recorder.modelIDs.last, modelB)
        XCTAssertEqual(viewModel.lastAssistantMessage?.modelDisplayName, "Model B")
        XCTAssertEqual(viewModel.messages.filter { $0.role == .user }.count, 1)
    }

    func testRegenerateWithDefaultModelClearsSessionOverride() async {
        let recorder = RequestRecorder()
        let modelB = UUID()
        let (viewModel, settings) = makeViewModelWithSettings(
            recorder: recorder,
            scripts: [[.answer("first answer")], [.answer("second answer")]],
            snapshots: [modelB: ProviderTargetSnapshot.testValue(modelID: modelB)]
        ) { settings in
            guard let catalog = settings.providerRegistry.catalog,
                  let providerID = catalog.providers.first?.id else { return }
            _ = try? settings.providerRegistry.saveModel(
                ModelConfiguration(
                    id: modelB,
                    displayName: "Model B",
                    upstreamModelID: "model-b",
                    providerID: providerID,
                    isStreamingEnabled: true
                )
            )
        }
        let defaultID = settings.providerRegistry.catalog?.selectedModelID

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)
        viewModel.selectSessionModel(id: modelB)
        XCTAssertEqual(viewModel.sessionModelID, modelB)

        XCTAssertTrue(viewModel.regenerateWithDefaultModel())
        await waitForIdle(viewModel)

        XCTAssertNil(viewModel.sessionModelID)
        XCTAssertEqual(recorder.modelIDs.last, defaultID)
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "second answer")
    }

    func testRegenerateWithUnknownModelDoesNotReplaceAnswer() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])

        viewModel.input = "question"
        viewModel.send()
        await waitForIdle(viewModel)
        let requestCount = recorder.requests.count

        XCTAssertFalse(viewModel.regenerate(withModelID: UUID()))
        XCTAssertEqual(recorder.requests.count, requestCount)
        XCTAssertEqual(viewModel.lastAssistantMessage?.content, "answer")
    }

    // MARK: - Attachments

    func testCanSendTrueWithOnlyAttachments() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])
        viewModel.addAttachments([makeAttachment()])

        XCTAssertTrue(viewModel.canSend)

        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        let userMessage = viewModel.messages.first { $0.role == .user }
        XCTAssertEqual(userMessage?.attachments.count, 1)
        XCTAssertTrue(viewModel.pendingAttachments.isEmpty)
    }

    func testSendMovesPendingAttachmentsIntoUserMessage() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])
        let attachment = makeAttachment()
        viewModel.input = "what is this?"
        viewModel.addAttachments([attachment])

        viewModel.send()
        await waitForIdle(viewModel)

        let userMessage = viewModel.messages.first { $0.role == .user }
        XCTAssertEqual(userMessage?.content, "what is this?")
        XCTAssertEqual(userMessage?.attachments, [attachment])
        XCTAssertEqual(userMessage?.attachments.first?.id, attachment.id)
    }

    func testNewConversationClearsPendingAttachments() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])
        viewModel.addAttachments([makeAttachment()])
        XCTAssertFalse(viewModel.pendingAttachments.isEmpty)

        viewModel.newConversation()

        XCTAssertTrue(viewModel.pendingAttachments.isEmpty)
    }

    func testRetryKeepsOriginalAttachments() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(
            recorder: recorder,
            scripts: [[.failure(.rateLimited(message: nil))], [.answer("recovered")]]
        )
        let attachment = makeAttachment()
        viewModel.input = "retry me"
        viewModel.addAttachments([attachment])
        viewModel.send()
        await waitForState(viewModel, .failed)

        viewModel.retry()
        await waitForIdle(viewModel)

        let requestMessages = recorder.requests.last?.messages ?? []
        let userMessage = requestMessages.first { $0.role == .user }
        XCTAssertEqual(userMessage?.attachments, [attachment])
    }

    func testFollowUpRequestIncludesEarlierAttachments() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("first answer")], [.answer("second answer")]])
        let attachment = makeAttachment(filename: "shot.png")
        viewModel.input = "first question"
        viewModel.addAttachments([attachment])
        viewModel.send()
        await waitForIdle(viewModel)

        viewModel.input = "follow up"
        viewModel.send()
        await waitForIdle(viewModel)

        XCTAssertEqual(recorder.requests.count, 2)
        let firstTurnUserMessage = recorder.requests[1].messages.first { $0.role == .user && $0.content == "first question" }
        XCTAssertEqual(firstTurnUserMessage?.attachments, [attachment])
    }

    func testFallbackPromptInjectedWhenOnlyAttachments() async {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [[.answer("answer")]])
        viewModel.addAttachments([makeAttachment(filename: "shot.png")])
        XCTAssertTrue(viewModel.canSend)

        viewModel.send()
        await waitForIdle(viewModel)

        let userMessage = recorder.requests.first?.messages.first { $0.role == .user }
        XCTAssertNotNil(userMessage)
        XCTAssertFalse(userMessage?.content.isEmpty ?? true)
        XCTAssertEqual(userMessage?.attachments.count, 1)
    }

    func testAttachmentLimitTruncatesAtEight() {
        let recorder = RequestRecorder()
        let viewModel = makeViewModel(recorder: recorder, scripts: [])
        let tooMany = (0 ..< 10).map { makeAttachment(filename: "file\($0).txt", text: "hello") }

        viewModel.addAttachments(tooMany)

        XCTAssertEqual(viewModel.pendingAttachments.count, AttachmentLimits.maxAttachmentsPerMessage)
    }

    func testSessionStoreStripsAttachments() async {
        let suiteName = "SpotAskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.retainSession = true
        let store = SessionStore(bundleIdentifier: suiteName)
        defer { try? store.clear() }
        let recorder = RequestRecorder()
        let viewModel = ChatViewModel(
            settings: settings,
            providerFactory: MockFactory(recorder: recorder, scripts: [[.answer("answer")]]),
            sessionStore: store
        )
        viewModel.input = "question"
        viewModel.addAttachments([makeAttachment(filename: "shot.png")])
        viewModel.send()
        await waitForIdle(viewModel)

        let restored = (try? store.load()) ?? []
        let userMessage = restored.first { $0.role == .user }
        XCTAssertEqual(userMessage?.content, "question")
        XCTAssertTrue(userMessage?.attachments.isEmpty ?? false)
    }

    func testOldSessionJSONWithoutAttachmentsStillDecodes() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","role":"user","content":"legacy","createdAt":\(Date().timeIntervalSince1970),"state":"complete"}]
        """
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].content, "legacy")
        XCTAssertTrue(decoded[0].attachments.isEmpty)
    }

    private func makeAttachment(filename: String = "shot.png", text: String? = nil) -> ChatAttachment {
        if let text {
            return ChatAttachment(
                filename: filename,
                mimeType: "text/plain",
                byteCount: text.utf8.count,
                payload: .text(text: text, originalKind: .text)
            )
        }
        return ChatAttachment(
            filename: filename,
            mimeType: "image/png",
            byteCount: 4,
            payload: .image(data: Data([0, 1, 2, 3]))
        )
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
    var modelIDs: [UUID] = []
}

@MainActor
private struct MockFactory: ChatProviderFactory {
    let recorder: RequestRecorder
    let scripts: [[MockStep]]
    let snapshotsByModelID: [UUID: ProviderTargetSnapshot]

    init(recorder: RequestRecorder, scripts: [[MockStep]], snapshotsByModelID: [UUID: ProviderTargetSnapshot] = [:]) {
        self.recorder = recorder
        self.scripts = scripts
        self.snapshotsByModelID = snapshotsByModelID
    }

    func makeProvider() throws -> any ChatProvider {
        let index = recorder.invocation
        recorder.invocation += 1
        return MockProvider(recorder: recorder, steps: scripts.indices.contains(index) ? scripts[index] : [])
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeTargetSnapshot(modelID: UUID) throws -> ProviderTargetSnapshot {
        recorder.modelIDs.append(modelID)
        if let snapshot = snapshotsByModelID[modelID] {
            return snapshot
        }
        return ProviderTargetSnapshot.testValue(modelID: modelID)
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        try makeProvider()
    }
}

private enum MockStep: Sendable {
    case reasoning(String)
    case answer(String)
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
                case let .reasoning(value): continuation.yield(.reasoningDelta(value))
                case let .answer(value): continuation.yield(.answerDelta(value))
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

@MainActor
private final class SnapshotFactory: ChatProviderFactory {
    private let snapshot: ProviderTargetSnapshot
    private let onSnapshot: () throws -> Void
    private let recorder = SnapshotRequestRecorder()
    var receivedTargets: [ProviderTargetSnapshot] { recorder.receivedTargets }
    var requests: [ChatRequest] { recorder.requests }

    init(snapshot: ProviderTargetSnapshot, onSnapshot: @escaping () throws -> Void) {
        self.snapshot = snapshot
        self.onSnapshot = onSnapshot
    }

    func makeProvider() throws -> any ChatProvider {
        try makeProvider(for: makeTargetSnapshot())
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        try onSnapshot()
        return snapshot
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        recorder.record(target: target)
        return SnapshotProvider(recorder: recorder)
    }
}

private struct SnapshotProvider: ChatProvider {
    let recorder: SnapshotRequestRecorder

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        recorder.record(request: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta("answer"))
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}

private final class SnapshotRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTargets: [ProviderTargetSnapshot] = []
    private var storedRequests: [ChatRequest] = []

    var receivedTargets: [ProviderTargetSnapshot] {
        lock.withLock { storedTargets }
    }

    var requests: [ChatRequest] {
        lock.withLock { storedRequests }
    }

    func record(target: ProviderTargetSnapshot) {
        lock.withLock { storedTargets.append(target) }
    }

    func record(request: ChatRequest) {
        lock.withLock { storedRequests.append(request) }
    }
}
