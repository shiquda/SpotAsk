import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private enum NewConversationConfirmation {
    static func present(
        settings: AppSettings,
        window: NSWindow?,
        onConfirm: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = L10n.string("chat.newConversationConfirmTitle")
        alert.informativeText = L10n.string("chat.newConversationConfirmMessage")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("chat.newConversation"))
        alert.addButton(withTitle: L10n.string("settings.cancel"))

        let skipFutureConfirmations = NSButton(
            checkboxWithTitle: L10n.string("chat.newConversationDontAskAgain"),
            target: nil,
            action: nil
        )
        alert.accessoryView = skipFutureConfirmations

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            if skipFutureConfirmations.state == .on {
                settings.confirmBeforeStartingNewConversation = false
            }
            onConfirm()
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
}

func shortcutPresetSelection(current: PromptPreset?, requested: PromptPreset) -> PromptPreset? {
    current?.id == requested.id ? nil : requested
}

enum ChatEscapeAction: Equatable {
    case preserveMarkedText
    case dismissPresetPopover
    case dismissModelPicker
    case cancelGeneration
    case startNewConversation
    case dismissWindow
}

func chatEscapeAction(
    hasMarkedText: Bool,
    isPresetPopoverPresented: Bool,
    isModelPickerPresented: Bool = false,
    isGenerating: Bool,
    startsNewConversation: Bool,
    hasMessages: Bool
) -> ChatEscapeAction {
    if hasMarkedText {
        return .preserveMarkedText
    }
    if isPresetPopoverPresented {
        return .dismissPresetPopover
    }
    if isModelPickerPresented {
        return .dismissModelPicker
    }
    if isGenerating {
        return .cancelGeneration
    }
    if startsNewConversation, hasMessages {
        return .startNewConversation
    }
    return .dismissWindow
}

/// Shared bounded preview scan used by the user and assistant display policies.
enum LongTextDisplayPolicy {
    static func collapsedPreview(
        _ content: String,
        characterThreshold: Int,
        explicitLineThreshold: Int
    ) -> String? {
        var characterCount = 0
        var explicitLineCount = 1
        var lastContentEnd = content.startIndex

        for index in content.indices {
            if characterCount == characterThreshold {
                return String(content[..<lastContentEnd])
            }

            let nextIndex = content.index(after: index)
            characterCount += 1

            if content[index].isNewline {
                if explicitLineCount == explicitLineThreshold {
                    return String(content[..<lastContentEnd])
                }
                explicitLineCount += 1
            } else {
                lastContentEnd = nextIndex
            }
        }

        return explicitLineCount >= explicitLineThreshold
            ? String(content[..<lastContentEnd])
            : nil
    }
}

/// Decides when a sent question needs an initially compact presentation.
/// The original message content is always retained and rendered when expanded.
enum UserMessageDisplayPolicy {
    static let characterThreshold = 500
    static let explicitLineThreshold = 8
    static let collapsedLineLimit = 8

    static func shouldCollapse(_ content: String) -> Bool {
        collapsedPreview(for: content) != nil
    }

    /// Returns only the text needed for the compact view. Scanning stops as
    /// soon as either collapse threshold is reached, avoiding work proportional
    /// to an arbitrarily long saved question.
    static func collapsedPreview(for content: String) -> String? {
        LongTextDisplayPolicy.collapsedPreview(
            content,
            characterThreshold: characterThreshold,
            explicitLineThreshold: explicitLineThreshold
        )
    }
}

/// Long assistant answers use a plain compact preview instead of running the
/// full Markdown renderer until the user asks to expand them.
enum AssistantMessageDisplayPolicy {
    static let characterThreshold = 4_000
    static let explicitLineThreshold = 120
    static let collapsedLineLimit = 12

    static func shouldCollapse(_ content: String) -> Bool {
        collapsedPreview(for: content) != nil
    }

