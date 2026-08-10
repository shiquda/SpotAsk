import XCTest
import SwiftUI
@testable import Textual

final class TextualMarkdownFormatterTests: XCTestCase {
    func testMarkdownFormatterRestoresBlockAndInlineMarkers() throws {
        let source = """
        # Title

        Paragraph with **bold** and `inline code`.

        - first
        - second

        > quoted line

        ```swift
        let value = 1
        ```
        """
        let attributed = try AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions()
        )

        let rendered = Formatter(attributed).markdown()

        XCTAssertTrue(rendered.contains("# Title"))
        XCTAssertTrue(rendered.contains("**bold**"))
        XCTAssertTrue(rendered.contains("`inline code`"))
        XCTAssertTrue(rendered.contains("- first"))
        XCTAssertTrue(rendered.contains("- second"))
        XCTAssertTrue(rendered.contains("> quoted line"))
        XCTAssertTrue(rendered.contains("```swift"))
        XCTAssertTrue(rendered.contains("let value = 1"))
    }

    func testSelectionRectsKeepNativeSpacingAcrossLayouts() {
        let model = TextSelectionModel(
            layoutCollection: TestTextLayoutCollection(layouts: [
                makeLayout(origin: CGPoint(x: 0, y: 0), sliceWidths: [10]),
                makeLayout(origin: CGPoint(x: 20, y: 30), sliceWidths: [10]),
            ])
        )

        let rects = model.selectionRects(
            for: TextRange(start: model.startPosition, end: model.endPosition)
        )

        XCTAssertEqual(rects.map { $0.rect.integral }, [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 20, y: 30, width: 10, height: 10),
        ])
    }

    func testSelectionHighlightIsTranslucentAndAdaptsToAppearance() {
        let lightOpacity = AppKitSelectionHighlightStyle.opacity(for: .light)
        let darkOpacity = AppKitSelectionHighlightStyle.opacity(for: .dark)

        XCTAssertGreaterThan(lightOpacity, 0)
        XCTAssertLessThan(lightOpacity, 1)
        XCTAssertGreaterThan(darkOpacity, lightOpacity)
        XCTAssertLessThan(darkOpacity, 1)
    }

    func testMovingDownAcrossIndentedLayoutsUsesGlobalXCoordinate() {
        let model = TextSelectionModel(
            layoutCollection: TestTextLayoutCollection(layouts: [
                makeLayout(origin: CGPoint(x: 0, y: 0), sliceWidths: [10, 10]),
                makeLayout(origin: CGPoint(x: 100, y: 20), sliceWidths: [10, 10]),
            ])
        )
        let position = TextPosition(
            indexPath: .init(runSlice: 1, run: 0, line: 0, layout: 0),
            affinity: .upstream
        )

        let result = model.positionBelow(position, anchor: position)

        XCTAssertEqual(
            result,
            TextPosition(
                indexPath: .init(runSlice: 0, run: 0, line: 0, layout: 1),
                affinity: .downstream
            )
        )
    }

    private func makeLayout(origin: CGPoint, sliceWidths: [CGFloat]) -> TestTextLayout {
        var x: CGFloat = 0
        let slices = sliceWidths.enumerated().map { index, width in
            defer { x += width }
            return TestTextRunSlice(
                typographicBounds: CGRect(x: x, y: 0, width: width, height: 10),
                characterRange: index..<(index + 1)
            )
        }
        let width = sliceWidths.reduce(0, +)
        let bounds = CGRect(x: 0, y: 0, width: width, height: 10)
        let run = TestTextRun(typographicBounds: bounds, slices: slices)
        let line = TestTextLine(typographicBounds: bounds, runs: [run])

        return TestTextLayout(
            attributedString: NSAttributedString(
                string: String(repeating: "x", count: sliceWidths.count)
            ),
            origin: origin,
            bounds: bounds,
            lines: [line]
        )
    }
}

private struct TestTextLayoutCollection: TextLayoutCollection {
    let storedLayouts: [TestTextLayout]

    init(layouts: [TestTextLayout]) {
        storedLayouts = layouts
    }

    var layouts: [any Textual.TextLayout] { storedLayouts }

    func isEqual(to other: any TextLayoutCollection) -> Bool { false }
    func needsPositionReconciliation(with other: any TextLayoutCollection) -> Bool { false }
    func index(of layout: Text.Layout) -> Int? { nil }
}

private struct TestTextLayout: Textual.TextLayout {
    let attributedString: NSAttributedString
    let origin: CGPoint
    let bounds: CGRect
    let storedLines: [TestTextLine]

    init(
        attributedString: NSAttributedString,
        origin: CGPoint,
        bounds: CGRect,
        lines: [TestTextLine]
    ) {
        self.attributedString = attributedString
        self.origin = origin
        self.bounds = bounds
        storedLines = lines
    }

    var lines: [any Textual.TextLine] { storedLines }
}

private struct TestTextLine: Textual.TextLine {
    let origin = CGPoint.zero
    let typographicBounds: CGRect
    let storedRuns: [TestTextRun]

    init(typographicBounds: CGRect, runs: [TestTextRun]) {
        self.typographicBounds = typographicBounds
        storedRuns = runs
    }

    var runs: [any Textual.TextRun] { storedRuns }
}

private struct TestTextRun: Textual.TextRun {
    let layoutDirection = LayoutDirection.leftToRight
    let typographicBounds: CGRect
    let url: URL? = nil
    let storedSlices: [TestTextRunSlice]

    init(typographicBounds: CGRect, slices: [TestTextRunSlice]) {
        self.typographicBounds = typographicBounds
        storedSlices = slices
    }

    var slices: [any Textual.TextRunSlice] { storedSlices }
}

private struct TestTextRunSlice: Textual.TextRunSlice {
    let typographicBounds: CGRect
    let characterRange: Range<Int>
}
