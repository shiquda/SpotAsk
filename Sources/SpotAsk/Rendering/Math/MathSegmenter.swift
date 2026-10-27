import Foundation

/// A message body split into markdown runs and display-math blocks.
///
/// Display math cannot stay inside the Textual text run: attachments are drawn
/// into a `Canvas` symbol, where a scroll view neither lays out nor scrolls.
/// Splitting it out lets the block own real scrolling and centring.
///
/// The document is parsed **once** as a whole before it is split: reference
/// link definitions, footnote definitions and list numbering are document-wide
/// rules, so every markdown run keeps the content Foundation resolved for it.
public enum MathMessageSegment: Identifiable {
    /// A markdown run. `text` is the plain rendering of `content` and is used
    /// only as the parser identity that lets Textual re-parse when it changes;
    /// `inlineFormulas` lets the view re-create the run only while its own
    /// formulas are still being rendered.
    case markdown(id: Int, content: AttributedString, text: String, inlineFormulas: [ExtractedFormula])
    case display(id: Int, formula: ExtractedFormula)

    public var id: Int {
        switch self {
        case let .markdown(id, _, _, _): id
        case let .display(id, _): id
        }
    }
}

public enum MathSegmenter {
    /// Isolates math, parses the whole document once, then cuts display math
    /// out of the parsed content.
    public static func segments(
        for content: String,
        fontSize: Double = 14.5
    ) -> [MathMessageSegment] {
        segments(for: MathIsolator.isolate(content), fontSize: fontSize)
    }

    /// Parses an already isolated document once and splits it.
    public static func segments(
        for document: IsolatedDocument,
        fontSize: Double = 14.5
    ) -> [MathMessageSegment] {
        let parser = NativeMathMarkupParser(isolated: document, fontSize: fontSize)
        let parsed =
            (try? parser.attributedString(for: document.sanitizedMarkdown))
            ?? AttributedString(document.sanitizedMarkdown)
        return segments(in: parsed, formulas: document.formulas)
    }

    /// Splits already parsed content. Display formulas become their own
    /// segment; every other formula stays inline with the surrounding text.
    public static func segments(
        in parsed: AttributedString,
        formulas: [ExtractedFormula]
    ) -> [MathMessageSegment] {
        let displayFormulas = formulas.filter(\.display)
        let inlineFormulas = formulas.filter { !$0.display }
        guard !displayFormulas.isEmpty else {
            let whole = trimmed(parsed)
            guard !whole.characters.isEmpty else { return [] }
            return [
                .markdown(
                    id: 0,
                    content: whole,
                    text: String(whole.characters),
                    inlineFormulas: inlineFormulas
                )
            ]
        }

        var segments: [MathMessageSegment] = []
        var cursor = parsed.startIndex
        var nextID = 0

        for formula in displayFormulas {
            guard let range = parsed[cursor...].range(of: formula.token) else { continue }
            let head = trimmed(AttributedString(parsed[cursor..<range.lowerBound]))
            if !head.characters.isEmpty {
                segments.append(
                    .markdown(
                        id: nextID,
                        content: head,
                        text: String(head.characters),
                        inlineFormulas: inlineFormulas
                    )
                )
                nextID += 1
            }
            segments.append(.display(id: nextID, formula: formula))
            nextID += 1
            cursor = range.upperBound
        }

        let tail = trimmed(AttributedString(parsed[cursor...]))
        if !tail.characters.isEmpty {
            segments.append(
                .markdown(
                    id: nextID,
                    content: tail,
                    text: String(tail.characters),
                    inlineFormulas: inlineFormulas
                )
            )
        }

        return segments
    }

    private static func trimmed(_ value: AttributedString) -> AttributedString {
        guard let first = value.characters.firstIndex(where: { !$0.isWhitespace }),
            let last = value.characters.lastIndex(where: { !$0.isWhitespace })
        else {
            return AttributedString()
        }
        return AttributedString(value[first...last])
    }
}