    static func collapsedPreview(for content: String) -> String? {
        LongTextDisplayPolicy.collapsedPreview(
            content,
            characterThreshold: characterThreshold,
            explicitLineThreshold: explicitLineThreshold
        )
    }
}

/// View-owned expansion state for long messages. Keeping it above lazy rows
/// preserves a user's choice while a row is temporarily recycled off-screen.
struct MessageExpansionState: Equatable {
    private(set) var expandedMessageIDs: Set<UUID> = []

    mutating func reconcile(messages: [ChatMessage], role: ChatRole) {
        let currentIDs = Set(messages.lazy.filter { $0.role == role }.map(\.id))
        expandedMessageIDs.formIntersection(currentIDs)
        // A message created in this window starts streaming before the user can
        // choose an expansion state. Keep it full-height through completion so
        // the terminal transition never collapses an answer the user just saw.
        if role == .assistant {
            expandedMessageIDs.formUnion(
                messages.lazy
                    .filter { $0.role == .assistant && $0.state == .streaming }
                    .map(\.id)
            )
        }
    }

    func isExpanded(messageID: UUID) -> Bool {
        expandedMessageIDs.contains(messageID)
    }

    mutating func toggle(messageID: UUID) {
        if expandedMessageIDs.contains(messageID) {
            expandedMessageIDs.remove(messageID)
        } else {
            expandedMessageIDs.insert(messageID)
        }
    }
}

