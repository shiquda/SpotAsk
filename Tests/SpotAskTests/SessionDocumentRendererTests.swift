import Foundation
import JavaScriptCore
import XCTest
@testable import SpotAsk

final class SessionDocumentRendererTests: XCTestCase {
    private var context: JSContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        context = JSContext()
        context.exceptionHandler = { _, exception in
            XCTFail("JS Exception: \(String(describing: exception))")
        }

        let global = context.globalObject!
        global.setValue(global, forProperty: "window")
        global.setValue(global, forProperty: "globalThis")

        guard let dir = SessionDocumentResources.directoryURL else {
            XCTFail("SessionDocument directory not found")
            return
        }

        let vendor = dir.appendingPathComponent("vendor")
        let mdURL = vendor.appendingPathComponent("markdown-it.min.js")
        let katexURL = vendor.appendingPathComponent("katex.min.js")
        let texmathURL = vendor.appendingPathComponent("texmath.js")
        let docURL = dir.appendingPathComponent("document.js")

        let mdCode = try String(contentsOf: mdURL, encoding: .utf8)
        let katexCode = try String(contentsOf: katexURL, encoding: .utf8)
        let texmathCode = try String(contentsOf: texmathURL, encoding: .utf8)
        let docCode = try String(contentsOf: docURL, encoding: .utf8)

        context.evaluateScript(mdCode)
        context.evaluateScript(katexCode)
        context.evaluateScript(texmathCode)
        context.evaluateScript(docCode)
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    private func render(_ markdown: String, renderMath: Bool = true) -> String {
        let fn = context.objectForKeyedSubscript("SessionDocument").objectForKeyedSubscript("renderMarkdown")!
        let result = fn.call(withArguments: [markdown, renderMath])!
        return result.toString()
    }

    // MARK: - Delimiter Tests

    func testInlineDollarMathRendersKaTeX() {
        let html = render("Formula $E = mc^2$ is classic")
        XCTAssertTrue(html.contains("class=\"katex\""), "Expected katex class in: \(html)")
        XCTAssertTrue(html.contains("annotation encoding=\"application/x-tex\">E = mc^2<"), "Expected annotation")
        XCTAssertFalse(html.contains("katex-error"))
    }

    func testBlockDollarMathRendersDisplayKaTeX() {
        let html = render("$$\n\\sum_{n=1}^\\infty \\frac{1}{n^2} = \\frac{\\pi^2}{6}\n$$")
        XCTAssertTrue(html.contains("katex-display"))
        XCTAssertTrue(html.contains("class=\"katex\""))
        XCTAssertFalse(html.contains("katex-error"))
    }

    func testInlineParenthesisMathRendersKaTeX() {
        let html = render("When \\(\\operatorname{Re}(s) > 1\\) holds")
        XCTAssertTrue(html.contains("class=\"katex\""), "Expected katex in: \(html)")
        XCTAssertTrue(html.contains("operatorname") || html.contains("Re"))
        XCTAssertFalse(html.contains("katex-error"))
    }

    func testBlockBracketMathRendersDisplayKaTeX() {
        let html = render("\\[\n\\zeta(s) = \\frac{1}{2}\n\\]")
        XCTAssertTrue(html.contains("katex-display"))
        XCTAssertFalse(html.contains("katex-error"))
    }

    // MARK: - Acceptance Criteria: Riemann Hypothesis Fixture

    func testRiemannHypothesisFullAnswerRendersAccurately() {
        let riemann = """
        黎曼猜想涉及黎曼 $\\zeta$ 函数：

        $$
        \\zeta(s) = \\sum_{n=1}^{\\infty} \\frac{1}{n^s} = \\prod_{p \\text{ 为素数}} \\frac{1}{1 - p^{-s}}
        $$

        并在全复平面上有解析延拓。非平凡零点位于临界带 $0 < \\operatorname{Re}(s) < 1$。猜想：所有非平凡零点其实都位于临界线：

        \\[
        \\operatorname{Re}(s) = \\frac{1}{2}
        \\]

        负偶数 $s = -2, -4, -6, \\dots$ 是平凡零点。
        """

        let html = render(riemann)
        XCTAssertFalse(html.contains("katex-error"), "KaTeX should parse all formulas without error: \(html)")
        XCTAssertTrue(html.contains("ζ") || html.contains("zeta"), "Expected zeta in mathml: \(html)")
        XCTAssertTrue(html.contains("operatorname") || html.contains("Re"), "Expected operatorname: \(html)")
        XCTAssertTrue(html.contains("dots") || html.contains("…"), "Expected dots: \(html)")
        XCTAssertTrue(html.contains("katex-display"), "Expected display equations")
        XCTAssertFalse(html.contains("```text"), "Should not fall back to text block")
    }

    // MARK: - False Positive Guards

    func testCurrencyDoesNotRenderAsMath() {
        let html = render("$5 和 $10 不是公式")
        XCTAssertFalse(html.contains("class=\"katex\""), "Currency must not match math: \(html)")
        XCTAssertTrue(html.contains("$5 和 $10 不是公式"))
    }

