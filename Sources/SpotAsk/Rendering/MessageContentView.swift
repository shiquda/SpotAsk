import SwiftUI

enum MessageBubbleMetrics {
    /// Similar desktop messengers keep bubbles around 70-80% of the chat
    /// content width; 520pt is about 77% of the default 722pt panel content.
    static let maxWidth: CGFloat = 520
}

/// A chat bubble that hugs short content but wraps once it reaches the
/// configured maximum width, instead of always filling the whole row.
struct MessageBubbleContainer<Content: View>: View {
    let fill: Color
    let foreground: Color?
    let border: Color?
    let maxWidth: CGFloat
    let alignment: Alignment
    let content: Content

    init(
        fill: Color = Brand.surface,
        foreground: Color? = nil,
        border: Color? = Brand.border,
        maxWidth: CGFloat = MessageBubbleMetrics.maxWidth,
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.foreground = foreground
        self.border = border
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        BubbleLayout(maxWidth: maxWidth - 24) {
            content
        }
        .foregroundStyle(foreground ?? Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if let border {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
        .frame(maxWidth: maxWidth, alignment: alignment)
    }
}

/// Measures the content at its natural width first, then clamps it to the
/// bubble cap so short messages stay compact and long messages wrap.
private struct BubbleLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let availableWidth = min(proposal.width ?? maxWidth, maxWidth)
        let naturalSize = subview.sizeThatFits(.unspecified)
        let contentWidth = naturalSize.width > 0
            ? min(naturalSize.width, availableWidth)
            : availableWidth
        let wrappedSize = subview.sizeThatFits(
            ProposedViewSize(width: contentWidth, height: nil)
        )
        return CGSize(
            width: contentWidth,
            height: max(wrappedSize.height, naturalSize.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

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
    let streamingChunks: [String]
    private let isBubble: Bool
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
        onToggleExpansion: @escaping () -> Void = {},
        streamingChunks: [String] = [],
        isBubble: Bool = false
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
        self.streamingChunks = streamingChunks
        self.isBubble = isBubble
        collapsedPreview = message.state == .streaming
            ? nil
            : AssistantMessageDisplayPolicy.collapsedPreview(for: message.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            messageBody

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

    @ViewBuilder
    private var messageBody: some View {
        if isBubble {
            MessageBubbleContainer(maxWidth: MessageBubbleMetrics.maxWidth) {
                messageContent
            }
        } else {
            messageContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        Group {
            if let collapsedPreview, !isExpanded, message.state != .streaming {
                Text(collapsedPreview)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .lineLimit(AssistantMessageDisplayPolicy.collapsedLineLimit)
            } else {
                StreamingMarkdownBlockView(
                    chunks: streamingChunks.isEmpty ? [message.content] : streamingChunks,
                    isComplete: message.state != .streaming,
                    fillsAvailableWidth: !isBubble
                )
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