typealias UserMessageExpansionState = MessageExpansionState

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let keyStore: any APIKeyStoring
    let providerFactory: any ChatProviderFactory
    let accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator
    let onDismiss: () -> Void
    let commandCenter: SpotAskCommandCenter

    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollFollowState = ScrollFollowState()
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var inputHeight = ChatInputTextView.minHeight
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

    /// Owns the standalone settings window. Created lazily on first use and
    /// reused thereafter so repeated opens never stack duplicate windows.
    @State private var settingsWindowController: SettingsWindowController?

    init(
        viewModel: ChatViewModel,
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator = AccessibilityPermissionCoordinator(),
        onDismiss: @escaping () -> Void = { NSApp.keyWindow?.orderOut(nil) },
        commandCenter: SpotAskCommandCenter = .shared
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
        self.accessibilityPermissionCoordinator = accessibilityPermissionCoordinator
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
        .onChange(of: viewModel.isSettingsPresented) { _, isPresented in
            if isPresented {
                presentSettingsWindow()
            }
        }
        .onChange(of: isModelPickerPresented) { _, isPresented in
            if !isPresented {
                inputFocused = true
            }
        }
        .onAppear {
            inputFocused = true
            viewModel.offerSessionChoiceIfNeeded()
            commandCenter.setActionConsumer(handleCommandAction)
            reasoningToggle.reconcile(messages: viewModel.messages, prefersExpanded: settings.defaultExpandReasoning)
            userMessageExpansionState.reconcile(messages: viewModel.messages, role: .user)
            assistantMessageExpansionState.reconcile(messages: viewModel.messages, role: .assistant)
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
            HeaderIconButton(action: { openSettings() }) {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if viewModel.isSessionChoicePending {
                    sessionChoiceBanner
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

    private var sessionChoiceBanner: some View {
        HStack(spacing: 10) {
            Text(L10n.string("chat.sessionIdleNotice"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(L10n.string("chat.continueConversation")) {
                viewModel.continueSession()
                inputFocused = true
            }
            .controlSize(.small)
            Button(L10n.string("chat.startNewQuestion")) {
                startFreshSession()
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
                    message: message,
                    reasoningState: reasoningToggle.state(for: message.id),
                    reduceMotion: reduceMotion,
                    isIM: settings.chatMessageStyle == .im,
                    isLatestAssistant: message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id,
                    canRegenerate: viewModel.canRegenerate,
                    onRegenerate: viewModel.regenerate,
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

    private func performShortcutTarget(_ target: InAppShortcutTarget) -> Bool {
        switch target {
        case let .promptPreset(id):
            guard let preset = settings.enabledPromptPreset(id: id) else { return false }
            applyPreset(shortcutPresetSelection(current: viewModel.selectedPromptPreset, requested: preset))
            return true
        case let .operation(operation):
            switch operation {
            case .focusInput:
                inputFocused = true
                viewModel.offerSessionChoiceIfNeeded()
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
                openSettings()
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

    /// Entry point for every settings request (header gear, command center).
    /// Sets the trigger boolean (the source of truth) and shows the window,
    /// bringing it to the front even if it is already open.
    private func openSettings() {
        viewModel.isSettingsPresented = true
        presentSettingsWindow()
    }

    /// Lazily builds the standalone settings window controller on first use and
    /// shows it. When the window closes, the controller clears
    /// `viewModel.isSettingsPresented`, keeping the trigger boolean in sync.
    private func presentSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                keyStore: keyStore,
                providerFactory: providerFactory,
                accessibilityPermissionCoordinator: accessibilityPermissionCoordinator,
                onClose: { viewModel.isSettingsPresented = false }
            )
        }
        settingsWindowController?.show()
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

    private func startFreshSession() {
        viewModel.startFreshSession()
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
            inputFocused = true
            viewModel.offerSessionChoiceIfNeeded()
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
            openSettings()
        }
    }

    private func receiveQuestion(_ question: String, promptPreset: PromptPreset?, selectionSnapshot: SelectedTextSnapshot? = nil) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputFocused = true
            return
        }
        // An explicit external question intentionally continues a restored
        // session, rather than leaving it blocked behind the interactive choice.
        viewModel.continueSession()
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
        viewModel.continueSession()
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

/// Renders one assistant message. Keeping this in its own view means a token
/// flush only invalidates the active answer row, not the whole conversation.
private struct AssistantMessageRow: View {
    let viewModel: ChatViewModel
    let message: ChatMessage
    let reasoningState: ReasoningToggleState
    let reduceMotion: Bool
    let isIM: Bool
    let isLatestAssistant: Bool
    let canRegenerate: Bool
    let onRegenerate: () -> Void
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
                providerName: displayedMessage.providerName
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
                    isBubble: isIM
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
                    messageID: message.id,
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
    }
}

fileprivate struct AssistantMessageHeader: View {
    let modelDisplayName: String?
    let providerName: String?

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
        }
    }
}

/// A reasoning transcript owns its own follow preference, so reading earlier
/// reasoning never changes the user's position in the conversation.
private struct ReasoningContentView: View {
    let messageID: UUID
    let reasoning: String

    @State private var scrollFollowState = ScrollFollowState()
    @State private var pendingScrollTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                Color.clear
                    .frame(height: 1)
                    .id(bottomAnchorID)
            }
            .defaultScrollAnchor(scrollFollowState.followsLatest ? .bottom : nil, for: .sizeChanges)
            .frame(height: 240)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            .onAppear {
                scrollToBottom(using: proxy)
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
            .onChange(of: reasoning) { _, _ in
                scrollToBottom(using: proxy)
            }
            .onDisappear {
                pendingScrollTask?.cancel()
            }
        }
    }

    private var bottomAnchorID: String {
        "reasoning-bottom-\(messageID.uuidString)"
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard scrollFollowState.followsLatest else { return }
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))

            guard scrollFollowState.followsLatest else { return }
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
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

// MARK: - Header material

/// The header's elevated chrome background. Uses a system Material on macOS 15
/// (`.regular` over the window, AppKit vibrancy under the hood) and the native
/// Liquid Glass chrome on macOS 26 — never a hand-drawn blur, backdrop filter,
/// or hard-coded translucent fill. The material supplies its own legibility,
/// so the header's text and icons render directly on it.
private struct HeaderMaterial: View {
    var body: some View {
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: .rect)
        } else {
            Rectangle()
                .fill(.regularMaterial)
        }
    }
}

// MARK: - Brand tokens

/// The six SpotAsk brand tokens from the redesign contract. Hover and glow
/// variants are derived with `darker` / `opacity` (the oklch-relative
/// adjustments of the prototype), never with a new hard-coded color.
enum Brand {
    static let bg = dynamic(light: 0xFFFFFF, dark: 0x17191D)
    static let surface = dynamic(light: 0xF7F8FA, dark: 0x22252B)
    static let fg = dynamic(light: 0x111111, dark: 0xF4F5F7)
    static let muted = dynamic(light: 0x6B7280, dark: 0xA9B1BD)
    static let border = dynamic(light: 0xD9DEE7, dark: 0x3C424C)
    static let accent = Color(red: 0x16 / 255, green: 0x77 / 255, blue: 0xFF / 255)

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

private extension Color {
    /// Darkens toward black in sRGB, standing in for the prototype's
    /// `oklch(from c calc(l - amount) c h)` hover adjustment.
    func darker(_ amount: Double) -> Color {
        let clamped = min(max(amount, 0), 1)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        func scaled(_ component: CGFloat) -> Double {
            Double(component) * (1 - clamped)
        }
        return Color(red: scaled(ns.redComponent),
                     green: scaled(ns.greenComponent),
                     blue: scaled(ns.blueComponent),
                     opacity: Double(ns.alphaComponent))
    }
}

// MARK: - Preset placeholder copy

/// The prototype switches the placeholder per preset. The preset prompt text
/// is localized, so per-preset guidance is derived here (the resource tables
/// are read-only for this change). Built-in presets are matched by their
/// stable identity or localized title; anything else falls back to a generic
/// task-oriented prompt.
private enum PresetPlaceholder {
    private static let translateID = UUID(uuidString: "EF8CF35C-386A-4389-A137-C207E4DB11FD")!
    private static let polishID = UUID(uuidString: "1C85A324-65B3-4EBD-B2C4-0C6B072E284A")!
    private static let summarizeID = UUID(uuidString: "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2")!
    private static let explainID = UUID(uuidString: "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248")!

    private static var isChinese: Bool {
        L10n.string("chat.inputPlaceholder").contains("输入")
    }

    static func text(for id: UUID, title: String) -> String {
        if id == translateID || title == L10n.string("preset.translate.title") {
            return isChinese ? "输入要翻译的内容…" : "Enter text to translate..."
        }
        if id == polishID || title == L10n.string("preset.polish.title") {
            return isChinese ? "输入要润色的文字…" : "Enter text to polish..."
        }
        if id == summarizeID || title == L10n.string("preset.summarize.title") {
            return isChinese ? "粘贴要总结的内容…" : "Paste content to summarize..."
        }
        if id == explainID || title == L10n.string("preset.explain.title") {
            return isChinese ? "输入要解释的内容…" : "Enter content to explain..."
        }
        return L10n.string("chat.usePrompt", title)
    }
}

// MARK: - Brand mark

/// Returns the app icon only when the executable app bundle provides it.
/// SwiftPM tests run from a different main bundle, so callers retain a local
/// SF Symbol fallback instead of depending on `Bundle.module`.
func spotAskAppIconImage(bundle: Bundle = .main) -> NSImage? {
    guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns") else {
        return nil
    }
    return NSImage(contentsOf: url)
}

/// The compact app icon shown alongside the title wordmark.
private struct BrandMark: View {
    var body: some View {
        Group {
            if let appIcon = spotAskAppIconImage() {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    // App icon resources are opaque; match the icon's native
                    // silhouette so its square corners do not show in the titlebar.
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Brand.accent)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The app icon gives the first empty conversation screen the same identity
/// as the app bundle while retaining the prior lightweight fallback.
private struct EmptyStateBrandMark: View {
    var body: some View {
        Group {
            if let appIcon = spotAskAppIconImage() {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Brand.muted)
            }
        }
        .accessibilityLabel(Text("SpotAsk"))
    }
}

// MARK: - Header icon button

/// The prototype's `.icon-btn`: a 28×28 hit target whose hover fills a
/// `surface` rounded square and darkens the glyph to `fg` (never grays it),
/// with a 2pt accent ring standing in for `:focus-visible`. Wraps the button's
/// label only; its behavior and accessibility stay on the caller.
private struct HeaderIconButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 16))
                .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                .frame(width: 28, height: 28)
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

struct ShortcutKeycap: View {
    let shortcut: InAppShortcut?

    var body: some View {
        if let shortcut {
            HStack(spacing: 2) {
                ForEach(InAppShortcutDisplay.labels(for: shortcut, includeCommand: false), id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Brand.border, lineWidth: 0.5)
                        }
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Empty-state preset strip

/// One-tap preset chips shown only before the first message. Tapping selects
/// the preset, highlights the chip, and hands focus back to the input.
private struct PresetStripView: View {
    let presets: [PromptPreset]
    @Binding var selection: PromptPreset?
    let showsShortcutHints: Bool
    let shortcutForPreset: (PromptPreset) -> InAppShortcut?
    let onSelect: (PromptPreset) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        ChipView(
                            title: preset.title,
                            icon: preset.symbolName,
                            isSelected: selection?.id == preset.id,
                            shortcut: showsShortcutHints ? shortcutForPreset(preset) : nil
                        ) {
                            onSelect(preset)
                        }
                    }
                }
                // A horizontal ScrollView lays out short content at its leading
                // edge. Match the viewport width so the chip group is centered
                // until it needs to scroll.
                .frame(minWidth: geometry.size.width, alignment: .center)
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: 460)
        .frame(height: 38)
    }
}

