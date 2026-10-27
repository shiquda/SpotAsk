import AppKit
import SwiftUI
import Textual

struct MarkdownTextView: View {
    let content: String
    let fillsAvailableWidth: Bool
    let rendersMath: Bool
    /// Pasteboard used by code block copy buttons; tests inject a private pasteboard.
    let codeBlockPasteboard: NSPasteboard

    @Environment(AppSettings.self) private var settings: AppSettings?

    private var effectiveFontSize: Double {
        Double(settings?.readingFontSize ?? 14.5)
    }
    init(
        content: String,
        fillsAvailableWidth: Bool = true,
        rendersMath: Bool = true,
        codeBlockPasteboard: NSPasteboard = .general
    ) {
        self.content = content
        self.fillsAvailableWidth = fillsAvailableWidth
        self.rendersMath = rendersMath
        self.codeBlockPasteboard = codeBlockPasteboard
    }

    @ViewBuilder
    var body: some View {
        let preparedContent = Self.markdownWithCopyableStandaloneCode(content)
        Group {
            if rendersMath {
                MathMessageBody(
                    content: preparedContent,
                    fontSize: effectiveFontSize,
                    pasteboard: codeBlockPasteboard
                )
            } else {
                StructuredText(
                    preparedContent,
                    parser: NativeMathMarkupParser(rendersMath: false, fontSize: effectiveFontSize)
                )
                .id("no-math")
                .textual.codeBlockStyle(CodeBlockView(pasteboard: codeBlockPasteboard))
                .textual.overflowMode(.wrap)
                .textual.structuredTextStyle(.gitHub)
                .textual.textSelection(.enabled)
            }
        }
        .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("chat.answerContent"))
    }

    // Textual deliberately treats inline code as text. When it occupies an
    // entire line, present it as a code block so users get the copy control.
    nonisolated static func markdownWithCopyableStandaloneCode(_ content: String) -> String {
        content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let tickCount = trimmed.prefix(while: { $0 == "`" }).count
                guard tickCount > 0 else { return String(line) }

                let delimiter = String(repeating: "`", count: tickCount)
                guard trimmed.count > tickCount * 2, trimmed.hasSuffix(delimiter) else {
                    return String(line)
                }

                let start = trimmed.index(trimmed.startIndex, offsetBy: tickCount)
                let end = trimmed.index(trimmed.endIndex, offsetBy: -tickCount)
                let code = String(trimmed[start..<end])
                guard !code.contains(delimiter) else { return String(line) }

                return "```\n\(code)\n```"
            }
            .joined(separator: "\n")
    }
}


enum MarkdownBlockKind: Equatable {
    case paragraph
    case heading
    case list
    case blockQuote
    case code
    case thematicBreak
    case table
    case other
}

struct MarkdownRenderBlock: Identifiable, Equatable {
    let id: Int
    let kind: MarkdownBlockKind
    let source: String
    let isSealed: Bool
}

/// Incremental Markdown document. Once a block is safely closed it is sealed
/// forever; subsequent streaming chunks only grow the live tail, so render work
/// stays proportional to the changing suffix instead of the whole answer.
struct MarkdownStreamingDocument: Equatable {
    private(set) var blocks: [MarkdownRenderBlock] = []
    private(set) var liveTail: MarkdownRenderBlock?
    private(set) var isComplete = false
    private(set) var processedChunkCount = 0

    private var pending = ""
    private var nextBlockID = 0
    private var liveTailID: Int?
    private var fenceDelimiter: String?

    mutating func consume(chunks: [String], isComplete: Bool) {
        if chunks.count < processedChunkCount, !isComplete {
            reset()
        }
        for chunk in chunks.dropFirst(processedChunkCount) {
            append(chunk)
        }
        processedChunkCount = chunks.count
        if isComplete {
            sealRemaining()
        }
    }

