import SwiftUI
import Textual

struct MarkdownTextView: View {
    let content: String

    var body: some View {
        StructuredText(markdown: Self.markdownWithCopyableStandaloneCode(content))
            .textual.codeBlockStyle(CodeBlockView())
            .textual.structuredTextStyle(.gitHub)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityLabel("回答内容")
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