private struct ChipView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let shortcut: InAppShortcut?
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.white : (isHovering ? Brand.fg : Brand.muted))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Brand.accent : Brand.surface)
            )
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? Brand.accent : (isHovering ? Brand.muted : Brand.border),
                    lineWidth: 1
                )
            }
            .overlay {
                if isFocused, !isSelected {
                    Capsule().strokeBorder(Brand.accent, lineWidth: 2).padding(-2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            ShortcutKeycap(shortcut: shortcut)
                .allowsHitTesting(false)
                .offset(x: 5, y: 5)
        }
        .zIndex(shortcut == nil ? 0 : 1)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .help(L10n.string("chat.usePrompt", title))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - In-conversation preset trigger + popover

/// The 36×36 circular trigger shown once a conversation has started. It opens
/// an upward popover listing "直接提问" plus every preset; the current item
/// carries a check. Selecting applies immediately and closes.
private struct PresetPopoverTrigger: View {
    let presets: [PromptPreset]
    @Binding var selection: PromptPreset?
    @Binding var isPresented: Bool
    let showsShortcutHints: Bool
    let shortcutForPreset: (PromptPreset) -> InAppShortcut?
    let onSelect: (PromptPreset?) -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var hasSelection: Bool { selection != nil }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(hasSelection ? Brand.accent : (isHovering ? Brand.fg : Brand.muted))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(isHovering || isPresented ? Brand.surface : Brand.bg)
                )
                .overlay {
                    Circle().strokeBorder(hasSelection ? Brand.accent : Brand.border, lineWidth: 1)
                }
                .overlay {
                    if isFocused {
                        Circle().strokeBorder(Brand.accent, lineWidth: 2).padding(-2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(L10n.string("chat.selectPrompt"))
        .accessibilityLabel(L10n.string("chat.selectPrompt"))
        .accessibilityValue(hasSelection ? selection!.title : L10n.string("chat.directQuestion"))
        .background(
            PopoverOutsideClickMonitor(isPresented: $isPresented)
        )
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
        ) {
            PresetPopoverContent(
                presets: presets,
                selection: selection,
                showsShortcutHints: showsShortcutHints,
                shortcutForPreset: shortcutForPreset
            ) { preset in
                isPresented = false
                onSelect(preset)
            }
        }
    }
}

private struct PresetPopoverContent: View {
    let presets: [PromptPreset]
    let selection: PromptPreset?
    let showsShortcutHints: Bool
    let shortcutForPreset: (PromptPreset) -> InAppShortcut?
    let onChoose: (PromptPreset?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverRow(
                title: L10n.string("chat.directQuestion"),
                icon: "text.bubble",
                isSelected: selection == nil
            ) {
                onChoose(nil)
            }
            Divider().padding(.vertical, 4).padding(.horizontal, 6)
            ForEach(presets) { preset in
                PopoverRow(
                    title: preset.title,
                    icon: preset.symbolName,
                    isSelected: selection?.id == preset.id,
                    shortcut: showsShortcutHints ? shortcutForPreset(preset) : nil
                ) {
                    onChoose(preset)
                }
            }
        }
        .padding(5)
        .frame(minWidth: 180)
        .fixedSize()
    }
}

private struct PopoverRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var shortcut: InAppShortcut? = nil
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.fg)
                Spacer(minLength: 8)
                ShortcutKeycap(shortcut: shortcut)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(isHovering ? Brand.surface : Color.clear)
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.accent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Circular send / stop button

