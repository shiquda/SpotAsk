import SwiftUI
import Textual

struct MarkdownTextView: View {
    let content: String

    var body: some View {
        StructuredText(markdown: Self.markdownWithCopyableStandaloneCode(content))
            .textual.codeBlockStyle(CodeBlockView())
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Lightweight streaming renderer. It parses Markdown off the main actor and
/// keeps showing the latest rendered result while the next chunk is parsed, so
/// the conversation never flashes raw Markdown or re-lays out Textual blocks on
/// every 40ms token flush.
struct StreamingMarkdownTextView: View {
    let content: String

    @State private var rendered = AttributedString()
    @State private var renderedContent = ""
    @State private var pendingContent = ""
    @State private var renderGeneration = 0
    @State private var renderTask: Task<Void, Never>?
    @State private var renderer = StreamingMarkdownRenderer()

    var body: some View {
        Group {
            if renderedContent.isEmpty {
                Text(content)
            } else {
                Text(rendered)
            }
        }
        .textSelection(.enabled)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(L10n.string("chat.answerContent"))
        .onAppear {
            scheduleRender(content)
        }
        .onChange(of: content) { _, newContent in
            scheduleRender(newContent)
        }
        .onDisappear {
            renderTask?.cancel()
        }
    }

    private func scheduleRender(_ newContent: String) {
        guard newContent != renderedContent, newContent != pendingContent else { return }
        pendingContent = newContent
        if renderTask == nil {
            startRender()
        }
    }

    private func startRender() {
        let contentToRender = pendingContent
        let generation = renderGeneration + 1
        renderGeneration = generation
        renderTask = Task { @MainActor in
            let result = await renderer.render(contentToRender, generation: generation)
            guard !Task.isCancelled else { return }
            rendered = result ?? AttributedString(contentToRender)
            renderedContent = contentToRender

            if pendingContent != contentToRender {
                // Avoid parsing every 40ms flush; settle on the newest chunk at
                // most about every 80ms while the stream keeps coming.
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                startRender()
            } else {
                pendingContent = ""
                renderTask = nil
            }
        }
    }
}

enum StreamingMarkdownParser {
    static func parse(_ content: String) -> AttributedString? {
        try? AttributedString(markdown: MarkdownTextView.markdownWithCopyableStandaloneCode(content))
    }
}

actor StreamingMarkdownRenderer {
    private var latestGeneration = 0

    func render(_ content: String, generation: Int) -> AttributedString? {
        guard generation >= latestGeneration else { return nil }
        latestGeneration = generation
        return StreamingMarkdownParser.parse(content)
    }
}
