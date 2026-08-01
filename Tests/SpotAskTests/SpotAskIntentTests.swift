import AppKit
import SwiftUI
import Testing
@testable import SpotAsk

struct SpotAskIntentTests {
    @Test @MainActor func coldStartAskReachesHostedChatViewModelExactlyOnce() async {
        let commandCenter = SpotAskCommandCenter()
        let panel = HostingPanelController()
        let settings = makeSettings()
        let preset = PromptPreset(title: "翻译", instruction: "Translate accurately")
        let requestRecorder = RequestRecorder()
        let viewModel = ChatViewModel(
            settings: settings,
            providerFactory: ImmediateProviderFactory(recorder: requestRecorder),
            sessionStore: SessionStore(bundleIdentifier: "SpotAskIntentTests.\(UUID().uuidString)")
        )
        viewModel.messages = [
            ChatMessage(role: .user, content: "已恢复的问题", createdAt: .now.addingTimeInterval(-31 * 60)),
            ChatMessage(role: .assistant, content: "已恢复的回答", createdAt: .now.addingTimeInterval(-30 * 60))
        ]

        commandCenter.ask("冷启动问题", promptPreset: preset)
        commandCenter.configure(panelController: panel)

        #expect(panel.didShow == false)

        commandCenter.setPanelContent {
            ChatView(
                viewModel: viewModel,
                settings: settings,
                keyStore: EmptyKeyStore(),
                providerFactory: ImmediateProviderFactory(),
                commandCenter: commandCenter
            )
        }

        await waitForUserMessages(in: viewModel, count: 2)

        #expect(panel.didSetContent)
        #expect(panel.didShow)
        #expect(viewModel.isSessionChoicePending == false)
        #expect(viewModel.messages.filter { $0.role == .user }.map(\.content) == ["已恢复的问题", "冷启动问题"])
        #expect(viewModel.messages.last(where: { $0.role == .user })?.appliedPresetTitle == preset.title)
        #expect(requestRecorder.requestCount == 1)
    }

    @Test @MainActor func warmAskIsDeliveredToReadyConsumer() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        commandCenter.ask("暖路径问题")

        #expect(panel.didShow)
        #expect(recorder.actions == [.ask("暖路径问题", nil)])
    }

    @Test @MainActor func repeatedConsumerReadinessDoesNotReplayBufferedAction() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.ask("只发送一次")

        commandCenter.setActionConsumer { recorder.actions.append($0) }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(recorder.actions == [.ask("只发送一次", nil)])
    }

    @Test @MainActor func bufferedAskPreservesPromptPreset() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        let preset = PromptPreset(title: "翻译", instruction: "Translate accurately")
        commandCenter.ask("  Hello  ", promptPreset: preset)
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }

        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(recorder.actions == [.ask("Hello", preset)])
    }

    @Test @MainActor func bufferedDifferentActionsKeepFIFOOrder() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        let preset = PromptPreset(title: "翻译", instruction: "Translate accurately")

        commandCenter.prepare(promptPreset: preset)
        commandCenter.ask("问题")
        commandCenter.showSettings()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(recorder.actions == [.prepare(preset), .ask("问题", nil), .showSettings])
    }

    @Test @MainActor func askDuringGenerationKeepsPresetWithPendingDraft() async {
        let commandCenter = SpotAskCommandCenter()
        let panel = HostingPanelController()
        let settings = makeSettings()
        let requestRecorder = RequestRecorder()
        let viewModel = ChatViewModel(
            settings: settings,
            providerFactory: HoldingProviderFactory(recorder: requestRecorder),
            sessionStore: SessionStore(bundleIdentifier: "SpotAskIntentTests.\(UUID().uuidString)")
        )
        let preset = PromptPreset(title: "润色", instruction: "Polish carefully")

        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent {
            ChatView(
                viewModel: viewModel,
                settings: settings,
                keyStore: EmptyKeyStore(),
                providerFactory: HoldingProviderFactory(recorder: requestRecorder),
                commandCenter: commandCenter
            )
        }
        commandCenter.ask("正在回答的问题")
        await waitForGeneration(in: viewModel)

        commandCenter.ask("待发送的问题", promptPreset: preset)

        #expect(viewModel.input == "待发送的问题")
        #expect(viewModel.selectedPromptPreset == preset)
        #expect(viewModel.messages.filter { $0.role == .user }.map(\.content) == ["正在回答的问题"])
        #expect(requestRecorder.requestCount == 1)
        viewModel.cancel()
    }

    @Test func askIntentUsesConciseQuestionTitle() {
        #expect(String(describing: AskSpotAskIntent.title).contains("问 AI？"))
    }

    @Test func askIntentRegistersSpotlightAliases() {
        let keywords = String(describing: AskSpotAskIntent.description.searchKeywords)

        #expect(keywords.contains("问AI"))
        #expect(keywords.contains("问 AI"))
        #expect(keywords.contains("？"))
        #expect(keywords.contains("?"))
    }

    @Test func askIntentPreservesSpotlightQuestion() {
        let intent = AskSpotAskIntent(question: "Swift 的 actor 是什么？")

        #expect(intent.question == "Swift 的 actor 是什么？")
    }

    @Test func presetActionsHaveDirectSearchEntries() {
        let titles = [
            String(describing: TranslateWithSpotAskIntent.title),
            String(describing: PolishWithSpotAskIntent.title),
            String(describing: SummarizeWithSpotAskIntent.title),
            String(describing: ExplainCodeWithSpotAskIntent.title)
        ]
        let keywords = [
            String(describing: TranslateWithSpotAskIntent.description.searchKeywords),
            String(describing: PolishWithSpotAskIntent.description.searchKeywords),
            String(describing: SummarizeWithSpotAskIntent.description.searchKeywords),
            String(describing: ExplainCodeWithSpotAskIntent.description.searchKeywords)
        ]

        #expect(titles.joined(separator: "\n").contains("翻译"))
        for actionKeywords in keywords {
            #expect(actionKeywords.contains("问AI"))
            #expect(actionKeywords.contains("？"))
        }
    }

    @Test func presetActionsPreserveSpotlightText() {
        #expect(TranslateWithSpotAskIntent(text: "Hello").text == "Hello")
        #expect(PolishWithSpotAskIntent(text: "Hello").text == "Hello")
        #expect(SummarizeWithSpotAskIntent(text: "Hello").text == "Hello")
        #expect(ExplainCodeWithSpotAskIntent(text: "let x = 1").text == "let x = 1")
    }
}

