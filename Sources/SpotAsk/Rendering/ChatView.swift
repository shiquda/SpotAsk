import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class ComposerTextViewReference {
    weak var textView: NSTextView?
}


struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let onDismiss: () -> Void
    let commandCenter: SpotAskCommandCenter

    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollFollowState = ScrollFollowState()
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var inputHeight = ChatInputTextView.minHeight
    @State private var composerTextView = ComposerTextViewReference()
    @State private var reasoningToggle = ReasoningToggleStateStore()
    @State private var userMessageExpansionState = UserMessageExpansionState()
    @State private var assistantMessageExpansionState = MessageExpansionState()
    @State private var isPresetPopoverPresented = false
    @State private var isModelPickerPresented = false
    @State private var isDropTargeted = false
    @State private var showsShortcutHints = false
    @State private var shortcutDispatcher: InAppShortcutDispatcher?
    @State private var chatWindowReference = ChatWindowReference()
    @State private var copiedMessageID: UUID?
    @State private var copyFeedbackToken = UUID()
    private let selectionReplacementWriter: any SelectionReplacementWriting = AccessibilitySelectionReplacementWriter()
    @State private var quickActionTrigger: QuickActionTrigger?


    init(
        viewModel: ChatViewModel,
        settings: AppSettings,
        onDismiss: @escaping () -> Void = { NSApp.keyWindow?.orderOut(nil) },
        commandCenter: SpotAskCommandCenter = .shared
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.onDismiss = onDismiss
        self.commandCenter = commandCenter
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // A single hairline separates the elevated header material from
            // the content below. The composer reads as part of the window's
            // bottom chrome, so it is not boxed in by a second divider.
            Divider()
            conversation
            composer
        }
        // Content spans the full window; the header's Material draws the
        // chrome and the conversation insets clear of it (see below).
        .ignoresSafeArea()
        .frame(minWidth: 364, minHeight: 320)
        .background(ChatWindowReader(reference: chatWindowReference))
        .onChange(of: isModelPickerPresented) { _, isPresented in
            if !isPresented {
                inputFocused = true
            }
        }
        .onAppear {
            inputFocused = true
            viewModel.prepareNewConversationAfterInactivity()
            commandCenter.setActionConsumer(handleCommandAction)
            reasoningToggle.reconcile(messages: viewModel.messages, prefersExpanded: settings.defaultExpandReasoning)
            userMessageExpansionState.reconcile(messages: viewModel.messages, role: .user)
            assistantMessageExpansionState.reconcile(messages: viewModel.messages, role: .assistant)
            quickActionTrigger?.resetForNewPanelPresentation()
            installShortcutDispatcher()
        }
        .onDisappear {
            pendingScrollTask?.cancel()
            shortcutDispatcher?.stop()
            shortcutDispatcher = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow) === chatWindowReference.window {
                showsShortcutHints = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            showsShortcutHints = false
        }
        .onExitCommand(perform: handleEscape)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Brand.accent, lineWidth: 1.5)
                    .background(Brand.accent.opacity(0.06))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
            return true
        }
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .font(contentFont)
        .environment(\.dynamicTypeSize, settings.interfaceZoomLevel.dynamicTypeSize)
        .preferredColorScheme(colorScheme)
        .overlay(alignment: .topTrailing) {
            StatusToastOverlay()
                .padding(.top, 36)
        }
        .environment(\.locale, settings.language.locale)
        .onChange(of: viewModel.messages) { _, messages in
            reasoningToggle.reconcile(messages: messages, prefersExpanded: settings.defaultExpandReasoning)
            userMessageExpansionState.reconcile(messages: messages, role: .user)
            assistantMessageExpansionState.reconcile(messages: messages, role: .assistant)
        }
        .onChange(of: settings.promptPresets) { _, _ in
            synchronizeSelectedPromptPreset()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                BrandMark()
                Text("SpotAsk")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.15)
                    .foregroundStyle(Brand.fg)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("SpotAsk"))
            ModelPickerHeaderButton(
                modelName: viewModel.effectiveModel?.displayName ?? "",
                providerIconSlug: effectiveProviderIconSlug,
                isDisabled: isGenerating,
                isPresented: $isModelPickerPresented
            ) {
                ModelPickerContent(
                    catalog: settings.providerRegistry.catalog,
                    effectiveModelID: viewModel.effectiveModelID,
                    hasSessionOverride: viewModel.sessionModelID != nil,
                    isDisabled: isGenerating,
                    onSelect: { id in
                        viewModel.selectSessionModel(id: id)
                        isModelPickerPresented = false
                        inputFocused = true
                    },
                    onUseDefault: {
                        viewModel.useDefaultModel()
                        isModelPickerPresented = false
                        inputFocused = true
                    }
                )
            }
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("chat.generating"))
            }
            Spacer()
            HeaderIconButton(action: { SpotAskCommandCenter.shared.toggleWindowOnTop() }) {
                Image(systemName: settings.keepWindowOnTop ? "pin.fill" : "pin")
            }
            .help(L10n.string("settings.windowOnTop"))
            .accessibilityLabel(L10n.string("settings.windowOnTop"))
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(for: .operation(.toggleWindowOnTop)))
                    .offset(x: 5, y: 5)
            }
            HeaderIconButton(action: { commandCenter.showSettings() }) {
                Image(systemName: "gearshape")
            }
            .help(L10n.string("settings.title"))
            .accessibilityLabel(L10n.string("settings.title"))
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(for: .operation(.showSettings)))
                    .offset(x: 5, y: 5)
            }
            HeaderIconButton(action: { newConversation() }) {
                Image(systemName: "plus.bubble")
            }
            .help(L10n.string("chat.newConversation"))
            .accessibilityLabel(L10n.string("chat.newConversation"))
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(for: .operation(.newConversation)))
                    .offset(x: 5, y: 5)
            }
        }
        // `fullSizeContentView` puts SwiftUI beneath the traffic lights.
        // Reserve their titlebar region so the brand never overlaps them.
        .padding(.leading, 78)
        .padding(.trailing, 14)
        // Keep the controls and material in the native 32pt titlebar band.
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The header is the one elevated chrome surface: a system Material
        // (AppKit vibrancy under the hood), not a hand-drawn blur. It sits in
        // the titlebar area and reads as the window's native top bar.
        .background(HeaderMaterial())
    }

    @ViewBuilder
    private var conversation: some View {
        if viewModel.messages.isEmpty {
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
                        shortcutForPreset: shortcutHint(for:),
                        onSelect: { applyPreset($0) }
                    )
                    .padding(.top, 10)
                    if !settings.enabledQuickActions.isEmpty {
                        QuickActionStripView(
                            actions: settings.enabledQuickActions,
                            showsShortcutHints: showsShortcutHints,
                            shortcutForAction: shortcutHint(for:),
                            onSelect: { triggerQuickAction(for: $0.id) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                if viewModel.canRestorePreviousSession {
                    sessionRestoreBanner
                    Divider()
                }
                GeometryReader { geometry in
                let contentWidth = conversationColumnWidth(viewportWidth: geometry.size.width)
                ScrollViewReader { proxy in
                ScrollView {
                    // Each row carries an explicit finite width (see messageRow),
                    // so a LazyVStack proposing ideal width to its children cannot
                    // re-center a short IM bubble. The horizontal padding then
                    // positions the column: IM sits flush to the 24pt content
                    // inset, standard mode centers the 760pt column.
                    conversationContent(contentWidth: contentWidth)
                        .padding(
                            .horizontal,
                            conversationColumnHorizontalPadding(viewportWidth: geometry.size.width)
                        )
                        .padding(.vertical, 20)
                }
                .defaultScrollAnchor(scrollFollowState.followsLatest ? .bottom : nil, for: .sizeChanges)
                // Keep scrolled content clear of the header Material and the
                // composer chrome as it passes beneath them at the edges.
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
    }

    /// The conversation column width inside the scroll viewport. IM rows span
    /// the full padded width so the trailing-aligned bubble reaches the right
    /// inset; standard mode keeps the familiar 760pt centered column.
    private func conversationColumnWidth(viewportWidth: CGFloat) -> CGFloat {
        let paddedWidth = max(0, viewportWidth - 48)
        return settings.chatMessageStyle == .im ? paddedWidth : min(paddedWidth, 760)
    }

    /// The symmetric horizontal inset that positions the measured column.
    /// In IM mode the column is exactly `viewport - 48`, so this resolves to
    /// the canonical 24pt inset and each row's trailing-aligned user bubble
    /// lands flush against the content right inset. In standard mode it grows
    /// beyond 24 only to center a column narrower than the viewport.
    private func conversationColumnHorizontalPadding(viewportWidth: CGFloat) -> CGFloat {
        let columnWidth = conversationColumnWidth(viewportWidth: viewportWidth)
        return max(24, (viewportWidth - columnWidth) / 2)
    }

    private func conversationContent(contentWidth: CGFloat) -> some View {
        return VStack(alignment: .leading, spacing: 20) {
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

    private static let conversationTailCount = 3

    private var historicalMessages: [ChatMessage] {
        Array(viewModel.messages.prefix(max(0, viewModel.messages.count - Self.conversationTailCount)))
    }

    private var activeTailMessages: [ChatMessage] {
        Array(viewModel.messages.suffix(Self.conversationTailCount))
    }

    private var sessionRestoreBanner: some View {
        HStack(spacing: 10) {
            Text(L10n.string("chat.sessionIdleNotice"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(L10n.string("chat.continueConversation")) {
                viewModel.restoreSession()
                inputFocused = true
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
                let canRetry = canRetry(userMessage: message)
                UserMessageContentView(
                    message: message,
                    isIM: settings.chatMessageStyle == .im,
                    isExpanded: userMessageExpansionState.isExpanded(messageID: message.id),
                    onToggleExpansion: { userMessageExpansionState.toggle(messageID: message.id) },
                    canRetry: canRetry,
                    onRetry: viewModel.retry,
                    retryShortcut: canRetry ? shortcutHint(for: .operation(.regenerateOrRetry)) : nil
                )
            case .assistant:
                AssistantMessageRow(
                    viewModel: viewModel,
                    settings: settings,
                    message: message,
                    reasoningState: reasoningToggle.state(for: message.id),
                    reduceMotion: reduceMotion,
                    isIM: settings.chatMessageStyle == .im,
                    isLatestAssistant: message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id,
                    canRegenerate: viewModel.canRegenerate,
                    canRetryWithModel: message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id && viewModel.canRegenerate,
                    onRegenerate: viewModel.regenerate,
                    onRetryWithModel: { retryLatestAnswer(with: $0) },
                    onRetryWithDefaultModel: retryLatestAnswerWithDefaultModel,
                    isCopied: copiedMessageID == message.id,
                    onCopy: { copyMessage(message) },
                    canInsertSelection: message.state == .complete && (viewModel.selectionSnapshot(for: message.id)?.canReplaceSelection ?? false),
                    onInsertSelection: { insertSelection(from: message) },
                    copyShortcut: shortcutHint(for: .operation(.copyAnswer)),
                    regenerateShortcut: shortcutHint(for: .operation(.regenerateOrRetry)),
                    retryShortcut: shortcutHint(for: .operation(.regenerateOrRetry)),
                    errorDescription: viewModel.error?.localizedDescription,
                    onRetry: viewModel.retry,
                    isExpanded: assistantMessageExpansionState.isExpanded(messageID: message.id),
                    onToggleExpansion: {
                        assistantMessageExpansionState.toggle(messageID: message.id)
                    },
                    onToggleReasoning: {
                        reasoningToggle.toggleByUser(messageID: message.id)
                    },
                    onLiveMessageChanged: { reconcileReasoningAfterStreamingUpdate($0) }
                )
            }
        }
        // A LazyVStack proposes ideal width to its children, so a short IM
        // bubble collapses to its intrinsic width and floats centered. Pin
        // each row to the measured content width: the trailing-aligned user
        // bubble reaches the right inset, and the assistant bubble stays left.
        .frame(
            width: contentWidth,
            alignment: settings.chatMessageStyle == .im && message.role == .user ? .trailing : .leading
        )
    }

    private func reconcileReasoningAfterStreamingUpdate(_ message: ChatMessage) {
        guard message.state == .streaming, message.reasoningContent?.isEmpty == false else { return }
        var updated = reasoningToggle
        updated.reconcile(message: message, prefersExpanded: settings.defaultExpandReasoning)
        if updated != reasoningToggle {
            reasoningToggle = updated
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !viewModel.pendingAttachments.isEmpty {
                attachmentStrip
            }
            HStack(alignment: .bottom, spacing: 8) {
                if !viewModel.messages.isEmpty {
                    PresetPopoverTrigger(
                        presets: settings.enabledPromptPresets,
                        selection: $viewModel.selectedPromptPreset,
                        isPresented: $isPresetPopoverPresented,
                        showsShortcutHints: showsShortcutHints,
                        shortcutForPreset: shortcutHint(for:),
                        onSelect: { applyPreset($0) }
                    )
                    .transition(.opacity)
                }
                AttachmentPickerButton(action: presentAttachmentPicker)
                ChatInputTextView(
                    text: $viewModel.input,
                    isFocused: $inputFocused,
                    height: $inputHeight,
                    isGenerating: isGenerating,
                    onSubmit: {
                        sendFromComposer()
                        return true
                    },
                    onEscape: handleEscape,
                    onPasteImage: { data in
                        Task { await viewModel.addScreenshot(data) }
                    },
                    onPasteFiles: { urls in
                        Task { @MainActor in
                            for url in urls {
                                await viewModel.addAttachment(from: url)
                            }
                        }
                    },
                    onTextViewReady: { composerTextView.textView = $0 },
                    onRecall: { viewModel.recallLastQuestion() }
                )
                .frame(height: inputHeight)
                .animation(.easeOut(duration: 0.12), value: inputHeight)
                .background(inputFocused ? Brand.bg : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(inputFocused ? Brand.accent : Brand.border, lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Brand.accent.opacity(0.15), lineWidth: 6)
                        .blur(radius: 4)
                        .opacity(inputFocused ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if viewModel.input.isEmpty {
                        Text(placeholderText)
                            .foregroundStyle(Brand.muted)
                            .padding(.leading, 14)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    ShortcutKeycap(shortcut: shortcutHint(for: .operation(.focusInput)))
                        .padding(8)
                }
                .animation(.easeOut(duration: 0.12), value: inputFocused)
                ComposerSendButton(
                    isGenerating: isGenerating,
                    canSend: viewModel.canSend,
                    shortcut: shortcutHint(for: .operation(.sendOrCancel)),
                    action: primaryAction
                )
            }
            if let preset = viewModel.selectedPromptPreset {
                HStack {
                    Spacer(minLength: 0)
                    SelectedPresetBadge(title: preset.title, icon: preset.symbolName) {
                        viewModel.selectedPromptPreset = nil
                        inputFocused = true
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.pendingAttachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        viewModel.removeAttachment(id: attachment.id)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(L10n.string("chat.attachments"))
    }

    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task { await viewModel.addAttachment(from: url) }
            }
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    await viewModel.addAttachment(from: url)
                }
            }
        }
    }

    private var placeholderText: String {
        guard let preset = viewModel.selectedPromptPreset else {
            return L10n.string("chat.inputPlaceholder")
        }
        return PresetPlaceholder.text(for: preset.id, title: preset.title)
    }

    private var isGenerating: Bool {
        viewModel.generationState == .connecting || viewModel.generationState == .streaming
    }

    private var effectiveProviderIconSlug: String? {
        guard let model = viewModel.effectiveModel,
              let provider = viewModel.effectiveProvider else { return nil }
        return ProviderBrandIconMatcher.match(
            providerName: provider.name,
            address: provider.address,
            modelName: model.displayName,
            upstreamModelID: model.upstreamModelID
        )
    }

    private var colorScheme: ColorScheme? {
        settings.appearance.colorScheme
    }

    private var contentFont: Font {
        let baseSize: CGFloat
        switch settings.fontSize {
        case .small: baseSize = 13
        case .standard: baseSize = 14.5
        case .large: baseSize = 17
        }
        return .system(size: baseSize * settings.interfaceZoomLevel.displayScale)
    }

    private func primaryAction() {
        if isGenerating { viewModel.cancel() }
        else {
            sendFromComposer()
        }
    }

    private func sendFromComposer() {
        synchronizeSelectedPromptPreset()
        if viewModel.send() {
            scrollFollowState.resumeFollowing()
        }
    }

    private func installShortcutDispatcher() {
        guard shortcutDispatcher == nil else { return }
        let dispatcher = InAppShortcutDispatcher(
            settings: settings,
            isForeground: {
                guard let window = chatWindowReference.window else { return false }
                return window === NSApp.keyWindow && window.isKeyWindow
            },
            hasMarkedText: composerHasMarkedText,
            handleTarget: performShortcutTarget,
            setHintsVisible: { showsShortcutHints = $0 }
        )
        dispatcher.start()
        shortcutDispatcher = dispatcher
    }

    private func composerHasMarkedText() -> Bool {
        responderHasMarkedText(chatWindowReference.window?.firstResponder)
    }

    private func focusInput() {
        inputFocused = true
        viewModel.prepareNewConversationAfterInactivity()
        guard let window = chatWindowReference.window,
              let composerTextView = composerTextView.textView,
              window.firstResponder !== composerTextView else { return }
        window.makeFirstResponder(composerTextView)
    }

    private func performShortcutTarget(_ target: InAppShortcutTarget) -> Bool {
        switch target {
        case let .promptPreset(id):
            guard let preset = settings.enabledPromptPreset(id: id) else { return false }
            applyPreset(shortcutPresetSelection(current: viewModel.selectedPromptPreset, requested: preset))
            return true
        case let .quickAction(id):
            return triggerQuickAction(for: id)
        case let .operation(operation):
            switch operation {
            case .focusInput:
                focusInput()
                return true
            case .regenerateOrRetry:
                if viewModel.canRegenerate {
                    viewModel.regenerate()
                    return true
                }
                if viewModel.generationState == .failed {
                    viewModel.retry()
                    return true
                }
                return false
            case .copyAnswer:
                guard let answer = viewModel.lastAssistantMessage, !answer.content.isEmpty else { return false }
                copyMessage(answer)
                return true
            case .toggleWindowOnTop:
                SpotAskCommandCenter.shared.toggleWindowOnTop()
                return true
            case .showSettings:
                commandCenter.showSettings()
                return true
            case .newConversation:
                newConversation()
                return true
            case .sendOrCancel:
                guard isGenerating || viewModel.canSend else { return false }
                primaryAction()
                return true
            case .zoomIn:
                adjustZoom(by: 1)
                return true
            case .zoomOut:
                adjustZoom(by: -1)
                return true
            }
        }
    }

    private func adjustZoom(by delta: Int) {
        let current = settings.interfaceZoomLevel
        let next = InterfaceZoomLevel.adjusted(from: current, by: delta)
        guard next != current else { return }
        settings.interfaceZoomLevel = next
    }

    private func shortcutHint(for target: InAppShortcutTarget) -> InAppShortcut? {
        inAppShortcutHint(settings.shortcut(for: target), commandHintsVisible: showsShortcutHints)
    }

    private func shortcutHint(for preset: PromptPreset) -> InAppShortcut? {
        shortcutHint(for: .promptPreset(preset.id))
    }

    private func shortcutHint(for action: QuickAction) -> InAppShortcut? {
        shortcutHint(for: .quickAction(action.id))
    }

    private func lazyQuickActionTrigger() -> QuickActionTrigger {
        if let trigger = quickActionTrigger {
            return trigger
        }
        let trigger = QuickActionTrigger(
            isSessionEmpty: { viewModel.messages.isEmpty },
            isGenerating: { isGenerating },
            currentInput: { viewModel.input },
            clearInput: { viewModel.input = "" },
            resolveAction: { settings.enabledQuickAction(id: $0) },
            closePanel: { commandCenter.close() }
        )
        quickActionTrigger = trigger
        return trigger
    }

    @discardableResult
    private func triggerQuickAction(for actionID: UUID) -> Bool {
        lazyQuickActionTrigger().trigger(actionID: actionID)
    }

    private func canRetry(userMessage: ChatMessage) -> Bool {
        guard viewModel.generationState == .failed,
              viewModel.messages.last?.role == .assistant,
              viewModel.messages.last?.state == .failed,
              let lastUserMessage = viewModel.messages.last(where: { $0.role == .user }) else { return false }
        return userMessage.id == lastUserMessage.id
    }

    private func copyMessage(_ message: ChatMessage) {
        Clipboard.copy(message.content)
        copiedMessageID = message.id
        let token = UUID()
        copyFeedbackToken = token
        Task {
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, copyFeedbackToken == token else { return }
            copiedMessageID = nil
        }
    }

    private func retryLatestAnswer(with modelID: UUID) {
        viewModel.regenerate(withModelID: modelID)
    }

    private func retryLatestAnswerWithDefaultModel() {
        viewModel.regenerateWithDefaultModel()
    }

    private func insertSelection(from message: ChatMessage) {
        guard let snapshot = viewModel.selectionSnapshot(for: message.id) else { return }
        Task {
            do {
                try await selectionReplacementWriter.replaceSelection(in: snapshot, with: message.content)
                StatusToastCenter.shared.show(L10n.string("chat.insertSelectionSucceeded"))
            } catch let error as SelectionReplacementError {
                let message: String
                switch error {
                case .selectionChanged: message = L10n.string("chat.insertSelectionChanged")
                case .unavailable, .failed: message = L10n.string("chat.insertSelectionUnavailable")
                }
                StatusToastCenter.shared.show(message, isError: true)
            } catch {
                StatusToastCenter.shared.show(L10n.string("chat.insertSelectionUnavailable"), isError: true)
            }
        }
    }


    /// Applies a preset from the quick-strip or the in-conversation popover.
    /// With a non-empty draft (typed text or pending attachments) it selects
    /// the preset and sends immediately, so the user skips the send button;
    /// with an empty draft it only selects the preset, swaps the placeholder,
    /// and focuses the input (Return still sends). "直接提问" passes nil and
    /// never sends.
    private func applyPreset(_ preset: PromptPreset?) {
        guard let preset else {
            viewModel.selectedPromptPreset = nil
            inputFocused = true
            return
        }
        guard let enabledPreset = settings.promptPresetAllowedForUse(preset) else {
            viewModel.selectedPromptPreset = nil
            inputFocused = true
            return
        }
        viewModel.selectedPromptPreset = enabledPreset
        inputFocused = true
        guard viewModel.canSend else { return }
        sendFromComposer()
    }

    private func synchronizeSelectedPromptPreset() {
        guard let selectedPreset = viewModel.selectedPromptPreset else { return }
        viewModel.selectedPromptPreset = settings.promptPresetAllowedForUse(selectedPreset)
    }

    private func newConversation() {
        guard viewModel.messages.isEmpty else {
            guard settings.confirmBeforeStartingNewConversation else {
                confirmNewConversation()
                return
            }
            NewConversationConfirmation.present(
                settings: settings,
                window: NSApp.keyWindow ?? NSApp.mainWindow,
                onConfirm: confirmNewConversation
            )
            return
        }
        confirmNewConversation()
    }

    private func confirmNewConversation() {
        viewModel.newConversation()
        inputFocused = true
        scrollFollowState.resumeFollowing()
    }
    private func handleEscape() {
        switch chatEscapeAction(
            hasMarkedText: composerHasMarkedText(),
            isPresetPopoverPresented: isPresetPopoverPresented,
            isModelPickerPresented: isModelPickerPresented,
            isGenerating: isGenerating,
            startsNewConversation: settings.escapeStartsNewConversation,
            hasMessages: !viewModel.messages.isEmpty
        ) {
        case .preserveMarkedText:
            break
        case .dismissPresetPopover:
            isPresetPopoverPresented = false
        case .dismissModelPicker:
            isModelPickerPresented = false
        case .cancelGeneration:
            viewModel.cancel()
        case .startNewConversation:
            newConversation()
        case .dismissWindow:
            dismiss()
        }
    }

    private func dismiss() {
        if settings.clearInputOnClose { viewModel.input = "" }
        onDismiss()
    }

    private func handleCommandAction(_ action: SpotAskCommandAction) {
        switch action {
        case .focusInput:
            focusInput()
        case let .compose(question, promptPreset):
            composeQuestion(question, promptPreset: promptPreset)
        case let .prepare(promptPreset):
            viewModel.selectedPromptPreset = settings.promptPresetAllowedForUse(promptPreset)
            inputFocused = true
        case .newConversation:
            newConversation()
        case let .ask(question, promptPreset, selectionSnapshot):
            receiveQuestion(question, promptPreset: promptPreset, selectionSnapshot: selectionSnapshot)
        case .showSettings:
            commandCenter.showSettings()
        }
    }

    private func receiveQuestion(_ question: String, promptPreset: PromptPreset?, selectionSnapshot: SelectedTextSnapshot? = nil) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputFocused = true
            return
        }
        // External questions always use the new conversation prepared after
        // inactivity; the previous one remains available only via the banner.
        viewModel.selectedPromptPreset = promptPreset.flatMap(settings.promptPresetAllowedForUse)
        // Do not start a second request while the view model is still unwinding
        // a cancelled stream. The supplied question remains ready to send.
        guard !isGenerating else {
            viewModel.input = trimmed
            inputFocused = true
            return
        }
        viewModel.input = trimmed
        if viewModel.send(selectionSnapshot: selectionSnapshot) {
            scrollFollowState.resumeFollowing()
        }
        inputFocused = true
    }

    private func composeQuestion(_ question: String, promptPreset: PromptPreset?) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputFocused = true
            return
        }
        viewModel.selectedPromptPreset = promptPreset.flatMap(settings.promptPresetAllowedForUse)
        viewModel.input = trimmed
        inputFocused = true
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