/// The 36×36 circular anchor of the composer. Accent when sending, near-black
/// when generating; hover darkens via the oklch-equivalent `darker`.
private struct ComposerSendButton: View {
    let isGenerating: Bool
    let canSend: Bool
    let shortcut: InAppShortcut?
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var isEnabled: Bool { isGenerating || canSend }

    private var fill: Color {
        let base = isGenerating ? Brand.fg : Brand.accent
        guard isHovering, isEnabled else { return base }
        return base.darker(isGenerating ? 0.05 : 0.08)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(fill))
                .overlay {
                    if isFocused {
                        Circle().strokeBorder(Brand.accent, lineWidth: 2).padding(-3)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(CircularPressButtonStyle())
        .focused($isFocused)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: fill)
        .help(isGenerating ? L10n.string("chat.stop") : L10n.string("chat.send"))
        .accessibilityLabel(isGenerating ? L10n.string("chat.stop") : L10n.string("chat.send"))
        .overlay(alignment: .bottomTrailing) {
            ShortcutKeycap(shortcut: shortcut)
                .offset(x: 5, y: 5)
        }
    }
}

/// Nudges the circle down 1pt while pressed, mirroring the prototype's
/// `:active { transform: translateY(1px) }`.
private struct CircularPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

// MARK: - Selected preset badge

