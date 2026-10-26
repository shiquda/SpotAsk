import AppKit
import Foundation
import SwiftUI
import Textual

/// Renders a message that contains math: markdown runs keep Textual's typography
/// and selection, while display formulas are native blocks that centre and
/// scroll.
///
/// The document is parsed once (`MathSegmenter`), so links and other
/// document-wide Markdown rules are resolved before the body is split.
struct MathMessageBody: View {
    let content: String
    let fontSize: Double
    let pasteboard: NSPasteboard

    var body: some View {
        bodyContent(revision: MathCoordinator.shared.revision)
    }

    private func resolvedCount(_ formulas: [ExtractedFormula]) -> Int {
        formulas.reduce(0) { count, formula in
            let resolved =
                MathCache.shared.get(tex: formula.tex, display: false) != nil
                || MathCache.shared.hasFailed(tex: formula.tex, display: false) != nil
            return count + (resolved ? 1 : 0)
        }
    }

    @ViewBuilder
    private func bodyContent(revision: Int) -> some View {
        let segments = MathSegmentCache.shared.segments(
            content: content,
            fontSize: fontSize,
            revision: revision
        )

        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment {
                case let .markdown(_, attributed, text, inlineFormulas):
                    StructuredText(text, parser: PreParsedMarkupParser(attributed))
                        // Re-create the run only while its own formulas are
                        // still resolving: an unrelated render elsewhere in the
                        // message must not drop the current selection.
                        .id("\(fontSize)-\(resolvedCount(inlineFormulas))")
                        .textual.codeBlockStyle(CodeBlockView(pasteboard: pasteboard))
                        .textual.overflowMode(.wrap)
                        .textual.structuredTextStyle(.gitHub)
                        .textual.textSelection(.enabled)
                case let .display(_, formula):
                    DisplayMathView(tex: formula.tex, fontSize: fontSize)
                }
            }
        }
    }
}

/// Single-entry memo for the parsed segments of the message being displayed.
///
/// Parsing happens per body evaluation, and the body is evaluated for hover,
/// selection and scroll events as well; recomputing the whole document each
/// time is avoidable work as long as content, font size and render revision are
/// unchanged.
@MainActor
final class MathSegmentCache {
    static let shared = MathSegmentCache()

    private struct Key: Hashable {
        let content: String
        let fontSize: Double
    }

    private struct Entry {
        let formulas: [ExtractedFormula]
        let resolved: Int
        let segments: [MathMessageSegment]
    }

    private let limit = 12
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []

    /// Returns the segments for one message, re-parsing it only when one of its
    /// own formulas finishes rendering. A render elsewhere in the conversation
    /// must not re-parse every message on screen.
    func segments(content: String, fontSize: Double, revision: Int) -> [MathMessageSegment] {
        let key = Key(content: content, fontSize: fontSize)
        if let entry = entries[key] {
            let resolved = Self.resolvedCount(entry.formulas)
            if resolved == entry.resolved {
                return entry.segments
            }
        }

        let document = MathIsolator.isolate(content)
        let inlineFormulas = document.formulas.filter { !$0.display }
        let entry = Entry(
            formulas: inlineFormulas,
            resolved: Self.resolvedCount(inlineFormulas),
            segments: MathSegmenter.segments(for: document, fontSize: fontSize)
        )
        store(entry, for: key)
        return entry.segments
    }

    private func store(_ entry: Entry, for key: Key) {
        if entries[key] == nil {
            order.append(key)
            if order.count > limit {
                let evicted = order.removeFirst()
                entries.removeValue(forKey: evicted)
            }
        }
        entries[key] = entry
    }

    private static func resolvedCount(_ formulas: [ExtractedFormula]) -> Int {
        formulas.reduce(0) { count, formula in
            let resolved =
                MathCache.shared.get(tex: formula.tex, display: false) != nil
                || MathCache.shared.hasFailed(tex: formula.tex, display: false) != nil
            return count + (resolved ? 1 : 0)
        }
    }

    func clear() {
        entries.removeAll()
        order.removeAll()
    }
}
