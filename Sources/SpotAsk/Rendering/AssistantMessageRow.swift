import AppKit
import SwiftUI
import UniformTypeIdentifiers
/// Renders one assistant message. Keeping this in its own view means a token
/// flush only invalidates the active answer row, not the whole conversation.
struct AssistantMessageRow: View { let viewModel: ChatViewModel
let settings: AppSettings
let message: ChatMessage
let reasoningState: ReasoningToggleState
let reduceMotion: Bool
let isIM: Bool
let isLatestAssistant: Bool
let canRegenerate: Bool
let canRetryWithModel: Bool
let onRegenerate: () -> Void
let onRetryWithModel: (UUID) -> Void
let onRetryWithDefaultModel: () -> Void
let isCopied: Bool
let onCopy: () -> Void
let canInsertSelection: Bool
let onInsertSelection: () -> Void
let copyShortcut: InAppShortcut?
let regenerateShortcut: InAppShortcut?
let retryShortcut: InAppShortcut?
let errorDescription: String?
let onRetry: () -> Void
let isExpanded: Bool
let onToggleExpansion: () -> Void
let onToggleReasoning: () -> Void
let onLiveMessageChanged: (ChatMessage) -> Void

var body: some View {
    let displayedMessage = viewModel.liveMessage(message)
    VStack(alignment: .leading, spacing: 8) {
        AssistantMessageHeader(
            modelDisplayName: displayedMessage.modelDisplayName,
            providerName: displayedMessage.providerName,
            catalog: settings.providerRegistry.catalog,
            effectiveModelID: viewModel.effectiveModelID,
            hasSessionOverride: viewModel.sessionModelID != nil,
            canRetryWithModel: canRetryWithModel,
            onRetryWithModel: onRetryWithModel,
            onRetryWithDefaultModel: onRetryWithDefaultModel
        )

        if let reasoning = displayedMessage.reasoningContent, !reasoning.isEmpty {
            reasoningSection(message: displayedMessage, reasoning: reasoning)
        }
        if displayedMessage.content.isEmpty, displayedMessage.state == .streaming {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.string("chat.generating"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(L10n.string("chat.generatingAnswer"))
        } else {
            MessageContentView(
                message: displayedMessage,
                canRegenerate: canRegenerate && isLatestAssistant,
                onRegenerate: onRegenerate,
                isCopied: isCopied,
                onCopy: onCopy,
                canInsertSelection: canInsertSelection,
                onInsertSelection: onInsertSelection,
                copyShortcut: isLatestAssistant ? copyShortcut : nil,
                regenerateShortcut: isLatestAssistant ? regenerateShortcut : nil,
                isExpanded: isExpanded,
                onToggleExpansion: onToggleExpansion,
                streamingChunks: streamingChunks,
                isBubble: isIM,
                rendersMath: settings.renderMath
            )
        }
        if displayedMessage.state == .failed {
            HStack(spacing: 8) {
                Text(errorDescription ?? L10n.string("chat.requestFailed"))
                    .font(.caption)
                    .foregroundStyle(.red)
                Button(L10n.string("chat.retry")) { onRetry() }
                    .accessibilityLabel(L10n.string("chat.retryFailedRequest"))
                    .overlay(alignment: .bottomTrailing) {
                        ShortcutKeycap(shortcut: retryShortcut)
                            .offset(x: 5, y: 4)
                    }
            }
        } else if displayedMessage.state == .cancelled {
            Text(L10n.string("chat.stopped"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .onChange(of: displayedMessage) { _, newValue in
        onLiveMessageChanged(newValue)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private var streamingChunks: [String] {
    if message.state == .streaming || message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id {
        return viewModel.streamingAnswerChunks
    }
    return []
}

@ViewBuilder
private func reasoningSection(message: ChatMessage, reasoning: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Button {
            onToggleReasoning()
        } label: {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                HStack(spacing: 5) {
                    Image(systemName: reasoningState.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.medium))
                        .frame(width: 14, height: 14)
                    Text(reasoningHeaderText(for: message, at: context.date))
                        .font(.caption.weight(.medium))
                    if message.state == .streaming, message.reasoningCompletedAt == nil {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(reasoningState.isExpanded ? L10n.string("chat.reasoningCollapse") : L10n.string("chat.reasoningExpand"))
        .accessibilityLabel(reasoningState.isExpanded ? L10n.string("chat.reasoningCollapse") : L10n.string("chat.reasoningExpand"))
        if reasoningState.isExpanded {
            ReasoningContentView(
                reasoning: reasoning
            )
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: reasoningState.isExpanded)
}

private func reasoningHeaderText(for message: ChatMessage, at now: Date) -> String {
    if let duration = message.reasoningDuration {
        return L10n.string("chat.reasoningCompleted", Self.elapsedSecondsText(duration))
    }
    if message.state == .streaming {
        let elapsed = max(0, now.timeIntervalSince(message.createdAt))
        return L10n.string("chat.reasoningStreaming", Self.elapsedSecondsText(elapsed))
    }
    if let duration = message.responseDuration {
        return L10n.string("chat.reasoningCompleted", Self.elapsedSecondsText(duration))
    }
    return L10n.string("chat.reasoning")
}

private static func elapsedSecondsText(_ interval: TimeInterval) -> String {
    String(format: "%.1f", interval)
} }

fileprivate struct AssistantMessageHeader: View {
    let modelDisplayName: String?
    let providerName: String?
    let catalog: ProviderModelCatalog?
    let effectiveModelID: UUID?
    let hasSessionOverride: Bool
    let canRetryWithModel: Bool
    let onRetryWithModel: (UUID) -> Void
    let onRetryWithDefaultModel: () -> Void

    @State private var isRetryPickerPresented = false

    var body: some View {
        let slug = ProviderBrandIconMatcher.match(
            providerName: providerName,
            modelName: modelDisplayName
        )
        HStack(spacing: 6) {
            ZStack {
                if slug != nil {
                    Circle().fill(Brand.surface)
                } else {
                    Circle().fill(
                        LinearGradient(
                            colors: [Brand.accent, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                ProviderBrandIconView(
                    slug: slug,
                    size: 18,
                    fallbackSymbol: "brain.head.profile",
                    fallbackColor: .white
                )
            }
            .frame(width: 18, height: 18)
            .accessibilityLabel(L10n.string("chat.assistant"))

            if let modelDisplayName {
                Text(modelDisplayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if canRetryWithModel {
                RetryWithModelButton(
                    isPresented: $isRetryPickerPresented,
                    catalog: catalog,
                    effectiveModelID: effectiveModelID,
                    hasSessionOverride: hasSessionOverride,
                    onRetryWithModel: { modelID in
                        isRetryPickerPresented = false
                        onRetryWithModel(modelID)
                    },
                    onRetryWithDefaultModel: {
                        isRetryPickerPresented = false
                        onRetryWithDefaultModel()
                    }
                )
            }
        }
    }
}

private struct RetryWithModelButton: View {
    @Binding var isPresented: Bool
    let catalog: ProviderModelCatalog?
    let effectiveModelID: UUID?
    let hasSessionOverride: Bool
    let onRetryWithModel: (UUID) -> Void
    let onRetryWithDefaultModel: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovering || isPresented ? Brand.fg : Brand.muted)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(isHovering || isPresented ? Brand.surface : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.string("chat.retryWithAnotherModel"))
        .accessibilityLabel(L10n.string("chat.retryWithAnotherModel"))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            ModelPickerContent(
                catalog: catalog,
                effectiveModelID: effectiveModelID,
                hasSessionOverride: hasSessionOverride,
                isDisabled: false,
                onSelect: onRetryWithModel,
                onUseDefault: onRetryWithDefaultModel
            )
        }
    }
}
