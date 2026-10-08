import SwiftUI

@MainActor
struct ChatMessageListView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let reconciliationCoordinator: ChatReconciliationCoordinator
    let pendingExternalAskID: UUID?
    let isPanelVisible: Bool
    let showsShortcutHints: Bool
    let reduceMotion: Bool
    @Binding var scrollFollowState: ScrollFollowState
    let copiedMessageID: UUID?
    let onApplyPreset: (PromptPreset?) -> Void
    let onSelectExternalAsk: (QuickAction) -> Void
    let onRetryWithExternalAsk: (QuickAction, UUID) -> Void
    let onInsertSelection: (ChatMessage) -> Void
    let onCopyMessage: (ChatMessage) -> Void
    let onRestoreSession: () -> Void
    let onRetryLatestAnswerWithModel: (UUID) -> Void
    let onRetryLatestAnswerWithDefaultModel: () -> Void
    let shortcutHint: (InAppShortcutTarget) -> InAppShortcut?

    @State private var pendingScrollTask: Task<Void, Never>?

    private static let conversationTailCount = 3

    private var historicalMessages: [ChatMessage] {
        Array(viewModel.messages.prefix(max(0, viewModel.messages.count - Self.conversationTailCount)))
    }

    private var activeTailMessages: [ChatMessage] {
        Array(viewModel.messages.suffix(Self.conversationTailCount))
    }

    var body: some View {
        if viewModel.messages.isEmpty {
            emptyConversation
        } else {
            messagesScrollView
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 0) {
            if viewModel.canRestorePreviousSession {
                sessionRestoreBanner
                Divider()
            }
            VStack(spacing: 8) {
                EmptyStateBrandMark()
                Text(L10n.string("chat.askAnything"))
                    .font(.system(size: 17, weight: .medium))
                    .kerning(-0.17)
                    .foregroundStyle(Brand.fg)
                Text(L10n.string("chat.selectPrompt"))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                PresetStripView(
                    presets: settings.enabledPromptPresets,
                    selection: $viewModel.selectedPromptPreset,
                    showsShortcutHints: showsShortcutHints,
                    shortcutForPreset: { shortcutHint(.promptPreset($0.id)) },
                    onSelect: onApplyPreset
                )
                .padding(.top, 10)
                if !settings.enabledQuickActions.isEmpty {
                    QuickActionStripView(
                        actions: settings.enabledQuickActions,
                        selectedActionID: pendingExternalAskID,
                        showsShortcutHints: showsShortcutHints,
                        shortcutForAction: { shortcutHint(.quickAction($0.id)) },
                        onSelect: onSelectExternalAsk
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var messagesScrollView: some View {
        VStack(spacing: 0) {
            if viewModel.canRestorePreviousSession {
                sessionRestoreBanner
                Divider()
            }
            GeometryReader { geometry in
                let contentWidth = conversationColumnWidth(viewportWidth: geometry.size.width)
                ScrollViewReader { proxy in
                    ScrollView {
                        conversationContent(contentWidth: contentWidth)
                            .padding(
                                .horizontal,
                                conversationColumnHorizontalPadding(viewportWidth: geometry.size.width)
                            )
                            .padding(.vertical, 20)
                    }
                    .defaultScrollAnchor(scrollFollowState.followsLatest ? .bottom : nil, for: .sizeChanges)
                    .contentMargins(.top, 32, for: .scrollContent)
                    .overlay(alignment: .bottomTrailing) {
                        if !scrollFollowState.followsLatest {
                            Button {
                                scrollFollowState.resumeFollowing()
                                withAnimation(.easeOut(duration: 0.16)) {
                                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                                }
                            } label: {
                                Image(systemName: "arrow.down")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .clipShape(Circle())
                            .padding(14)
                            .help(L10n.string("chat.goToBottom"))
                            .accessibilityLabel(L10n.string("chat.goToBottom"))
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                    }
                    .onDisappear {
                        pendingScrollTask?.cancel()
                    }
                    .onScrollGeometryChange(for: Bool.self, of: Self.isNearBottom) { _, isNearBottom in
                        if scrollFollowState.isNearBottomValue != isNearBottom {
                            scrollFollowState.positionChanged(isNearBottom: isNearBottom)
                        }
                    }
                    .onScrollPhaseChange { _, newPhase, context in
                        let isNearBottom = Self.isNearBottom(context.geometry)
                        if scrollFollowState.isNearBottomValue != isNearBottom {
                            scrollFollowState.positionChanged(isNearBottom: isNearBottom)
                        }
                        scrollFollowState.phaseChanged(to: Self.scrollFollowPhase(for: newPhase))
                    }
                    .onChange(of: viewModel.messages.last?.id) { _, _ in
                        scrollToBottom(using: proxy)
                    }
                }
            }
        }
    }

    private func conversationColumnWidth(viewportWidth: CGFloat) -> CGFloat {
        let paddedWidth = max(0, viewportWidth - 48)
        return settings.chatMessageStyle == .im ? paddedWidth : min(paddedWidth, 760)
    }

    private func conversationColumnHorizontalPadding(viewportWidth: CGFloat) -> CGFloat {
        let columnWidth = conversationColumnWidth(viewportWidth: viewportWidth)
        return max(24, (viewportWidth - columnWidth) / 2)
    }

    private func conversationContent(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !historicalMessages.isEmpty {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(historicalMessages) { message in
                        messageRow(message, contentWidth: contentWidth)
                            .id(message.id)
                    }
                }
            }
            ForEach(activeTailMessages) { message in
                messageRow(message, contentWidth: contentWidth)
                    .id(message.id)
            }
            Color.clear
                .frame(height: 1)
                .id("conversation-bottom")
        }
    }

    private var sessionRestoreBanner: some View {
        HStack(spacing: 10) {
            Text(L10n.string("chat.sessionIdleNotice"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(L10n.string("chat.continueConversation")) {
                onRestoreSession()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quinary)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage, contentWidth: CGFloat) -> some View {
        Group {
            switch message.role {
            case .system:
                EmptyView()
            case .user:
                let canRetry = canRetryUserMessage(message)
                UserMessageContentView(
                    message: message,
                    isIM: settings.chatMessageStyle == .im,
                    isExpanded: reconciliationCoordinator.userMessageExpansionState.isExpanded(messageID: message.id),
                    onToggleExpansion: { reconciliationCoordinator.userMessageExpansionState.toggle(messageID: message.id) },
                    canRetry: canRetry,
                    onRetry: viewModel.retry,
                    retryShortcut: canRetry ? shortcutHint(.operation(.regenerateOrRetry)) : nil
                )
            case .assistant:
                AssistantMessageRow(
                    viewModel: viewModel,
                    settings: settings,
                    message: message,
                    reasoningState: reconciliationCoordinator.reasoningToggle.state(for: message.id),
                    reduceMotion: reduceMotion,
                    isIM: settings.chatMessageStyle == .im,
                    isLatestAssistant: message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id,
                    canRegenerate: viewModel.canRegenerate,
                    canRetryWithModel: message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id && viewModel.canRegenerate,
                    onRegenerate: viewModel.regenerate,
                    onRetryWithModel: onRetryLatestAnswerWithModel,
                    onRetryWithDefaultModel: onRetryLatestAnswerWithDefaultModel,
                    externalAsks: settings.enabledQuickActions,
                    onRetryWithExternalAsk: { action in
                        onRetryWithExternalAsk(action, message.id)
                    },
                    isCopied: copiedMessageID == message.id,
                    onCopy: { onCopyMessage(message) },
                    canInsertSelection: message.state == .complete && (viewModel.selectionSnapshot(for: message.id)?.canReplaceSelection ?? false),
                    onInsertSelection: { onInsertSelection(message) },
                    copyShortcut: shortcutHint(.operation(.copyAnswer)),
                    regenerateShortcut: shortcutHint(.operation(.regenerateOrRetry)),
                    retryShortcut: shortcutHint(.operation(.regenerateOrRetry)),
                    errorDescription: viewModel.error?.localizedDescription,
                    onRetry: viewModel.retry,
                    isExpanded: reconciliationCoordinator.assistantMessageExpansionState.isExpanded(messageID: message.id),
                    onToggleExpansion: {
                        reconciliationCoordinator.assistantMessageExpansionState.toggle(messageID: message.id)
                    },
                    onToggleReasoning: {
                        reconciliationCoordinator.reasoningToggle.toggleByUser(messageID: message.id)
                    },
                    onLiveMessageChanged: {
                        reconciliationCoordinator.reconcileStreamingMessage($0, prefersExpanded: settings.defaultExpandReasoning)
                    },
                    isPanelVisible: isPanelVisible
                )
            }
        }
        .frame(
            width: contentWidth,
            alignment: settings.chatMessageStyle == .im && message.role == .user ? .trailing : .leading
        )
    }

    private func canRetryUserMessage(_ userMessage: ChatMessage) -> Bool {
        guard viewModel.generationState == .failed,
              viewModel.messages.last?.role == .assistant,
              viewModel.messages.last?.state == .failed,
              let lastUserMessage = viewModel.messages.last(where: { $0.role == .user }) else { return false }
        return userMessage.id == lastUserMessage.id
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard scrollFollowState.followsLatest else { return }
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))

            guard scrollFollowState.followsLatest else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }

    private static func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        geometry.visibleRect.maxY >= geometry.contentSize.height - 12
    }

    private static func scrollFollowPhase(for phase: ScrollPhase) -> ScrollFollowState.Phase {
        switch phase {
        case .idle:
            .idle
        case .tracking, .interacting:
            .userInteracting
        case .decelerating:
            .userDecelerating
        case .animating:
            .programmaticAnimating
        }
    }
}
