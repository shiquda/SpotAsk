import SwiftUI
import Textual

struct MarkdownTextView: View {
    let content: String
    let fillsAvailableWidth: Bool
    let rendersMath: Bool

    init(content: String, fillsAvailableWidth: Bool = true, rendersMath: Bool = true) {
        self.content = content
        self.fillsAvailableWidth = fillsAvailableWidth
        self.rendersMath = rendersMath
    }

    @ViewBuilder
    var body: some View {
        let preparedContent = Self.markdownWithCopyableStandaloneCode(content)
        let markdownSource = rendersMath ? MathMarkdownNormalizer.normalize(preparedContent) : preparedContent
        let markdown = StructuredText(
            markdown: markdownSource,
            syntaxExtensions: rendersMath ? [.math] : []
        )
            .textual.codeBlockStyle(CodeBlockView())
            .textual.overflowMode(.wrap)
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
        Group {
            if fillsAvailableWidth {
                markdown
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                markdown
            }
        }
        .multilineTextAlignment(.leading)
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

enum MathMarkdownNormalizer {
    private struct Fence {
        let marker: Character
        let length: Int
    }

    static func normalize(_ markdown: String) -> String {
        let delimiterNormalized = normalizeBackslashDelimiters(markdown)
        return normalizeStandaloneDollarBlocks(delimiterNormalized)
    }

    private static func normalizeBackslashDelimiters(_ markdown: String) -> String {
        guard markdown.contains(#"\("#) || markdown.contains(#"\["#) else { return markdown }

        var activeFence: Fence?
        var isInBlockMath = false
        var normalizedLines: [String] = []
        normalizedLines.reserveCapacity(markdown.reduce(into: 1) { if $1 == "\n" { $0 += 1 } })

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if let fence = activeFence {
                normalizedLines.append(line)
                if isClosingFence(line, fence: fence) {
                    activeFence = nil
                }
                continue
            }
            if let fence = openingFence(in: line) {
                activeFence = fence
                normalizedLines.append(line)
                continue
            }
            normalizedLines.append(normalizeLine(line, isInBlockMath: &isInBlockMath))
        }
        return normalizedLines.joined(separator: "\n")
    }

    // Textual renders ```math blocks directly at the block layout layer. This
    // avoids relying on post-Markdown pattern replacement across attributed
    // runs, which is unreliable for some macOS block-math documents.
    private static func normalizeStandaloneDollarBlocks(_ markdown: String) -> String {
        guard markdown.contains("$$") else { return markdown }

        var activeFence: Fence?
        var activeDollarBlock: [String]?
        var normalizedLines: [String] = []
        normalizedLines.reserveCapacity(markdown.reduce(into: 1) { if $1 == "\n" { $0 += 1 } })

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if let fence = activeFence {
                normalizedLines.append(line)
                if isClosingFence(line, fence: fence) {
                    activeFence = nil
                }
                continue
            }
            if let fence = openingFence(in: line) {
                activeFence = fence
                normalizedLines.append(line)
                continue
            }

            if let existingBlock = activeDollarBlock {
                var blockLines = existingBlock
                if let closingContent = closingDollarBlockContent(in: line) {
                    if !closingContent.isEmpty {
                        blockLines.append(closingContent)
                    }
                    appendMathFence(with: blockLines, to: &normalizedLines)
                    activeDollarBlock = nil
                } else {
                    blockLines.append(line)
                    activeDollarBlock = blockLines
                }
                continue
            }

            if let content = completeDollarBlockContent(in: line) {
                appendMathFence(with: [content], to: &normalizedLines)
            } else if isDollarBlockOpening(line) {
                activeDollarBlock = []
            } else {
                normalizedLines.append(line)
            }
        }

        if let activeDollarBlock {
            normalizedLines.append("$$")
            normalizedLines.append(contentsOf: activeDollarBlock)
        }
        return normalizedLines.joined(separator: "\n")
    }

    private static func appendMathFence(with lines: [String], to output: inout [String]) {
        output.append("```math")
        output.append(normalizeRendererCompatibility(lines.joined(separator: "\n")))
        output.append("```")
    }

    private static func normalizeRendererCompatibility(_ latex: String) -> String {
        guard latex.contains(#"\begin{aligned}"#) else { return latex }

        var isInAlignedEnvironment = false
        return latex
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine in
                var line = String(rawLine)
                if line.contains(#"\begin{aligned}"#) {
                    isInAlignedEnvironment = true
                }
                if isInAlignedEnvironment {
                    // SwiftUIMath's aligned environment supports exactly two
                    // columns. Keep the first alignment point and turn the
                    // common `&&` annotation separator into visual spacing.
                    line = line.replacingOccurrences(of: "&&", with: #"\quad "#)
                    line = removingUnsupportedRowSpacing(from: line)
                }
                if line.contains(#"\end{aligned}"#) {
                    isInAlignedEnvironment = false
                }
                return line
            }
            .joined(separator: "\n")
    }

    private static func removingUnsupportedRowSpacing(from line: String) -> String {
        guard
            let opening = line.range(of: #"\\["#, options: .backwards),
            let closing = line[opening.upperBound...].firstIndex(of: "]")
        else {
            return line
        }

        var normalized = line
        normalized.replaceSubrange(opening.lowerBound ... closing, with: #"\\"#)
        return normalized
    }

    private static func completeDollarBlockContent(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
        let content = trimmed[start ..< end].trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty || content.contains("$$") ? nil : content
    }

    private static func isDollarBlockOpening(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "$$"
    }

    private static func closingDollarBlockContent(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("$$") else { return nil }
        let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeLine(_ line: String, isInBlockMath: inout Bool) -> String {
        var output = ""
        output.reserveCapacity(line.count)
        var index = line.startIndex

        while index < line.endIndex {
            if isInBlockMath {
                if isDelimiter(in: line, at: index, closing: "]") {
                    output += "$$"
                    index = line.index(index, offsetBy: 2)
                    isInBlockMath = false
                } else {
                    output.append(line[index])
                    index = line.index(after: index)
                }
                continue
            }

            if line[index] == "`" {
                let tickCount = runLength(of: "`", in: line, from: index)
                let contentStart = line.index(index, offsetBy: tickCount)
                if let closing = matchingBacktickRun(in: line, from: contentStart, length: tickCount) {
                    let closingEnd = line.index(closing, offsetBy: tickCount)
                    output += line[index ..< closingEnd]
                    index = closingEnd
                } else {
                    output += line[index...]
                    index = line.endIndex
                }
                continue
            }

            if isDelimiter(in: line, at: index, closing: "[") {
                output += "$$"
                index = line.index(index, offsetBy: 2)
                isInBlockMath = true
                continue
            }

            if isDelimiter(in: line, at: index, closing: "("),
               let closing = findDelimiter(in: line, from: line.index(index, offsetBy: 2), closing: ")") {
                output += "$"
                output += line[line.index(index, offsetBy: 2) ..< closing]
                output += "$"
                index = line.index(closing, offsetBy: 2)
                continue
            }

            output.append(line[index])
            index = line.index(after: index)
        }
        return output
    }

    private static func isDelimiter(
        in line: String,
        at index: String.Index,
        closing: Character
    ) -> Bool {
        guard line[index] == "\\" else { return false }
        let next = line.index(after: index)
        guard next < line.endIndex, line[next] == closing else { return false }
        return !isEscapedBackslash(in: line, at: index)
    }

    private static func findDelimiter(
        in line: String,
        from start: String.Index,
        closing: Character
    ) -> String.Index? {
        var index = start
        while index < line.endIndex {
            if isDelimiter(in: line, at: index, closing: closing) { return index }
            index = line.index(after: index)
        }
        return nil
    }

    private static func isEscapedBackslash(in line: String, at index: String.Index) -> Bool {
        var cursor = index
        var count = 0
        while cursor > line.startIndex {
            let previous = line.index(before: cursor)
            guard line[previous] == "\\" else { break }
            count += 1
            cursor = previous
        }
        return count.isMultiple(of: 2) == false
    }

    private static func matchingBacktickRun(
        in line: String,
        from start: String.Index,
        length: Int
    ) -> String.Index? {
        var index = start
        while index < line.endIndex {
            if line[index] == "`", runLength(of: "`", in: line, from: index) == length {
                return index
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func runLength(of character: Character, in line: String, from start: String.Index) -> Int {
        var count = 0
        var index = start
        while index < line.endIndex, line[index] == character {
            count += 1
            index = line.index(after: index)
        }
        return count
    }

    private static func openingFence(in line: String) -> Fence? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        return length >= 3 ? Fence(marker: marker, length: length) : nil
    }

    private static func isClosingFence(_ line: String, fence: Fence) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.prefix(while: { $0 == fence.marker }).count >= fence.length
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

/// Renders a sealed or streaming block with the same Textual renderer, so
/// completing an answer only seals the tail instead of replacing the view tree.
struct StreamingMarkdownBlockView: View {
    let chunks: [String]
    let isComplete: Bool
    let fillsAvailableWidth: Bool

    @State private var document = MarkdownStreamingDocument()

    init(chunks: [String], isComplete: Bool, fillsAvailableWidth: Bool = true) {
        self.chunks = chunks
        self.isComplete = isComplete
        self.fillsAvailableWidth = fillsAvailableWidth
    }

    @ViewBuilder
    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            ForEach(document.blocks) { block in
                MarkdownBlockView(block: block, fillsAvailableWidth: fillsAvailableWidth)
                    .id(block.id)
            }
            if let tail = document.liveTail {
                MarkdownBlockView(block: tail, fillsAvailableWidth: fillsAvailableWidth)
                    .id(tail.id)
            }
        }
        Group {
            if fillsAvailableWidth {
                content.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
            }
        }
        .onAppear {
            document.consume(chunks: chunks, isComplete: isComplete)
        }
        .onChange(of: chunks) { _, newChunks in
            document.consume(chunks: newChunks, isComplete: isComplete)
        }
        .onChange(of: isComplete) { _, complete in
            document.consume(chunks: chunks, isComplete: complete)
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownRenderBlock
    let fillsAvailableWidth: Bool

    init(block: MarkdownRenderBlock, fillsAvailableWidth: Bool = true) {
        self.block = block
        self.fillsAvailableWidth = fillsAvailableWidth
    }

    var body: some View {
        if block.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            MarkdownTextView(content: block.source, fillsAvailableWidth: fillsAvailableWidth)
        }
    }
}