@MainActor
private final class ActionRecorder {
    var actions: [SpotAskCommandAction] = []
}

private final class RequestRecorder: @unchecked Sendable {
    var requestCount = 0
}

@MainActor
private final class PanelControllerSpy: SpotAskPanelControlling {
    var didSetContent = false
    var didShow = false
    var isVisible = false

    func setContent(_ content: @escaping () -> AnyView) {
        didSetContent = true
        _ = content()
    }

    func show() {
        didShow = true
        isVisible = true
    }
    func hide() {}
    func toggle() { isVisible.toggle() }
    func toggleWindowOnTop() {}
}

@MainActor
private final class HostingPanelController: SpotAskPanelControlling {
    var didSetContent = false
    var didShow = false
    var isVisible = false
    private var hostingView: NSHostingView<AnyView>?
    private var contentBuilder: (() -> AnyView)?
    private var window: NSWindow?

    func setContent(_ content: @escaping () -> AnyView) {
        didSetContent = true
        contentBuilder = content
    }

    func show() {
        didShow = true
        isVisible = true
        guard hostingView == nil, let contentBuilder else {
            hostingView?.layoutSubtreeIfNeeded()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.mount(contentBuilder)
        }
    }

    private func mount(_ contentBuilder: @escaping () -> AnyView) {
        guard hostingView == nil else { return }
        let hostingView = NSHostingView(rootView: contentBuilder())
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        self.hostingView = hostingView
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        self.window = window
        window.orderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
    }

    func hide() { isVisible = false }
    func toggle() { isVisible.toggle() }
    func toggleWindowOnTop() {}
}

@MainActor
private func makeSettings() -> AppSettings {
    let suiteName = "SpotAskIntentTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return AppSettings(defaults: defaults)
}

@MainActor
private func waitForUserMessages(in viewModel: ChatViewModel, count: Int) async {
    for _ in 0 ..< 100 {
        if viewModel.messages.filter({ $0.role == .user }).count == count { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for \(count) user messages")
}

@MainActor
private func waitForGeneration(in viewModel: ChatViewModel) async {
    for _ in 0 ..< 100 {
        if viewModel.generationState == .streaming { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for a streaming response")
}

private struct EmptyKeyStore: APIKeyStoring {
    func readAPIKey(for providerID: UUID) throws -> String? { nil }
    func saveAPIKey(_ key: String, for providerID: UUID) throws {}
    func deleteAPIKey(for providerID: UUID) throws {}
    func deleteAllAPIKeys() throws {}
}

@MainActor
private struct ImmediateProviderFactory: ChatProviderFactory {
    let recorder: RequestRecorder?

    init(recorder: RequestRecorder? = nil) {
        self.recorder = recorder
    }

    func makeProvider() throws -> any ChatProvider { ImmediateProvider(recorder: recorder) }
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot { .testValue() }
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        ImmediateProvider(recorder: recorder)
    }
}

private struct ImmediateProvider: ChatProvider {
    let recorder: RequestRecorder?

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        recorder?.requestCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta("answer"))
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}

@MainActor
private struct HoldingProviderFactory: ChatProviderFactory {
    let recorder: RequestRecorder

    func makeProvider() throws -> any ChatProvider { HoldingProvider(recorder: recorder) }
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot { .testValue() }
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        HoldingProvider(recorder: recorder)
    }
}

private struct HoldingProvider: ChatProvider {
    let recorder: RequestRecorder

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        recorder.requestCount += 1
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    func testConnection() async throws {}
}
