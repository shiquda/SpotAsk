import AppKit
import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let keyStore: any APIKeyStoring
    let providerFactory: any ChatProviderFactory
    let onDismiss: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var followsLatest = true
    @State private var didCopyLastAnswer = false

    init(
        viewModel: ChatViewModel,
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        onDismiss: @escaping () -> Void = { NSApp.keyWindow?.orderOut(nil) }
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            composer
        }
        .frame(minWidth: 520, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(settings: settings, keyStore: keyStore, providerFactory: providerFactory)
        }
        .onAppear { inputFocused = true }
        .onExitCommand(perform: handleEscape)
        .onReceive(NotificationCenter.default.publisher(for: .spotAskFocusInput)) { _ in
            inputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotAskNewConversation)) { _ in
            newConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotAskAskQuestion)) { notification in
            receiveQuestion(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotAskSelectPromptPreset)) { notification in
            selectPromptPreset(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotAskShowSettings)) { _ in
            viewModel.isSettingsPresented = true
        }
        .font(contentFont)
        .preferredColorScheme(colorScheme)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("SpotAsk")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在生成")
            }
            Spacer()
            if let answer = viewModel.lastAssistantMessage, !answer.content.isEmpty {
                Button { copyLastAnswer(answer.content) } label: {
                    Image(systemName: didCopyLastAnswer ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help(didCopyLastAnswer ? "已复制" : "复制最后一条完整回答")
                .accessibilityLabel(didCopyLastAnswer ? "最后一条完整回答已复制" : "复制最后一条完整回答")
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            Button { inputFocused = true } label: {
                Image(systemName: "cursorarrow.rays")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help("聚焦输入框")
            .accessibilityLabel("聚焦输入框")
            .keyboardShortcut("l", modifiers: .command)
            Button { SpotAskCommandCenter.shared.toggleWindowOnTop() } label: {
                Image(systemName: settings.keepWindowOnTop ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help(settings.keepWindowOnTop ? "取消窗口置顶" : "窗口置顶")
            .accessibilityLabel(settings.keepWindowOnTop ? "取消窗口置顶" : "窗口置顶")
            Button { viewModel.isSettingsPresented = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help("设置")
            .accessibilityLabel("设置")
            .keyboardShortcut(",", modifiers: .command)
            Button { newConversation() } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help("开始新对话")
            .accessibilityLabel("开始新对话")
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
                Text("想问点什么？")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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
                        .accessibilityLabel("回到底部")
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
            }
        }
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
                if message.content.isEmpty, (message.state == .streaming || message.state == .complete) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在生成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("正在生成回答")
                } else {
                    MessageContentView(message: message)
                }
                if message.state == .failed {
                    HStack(spacing: 8) {
                        Text(viewModel.error?.localizedDescription ?? "请求失败")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("重试") { viewModel.retry() }
                            .keyboardShortcut("r", modifiers: .command)
                            .accessibilityLabel("重试最近一次失败请求")
                    }
                } else if message.state == .cancelled {
                    Text("已停止生成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                onSubmit: viewModel.send,
                onEscape: handleEscape
            )
            .frame(height: 52)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if viewModel.input.isEmpty {
                    Text("输入问题…")
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
            .help(isGenerating ? "停止生成" : "发送问题")
            .accessibilityLabel(isGenerating ? "停止生成" : "发送问题")
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
        viewModel.newConversation()
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

    private func receiveQuestion(from notification: Notification) {
        guard let question = notification.userInfo?["question"] as? String else {
            inputFocused = true
            return
        }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputFocused = true
            return
        }
        // Do not start a second request while the view model is still unwinding
        // a cancelled stream. The supplied question remains ready to send.
        guard !isGenerating else {
            viewModel.input = trimmed
            inputFocused = true
            return
        }
        selectPromptPreset(from: notification)
        viewModel.input = trimmed
        viewModel.send()
    }

    private func selectPromptPreset(from notification: Notification) {
        guard let presetID = notification.userInfo?["promptPresetID"] as? String,
              let id = UUID(uuidString: presetID) else { return }
        viewModel.selectedPromptPreset = settings.promptPresets.first { $0.id == id }
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
                    Label("直接提问", systemImage: "checkmark")
                } else {
                    Text("直接提问")
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
        guard let selection else { return "选择提问方式" }
        return "本次使用：\(selection.title)"
    }
}

private struct UserMessageContentView: View {
    let message: ChatMessage

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("你")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
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
                .help(didCopy ? "已复制" : "复制问题")
                .accessibilityLabel(didCopy ? "问题已复制" : "复制问题")
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
        .accessibilityLabel("你的问题")
    }
}
