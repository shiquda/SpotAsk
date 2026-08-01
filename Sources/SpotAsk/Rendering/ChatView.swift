import AppKit
import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let keyStore: any APIKeyStoring
    let providerFactory: any ChatProviderFactory
    let onDismiss: () -> Void
    let commandCenter: SpotAskCommandCenter

    @FocusState private var inputFocused: Bool
    @State private var followsLatest = true
    @State private var didCopyLastAnswer = false
    @State private var inputHeight = ChatInputTextView.minHeight
    @State private var showsNewConversationConfirmation = false
    @State private var reasoningToggle = ReasoningToggleStateStore()

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
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(settings: settings, keyStore: keyStore, providerFactory: providerFactory)
        }
        .alert(L10n.string("chat.newConversationConfirmTitle"), isPresented: $showsNewConversationConfirmation) {
            Button(L10n.string("settings.cancel"), role: .cancel) {}
            Button(L10n.string("chat.newConversation"), role: .destructive) { confirmNewConversation() }
        } message: {
            Text(L10n.string("chat.newConversationConfirmMessage"))
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
            Text("SpotAsk")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("chat.generating"))
            }
            Spacer()
            if viewModel.canRegenerate {
                Button { viewModel.regenerate() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help(L10n.string("chat.regenerate"))
                .accessibilityLabel(L10n.string("chat.regenerate"))
                .keyboardShortcut("r", modifiers: .command)
            }
            if let answer = viewModel.lastAssistantMessage, !answer.content.isEmpty {
                Button { copyLastAnswer(answer.content) } label: {
                    Image(systemName: didCopyLastAnswer ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help(didCopyLastAnswer ? L10n.string("chat.copied") : L10n.string("chat.copyLastAnswer"))
                .accessibilityLabel(didCopyLastAnswer ? L10n.string("chat.copied") : L10n.string("chat.copyLastAnswer"))
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            Button { inputFocused = true } label: {
                Image(systemName: "cursorarrow.rays")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help(L10n.string("chat.focusInput"))
            .accessibilityLabel(L10n.string("chat.focusInput"))
            .keyboardShortcut("l", modifiers: .command)
            Button { SpotAskCommandCenter.shared.toggleWindowOnTop() } label: {
                Image(systemName: settings.keepWindowOnTop ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help(L10n.string("settings.windowOnTop"))
            .accessibilityLabel(L10n.string("settings.windowOnTop"))
            Button { viewModel.isSettingsPresented = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help(L10n.string("settings.title"))
            .accessibilityLabel(L10n.string("settings.title"))
            .keyboardShortcut(",", modifiers: .command)
            Button { newConversation() } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help(L10n.string("chat.newConversation"))
            .accessibilityLabel(L10n.string("chat.newConversation"))
            .keyboardShortcut("n", modifiers: .command)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    @ViewBuilder
    private var conversation: some View {
        if viewModel.messages.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.string("chat.askAnything"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
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
                        ScrollPositionObserver { isNearBottom in
                            followsLatest = isNearBottom
                        }
                        .frame(height: 0)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                            followsLatest = true
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Circle())
                        .padding(14)
                        .accessibilityLabel(L10n.string("chat.goToBottom"))
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
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
        HStack(alignment: .bottom, spacing: 8) {
            PromptPresetPicker(
                presets: settings.promptPresets,
                selection: $viewModel.selectedPromptPreset
            )
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
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if viewModel.input.isEmpty {
                    Text(L10n.string("chat.inputPlaceholder"))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 10)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
            Button(action: primaryAction) {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!isGenerating && !viewModel.canSend)
            .help(isGenerating ? L10n.string("chat.stop") : L10n.string("chat.send"))
            .accessibilityLabel(isGenerating ? L10n.string("chat.stop") : L10n.string("chat.send"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private func newConversation() {
        guard viewModel.messages.isEmpty else {
            showsNewConversationConfirmation = true
            return
        }
        confirmNewConversation()
    }

    private func confirmNewConversation() {
        viewModel.newConversation()
        inputFocused = true
        followsLatest = true
    }

    private func startFreshSession() {
        viewModel.startFreshSession()
        inputFocused = true
        followsLatest = true
    }

    private func handleEscape() {
        if isGenerating { viewModel.cancel() }
        else { dismiss() }
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
            viewModel.isSettingsPresented = true
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
        guard followsLatest else { return }
        DispatchQueue.main.async {
            guard followsLatest else { return }
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }
}

private struct PromptPresetPicker: View {
    let presets: [PromptPreset]
    @Binding var selection: PromptPreset?

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label(L10n.string("chat.directQuestion"), systemImage: "checkmark")
                } else {
                    Text(L10n.string("chat.directQuestion"))
                }
            }

            Divider()

            ForEach(presets) { preset in
                Button {
                    selection = preset
                } label: {
                    if selection?.id == preset.id {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selection == nil ? "wand.and.stars" : "sparkles")
                if let selection {
                    Text(selection.title)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 28, maxWidth: 116)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: selection != nil, vertical: false)
        .help(menuHelp)
        .accessibilityLabel(menuHelp)
    }

    private var menuHelp: String {
        guard let selection else { return L10n.string("chat.selectPrompt") }
        return L10n.string("chat.usePrompt", selection.title)
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
