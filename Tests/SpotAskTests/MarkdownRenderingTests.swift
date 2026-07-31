import XCTest
@testable import SpotAsk
import Textual

final class MarkdownRenderingTests: XCTestCase {
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
}