    func testEscapedDollarsDoNotRenderAsMath() {
        let html = render("Here is \\$5\\$ literal text")
        XCTAssertFalse(html.contains("class=\"katex\""), "Escaped dollars must stay literal: \(html)")
    }

    func testInlineCodeProtectsMathDelimiters() {
        let html = render("Run `$x$` and `\\(y\\)` inside code")
        XCTAssertTrue(html.contains("<code>$x$</code>"))
        XCTAssertTrue(html.contains("<code>\\(y\\)</code>"))
        XCTAssertFalse(html.contains("class=\"katex\""))
    }

    func testFencedCodeProtectsMathDelimiters() {
        let html = render("```python\n$x$ = 1\n\\[y\\] = 2\n```")
        XCTAssertTrue(html.contains("<code"))
        XCTAssertTrue(html.contains("$x$ = 1"))
        XCTAssertFalse(html.contains("class=\"katex\""))
    }

    func testStarsInsideFormulaDoNotBecomeEmphasis() {
        let html = render("Formula $x^{*}+y^{*}$ preserved")
        XCTAssertTrue(html.contains("class=\"katex\""))
        XCTAssertFalse(html.contains("<em>"))
    }

    func testMathCanBeDisabledViaSetting() {
        let withMath = render("$E = mc^2$", renderMath: true)
        let withoutMath = render("$E = mc^2$", renderMath: false)
        XCTAssertTrue(withMath.contains("class=\"katex\""))
        XCTAssertFalse(withoutMath.contains("class=\"katex\""))
        XCTAssertTrue(withoutMath.contains("$E = mc^2$"))
    }

    // MARK: - Security Guards

    func testScriptTagsAreSanitized() {
        let html = render("<script>alert(1)</script>")
        XCTAssertFalse(html.contains("<script>"), "Raw script tag must not exist: \(html)")
        XCTAssertTrue(html.contains("&lt;script&gt;"), "Script tag should be escaped as text: \(html)")
    }

    func testJavaScriptLinksAreSanitized() {
        let html = render("[click](javascript:alert(1))")
        XCTAssertFalse(html.contains("<a href=\"javascript:"), "javascript: link must never be an href: \(html)")
    }

    func testKaTeXTrustIsFalse() {
        let html = render("$\\href{http://evil.com}{click}$")
        XCTAssertFalse(html.contains("href=\"http://evil.com\""))
    }

    // MARK: - Streaming Document Splitter

    func testStreamingBodySeparatesStablePrefixFromTail() {
        let fn = context.objectForKeyedSubscript("SessionDocument").objectForKeyedSubscript("streamingBody")!
        let source = "第一段已完成。\n\n第二段 $E = mc^2$\n\n第三段\n\n```swift\nlet x = 1"
        let result = fn.call(withArguments: [source, true, false])!
        let mode = result.objectForKeyedSubscript("mode")!.toString()
        let stableHTML = result.objectForKeyedSubscript("stableHTML")!.toString()
        let tailText = result.objectForKeyedSubscript("tailText")!.toString()

        XCTAssertEqual(mode, "streaming")
        XCTAssertTrue(stableHTML?.contains("katex") == true, "Stable portion should have rendered math")
        XCTAssertTrue(tailText?.contains("```swift") == true, "Unclosed fence must stay raw tail")
    }

    func testCompletedStreamProducesFullDocument() {
        let fn = context.objectForKeyedSubscript("SessionDocument").objectForKeyedSubscript("streamingBody")!
        let source = "第一段已完成。\n\n```swift\nlet x = 1\n```\n"
        let result = fn.call(withArguments: [source, true, true])!
        let mode = result.objectForKeyedSubscript("mode")!.toString()
        let html = result.objectForKeyedSubscript("html")?.toString()

        XCTAssertEqual(mode, "complete")
        XCTAssertTrue(html?.contains("<code") == true)
    }

    // MARK: - Bridge Validation

    func testBridgeRejectsMismatchedGeneration() {
        let id = UUID()
        let action = SessionDocumentAction.parse(
            body: ["generation": "wrong", "type": "copy-message", "messageID": id.uuidString],
            expectedGeneration: "current",
            knownMessageIDs: [id]
        )
        XCTAssertNil(action)
    }

    func testBridgeRejectsUnknownMessageID() {
        let known = UUID()
        let unknown = UUID()
        let action = SessionDocumentAction.parse(
            body: ["generation": "current", "type": "copy-message", "messageID": unknown.uuidString],
            expectedGeneration: "current",
            knownMessageIDs: [known]
        )
        XCTAssertNil(action)
    }

    func testBridgeAcceptsValidAction() {
        let id = UUID()
        let action = SessionDocumentAction.parse(
            body: ["generation": "current", "type": "copy-message", "messageID": id.uuidString],
            expectedGeneration: "current",
            knownMessageIDs: [id]
        )
        XCTAssertEqual(action, .copyMessage(id: id))
    }

