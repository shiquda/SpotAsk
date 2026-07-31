import SwiftUI
import Testing
@testable import SpotAsk

struct SpotAskIntentTests {
    @Test @MainActor func deferredAskWaitsForPanelContentBeforeDispatching() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = AskQuestionRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .spotAskAskQuestion,
            object: nil,
            queue: nil
        ) { notification in
            recorder.question = notification.userInfo?["question"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        commandCenter.ask("冷启动问题")
        commandCenter.configure(panelController: panel)

        #expect(panel.didShow == false)
        #expect(recorder.question == nil)

        commandCenter.setPanelContent { EmptyView() }

        #expect(panel.didSetContent)
        #expect(panel.didShow)
        #expect(recorder.question == "冷启动问题")
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

private final class AskQuestionRecorder: @unchecked Sendable {
    var question: String?
}

@MainActor
private final class PanelControllerSpy: SpotAskPanelControlling {
    var didSetContent = false
    var didShow = false

    func setContent(_ content: @escaping () -> AnyView) {
        didSetContent = true
        _ = content()
    }

    func show() { didShow = true }
    func hide() {}
    func toggle() {}
    func toggleWindowOnTop() {}
}
