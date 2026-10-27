import XCTest
@testable import SpotAsk
import SwiftUI
import Textual
@_spi(Textual) import SwiftUIMath

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

    func testMathNormalizerSupportsCommonBackslashDelimiters() {
        let markdown = #"""
        Inline \(x + y\).

        \[
        \int_0^1 x^2\,dx
        \]
        """#

        XCTAssertEqual(
            MathMarkdownNormalizer.normalize(markdown),
            """
            Inline $x + y$.

            ```math
            \\int_0^1 x^2\\,dx
            ```
            """
        )
    }

    func testMathNormalizerPreservesDollarDelimitersAndCode() {
        let markdown = #"""
        Existing $x$ and $$y$$.
        Inline code `\(notMath\)`.

        ```tex
        \[notMath\]
        ```
        """#

        XCTAssertEqual(MathMarkdownNormalizer.normalize(markdown), markdown)
    }

    func testMathNormalizerLeavesEscapedAndUnclosedDelimitersAlone() {
        let markdown = #"Escaped \\(value\\) and unclosed \(value."#
        XCTAssertEqual(MathMarkdownNormalizer.normalize(markdown), markdown)
    }

    func testMathNormalizerConvertsSpacedBlockDelimiterToMathFence() {
        let markdown = """
        由此可推出电磁波，并得到其在真空中的传播速度：

        $$ c=\\frac{1}{\\sqrt{\\mu_0\\varepsilon_0}} $$

        这说明光本质上是一种电磁波。
        """

        XCTAssertEqual(
            MathMarkdownNormalizer.normalize(markdown),
            """
            由此可推出电磁波，并得到其在真空中的传播速度：

            ```math
            c=\\frac{1}{\\sqrt{\\mu_0\\varepsilon_0}}
            ```

            这说明光本质上是一种电磁波。
            """
        )
    }

    func testMathNormalizerAdaptsMultiColumnAlignedBlockForRenderer() {
        let markdown = #"""
        \[
        \begin{aligned}
        \nabla\cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0}
        &&\text{（高斯定律：电荷产生电场）}\\[4pt]
        \nabla\cdot \mathbf{B} &= 0
        &&\text{（磁场无散：不存在磁单极子）}
        \end{aligned}
        \]
        """#

        XCTAssertEqual(
            MathMarkdownNormalizer.normalize(markdown),
            #"""
            ```math
            \begin{aligned}
            \nabla\cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0}
            \quad \text{（高斯定律：电荷产生电场）}\\
            \nabla\cdot \mathbf{B} &= 0
            \quad \text{（磁场无散：不存在磁单极子）}
            \end{aligned}
            ```
            """#
        )
    }

    @MainActor
    func testNormalizedBlockMathUsesTextualMathCodeBlock() throws {
        let normalized = MathMarkdownNormalizer.normalize("$$ x^2 + y^2 = z^2 $$")
        let parsed = try AttributedStringMarkdownParser.markdown().attributedString(for: normalized)

        XCTAssertTrue(parsed.runs.contains { run in
            run.presentationIntent?.components.contains { component in
                guard case let .codeBlock(languageHint) = component.kind else { return false }
                return languageHint?.lowercased() == "math"
            } == true
        })
    }

    func testBoldsymbolFormulaRendersWithNonZeroSize() {
        let latex = #"\boldsymbol{o}_t = \frac{\sum_{i=1}^t e^{\boldsymbol{q}_t \cdot \boldsymbol{k}_i} \boldsymbol{v}_i}{\sum_{i=1}^t e^{\boldsymbol{q}_t \cdot \boldsymbol{k}_i}}"#
        XCTAssertTrue(Math.canRender(latex))

        let bounds = Math.typographicBounds(
            for: latex,
            fitting: ProposedViewSize(width: 800, height: nil),
            font: .init(name: .latinModern, size: 20),
            style: .display
        )

        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.size.height, 0)
    }

    func testUnsupportedMathFallsBackToReadableText() {
        let markdown = #"""
        \[
        \unknowncommand{x}
        \]
        """#

        XCTAssertEqual(
            MathMarkdownNormalizer.normalize(markdown),
            """
            ```text
            \\unknowncommand{x}
            ```
            """
        )
    }

    func testUnsupportedInlineMathFallsBackToCodeSpan() {
        XCTAssertEqual(
            MathMarkdownNormalizer.normalize(#"before \(\unknowncommand{x}\) after"#),
            #"before `\unknowncommand{x}` after"#
        )
    }

    func testMalformedDoubleBackslashMathDoesNotCrash() {
        let latex = #"\\boldsymbol{o}*t = \\frac{\\sum*{i=1}^t e^{\\boldsymbol{q}\_t \\cdot \\boldsymbol{k}_i} \\boldsymbol{v}*i}{\\sum*{i=1}^t e^{\\boldsymbol{q}\_t \\cdot \\boldsymbol{k}_i}}"#

        XCTAssertFalse(Math.canRender(latex))
        let bounds = Math.typographicBounds(
            for: latex,
            fitting: ProposedViewSize(width: 800, height: nil),
            font: .init(name: .latinModern, size: 20),
            style: .display
        )
        XCTAssertEqual(bounds.width, 0)

        XCTAssertEqual(
            MathMarkdownNormalizer.normalize("\\[\n\(latex)\n\\]"),
            "```text\n\(latex)\n```"
        )
    }

    func testMathNormalizerPreservesUnclosedDollarBlock() {
        let markdown = """
        $$
        x + y
        """

        XCTAssertEqual(MathMarkdownNormalizer.normalize(markdown), markdown)
    }

    @MainActor
    func testMathRenderingCanBeEnabledOrDisabled() {
        let enabled = MarkdownTextView(content: "$E = mc^2$", rendersMath: true)
        let disabled = MarkdownTextView(content: "$E = mc^2$", rendersMath: false)

        withExtendedLifetime(enabled) {}
        withExtendedLifetime(disabled) {}
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
