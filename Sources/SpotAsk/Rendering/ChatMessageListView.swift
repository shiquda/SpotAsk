import SwiftUI

@MainActor
struct ChatMessageListView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let host: SessionDocumentHost
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

    @Environment(\.colorScheme) private var colorScheme

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
            ZStack(alignment: .bottomTrailing) {
                SessionDocumentWebView(host: host)
                if !scrollFollowState.followsLatest {
                    Button {
                        scrollFollowState.resumeFollowing()
                        host.scrollToBottom()
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
        }
        .onAppear {
            wireHostCallbacks()
            applySnapshot()
        }
        .onChange(of: viewModel.messages) { _, _ in
            applySnapshot()
        }
        .onChange(of: viewModel.streamingAnswerChunks) { _, _ in
            applySnapshot()
        }
        .onChange(of: copiedMessageID) { _, _ in
            applySnapshot()
        }
        .onChange(of: settings.renderMath) { _, _ in
            applySnapshot()
        }
        .onChange(of: settings.chatMessageStyle) { _, _ in
            applySnapshot()
        }
        .onChange(of: settings.fontSize) { _, _ in
            applySnapshot()
        }
        .onChange(of: settings.interfaceZoomLevel) { _, _ in
            applySnapshot()
        }
        .onChange(of: settings.appearance) { _, _ in
            applySnapshot()
        }
        .onChange(of: scrollFollowState.followsLatest) { _, _ in
            applySnapshot()
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

    private func applySnapshot() {
        let liveMessages = viewModel.messages.map(viewModel.liveMessage)
        let snapshot = SessionDocumentSnapshotBuilder.make(
            messages: liveMessages,
            settings: settings,
            effectiveAppearance: colorScheme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua),
            generation: host.generation,
            copiedMessageID: copiedMessageID,
            isReasoningExpanded: { reconciliationCoordinator.reasoningToggle.state(for: $0).isExpanded },
            isAssistantExpanded: { reconciliationCoordinator.assistantMessageExpansionState.isExpanded(messageID: $0) },
            canInsertSelection: { id in
                viewModel.selectionSnapshot(for: id)?.canReplaceSelection ?? false
            },
            pendingExternalAskID: pendingExternalAskID,
            showsShortcutHints: showsShortcutHints,
            shortcutHint: shortcutHint,
            followsLatest: scrollFollowState.followsLatest
        )
        let attachments = liveMessages.flatMap(\.attachments)
        host.catalog = settings.providerRegistry.catalog
        host.effectiveModelID = viewModel.effectiveModel?.id
        host.hasSessionOverride = viewModel.sessionModelID != nil
        host.externalAsks = settings.enabledQuickActions
        host.apply(snapshot: snapshot, attachments: attachments)
    }

    private func wireHostCallbacks() {
        host.catalog = settings.providerRegistry.catalog
        host.effectiveModelID = viewModel.effectiveModel?.id
        host.hasSessionOverride = viewModel.sessionModelID != nil
        host.externalAsks = settings.enabledQuickActions

        host.onCopyMessage = { messageID in
            if let msg = viewModel.messages.first(where: { $0.id == messageID }) {
                onCopyMessage(msg)
            }
        }
        host.onCopyCode = { _, code in
            Clipboard.copy(code)
        }
        host.onOpenLink = { url in
            NSWorkspace.shared.open(url)
        }
        host.onToggleReasoning = { id in
            reconciliationCoordinator.reasoningToggle.toggleByUser(messageID: id)
            applySnapshot()
        }
        host.onToggleExpand = { id in
            reconciliationCoordinator.assistantMessageExpansionState.toggle(messageID: id)
            applySnapshot()
        }
        host.onRetryUserMessage = { _ in
            viewModel.retry()
        }
        host.onRetryLatestWithModel = { modelID in
            onRetryLatestAnswerWithModel(modelID)
        }
        host.onRetryLatestWithDefaultModel = {
            onRetryLatestAnswerWithDefaultModel()
        }
        host.onSelectExternalAsk = { action in
            if let lastAssistant = viewModel.messages.last(where: { $0.role == .assistant }) {
                onRetryWithExternalAsk(action, lastAssistant.id)
            }
        }
        host.onInsertSelection = { id in
            if let msg = viewModel.messages.first(where: { $0.id == id }) {
                onInsertSelection(msg)
            }
        }
        host.onRegenerate = {
            viewModel.regenerate()
        }
        host.onRetry = {
            viewModel.retry()
        }
        host.onScrollPhaseChanged = { phase in
            scrollFollowState.phaseChanged(to: phase)
        }
        host.onScrollPositionChanged = { nearBottom in
            scrollFollowState.positionChanged(isNearBottom: nearBottom)
        }
    }
}
