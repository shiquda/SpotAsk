import AppKit
import SwiftUI
import UniformTypeIdentifiers
struct UserMessageContentView: View { let message: ChatMessage
let isIM: Bool
let isExpanded: Bool
let onToggleExpansion: () -> Void
private let collapsedPreview: String?
let canRetry: Bool
let onRetry: () -> Void
let retryShortcut: InAppShortcut?

@State private var didCopy = false

init(
    message: ChatMessage,
    isIM: Bool,
    isExpanded: Bool,
    onToggleExpansion: @escaping () -> Void,
    canRetry: Bool,
    onRetry: @escaping () -> Void,
    retryShortcut: InAppShortcut?
) {
    self.message = message
    self.isIM = isIM
    self.isExpanded = isExpanded
    self.onToggleExpansion = onToggleExpansion
    self.canRetry = canRetry
    self.onRetry = onRetry
    self.retryShortcut = retryShortcut
    collapsedPreview = UserMessageDisplayPolicy.collapsedPreview(for: message.content)
}

private var isCollapsible: Bool {
    collapsedPreview != nil
}

private var displayedContent: String {
    if let collapsedPreview, !isExpanded {
        return collapsedPreview
    }
    return message.content
}

var body: some View {
    Group {
        if isIM {
            VStack(alignment: .trailing, spacing: 5) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(alignment: .top, spacing: 0) {
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.string("chat.user"))
}

@ViewBuilder
private var content: some View {
    VStack(alignment: isIM ? .trailing : .leading, spacing: 5) {
            header

            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            MessageAttachmentThumbnail(attachment: attachment)
                        }
                    }
                    .padding(.leading, isIM ? 0 : 12)
                    .padding(.trailing, isIM ? 12 : 0)
                }
                .frame(maxWidth: isIM ? MessageBubbleMetrics.maxWidth : 620, alignment: isIM ? .trailing : .leading)
            }

            if !message.content.isEmpty {
                if isIM {
                    MessageBubbleContainer(
                        fill: Brand.accent,
                        foreground: .white,
                        border: nil,
                        maxWidth: MessageBubbleMetrics.maxWidth,
                        alignment: .trailing
                    ) {
                        userMessageText
                    }
                } else {
                    userMessageText
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Color(nsColor: .quaternarySystemFill),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .foregroundStyle(Color.primary)
                }
            }

            if isCollapsible {
                Button(action: onToggleExpansion) {
                    Label(
                        isExpanded
                            ? L10n.string("chat.collapseQuestion")
                            : L10n.string("chat.showFullQuestion"),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? L10n.string("chat.collapseQuestion") : L10n.string("chat.showFullQuestion"))
                .accessibilityLabel(isExpanded ? L10n.string("chat.collapseQuestion") : L10n.string("chat.showFullQuestion"))
            }

            HStack(spacing: 4) {
                if isIM {
                    Spacer(minLength: 8)
                }
                MessageToolbarIconButton {
                    Clipboard.copy(message.content)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1_500))
                        guard !Task.isCancelled else { return }
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .help(didCopy ? L10n.string("chat.copied") : L10n.string("chat.copyQuestion"))
                .accessibilityLabel(didCopy ? L10n.string("chat.questionCopied") : L10n.string("chat.copyQuestion"))

                if canRetry {
                    MessageToolbarIconButton(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.string("chat.retry"))
                    .accessibilityLabel(L10n.string("chat.retryFailedRequest"))
                    .overlay(alignment: .bottomTrailing) {
                        ShortcutKeycap(shortcut: retryShortcut)
                            .offset(x: 4, y: 4)
                    }
                }

                if !isIM {
                    Spacer(minLength: 8)
                }
            }
            .controlSize(.small)
        }
}

private var userMessageText: some View {
    Text(displayedContent)
        .textSelection(.enabled)
        .lineSpacing(2)
        .lineLimit(isCollapsible && !isExpanded ? UserMessageDisplayPolicy.collapsedLineLimit : nil)
        // A line-limit transition inside a lazy stack can otherwise reuse
        // the collapsed measurement for one layout pass. Force vertical
        // intrinsic measurement and a fresh text identity so the bubble
        // grows before the controls below it are placed.
        .fixedSize(horizontal: false, vertical: true)
        .id("question-text-\(message.id.uuidString)-\(isExpanded ? "expanded" : "collapsed")")
}

private var header: some View {
    HStack(spacing: 6) {
        if isIM {
            Spacer(minLength: 8)
            if let presetTitle = message.appliedPresetTitle {
                Label(L10n.string("chat.usedPrompt", presetTitle), systemImage: message.appliedPresetIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("chat.usedPrompt", presetTitle))
            }
            Text(L10n.string("chat.user"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            userAvatar
        } else {
            userAvatar
            Text(L10n.string("chat.user"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let presetTitle = message.appliedPresetTitle {
                Label(L10n.string("chat.usedPrompt", presetTitle), systemImage: message.appliedPresetIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("chat.usedPrompt", presetTitle))
            }
        }
    }
}

private var userAvatar: some View {
    ZStack {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.cyan, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        Image(systemName: "person.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
    }
    .frame(width: 18, height: 18)
    .accessibilityLabel(L10n.string("chat.user"))
} }
