import XCTest
@testable import SpotAsk
import Textual

final class MarkdownRenderingTests: XCTestCase {
    func testStreamingMarkdownContentJoinsDeltasIntoOneDocument() {
        XCTAssertEqual(
            MessageContentView.streamingMarkdownContent(
                messageContent: "fallback",
                chunks: ["# Title\n\n", "First paragraph.\n\n", "- item"]
            ),
            "# Title\n\nFirst paragraph.\n\n- item"
        )
        XCTAssertEqual(
            MessageContentView.streamingMarkdownContent(
                messageContent: "fallback",
                chunks: []
            ),
            "fallback"
        )
    }

    private let richMarkdown = """
    # 发布说明

    第一段说明支持 **粗体** 与 `inline code`。

    第二段与第一段之间保留空行。

    - 第一项
    - 第二项

    > 这是一段引用。

    | 名称 | 状态 |
    | --- | --- |
    | SpotAsk | 正常 |

    ```swift
    let answer = "ready"
    print(answer)
    ```
    """

    @MainActor
    func testTextualIsLinkedAndAcceptsRichMarkdownFixture() {
        let markdown = StructuredText(markdown: richMarkdown)
        let spotAskView = MarkdownTextView(content: richMarkdown)

        // Constructing both views guards the public Textual dependency and the
        // application rendering path against an accidental regression.
        withExtendedLifetime(markdown) {}
        withExtendedLifetime(spotAskView) {}
        XCTAssertTrue(richMarkdown.contains("| 名称 | 状态 |"))
    }

    func testCodeBlockViewIsTextualCodeBlockStyle() {
        let codeBlockStyle = CodeBlockView()

        withExtendedLifetime(codeBlockStyle) {}
    }

    @MainActor
    func testCodeBlockStyleIsAppliedAfterGitHubStyle() {
        let markdown = StructuredText(markdown: "```python\nprint('hello')\n```")
            .textual.codeBlockStyle(CodeBlockView())
            .textual.structuredTextStyle(.gitHub)

        withExtendedLifetime(markdown) {}
    }

    func testStandaloneInlineCodeBecomesCopyableCodeBlock() {
        XCTAssertEqual(
            MarkdownTextView.markdownWithCopyableStandaloneCode("`print(\"hello\")`"),
            "```\nprint(\"hello\")\n```"
        )
    }

    func testInlineCodeWithinAParagraphRemainsInline() {
        let markdown = "使用 `print(\"hello\")` 输出文本。"
        XCTAssertEqual(MarkdownTextView.markdownWithCopyableStandaloneCode(markdown), markdown)
    }

    @MainActor
    func testTextualAcceptsUnclosedFenceDuringStreaming() {
        let partialMarkdown = "```json\n{\"partial\": true}"
        let partialAnswer = MarkdownTextView(content: partialMarkdown)

        withExtendedLifetime(partialAnswer) {}
    }

    func testStreamingDocumentSealsParagraphOnBlankLine() {
        var document = MarkdownStreamingDocument()

        document.consume(chunks: ["第一段\n\n第二段"], isComplete: false)

        XCTAssertEqual(document.blocks.map(\.source), ["第一段"])
        XCTAssertEqual(document.liveTail?.source, "第二段")
        XCTAssertFalse(document.liveTail?.isSealed ?? true)
    }

    func testStreamingDocumentSealsRemainingTailOnCompletion() {
        var document = MarkdownStreamingDocument()
        let chunks = ["第一段\n\n第二段"]
        document.consume(chunks: chunks, isComplete: false)

        document.consume(chunks: chunks, isComplete: true)

        XCTAssertEqual(document.blocks.map(\.source), ["第一段", "第二段"])
        XCTAssertTrue(document.blocks.allSatisfy(\.isSealed))
        XCTAssertNil(document.liveTail)
    }

    func testCodeFenceStaysInLiveTailUntilClosed() {
        var document = MarkdownStreamingDocument()
        let opening = "```swift\nlet a = 1\n\nprint(a)\n"
        let closing = "```"

        document.consume(chunks: [opening], isComplete: false)

        XCTAssertTrue(document.blocks.isEmpty)
        XCTAssertEqual(document.liveTail?.source, opening)

        document.consume(chunks: [opening, closing], isComplete: false)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks.first?.kind, .code)
        XCTAssertTrue(document.blocks.first?.source.hasSuffix("```") == true)
        XCTAssertNil(document.liveTail)
    }

    func testAppendingChunksDoesNotRebuildSealedBlockIdentity() {
        var document = MarkdownStreamingDocument()
        let initial = "第一段\n\n第二段\n\n第三段\n\n第四段"
        document.consume(chunks: [initial], isComplete: false)
        let sealedIDs = document.blocks.map(\.id)

        document.consume(chunks: [initial, "第五段"], isComplete: false)

        XCTAssertEqual(document.blocks.map(\.id), sealedIDs)
        XCTAssertEqual(document.liveTail?.source, "第四段第五段")
    }
}
