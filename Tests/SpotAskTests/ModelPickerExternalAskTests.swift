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

    @Test("The query prefers the draft, then the most recent user turn")
    func queryPrefersDraftThenLatestUserTurn() {
        let messages = [
            ChatMessage(role: .user, content: "first question"),
            ChatMessage(role: .assistant, content: "first answer"),
            ChatMessage(role: .user, content: "  latest question  ")
        ]

        #expect(ModelPickerExternalAsk.query(input: "  draft  ", messages: messages) == "draft")
        #expect(ModelPickerExternalAsk.query(input: "", messages: messages) == "latest question")
        #expect(ModelPickerExternalAsk.query(input: "   ", messages: messages) == "latest question")
        #expect(ModelPickerExternalAsk.query(input: "", messages: []) == "")
        #expect(
            ModelPickerExternalAsk.query(
                input: "",
                messages: [ChatMessage(role: .assistant, content: "orphan answer")]
            ) == ""
        )
    }

    @Test("Launching from the picker keeps the conversation and clears only the consumed draft")
    func launchKeepsConversationAndClearsConsumedDraft() {
        let viewModel = makeViewModel()
        viewModel.messages = [
            ChatMessage(role: .user, content: "first question"),
            ChatMessage(role: .assistant, content: "first answer")
        ]
        var coordinator = ComposerModeCoordinator()
        coordinator.attachExternalAsk(grok, selectedPreset: &viewModel.selectedPromptPreset)
        let executor = RecordingQuickActionExecutor()
        var clearedComposerText = false

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            viewModel: viewModel,
            coordinator: &coordinator,
            clearComposerText: { clearedComposerText = true },
            executor: executor
        )

        #expect(outcome == .launched)
        // The history carried the topic, so the request went out with that text.
        #expect(executor.performed == [ResolvedQuickAction.resolve(chatGPT, query: "first question")])
        #expect(viewModel.messages.map(\.content) == ["first question", "first answer"])
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(viewModel.input == "")
        #expect(clearedComposerText)
    }

    @Test("The draft wins over the history and is the text that gets launched")
    func draftIsWhatGetsLaunched() {
        let viewModel = makeViewModel()
        viewModel.messages = [ChatMessage(role: .user, content: "old question")]
        viewModel.input = "  fresh question  "
        var coordinator = ComposerModeCoordinator()
        let executor = RecordingQuickActionExecutor()

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            viewModel: viewModel,
            coordinator: &coordinator,
            executor: executor
        )

        #expect(outcome == .launched)
        #expect(executor.performed == [ResolvedQuickAction.resolve(chatGPT, query: "fresh question")])
        #expect(viewModel.messages.map(\.content) == ["old question"])
        #expect(viewModel.input == "")
    }

    @Test("A failed launch keeps the draft untouched so the user can retry")
    func failedLaunchKeepsDraft() {
        let viewModel = makeViewModel()
        viewModel.input = "  hello world  "
        var coordinator = ComposerModeCoordinator()
        let executor = RecordingQuickActionExecutor()
        executor.shouldSucceed = false
        var clearedComposerText = false

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            viewModel: viewModel,
            coordinator: &coordinator,
            clearComposerText: { clearedComposerText = true },
            executor: executor
        )

        #expect(outcome == .launchFailed(chatGPT))
        #expect(viewModel.input == "  hello world  ")
        #expect(!clearedComposerText)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(executor.performed.isEmpty)
    }

    @Test("Without a draft and without a user turn the target mounts on the composer instead")
    func emptyComposerMountsTheTarget() {
        let viewModel = makeViewModel()
        viewModel.selectedPromptPreset = PromptPreset.builtIn[0]
        var coordinator = ComposerModeCoordinator()
        let executor = RecordingQuickActionExecutor()

        let outcome = ModelPickerExternalAsk.perform(
            chatGPT,
            viewModel: viewModel,
            coordinator: &coordinator,
            executor: executor
        )

        #expect(outcome == .becamePending)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(viewModel.selectedPromptPreset == nil)
        #expect(viewModel.messages.isEmpty)
        #expect(executor.performed.isEmpty)
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
