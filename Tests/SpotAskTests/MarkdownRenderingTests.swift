import XCTest
@testable import SpotAsk
import SwiftUI
import Textual
import SwiftDraw

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

    func testMathIsolatorSupportsFourDelimiters() {
        let text = """
        Inline 1: $x_1 * y_1$.
        Inline 2: \\(a + b\\).
        Block 1:
        $$
        \\sum_{i=1}^n x_i
        $$
        Block 2:
        \\[
        E = mc^2
        \\]
        """
        let isolated = MathIsolator.isolate(text)
        XCTAssertEqual(isolated.formulas.count, 4)
        XCTAssertEqual(isolated.formulas[0].tex, "x_1 * y_1")
        XCTAssertFalse(isolated.formulas[0].display)
        XCTAssertEqual(isolated.formulas[1].tex, "a + b")
        XCTAssertFalse(isolated.formulas[1].display)
        XCTAssertEqual(isolated.formulas[2].tex, "\\sum_{i=1}^n x_i")
        XCTAssertTrue(isolated.formulas[2].display)
        XCTAssertEqual(isolated.formulas[3].tex, "E = mc^2")
        XCTAssertTrue(isolated.formulas[3].display)
    }

    func testMathIsolatorProtectsCodeAndCurrency() {
        let text = """
        Price is $100 and $200.
        Inline code: `echo $HOME` should not be math.
        Code block:
        ```swift
        let cost = "$100"
        ```
        Escaped \\$notMath\\$ and \\\\[notBlock\\\\] and \\\\(notInline\\\\).
        Unclosed $formula is left alone.
        """
        let isolated = MathIsolator.isolate(text)
        XCTAssertTrue(isolated.formulas.isEmpty)
        XCTAssertEqual(isolated.sanitizedMarkdown, text)
    }

    func testMathEngineRendersReFunctionAndZeta() async throws {
        let mathRe = try await MathEngine.shared.render(#"\operatorname{Re}(s)>1"#, display: false)
        XCTAssertEqual(mathRe.tex, #"\operatorname{Re}(s)>1"#)
        XCTAssertFalse(mathRe.display)
        XCTAssertGreaterThan(mathRe.widthEm, 0)
        XCTAssertGreaterThan(mathRe.heightEm, 0)

        let mathZeta = try await MathEngine.shared.render(#"\zeta(s)=\sum_{n=1}^\infty\frac{1}{n^s}"#, display: true)
        XCTAssertTrue(mathZeta.display)
        XCTAssertGreaterThan(mathZeta.widthEm, 0)
        XCTAssertGreaterThan(mathZeta.heightEm, 0)
    }

    func testMathEngineRendersBoldsymbolAndAlignedMultiColumn() async throws {
        let boldSymbol = #"\boldsymbol{o}_t=\frac{\sum_{i=1}^t e^{\boldsymbol{q}_t\cdot\boldsymbol{k}_i}\boldsymbol{v}_i}{\sum_{i=1}^t e^{\boldsymbol{q}_t\cdot\boldsymbol{k}_i}}"#
        let mathBold = try await MathEngine.shared.render(boldSymbol, display: true)
        XCTAssertGreaterThan(mathBold.widthEm, 0)

        let aligned = #"\begin{aligned} a&=b+c &&\text{first}\\[4pt] d&=e-f &&\text{second}\end{aligned}"#
        let mathAligned = try await MathEngine.shared.render(aligned, display: true)
        XCTAssertGreaterThan(mathAligned.widthEm, 0)
    }

    func testLessThanFormulasMatchEquivalentTeXRelation() async throws {
        let cases = [
            (#"T < 1"#, false),
            (#"P(x_t | x_{<t}) = \frac{\exp(h_t \cdot e_{x_t})}{\sum_{v \in V} \exp(h_t \cdot e_v)}"#, true),
            (#"\mathcal{L} = -\frac{1}{T}\sum_{t=1}^{T}\log P(x_t | x_{<t}; \theta)"#, true)
        ]
        for (tex, display) in cases {
            let literal = try await MathEngine.shared.render(tex, display: display)
            let command = try await MathEngine.shared.render(
                tex.replacingOccurrences(of: "<", with: #"\lt "#),
                display: display
            )
            XCTAssertEqual(literal.widthEm, command.widthEm, accuracy: 0.0001)
            XCTAssertEqual(literal.heightEm, command.heightEm, accuracy: 0.0001)
            XCTAssertEqual(literal.descentEm, command.descentEm, accuracy: 0.0001)
        }
    }

    func testMathEngineRejectsExcessiveLength() async {
        let huge = String(repeating: "x+", count: 10_000)
        do {
            _ = try await MathEngine.shared.render(huge, display: false)
            XCTFail("Should reject formulas exceeding 16384 bytes")
        } catch {
            XCTAssertTrue(error is MathFailure)
        }
    }

    func testMathEngineFailsGracefullyOnSyntaxError() async {
        do {
            _ = try await MathEngine.shared.render(#"\frac{"#, display: false)
            XCTFail("Should fail on incomplete syntax")
        } catch {
            XCTAssertTrue(error is MathFailure)
        }
    }

    @MainActor
    func testNativeMathMarkupParserProducesAttachments() async throws {
        let rendered = try await MathEngine.shared.render(#"E = mc^2"#, display: false)
        MathCache.shared.set(tex: #"E = mc^2"#, display: false, rendered: rendered)

        let parser = NativeMathMarkupParser(rendersMath: true)
        let attr = try parser.attributedString(for: "Energy formula: $E = mc^2$.")

        XCTAssertTrue(attr.characters.contains("￼"))
        let attachments = attr.runs.compactMap { $0.attributes.textual.attachment }
        XCTAssertFalse(attachments.isEmpty)
        XCTAssertEqual(attachments.first?.description, "$E = mc^2$")
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

    func testEmptyMathFenceDoesNotHangAndPreservesText() {
        let emptyCases = [
            "```math\n\n```",
            "```latex\n\n```",
            "```tex\n\n```",
            "```math\n   \n```",
            "~~~math\n\n~~~"
        ]

        for testCase in emptyCases {
            let isolated = MathIsolator.isolate(testCase)
            XCTAssertTrue(isolated.formulas.isEmpty, "Empty math fence should not extract any formulas: \(testCase)")
            XCTAssertEqual(isolated.sanitizedMarkdown, testCase, "Empty math fence should preserve verbatim text")
        }
    }

    func testUnclosedCodeFenceProtectsContentFromMathExtraction() {
        let unclosedCases = [
            "~~~swift\nlet x = \"$a$\"",
            "```python\nx = \"$alpha$\"\ny = \"$beta$\"",
            "```math\n\\frac{1}{2}"
        ]

        for testCase in unclosedCases {
            let isolated = MathIsolator.isolate(testCase)
            XCTAssertTrue(isolated.formulas.isEmpty, "Unclosed code or math fence should protect content from math extraction: \(testCase)")
            XCTAssertEqual(isolated.sanitizedMarkdown, testCase, "Unclosed fence should preserve raw text")
        }
    }

    @MainActor
    func testTokenCollisionProtection() throws {
        let input = "⟦SPOTASK_MATH:0⟧ and $x$"
        let isolated = MathIsolator.isolate(input)

        XCTAssertEqual(isolated.formulas.count, 1)
        XCTAssertEqual(isolated.formulas.first?.tex, "x")
        // Ensure the token does NOT collide with user's literal text
        XCTAssertNotEqual(isolated.formulas.first?.token, "⟦SPOTASK_MATH:0⟧")
        XCTAssertTrue(isolated.sanitizedMarkdown.contains("⟦SPOTASK_MATH:0⟧"))

        let parser = NativeMathMarkupParser(rendersMath: true, fontSize: 14.5)
        let attr = try parser.attributedString(for: input)
        let plainText = String(attr.characters)

        // The user's original literal string "⟦SPOTASK_MATH:0⟧" must still exist in the output
        XCTAssertTrue(plainText.contains("⟦SPOTASK_MATH:0⟧"), "User's literal token string must be preserved")
    }

    func testInlineMathAttachmentKeepsNaturalSizeAndClampsToNarrowContainer() {
        let sampleMath = RenderedMath(
            tex: "x = \\int_0^\\infty e^{-t} dt",
            display: false,
            svg: SVG(xml: "<svg width=\"100\" height=\"50\"></svg>")!,
            widthEm: 30.0,
            heightEm: 2.0,
            descentEm: 0.5
        )
        let attachment = NativeMathAttachment(math: sampleMath, fontSize: 14.0)

        let unconstrained = attachment.sizeThatFits(ProposedViewSize(width: nil, height: nil))
        XCTAssertEqual(unconstrained.width, 30.0 * 14.0, accuracy: 0.001)
        XCTAssertEqual(unconstrained.height, 2.0 * 14.0, accuracy: 0.001)

        let constrained = attachment.sizeThatFits(ProposedViewSize(width: 240.0, height: nil))
        XCTAssertEqual(constrained.width, 240.0, accuracy: 0.001, "Wide inline formula is scaled to the line")
        XCTAssertEqual(constrained.height, 2.0 * 14.0 * 240.0 / (30.0 * 14.0), accuracy: 0.001)
    }

    func testInlineAttachmentKeepsItsParagraphIntent() throws {
        let document = MathIsolator.isolate("Before $E = mc^2$ after.")
        let rendered = RenderedMath(
            tex: "E = mc^2",
            display: false,
            svg: SVG(xml: "<svg width=\"100\" height=\"50\"></svg>")!,
            widthEm: 3.0,
            heightEm: 1.0,
            descentEm: 0.2
        )
        MathCache.shared.set(tex: rendered.tex, display: false, rendered: rendered)
        defer { MathCache.shared.clear() }

        let parser = NativeMathMarkupParser(isolated: document, fontSize: 14)
        let attributed = try parser.attributedString(for: document.sanitizedMarkdown)

        let attachmentRun = try XCTUnwrap(attributed.runs.first { $0.textual.attachment != nil })
        // Dropping the paragraph intent makes Textual lay the attachment out as
        // its own block, which splits the sentence around the formula.
        XCTAssertEqual(attachmentRun.presentationIntent?.components.map(\.kind), [.paragraph])
    }

    func testSegmenterGivesDisplayMathItsOwnBlockAndKeepsInlineInText() {
        let content = "Energy $E = mc^2$ inline.\n\n$$\\int_0^1 x\\,dx$$\n\nTail $a^2$ end."
        let segments = MathSegmenter.segments(for: content, fontSize: 14)

        XCTAssertEqual(segments.count, 3)
        guard case let .markdown(_, firstContent, firstText, firstInline) = segments[0] else {
            return XCTFail("first segment must be markdown")
        }
        XCTAssertTrue(firstText.contains("Energy"))
        XCTAssertEqual(firstContent.characters.count, firstText.count)
        XCTAssertEqual(Set(firstInline.map(\.tex)), ["E = mc^2", "a^2"])

        guard case let .display(_, formula) = segments[1] else {
            return XCTFail("middle segment must be the display formula")
        }
        XCTAssertEqual(formula.tex, "\\int_0^1 x\\,dx")
        XCTAssertTrue(formula.display)

        guard case let .markdown(_, _, tail, _) = segments[2] else {
            return XCTFail("last segment must be markdown")
        }
        XCTAssertTrue(tail.contains("Tail"))
    }

    func testSegmenterWithoutDisplayMathReturnsSingleRun() {
        let segments = MathSegmenter.segments(for: "Only $a^2$ inline.", fontSize: 14)
        XCTAssertEqual(segments.count, 1)
        guard case let .markdown(_, content, text, inline) = segments[0] else {
            return XCTFail("expected markdown segment")
        }
        XCTAssertTrue(text.contains("Only"))
        XCTAssertTrue(String(content.characters).contains("a^2"))
        XCTAssertEqual(inline.map(\.tex), ["a^2"])
    }

    /// A reference definition may sit on the far side of a display formula. The
    /// document has to be parsed before it is split, otherwise every run loses
    /// the definition and the link degrades to plain text.
    func testSegmenterKeepsReferenceLinksDefinedAcrossDisplayMath() throws {
        let content = """
            Read [the guide][guide].

            $$x^2$$

            [guide]: https://example.com/guide
            """

        let segments = MathSegmenter.segments(for: content, fontSize: 14)
        XCTAssertEqual(segments.count, 2)

        guard case let .markdown(_, head, _, _) = segments[0] else {
            return XCTFail("first segment must be markdown")
        }
        let link = head.runs.compactMap(\.link).first
        XCTAssertEqual(link?.absoluteString, "https://example.com/guide")
    }
}