    private mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        pending += chunk
        sealAvailableBlocks()
        updateLiveTail()
    }

    private mutating func sealAvailableBlocks() {
        while true {
            if pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pending = ""
                updateLiveTail()
                return
            }

            let lines = pending.split(separator: "\n", omittingEmptySubsequences: false)
            var start = 0
            while start < lines.count,
                  lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                start += 1
            }
            if start > 0 {
                pending = lines[start...].joined(separator: "\n")
                continue
            }

            if let fenceDelimiter {
                if let closeIndex = lines.firstIndex(where: {
                    Self.isClosingFenceLine($0, delimiter: fenceDelimiter)
                }) {
                    let source = lines[..<(closeIndex + 1)].joined(separator: "\n")
                    pending = lines[(closeIndex + 1)...].joined(separator: "\n")
                    self.fenceDelimiter = nil
                    sealSource(source, kind: .code)
                    continue
                }
                updateLiveTail()
                return
            }

            if let opening = Self.openingFenceDelimiter(for: lines[0]) {
                fenceDelimiter = opening
                updateLiveTail()
                return
            }

            if let blankIndex = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
            blankIndex > 0,
            lines[(blankIndex + 1)...].contains(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                let source = lines[..<blankIndex].joined(separator: "\n")
                var after = blankIndex + 1
                while after < lines.count,
                      lines[after].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    after += 1
                }
                pending = lines[after...].joined(separator: "\n")
                sealSource(source, kind: Self.kind(for: source))
                continue
            }

            updateLiveTail()
            return
        }
    }

    private mutating func sealRemaining() {
        guard !isComplete else { return }
        isComplete = true
        let normalized = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            sealSource(normalized, kind: Self.kind(for: pending))
        }
        pending = ""
        fenceDelimiter = nil
        liveTail = nil
        liveTailID = nil
    }

    private mutating func sealSource(_ source: String, kind: MarkdownBlockKind) {
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let id = liveTailID ?? nextBlockID
        if liveTailID == nil {
            nextBlockID += 1
        }
        blocks.append(MarkdownRenderBlock(id: id, kind: kind, source: normalized, isSealed: true))
        liveTail = nil
        liveTailID = nil
    }

    private mutating func updateLiveTail() {
        guard !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            liveTail = nil
            liveTailID = nil
            pending = ""
            return
        }
        if liveTailID == nil {
            liveTailID = nextBlockID
            nextBlockID += 1
        }
        liveTail = MarkdownRenderBlock(
            id: liveTailID ?? 0,
            kind: Self.kind(for: pending),
            source: pending,
            isSealed: false
        )
    }

    private mutating func reset() {
        blocks = []
        liveTail = nil
        isComplete = false
        processedChunkCount = 0
        pending = ""
        nextBlockID = 0
        liveTailID = nil
        fenceDelimiter = nil
    }

    private static func openingFenceDelimiter(for line: Substring) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            let count = trimmed.prefix(while: { $0 == "`" }).count
            guard count >= 3 else { return nil }
            let rest = trimmed.dropFirst(count)
            guard rest.isEmpty || !rest.contains("`") else { return nil }
            return String(repeating: "`", count: count)
        }
        if trimmed.hasPrefix("~~~") {
            let count = trimmed.prefix(while: { $0 == "~" }).count
            guard count >= 3 else { return nil }
            let rest = trimmed.dropFirst(count)
            guard rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return String(repeating: "~", count: count)
        }
        return nil
    }

    private static func isClosingFenceLine(_ line: Substring, delimiter: String) -> Bool {
        guard let first = delimiter.first else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == first else { return false }
        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= delimiter.count else { return false }
        return trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func kind(for source: String) -> MarkdownBlockKind {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.hasPrefix("#") { return .heading }
        if firstLine.hasPrefix(">") { return .blockQuote }
        if firstLine.hasPrefix("- ") || firstLine.hasPrefix("* ") || firstLine.hasPrefix("+ ") {
            return .list
        }
        if firstLine.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil {
            return .list
        }
        if firstLine.hasPrefix("```") || firstLine.hasPrefix("~~~") { return .code }
        if firstLine == "---" || firstLine == "***" || firstLine == "___" {
            return .thematicBreak
        }
        if firstLine.contains("|") { return .table }
        return .paragraph
    }
}
