import Foundation
import SwiftUI
import Textual

/// Parses markdown into attributed content, replacing math tokens with
/// Textual attachments.
///
/// Only *inline* math is attached. Display math is laid out by
/// `DisplayMathView` outside the text run, because Textual draws attachments
/// into a `Canvas` symbol where scroll views and buttons are neither laid out
/// nor interactive.
public struct NativeMathMarkupParser: MarkupParser {
    public let baseURL: URL?
    public let options: AttributedString.MarkdownParsingOptions
    public let rendersMath: Bool
    public let fontSize: Double
    /// When set, the parser consumes an already isolated document instead of
    /// isolating `input` again. Callers that split a message into segments
    /// isolate once and reuse the result so tokens keep their nonce.
    private let preisolated: IsolatedDocument?

    nonisolated public init(
        baseURL: URL? = nil,
        options: AttributedString.MarkdownParsingOptions = .init(),
        rendersMath: Bool = true,
        fontSize: Double = 14.5
    ) {
        self.baseURL = baseURL
        self.options = options
        self.rendersMath = rendersMath
        self.fontSize = fontSize
        self.preisolated = nil
    }

    nonisolated public init(
        baseURL: URL? = nil,
        options: AttributedString.MarkdownParsingOptions = .init(),
        isolated: IsolatedDocument,
        fontSize: Double = 14.5
    ) {
        self.baseURL = baseURL
        self.options = options
        self.rendersMath = true
        self.fontSize = fontSize
        self.preisolated = isolated
    }

    nonisolated public func attributedString(for input: String) throws -> AttributedString {
        guard rendersMath else {
            return try AttributedString(
                markdown: input,
                including: \.textual,
                options: options,
                baseURL: baseURL
            )
        }

        let document: IsolatedDocument
        let markdown: String
        if let preisolated {
            document = preisolated
            markdown = input
        } else {
            document = MathIsolator.isolate(input)
            markdown = document.sanitizedMarkdown
        }

        guard !document.formulas.isEmpty else {
            return try AttributedString(
                markdown: markdown,
                including: \.textual,
                options: options,
                baseURL: baseURL
            )
        }

        // Only inline math reaches this parser; display math is rendered by
        // `DisplayMathView`.
        let inlineFormulas = document.formulas.filter { !$0.display }
        if !inlineFormulas.isEmpty {
            Task { @MainActor in
                MathCoordinator.shared.ensureRendered(
                    formulas: inlineFormulas.map { ($0.tex, false) }
                )
            }
        }

        var attr = try AttributedString(
            markdown: markdown,
            including: \.textual,
            options: options,
            baseURL: baseURL
        )

        for formula in inlineFormulas {
            guard let range = attr.range(of: formula.token) else { continue }

            // Keep the token's own attributes. Dropping the paragraph
            // presentation intent makes Textual treat the attachment as an
            // independent block, which breaks the surrounding sentence.
            let inherited = attr[range].runs.first?.attributes ?? AttributeContainer()

            if let rendered = MathCache.shared.get(tex: formula.tex, display: false) {
                var container = inherited
                container.textual.attachment = AnyAttachment(
                    NativeMathAttachment(math: rendered, fontSize: fontSize)
                )
                attr.replaceSubrange(
                    range,
                    with: AttributedString("\u{FFFC}", attributes: container)
                )
            } else if MathCache.shared.hasFailed(tex: formula.tex, display: false) != nil {
                var fallback = AttributedString("$\(formula.tex)$")
                fallback.setAttributes(inherited)
                fallback.font = Font.system(size: fontSize * 0.95, design: .monospaced)
                fallback.backgroundColor = Color.red.opacity(0.12)
                fallback.foregroundColor = Color.red.opacity(0.9)
                attr.replaceSubrange(range, with: fallback)
            } else {
                var placeholder = AttributedString("$\(formula.tex)$")
                placeholder.setAttributes(inherited)
                attr.replaceSubrange(range, with: placeholder)
            }
        }

        return attr
    }
}

/// Hands Textual content that was already parsed (for example a slice of a
/// document whose reference links were resolved before splitting). The input
/// string is ignored; it only lets `StructuredText` notice content changes.
public struct PreParsedMarkupParser: MarkupParser {
    private let content: AttributedString

    nonisolated public init(_ content: AttributedString) {
        self.content = content
    }

    nonisolated public func attributedString(for input: String) throws -> AttributedString {
        content
    }
}
