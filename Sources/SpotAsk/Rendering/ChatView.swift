import AppKit
import SwiftUI

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

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let keyStore: any APIKeyStoring
    let providerFactory: any ChatProviderFactory
    let onDismiss: () -> Void
    let commandCenter: SpotAskCommandCenter

    @FocusState private var inputFocused: Bool
    @State private var scrollFollowState = ScrollFollowState()
    @State private var didCopyLastAnswer = false
    @State private var inputHeight = ChatInputTextView.minHeight
    @State private var reasoningToggle = ReasoningToggleStateStore()
    @State private var isPresetPopoverPresented = false

    /// Owns the standalone settings window. Created lazily on first use and
    /// reused thereafter so repeated opens never stack duplicate windows.
    @State private var settingsWindowController: SettingsWindowController?

    init(
        viewModel: ChatViewModel,
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        onDismiss: @escaping () -> Void = { NSApp.keyWindow?.orderOut(nil) },
        commandCenter: SpotAskCommandCenter = .shared
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
        self.onDismiss = onDismiss
        self.commandCenter = commandCenter
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            composer
        }
        .frame(minWidth: 364, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: viewModel.isSettingsPresented) { _, isPresented in
            if isPresented {
                presentSettingsWindow()
            }
        }
        .onAppear {
            inputFocused = true
            viewModel.offerSessionChoiceIfNeeded()
            commandCenter.setActionConsumer(handleCommandAction)
            reasoningToggle.reconcile(messages: viewModel.messages)
        }
        .onExitCommand(perform: handleEscape)
        .font(contentFont)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, settings.language.locale)
        .onChange(of: viewModel.messages) { _, messages in
            reasoningToggle.reconcile(messages: messages)
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
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("chat.generating"))
            }
            Spacer()
            // Cmd-L keeps focusing the (always-focused) composer even though
            // the visible header icon was removed. A zero-size, hidden button
            // carries the shortcut so nothing renders and VoiceOver skips it.
            Button(action: { inputFocused = true }) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut("l", modifiers: .command)
            if viewModel.canRegenerate {
                HeaderIconButton(action: { viewModel.regenerate() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.string("chat.regenerate"))
                .accessibilityLabel(L10n.string("chat.regenerate"))
                .keyboardShortcut("r", modifiers: .command)
            }
            if let answer = viewModel.lastAssistantMessage, !answer.content.isEmpty {
                HeaderIconButton(action: { copyLastAnswer(answer.content) }) {
                    Image(systemName: didCopyLastAnswer ? "checkmark" : "doc.on.doc")
                }
                .help(didCopyLastAnswer ? L10n.string("chat.copied") : L10n.string("chat.copyLastAnswer"))
                .accessibilityLabel(didCopyLastAnswer ? L10n.string("chat.copied") : L10n.string("chat.copyLastAnswer"))
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            HeaderIconButton(action: { SpotAskCommandCenter.shared.toggleWindowOnTop() }) {
                Image(systemName: settings.keepWindowOnTop ? "pin.fill" : "pin")
            }
            .help(L10n.string("settings.windowOnTop"))
            .accessibilityLabel(L10n.string("settings.windowOnTop"))
            HeaderIconButton(action: { openSettings() }) {
                Image(systemName: "gearshape")
            }
            .help(L10n.string("settings.title"))
            .accessibilityLabel(L10n.string("settings.title"))
            .keyboardShortcut(",", modifiers: .command)
            HeaderIconButton(action: { newConversation() }) {
                Image(systemName: "square.and.pencil")
            }
            .help(L10n.string("chat.newConversation"))
            .accessibilityLabel(L10n.string("chat.newConversation"))
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    @ViewBuilder
    private var conversation: some View {
        if viewModel.messages.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Brand.muted)
                Text(L10n.string("chat.askAnything"))
                    .font(.system(size: 17, weight: .medium))
                    .kerning(-0.17)
                    .foregroundStyle(Brand.fg)
                Text(L10n.string("chat.selectPrompt"))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                PresetStripView(
                    presets: PromptPreset.builtIn,
                    selection: $viewModel.selectedPromptPreset,
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
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom")
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
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
                    scrollFollowState.positionChanged(isNearBottom: isNearBottom)
                }
                .onScrollPhaseChange { _, newPhase, context in
                    scrollFollowState.positionChanged(isNearBottom: Self.isNearBottom(context.geometry))
                    scrollFollowState.phaseChanged(to: Self.scrollFollowPhase(for: newPhase))
                }
                .onChange(of: viewModel.messages.last?.id) { _, _ in
                    scrollToBottom(using: proxy)
                }
                .onChange(of: viewModel.messages.last?.content) { _, _ in
                    scrollToBottom(using: proxy)
                }
                .onChange(of: viewModel.messages.last?.reasoningContent) { _, _ in
                    scrollToBottom(using: proxy)
                }
                }
            }
        }
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
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .system:
            EmptyView()
        case .user:
            UserMessageContentView(message: message)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                    reasoningSection(message: message, reasoning: reasoning)
                }
                if message.content.isEmpty, message.state == .streaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n.string("chat.generating"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.string("chat.generatingAnswer"))
                } else {
                    MessageContentView(message: message)
                }
                if message.state == .failed {
                    HStack(spacing: 8) {
                        Text(viewModel.error?.localizedDescription ?? L10n.string("chat.requestFailed"))
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button(L10n.string("chat.retry")) { viewModel.retry() }
                            .keyboardShortcut("r", modifiers: .command)
                            .accessibilityLabel(L10n.string("chat.retryFailedRequest"))
                    }
                } else if message.state == .cancelled {
                    Text(L10n.string("chat.stopped"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func reasoningSection(message: ChatMessage, reasoning: String) -> some View {
        let state = reasoningToggle.state(for: message.id)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                reasoningToggle.toggleByUser(messageID: message.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: state.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.medium))
                        .frame(width: 14, height: 14)
                    Text(L10n.string("chat.reasoning"))
                        .font(.caption.weight(.medium))
                    if message.state == .streaming {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(state.isExpanded ? L10n.string("chat.reasoningCollapse") : L10n.string("chat.reasoningExpand"))
            .accessibilityLabel(state.isExpanded ? L10n.string("chat.reasoningCollapse") : L10n.string("chat.reasoningExpand"))
            if state.isExpanded {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 8) {
                if !viewModel.messages.isEmpty {
                    PresetPopoverTrigger(
                        presets: PromptPreset.builtIn,
                        selection: $viewModel.selectedPromptPreset,
                        isPresented: $isPresetPopoverPresented,
                        onSelect: { applyPreset($0) }
                    )
                    .transition(.opacity)
                }
                ChatInputTextView(
                    text: $viewModel.input,
                    isFocused: $inputFocused,
                    height: $inputHeight,
                    onSubmit: viewModel.send,
                    onEscape: handleEscape,
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
                .animation(.easeOut(duration: 0.12), value: inputFocused)
                ComposerSendButton(isGenerating: isGenerating, canSend: viewModel.canSend, action: primaryAction)
            }
            if let preset = viewModel.selectedPromptPreset {
                HStack {
                    Spacer(minLength: 0)
                    SelectedPresetBadge(title: preset.title, icon: PresetIcon.symbol(for: preset.id)) {
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

    private var placeholderText: String {
        guard let preset = viewModel.selectedPromptPreset else {
            return L10n.string("chat.inputPlaceholder")
        }
        return PresetPlaceholder.text(for: preset.id, title: preset.title)
    }

    private var isGenerating: Bool {
        viewModel.generationState == .connecting || viewModel.generationState == .streaming
    }

    private var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var contentFont: Font {
        switch settings.fontSize {
        case .small: .callout
        case .standard: .body
        case .large: .system(size: 16)
        }
    }

    private func primaryAction() {
        if isGenerating { viewModel.cancel() }
        else { viewModel.send() }
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
                onClose: { viewModel.isSettingsPresented = false }
            )
        }
        settingsWindowController?.show()
    }

    /// Applies a preset from the quick-strip or the in-conversation popover.
    /// With a non-empty draft it selects the preset and sends immediately, so
    /// the user skips the send button; with an empty or whitespace-only draft
    /// it only selects the preset, swaps the placeholder, and focuses the
    /// input (Return still sends). "直接提问" passes nil and never sends.
    private func applyPreset(_ preset: PromptPreset?) {
        guard let preset else {
            viewModel.selectedPromptPreset = nil
            inputFocused = true
            return
        }
        viewModel.selectedPromptPreset = preset
        inputFocused = true
        guard !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              viewModel.canSend else { return }
        viewModel.send()
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
        if isPresetPopoverPresented {
            isPresetPopoverPresented = false
        } else if isGenerating {
            viewModel.cancel()
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        if settings.clearInputOnClose { viewModel.input = "" }
        onDismiss()
    }

    private func copyLastAnswer(_ content: String) {
        Clipboard.copy(content)
        didCopyLastAnswer = true
        Task {
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            didCopyLastAnswer = false
        }
    }

    private func handleCommandAction(_ action: SpotAskCommandAction) {
        switch action {
        case .focusInput:
            inputFocused = true
            viewModel.offerSessionChoiceIfNeeded()
        case let .prepare(promptPreset):
            viewModel.selectedPromptPreset = promptPreset
            inputFocused = true
        case .newConversation:
            newConversation()
        case let .ask(question, promptPreset):
            receiveQuestion(question, promptPreset: promptPreset)
        case .showSettings:
            openSettings()
        }
    }

    private func receiveQuestion(_ question: String, promptPreset: PromptPreset?) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputFocused = true
            return
        }
        // An explicit external question intentionally continues a restored
        // session, rather than leaving it blocked behind the interactive choice.
        viewModel.continueSession()
        viewModel.selectedPromptPreset = promptPreset
        // Do not start a second request while the view model is still unwinding
        // a cancelled stream. The supplied question remains ready to send.
        guard !isGenerating else {
            viewModel.input = trimmed
            inputFocused = true
            return
        }
        viewModel.input = trimmed
        viewModel.send()
        inputFocused = true
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard scrollFollowState.followsLatest else { return }
        DispatchQueue.main.async {
            guard scrollFollowState.followsLatest else { return }
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
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

// MARK: - Brand tokens

/// The six SpotAsk brand tokens from the redesign contract. Hover and glow
/// variants are derived with `darker` / `opacity` (the oklch-relative
/// adjustments of the prototype), never with a new hard-coded color.
private enum Brand {
    static let bg = Color(red: 1, green: 1, blue: 1)
    static let surface = Color(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255)
    static let fg = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let muted = Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
    static let border = Color(red: 0xD9 / 255, green: 0xDE / 255, blue: 0xE7 / 255)
    static let accent = Color(red: 0x16 / 255, green: 0x77 / 255, blue: 0xFF / 255)
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

// MARK: - Preset semantic icons

/// SF Symbol per built-in preset, keyed by its stable UUID (the same identity
/// used for the placeholder copy). Falls back to the brand sparkle for any
/// preset without a specific mapping. No third-party icons or assets.
private enum PresetIcon {
    static func symbol(for id: UUID) -> String {
        switch id.uuidString.uppercased() {
        case "EF8CF35C-386A-4389-A137-C207E4DB11FD": return "globe"
        case "1C85A324-65B3-4EBD-B2C4-0C6B072E284A": return "pencil.and.scribble"
        case "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2": return "text.alignleft"
        case "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248": return "lightbulb"
        default: return "sparkles"
        }
    }
}

// MARK: - Brand mark

/// The 18×18 accent square with a white sparkle, paired with the wordmark.
private struct BrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Brand.accent)
            .frame(width: 18, height: 18)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Header icon button

/// The prototype's `.icon-btn`: a 28×28 hit target whose hover fills a
/// `surface` rounded square and darkens the glyph to `fg` (never grays it),
/// with a 2pt accent ring standing in for `:focus-visible`. Wraps the button's
/// label only — action, help, accessibility label, and keyboard shortcut stay
/// on the caller.
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

// MARK: - Empty-state preset strip

/// One-tap preset chips shown only before the first message. Tapping selects
/// the preset, highlights the chip, and hands focus back to the input.
private struct PresetStripView: View {
    let presets: [PromptPreset]
    @Binding var selection: PromptPreset?
    let onSelect: (PromptPreset) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets) { preset in
                ChipView(
                    title: preset.title,
                    icon: PresetIcon.symbol(for: preset.id),
                    isSelected: selection?.id == preset.id
                ) {
                    onSelect(preset)
                }
            }
        }
        .frame(maxWidth: 460)
    }
}

private struct ChipView: View {
    let title: String
    let icon: String
    let isSelected: Bool
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
                selection: selection
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
                    icon: PresetIcon.symbol(for: preset.id),
                    isSelected: selection?.id == preset.id
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

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.string("chat.user"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                if let presetTitle = message.appliedPresetTitle {
                    Label(L10n.string("chat.usedPrompt", presetTitle), systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.string("chat.usedPrompt", presetTitle))
                }
                Spacer()
                Button {
                    Clipboard.copy(message.content)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1_500))
                        guard !Task.isCancelled else { return }
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help(didCopy ? L10n.string("chat.copied") : L10n.string("chat.copyQuestion"))
                .accessibilityLabel(didCopy ? L10n.string("chat.questionCopied") : L10n.string("chat.copyQuestion"))
            }

            Text(message.content)
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("chat.user"))
    }
}
