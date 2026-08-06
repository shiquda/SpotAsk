import SwiftUI

struct MessageContentView: View {
    let message: ChatMessage
    let canRegenerate: Bool
    let onRegenerate: () -> Void
    let isCopied: Bool
    let onCopy: () -> Void
    let canInsertSelection: Bool
    let onInsertSelection: () -> Void
    let copyShortcut: InAppShortcut?
    let regenerateShortcut: InAppShortcut?
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    private let collapsedPreview: String?

    init(
        message: ChatMessage,
        canRegenerate: Bool,
        onRegenerate: @escaping () -> Void,
        isCopied: Bool,
        onCopy: @escaping () -> Void,
        canInsertSelection: Bool = false,
        onInsertSelection: @escaping () -> Void = {},
        copyShortcut: InAppShortcut?,
        regenerateShortcut: InAppShortcut?,
        isExpanded: Bool = false,
        onToggleExpansion: @escaping () -> Void = {}
    ) {
        self.message = message
        self.canRegenerate = canRegenerate
        self.onRegenerate = onRegenerate
        self.isCopied = isCopied
        self.onCopy = onCopy
        self.canInsertSelection = canInsertSelection
        self.onInsertSelection = onInsertSelection
        self.copyShortcut = copyShortcut
        self.regenerateShortcut = regenerateShortcut
        self.isExpanded = isExpanded
        self.onToggleExpansion = onToggleExpansion
        collapsedPreview = message.state == .streaming
            ? nil
            : AssistantMessageDisplayPolicy.collapsedPreview(for: message.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let collapsedPreview, !isExpanded {
                Text(collapsedPreview)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .lineLimit(AssistantMessageDisplayPolicy.collapsedLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownTextView(content: message.content)
            }

            if collapsedPreview != nil {
                Button(action: onToggleExpansion) {
                    Label(
                        isExpanded
                            ? L10n.string("chat.collapseAnswer")
                            : L10n.string("chat.expandAnswer"),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help(
                    isExpanded
                        ? L10n.string("chat.collapseAnswer")
                        : L10n.string("chat.expandAnswer")
                )
                .accessibilityLabel(
                    isExpanded
                        ? L10n.string("chat.collapseAnswer")
                        : L10n.string("chat.expandAnswer")
                )
            }

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

                    if canInsertSelection {
                        MessageToolbarIconButton(action: onInsertSelection) {
                            Image(systemName: "arrow.down.doc")
                        }
                        .help(L10n.string("chat.insertSelection"))
                        .accessibilityLabel(L10n.string("chat.insertSelection"))
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
