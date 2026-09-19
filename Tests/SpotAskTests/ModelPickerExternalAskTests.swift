import Foundation
import Testing
@testable import SpotAsk

@Suite("Model picker External Ask")
@MainActor
struct ModelPickerExternalAskTests {
    private var chatGPT: QuickAction { QuickAction.builtIn[0] }
    private var grok: QuickAction { QuickAction.builtIn[1] }

    private func makeModel(_ displayName: String) -> ModelConfiguration {
        ModelConfiguration(
            displayName: displayName,
            upstreamModelID: displayName.lowercased(),
            providerID: UUID(),
            isStreamingEnabled: true
        )
    }

    private func makeViewModel() -> ChatViewModel {
        let suiteName = "SpotAskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        return ChatViewModel(
            settings: settings,
            providerFactory: StubProviderFactory(),
            sessionStore: SessionStore(bundleIdentifier: suiteName)
        )
    }

    @Test("The picker's search box also reaches External Ask targets")
    func searchFiltersExternalAsks() {
        let custom = QuickAction(name: "Perplexity", kind: .uriScheme(urlTemplate: "pplx://ask?q={query}"))
        let terminal = QuickAction(name: "omp", kind: .terminal(commandTemplate: "omp {query}"))
        let asks = [chatGPT, grok, custom, terminal]

        #expect(ModelPickerList.externalAsks(asks, matching: "   ").map(\.id) == asks.map(\.id))
        #expect(ModelPickerList.externalAsks(asks, matching: "chatgpt").map(\.id) == [chatGPT.id])
        #expect(ModelPickerList.externalAsks(asks, matching: "PERPLEXITY").map(\.id) == [custom.id])
        #expect(ModelPickerList.externalAsks(asks, matching: "应用").map(\.id) == [custom.id])
        #expect(ModelPickerList.externalAsks(asks, matching: "终端").map(\.id) == [terminal.id])
        #expect(ModelPickerList.externalAsks(asks, matching: "外部提问").map(\.id) == asks.map(\.id))
        #expect(ModelPickerList.externalAsks(asks, matching: "External Ask").map(\.id) == asks.map(\.id))
        #expect(ModelPickerList.externalAsks(asks, matching: "zzz").isEmpty)
    }

    @Test("Keyboard order runs the models first and the External Ask rows after")
    func keyboardOrderSpansModelsAndExternalAsks() {
        let models = [makeModel("GPT-5"), makeModel("Claude")]
        let ids = ModelPickerList.orderedIDs(models: models, externalAsks: [chatGPT, grok])
        #expect(ids == [models[0].id, models[1].id, chatGPT.id, grok.id])

        // Down walks off the last model onto the first External Ask, and the
        // highlight stops at both ends instead of wrapping.
        #expect(ModelPickerList.movedHighlight(from: models[1].id, in: ids, by: 1) == chatGPT.id)
        #expect(ModelPickerList.movedHighlight(from: chatGPT.id, in: ids, by: 1) == grok.id)
        #expect(ModelPickerList.movedHighlight(from: grok.id, in: ids, by: 1) == grok.id)
        #expect(ModelPickerList.movedHighlight(from: grok.id, in: ids, by: -1) == chatGPT.id)
        #expect(ModelPickerList.movedHighlight(from: models[0].id, in: ids, by: -1) == models[0].id)
        #expect(ModelPickerList.movedHighlight(from: nil, in: ids, by: 1) == models[0].id)
        #expect(ModelPickerList.movedHighlight(from: nil, in: [], by: 1) == nil)
    }

    @Test("A still-visible highlight survives narrowing; a filtered-away model does not")
    func highlightFollowsTheFilteredList() {
        let model = makeModel("GPT-5").id
        let ids = [chatGPT.id, grok.id]

        #expect(ModelPickerList.resolvedHighlight(current: grok.id, preferred: model, in: ids) == grok.id)
        #expect(ModelPickerList.resolvedHighlight(current: model, preferred: model, in: ids) == chatGPT.id)
        #expect(ModelPickerList.resolvedHighlight(current: nil, preferred: nil, in: ids) == chatGPT.id)
        #expect(ModelPickerList.resolvedHighlight(current: nil, preferred: nil, in: []) == nil)
    }

    @Test("Resolving the question extracts the preceding user turn for that assistant message")
    func questionExtractsUserTurnAnsweringTheTargetAssistantMessage() {
        let u1 = ChatMessage(role: .user, content: "first question")
        let a1 = ChatMessage(role: .assistant, content: "first answer")
        let u2 = ChatMessage(role: .user, content: "  second question  ")
        let a2 = ChatMessage(role: .assistant, content: "second answer")
        let messages = [u1, a1, u2, a2]

        #expect(ModelPickerExternalAsk.question(answering: a1.id, in: messages) == "first question")
        #expect(ModelPickerExternalAsk.question(answering: a2.id, in: messages) == "second question")
        #expect(ModelPickerExternalAsk.question(answering: u1.id, in: messages) == "")
        #expect(ModelPickerExternalAsk.question(answering: UUID(), in: messages) == "")
        #expect(
            ModelPickerExternalAsk.question(
                answering: a1.id,
                in: [ChatMessage(role: .assistant, content: "orphan answer")]
            ) == ""
        )
    }

    @Test("Launching from the retry picker carries the question and leaves conversation and draft untouched")
    func launchCarriesAnswerQuestionAndKeepsConversationAndDraft() {
        let viewModel = makeViewModel()
        let u1 = ChatMessage(role: .user, content: "first question")
        let a1 = ChatMessage(role: .assistant, content: "first answer")
        viewModel.messages = [u1, a1]
        viewModel.input = "unrelated draft"
        var coordinator = ComposerModeCoordinator()
        coordinator.attachExternalAsk(grok, selectedPreset: &viewModel.selectedPromptPreset)
        let executor = RecordingQuickActionExecutor()

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            answering: a1.id,
            viewModel: viewModel,
            coordinator: &coordinator,
            executor: executor
        )

        #expect(outcome == .launched)
        #expect(executor.performed == [ResolvedQuickAction.resolve(chatGPT, query: "first question")])
        #expect(viewModel.messages.map(\.content) == ["first question", "first answer"])
        #expect(viewModel.input == "unrelated draft")
        #expect(coordinator.pendingExternalAsk == grok)
    }

    @Test("A failed launch reports failure and keeps the conversation and draft untouched")
    func failedLaunchKeepsDraft() {
        let viewModel = makeViewModel()
        let u1 = ChatMessage(role: .user, content: "hello world")
        let a1 = ChatMessage(role: .assistant, content: "answer")
        viewModel.messages = [u1, a1]
        viewModel.input = "draft"
        var coordinator = ComposerModeCoordinator()
        let executor = RecordingQuickActionExecutor()
        executor.shouldSucceed = false

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            answering: a1.id,
            viewModel: viewModel,
            coordinator: &coordinator,
            executor: executor
        )

        #expect(outcome == .launchFailed(chatGPT))
        #expect(viewModel.input == "draft")
        #expect(executor.performed.isEmpty)
    }

    @Test("Without a question for the answer the target mounts on the composer instead")
    func emptyQuestionMountsTheTarget() {
        let viewModel = makeViewModel()
        let orphanAnswer = ChatMessage(role: .assistant, content: "orphan")
        viewModel.messages = [orphanAnswer]
        viewModel.selectedPromptPreset = PromptPreset.builtIn[0]
        var coordinator = ComposerModeCoordinator()
        let executor = RecordingQuickActionExecutor()

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            answering: orphanAnswer.id,
            viewModel: viewModel,
            coordinator: &coordinator,
            executor: executor
        )

        #expect(outcome == .becamePending)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(viewModel.selectedPromptPreset == nil)
        #expect(executor.performed.isEmpty)
    }

    @Test("Resetting the coordinator clears pending External Ask and skip flag")
    func coordinatorResetClearsPendingExternalAsk() {
        var coordinator = ComposerModeCoordinator()
        var preset: PromptPreset?
        coordinator.attachExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(coordinator.skipEmptyPendingClear == true)

        coordinator.reset()
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(coordinator.skipEmptyPendingClear == false)
    }
}

@MainActor
private final class RecordingQuickActionExecutor: QuickActionExecuting, @unchecked Sendable {
    var shouldSucceed = true
    var performed: [ResolvedQuickAction] = []

    func perform(_ resolved: ResolvedQuickAction) -> Bool {
        guard shouldSucceed else { return false }
        performed.append(resolved)
        return true
    }
}

private struct StubProviderFactory: ChatProviderFactory {
    struct Unused: Error {}

    func makeProvider() throws -> any ChatProvider { throw Unused() }
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot { throw Unused() }
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider { throw Unused() }
}