private struct SelectedPresetBadge: View {
    let title: String
    let icon: String
    let onClear: () -> Void

    @State private var isClearHovering = false
    @FocusState private var isClearFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isClearHovering ? Brand.fg : Brand.muted)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 3).fill(isClearHovering ? Brand.surface : Color.clear)
                    )
                    .overlay {
                        if isClearFocused {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Brand.accent, lineWidth: 2)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isClearFocused)
            .onHover { isClearHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isClearHovering)
            .help(L10n.string("chat.clearPrompt"))
            .accessibilityLabel(L10n.string("chat.clearPrompt"))
        }
        .foregroundStyle(Brand.accent)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Click-outside-to-close for the preset popover

/// Installs a local event monitor while the popover is open. A left or right
/// mouse-down outside the popover's window closes it (the click also proceeds
/// to its target); clicks inside the popover pass through untouched. `esc`
/// closes separately via the composer's existing escape handling.
private struct PopoverOutsideClickMonitor: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.updateMonitoring(anchor: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.updateMonitoring(anchor: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var isPresented: Binding<Bool>
        private weak var anchor: NSView?
        private var monitor: Any?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        @MainActor
        func updateMonitoring(anchor: NSView) {
            self.anchor = anchor
            if isPresented.wrappedValue {
                start()
            } else {
                stop()
            }
        }

        @MainActor
        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.isPresented.wrappedValue else { return event }
                if let anchor = self.anchor,
                   let eventWindow = event.window,
                   let anchorWindow = anchor.window,
                   eventWindow != anchorWindow {
                    // The click landed in another window of this app — the
                    // transient popover window. Let it through without closing.
                    return event
                }
                self.isPresented.wrappedValue = false
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct UserMessageContentView: View {
    let message: ChatMessage
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
    }
}

// MARK: - Model picker

/// The header's quiet model selector: visually weaker than the SpotAsk brand,
/// opens a searchable popover, and stays disabled while a response is running.
private struct ModelPickerHeaderButton<PopoverContent: View>: View {
    let modelName: String
    let providerIconSlug: String?
    let isDisabled: Bool
    @Binding var isPresented: Bool
    @ViewBuilder let popoverContent: () -> PopoverContent

    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                ProviderBrandIconView(
                    slug: providerIconSlug,
                    size: 14,
                    fallbackSymbol: "sparkles",
                    fallbackColor: isHovering ? Brand.fg : Brand.muted
                )
                Text(modelName.isEmpty ? L10n.string("chat.model") : modelName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(isHovering || isPresented ? Brand.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .help(isDisabled ? L10n.string("chat.modelChangeDisabledWhileGenerating") : L10n.string("chat.model"))
        .accessibilityLabel(L10n.string("chat.model"))
        .accessibilityValue(modelName)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            popoverContent()
        }
    }
}

/// Searchable model list grouped by provider. Keyboard: arrows move the
/// highlight, Return selects, Escape closes (the popover's default).
private struct ModelPickerContent: View {
    let catalog: ProviderModelCatalog?
    let effectiveModelID: UUID?
    let hasSessionOverride: Bool
    let isDisabled: Bool
    let onSelect: (UUID) -> Void
    let onUseDefault: () -> Void

    @State private var searchText = ""
    @State private var highlightedID: UUID?
    @FocusState private var isSearchFocused: Bool

    private var filteredGroups: [(provider: ProviderConfiguration, models: [ModelConfiguration])] {
        guard let catalog else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalog.providers.compactMap { provider in
            let models = catalog.models
                .filter { $0.providerID == provider.id }
                .filter { model in
                    guard !query.isEmpty else { return true }
                    return model.displayName.lowercased().contains(query)
                        || model.upstreamModelID.lowercased().contains(query)
                        || provider.name.lowercased().contains(query)
                }
            return models.isEmpty ? nil : (provider, models)
        }
    }

    private var flattenedModels: [ModelConfiguration] {
        filteredGroups.flatMap(\.models)
    }

    private var defaultModelName: String? {
        guard let catalog else { return nil }
        return catalog.models.first(where: { $0.id == catalog.selectedModelID })?.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L10n.string("chat.modelPickerSearchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.border, lineWidth: 0.5)
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if let highlightedID {
                        onSelect(highlightedID)
                    }
                    return .handled
                }
                .onChange(of: searchText) { _, _ in
                    highlightFirst()
                }
                .onAppear {
                    highlightFirst()
                    isSearchFocused = true
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if hasSessionOverride, let defaultModelName {
                        UseDefaultModelRow(modelName: defaultModelName) {
                            onUseDefault()
                        }
                        Divider().padding(.vertical, 4)
                    }
                    ForEach(filteredGroups, id: \.provider.id) { group in
                        HStack(spacing: 5) {
                            ProviderBrandIconView(
                                slug: ProviderBrandIconMatcher.match(
                                    providerName: group.provider.name,
                                    address: group.provider.address
                                ),
                                size: 12,
                                fallbackSymbol: "server.rack",
                                fallbackColor: Brand.muted
                            )
                            Text(group.provider.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Brand.muted)
                                .textCase(.uppercase)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                        ForEach(group.models) { model in
                            modelRow(model, provider: group.provider)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(8)
        .frame(width: 300, height: 340)
    }

    private func modelRow(_ model: ModelConfiguration, provider: ProviderConfiguration) -> some View {
        let isHighlighted = highlightedID == model.id
        return Button {
            guard !isDisabled else { return }
            onSelect(model.id)
        } label: {
            HStack(spacing: 8) {
                ProviderBrandIconView(
                    slug: ProviderBrandIconMatcher.match(
                        providerName: provider.name,
                        address: provider.address,
                        modelName: model.displayName,
                        upstreamModelID: model.upstreamModelID
                    ),
                    size: 16,
                    fallbackSymbol: "sparkles",
                    fallbackColor: Brand.muted
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.fg)
                        .lineLimit(1)
                    if model.displayName != model.upstreamModelID {
                        Text(model.upstreamModelID)
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 14)
                    .opacity(model.id == effectiveModelID ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Brand.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? L10n.string("chat.modelChangeDisabledWhileGenerating") : model.displayName)
        .accessibilityLabel(model.displayName)
        .accessibilityAddTraits(model.id == effectiveModelID ? .isSelected : [])
    }

    private func highlightFirst() {
        if let highlightedID, flattenedModels.contains(where: { $0.id == highlightedID }) {
            return
        }
        highlightedID = effectiveModelID ?? flattenedModels.first?.id
    }

    private func moveHighlight(by delta: Int) {
        let models = flattenedModels
        guard !models.isEmpty else { return }
        let currentIndex = models.firstIndex(where: { $0.id == highlightedID }) ?? -1
        let nextIndex = min(max(currentIndex + delta, 0), models.count - 1)
        highlightedID = models[nextIndex].id
    }
}

private struct UseDefaultModelRow: View {
    let modelName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.string("chat.useDefaultModel"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.fg)
                    Text(modelName)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(isHovering ? Brand.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(L10n.string("chat.useDefaultModel"))
    }
}

// MARK: - Attachment picker button

private struct AttachmentPickerButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperclip")
                .font(.system(size: 15))
                .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(isHovering ? Brand.surface : Brand.bg)
                )
                .overlay {
                    Circle().strokeBorder(Brand.border, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(L10n.string("chat.attachmentPicker"))
        .accessibilityLabel(L10n.string("chat.attachmentPicker"))
    }
}

// MARK: - Attachment chips

/// Draft attachment chip in the composer with a remove affordance.
private struct AttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    @State private var isHovering = false

    private var thumbnail: NSImage? {
        if case let .image(data) = attachment.payload {
            return NSImage(data: data)
        }
        return nil
    }

    private var symbolName: String {
        attachment.kind == .code ? "chevron.left.forwardslash.chevron.right" : "doc.text"
    }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 9))
                        .foregroundStyle(Brand.muted)
                        .frame(width: 18, height: 18)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 3))
                }
            }
            Text(attachment.filename)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                    .frame(width: 12, height: 12)
                    .background(
                        Circle().fill(isHovering ? Brand.surface : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.string("chat.removeAttachment"))
            .accessibilityLabel(L10n.string("chat.removeAttachment"))
        }
        .padding(.leading, 5)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.border, lineWidth: 0.5)
        }
        .help(attachmentTooltip)
        .onHover { isHovering = $0 }
        .accessibilityLabel(attachment.filename)
    }

    private var attachmentTooltip: String {
        if attachment.isTruncated {
            return L10n.string("chat.attachmentTruncated", "\(AttachmentLimits.maxExtractedTextPerAttachment)")
        }
        return attachment.filename
    }
}

/// Read-only attachment chip shown inside a sent user message.
private struct MessageAttachmentThumbnail: View {
    let attachment: ChatAttachment

    private var thumbnail: NSImage? {
        if case let .image(data) = attachment.payload {
            return NSImage(data: data)
        }
        return nil
    }

    private var symbolName: String {
        attachment.kind == .code ? "chevron.left.forwardslash.chevron.right" : "doc.text"
    }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 9))
                        .foregroundStyle(Brand.muted)
                        .frame(width: 18, height: 18)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 3))
                }
            }
            Text(attachment.filename)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.fg)
                .lineLimit(1)
        }
        .help(attachment.filename)
        .accessibilityLabel(attachment.filename)
    }
}
