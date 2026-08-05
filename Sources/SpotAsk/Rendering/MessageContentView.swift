import SwiftUI

struct MessageContentView: View {
    let message: ChatMessage
    let canRegenerate: Bool
    let onRegenerate: () -> Void
    let isCopied: Bool
    let onCopy: () -> Void
    let copyShortcut: InAppShortcut?
    let regenerateShortcut: InAppShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownTextView(content: message.content)

            if message.role == .assistant {
                HStack(spacing: 4) {
                    MessageToolbarIconButton {
                        onCopy()
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .help(toolbarHelp(
                        isCopied ? L10n.string("chat.copied") : L10n.string("chat.copyCompleteAnswer"),
                        shortcut: copyShortcut
                    ))
                    .accessibilityLabel(isCopied ? L10n.string("chat.copyAnswer") : L10n.string("chat.copyCompleteAnswer"))
                    .overlay(alignment: .bottomTrailing) {
                        ShortcutKeycap(shortcut: copyShortcut)
                            .offset(x: 4, y: 4)
                    }

                    if canRegenerate {
                        MessageToolbarIconButton(action: onRegenerate) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(toolbarHelp(L10n.string("chat.regenerate"), shortcut: regenerateShortcut))
                        .accessibilityLabel(L10n.string("chat.regenerate"))
                        .overlay(alignment: .bottomTrailing) {
                            ShortcutKeycap(shortcut: regenerateShortcut)
                                .offset(x: 4, y: 4)
                        }
                    }

                    Spacer(minLength: 8)

                    if let metadata = responseMetadata {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 140, alignment: .trailing)
                            .help(metadata)
                            .accessibilityLabel(metadata)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var responseMetadata: String? {
        guard let modelDisplayName = message.modelDisplayName else { return nil }
        guard let duration = message.responseDuration else { return modelDisplayName }
        let seconds = duration.formatted(.number.precision(.fractionLength(1)))
        return "\(modelDisplayName) · \(seconds)s"
    }

    private func toolbarHelp(_ title: String, shortcut: InAppShortcut?) -> String {
        guard let shortcut else { return title }
        let shortcutText = InAppShortcutDisplay.labels(for: shortcut).joined()
        return "\(title) (\(shortcutText))"
    }
}

struct MessageToolbarIconButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 10))
                .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(isHovering ? Brand.surface : Color.clear)
                )
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.accent, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
