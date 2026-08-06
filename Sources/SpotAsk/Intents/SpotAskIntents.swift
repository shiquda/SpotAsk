import AppIntents
import Foundation

@MainActor
func enabledBuiltInPromptPreset(id: UUID, settings: AppSettings) -> PromptPreset? {
    guard PromptPreset.builtIn.contains(where: { $0.id == id }) else { return nil }
    return settings.enabledPromptPreset(id: id)
}

struct OpenSpotAskIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 SpotAsk"
    static let description = IntentDescription("打开 SpotAsk 的快速提问窗口。")

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await SpotAskCommandCenter.shared.open()
        return .result()
    }
}

struct AskSpotAskIntent: AppIntent {
    static let title: LocalizedStringResource = "问 AI？"
    static let description = IntentDescription(
        "在 SpotAsk 中提出一个问题并查看回答。",
        searchKeywords: ["问AI", "问 AI", "？", "?", "ask", "question"]
    )

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    @Parameter(title: "问题") var question: String

    init() {
        question = ""
    }

    init(question: String) {
        self.question = question
    }

    static var parameterSummary: some ParameterSummary {
        Summary("使用 SpotAsk 提问 \(\.$question)")
    }

    func perform() async throws -> some IntentResult {
        await SpotAskCommandCenter.shared.ask(question)
        return .result()
    }
}

struct TranslateWithSpotAskIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译"
    static let description = IntentDescription(
        "使用 SpotAsk 翻译内容。",
        searchKeywords: ["翻译", "问AI", "问 AI", "？", "?", "translate"]
    )

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    @Parameter(title: "内容") var text: String

    init() {
        text = ""
    }

    init(text: String) {
        self.text = text
    }

    static var parameterSummary: some ParameterSummary {
        Summary("使用 SpotAsk 翻译 \(\.$text)")
    }

    func perform() async throws -> some IntentResult {
        guard let preset = await MainActor.run(body: {
            enabledBuiltInPromptPreset(id: PromptPreset.builtIn[0].id, settings: AppSettings.shared)
        }) else {
            return .result()
        }
        await SpotAskCommandCenter.shared.ask(text, promptPreset: preset)
        return .result()
    }
}

struct PolishWithSpotAskIntent: AppIntent {
    static let title: LocalizedStringResource = "润色"
    static let description = IntentDescription(
        "使用 SpotAsk 润色内容。",
        searchKeywords: ["润色", "问AI", "问 AI", "？", "?", "polish", "rewrite"]
    )

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    @Parameter(title: "内容") var text: String

    init() {
        text = ""
    }

    init(text: String) {
        self.text = text
    }

    static var parameterSummary: some ParameterSummary {
        Summary("使用 SpotAsk 润色 \(\.$text)")
    }

    func perform() async throws -> some IntentResult {
        guard let preset = await MainActor.run(body: {
            enabledBuiltInPromptPreset(id: PromptPreset.builtIn[3].id, settings: AppSettings.shared)
        }) else {
            return .result()
        }
        await SpotAskCommandCenter.shared.ask(text, promptPreset: preset)
        return .result()
    }
}

struct SummarizeWithSpotAskIntent: AppIntent {
    static let title: LocalizedStringResource = "总结"
    static let description = IntentDescription(
        "使用 SpotAsk 总结内容。",
        searchKeywords: ["总结", "问AI", "问 AI", "？", "?", "summarize", "summary"]
    )

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    @Parameter(title: "内容") var text: String

    init() {
        text = ""
    }

    init(text: String) {
        self.text = text
    }

    static var parameterSummary: some ParameterSummary {
        Summary("使用 SpotAsk 总结 \(\.$text)")
    }

    func perform() async throws -> some IntentResult {
        guard let preset = await MainActor.run(body: {
            enabledBuiltInPromptPreset(id: PromptPreset.builtIn[2].id, settings: AppSettings.shared)
        }) else {
            return .result()
        }
        await SpotAskCommandCenter.shared.ask(text, promptPreset: preset)
        return .result()
    }
}

struct ExplainWithSpotAskIntent: AppIntent {
    static let title: LocalizedStringResource = "解释"
    static let description = IntentDescription(
        "使用 SpotAsk 解释内容。",
        searchKeywords: ["解释", "问AI", "问 AI", "？", "?", "explain"]
    )

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    @Parameter(title: "内容") var text: String

    init() {
        text = ""
    }

    init(text: String) {
        self.text = text
    }

    static var parameterSummary: some ParameterSummary {
        Summary("使用 SpotAsk 解释 \(\.$text)")
    }

    func perform() async throws -> some IntentResult {
        guard let preset = await MainActor.run(body: {
            enabledBuiltInPromptPreset(id: PromptPreset.builtIn[1].id, settings: AppSettings.shared)
        }) else {
            return .result()
        }
        await SpotAskCommandCenter.shared.ask(text, promptPreset: preset)
        return .result()
    }
}

struct NewSpotAskConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "开始新的 SpotAsk 对话"
    static let description = IntentDescription("清空当前对话并打开 SpotAsk。")

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @available(macOS, introduced: 13.0, deprecated: 26.0)
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await SpotAskCommandCenter.shared.startNewConversation()
        return .result()
    }
}

struct SpotAskShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSpotAskIntent(),
            phrases: ["打开 \(.applicationName)", "启动 \(.applicationName)"],
            shortTitle: "打开 SpotAsk",
            systemImageName: "sparkle"
        )
        AppShortcut(
            intent: AskSpotAskIntent(),
            phrases: ["使用 \(.applicationName) 提问", "让 \(.applicationName) 回答", "问 \(.applicationName)"],
            shortTitle: "问 AI？",
            systemImageName: "questionmark.bubble"
        )
        AppShortcut(
            intent: TranslateWithSpotAskIntent(),
            phrases: ["使用 \(.applicationName) 翻译"],
            shortTitle: "翻译",
            systemImageName: "translate"
        )
        AppShortcut(
            intent: ExplainWithSpotAskIntent(),
            phrases: ["使用 \(.applicationName) 解释"],
            shortTitle: "解释",
            systemImageName: "doc.text.magnifyingglass"
        )
        AppShortcut(
            intent: SummarizeWithSpotAskIntent(),
            phrases: ["使用 \(.applicationName) 总结"],
            shortTitle: "总结",
            systemImageName: "text.line.first.and.arrowtriangle.forward"
        )
        AppShortcut(
            intent: PolishWithSpotAskIntent(),
            phrases: ["使用 \(.applicationName) 润色"],
            shortTitle: "润色",
            systemImageName: "pencil.and.scribble"
        )
        AppShortcut(
            intent: NewSpotAskConversationIntent(),
            phrases: ["在 \(.applicationName) 开始新对话"],
            shortTitle: "新对话",
            systemImageName: "plus.bubble"
        )
    }
}