    func testBridgeRejectsNonHTTPURL() {
        let action = SessionDocumentAction.parse(
            body: ["generation": "current", "type": "open-link", "url": "javascript:alert(1)"],
            expectedGeneration: "current",
            knownMessageIDs: []
        )
        XCTAssertNil(action)
    }

    func testBridgeAcceptsHTTPSURL() {
        let action = SessionDocumentAction.parse(
            body: ["generation": "current", "type": "open-link", "url": "https://example.com"],
            expectedGeneration: "current",
            knownMessageIDs: []
        )
        XCTAssertEqual(action, .openLink(url: URL(string: "https://example.com")!))
    }

    // MARK: - Snapshot Builder Excludes Secrets

    @MainActor
    func testSnapshotBuilderExcludesAPIKeysAndSystemPrompts() {
        let settings = AppSettings()
        let userMsg = ChatMessage(role: .user, content: "Hello $x$")
        let systemMsg = ChatMessage(role: .system, content: "Secret system prompt with API key sk-12345")
        let assistantMsg = ChatMessage(role: .assistant, content: "Answer $y$")

        let snapshot = SessionDocumentSnapshotBuilder.make(
            messages: [systemMsg, userMsg, assistantMsg],
            settings: settings,
            effectiveAppearance: nil,
            generation: "gen-1",
            copiedMessageID: nil,
            isReasoningExpanded: { _ in false },
            isAssistantExpanded: { _ in false },
            canInsertSelection: { _ in false },
            pendingExternalAskID: nil,
            showsShortcutHints: false,
            shortcutHint: { _ in nil },
            followsLatest: true
        )

        XCTAssertEqual(snapshot.messages.count, 2, "System messages must be filtered out")
        let dict = snapshot.toDictionary()!
        let jsonString = String(data: try! JSONSerialization.data(withJSONObject: dict), encoding: .utf8)!
        XCTAssertFalse(jsonString.contains("Secret system prompt"))
        XCTAssertFalse(jsonString.contains("sk-12345"))
        XCTAssertTrue(jsonString.contains("Hello $x$"))
        XCTAssertTrue(jsonString.contains("Answer $y$"))
    }
 
     @MainActor
     func testMessageActionsMatchNativeToolbar() {
         let user = ChatMessage(role: .user, content: "Question")
         let assistant = ChatMessage(
             role: .assistant,
             content: "Answer",
             modelDisplayName: "Claude 3.7 Sonnet",
             providerName: "Anthropic"
         )
         let failedUser = ChatMessage(role: .user, content: "Failed question")
         let failedAssistant = ChatMessage(role: .assistant, content: "partial", state: .failed)
 
         let idle = SessionDocumentSnapshotBuilder.make(
             messages: [user, assistant],
             settings: AppSettings(),
             effectiveAppearance: nil,
             generation: "gen",
             copiedMessageID: nil,
             isReasoningExpanded: { _ in false },
             isAssistantExpanded: { _ in false },
             canInsertSelection: { _ in true },
             pendingExternalAskID: nil,
             showsShortcutHints: false,
             shortcutHint: { _ in nil },
             followsLatest: true
         )
         XCTAssertEqual(idle.messages.count, 2)
         XCTAssertFalse(idle.messages[0].canRetryUser)
         XCTAssertFalse(idle.messages[0].canRegenerate)
         XCTAssertTrue(idle.messages[1].canCopy)
         XCTAssertTrue(idle.messages[1].canInsert)
         XCTAssertTrue(idle.messages[1].canRegenerate)
         XCTAssertTrue(idle.messages[1].canRetryWithModel)
         XCTAssertTrue(idle.messages[1].isLatest)
         XCTAssertEqual(idle.messages[1].iconSlug, "claude-color")
         XCTAssertEqual(idle.messages[1].metadata, "Claude 3.7 Sonnet")
         XCTAssertFalse(idle.messages[1].canRetry)
 
         let failed = SessionDocumentSnapshotBuilder.make(
             messages: [failedUser, failedAssistant],
             settings: AppSettings(),
             effectiveAppearance: nil,
             generation: "gen",
             copiedMessageID: nil,
             isReasoningExpanded: { _ in false },
             isAssistantExpanded: { _ in false },
             canInsertSelection: { _ in false },
             pendingExternalAskID: nil,
             showsShortcutHints: false,
             shortcutHint: { _ in nil },
             followsLatest: true,
             generationState: .failed
         )
         XCTAssertTrue(failed.messages[0].canRetryUser)
         XCTAssertFalse(failed.messages[1].canRegenerate)
         XCTAssertTrue(failed.messages[1].canRetry)
         XCTAssertEqual(failed.messages[1].cancelledText, nil)
         XCTAssertEqual(failed.messages[1].errorText, L10n.string("chat.requestFailed"))
     }
}
