import Observation
import ServiceManagement
import SwiftUI

enum SettingsSection: CaseIterable, Hashable, Identifiable {
    case provider
    case prompts
    case general
    case appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .provider: "服务设置"
        case .prompts: "提示词"
        case .general: "通用"
        case .appearance: "外观"
        }
    }

    var symbol: String {
        switch self {
        case .provider: "network"
        case .prompts: "text.badge.plus"
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .provider: .cyan
        case .prompts: .mint
        case .general: .gray
        case .appearance: .indigo
        }
    }
}

struct SettingsView: View {
    let settings: AppSettings

    @State private var selectedSection: SettingsSection = .provider
    @State private var providerState: ProviderSettingsState

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory
    ) {
        self.settings = settings
        _providerState = State(initialValue: ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: providerFactory
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedSection)
            Divider()
            ScrollView {
                Group {
                    switch selectedSection {
                    case .provider:
                        ProviderSettingsPage(settings: settings, state: providerState)
                    case .prompts:
                        PromptPresetsSettingsPage(settings: settings)
                    case .general:
                        GeneralSettingsPage(settings: settings, providerState: providerState)
                    case .appearance:
                        AppearanceSettingsPage(settings: settings)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 820, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(section.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(section.title)
                            .font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(selection == section ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Label("SpotAsk", systemImage: "sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .padding(.top, 24)
        .frame(width: 190)
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(12)
    }
}

private struct ProviderSettingsPage: View {
    @Bindable var settings: AppSettings
    @Bindable var state: ProviderSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .provider)
            SettingsCallout("连接你的 AI 服务，设置会自动保存。")

            SettingsGroup(title: "连接") {
                SettingsFieldRow(label: settings.useFullEndpoint ? "完整服务地址" : "服务地址") {
                    TextField("https://api.openai.com/v1", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.baseURL) { _, value in state.validateURL(value) }
                }
                SettingsToggleRow(label: "服务地址已包含完整路径", isOn: $settings.useFullEndpoint)
                    .onChange(of: settings.useFullEndpoint) { _, _ in state.validateURL(settings.baseURL) }
                if let endpointError = state.endpointError {
                    Text(endpointError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 148)
                }
                Divider()
                SettingsFieldRow(label: "模型") {
                    TextField("gpt-5-mini", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsToggleRow(label: "实时显示回答", isOn: $settings.streaming)
                SettingsFieldRow(label: "响应等待时间") {
                    Stepper("\(Int(settings.timeout)) 秒", value: $settings.timeout, in: 10...300, step: 10)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(settings.timeout)) 秒")
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroup(title: "访问密钥") {
                SettingsFieldRow(label: "密钥") {
                    SecureField("输入密钥以保存或更新", text: $state.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                Text("访问密钥仅保存在这台 Mac 上。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 148)
                Divider()
                HStack(spacing: 10) {
                    Button("保存密钥") { state.saveKey() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                    Button("测试连接") { state.testConnection() }
                        .disabled(state.isTesting)
                    Button("清除密钥", role: .destructive) { state.clearKey() }
                    Spacer()
                    if state.isTesting { ProgressView().controlSize(.small) }
                    if !state.status.isEmpty {
                        Text(state.status)
                            .font(.caption)
                            .foregroundStyle(state.statusIsError ? .red : .green)
                    }
                }
            }

            SettingsGroup(title: "自定义指令") {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 76)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("自定义指令")
            }
        }
    }
}

private struct PromptPresetsSettingsPage: View {
    @Bindable var settings: AppSettings
    @State private var editorPreset: PromptPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .prompts)
            SettingsCallout("在提问窗口选择提示词，可仅用于下一次提问；也可以设为默认指令。")

            SettingsGroup(title: "常用提示词") {
                ForEach(PromptPreset.builtIn) { preset in
                    PromptPresetRow(preset: preset) {
                        settings.systemPrompt = preset.instruction
                    }
                    if preset.id != PromptPreset.builtIn.last?.id { Divider() }
                }
            }

            SettingsGroup(title: "我的提示词") {
                HStack {
                    Text("新建适合自己常用任务的提示词。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editorPreset = PromptPreset(title: "", instruction: "")
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if settings.customPromptPresets.isEmpty {
                    Text("还没有自定义提示词。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    Divider()
                    ForEach(settings.customPromptPresets) { preset in
                        PromptPresetRow(
                            preset: preset,
                            onSetDefault: { settings.systemPrompt = preset.instruction },
                            onEdit: { editorPreset = preset },
                            onDelete: { settings.deleteCustomPromptPreset(id: preset.id) }
                        )
                        if preset.id != settings.customPromptPresets.last?.id { Divider() }
                    }
                }
            }
        }
        .sheet(item: $editorPreset) { preset in
            PromptPresetEditor(preset: preset) { savedPreset in
                guard settings.saveCustomPromptPreset(savedPreset) else { return }
                editorPreset = nil
            }
        }
    }
}

private struct PromptPresetRow: View {
    let preset: PromptPreset
    let onSetDefault: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(preset.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                Button("设为默认", action: onSetDefault)
                    .buttonStyle(.borderless)
                    .help("设为默认指令")
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("编辑")
                    .accessibilityLabel("编辑\(preset.title)")
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除")
                    .accessibilityLabel("删除\(preset.title)")
                }
            }
        }
    }
}

private struct PromptPresetEditor: View {
    let preset: PromptPreset
    let onSave: (PromptPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var instruction: String

    init(preset: PromptPreset, onSave: @escaping (PromptPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _title = State(initialValue: preset.title)
        _instruction = State(initialValue: preset.instruction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(preset.title.isEmpty ? "新建提示词" : "编辑提示词")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("名称")
                    .font(.headline)
                TextField("例如：改写邮件", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("内容")
                    .font(.headline)
                TextEditor(text: $instruction)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(PromptPreset(id: preset.id, title: title, instruction: instruction))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct GeneralSettingsPage: View {
    let settings: AppSettings
    let providerState: ProviderSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .general)
            SettingsCallout("调整 SpotAsk 的启动、快捷键和对话保留方式。所有更改会立即生效。")

            SettingsGroup(title: "行为") {
                SettingsFieldRow(label: "全局快捷键") {
                    Picker("全局快捷键", selection: Bindable(settings).hotKeyPreset) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.hotKeyPreset) { _, _ in
                        NotificationCenter.default.post(name: .spotAskHotKeyChanged, object: nil)
                    }
                }
                SettingsToggleRow(label: "登录时启动", isOn: Bindable(settings).launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                SettingsToggleRow(label: "恢复最近会话", isOn: Bindable(settings).retainSession)
                SettingsToggleRow(label: "关闭窗口时清空输入框", isOn: Bindable(settings).clearInputOnClose)
                SettingsToggleRow(
                    label: "窗口置顶",
                    isOn: Binding(
                        get: { settings.keepWindowOnTop },
                        set: { _ in SpotAskCommandCenter.shared.toggleWindowOnTop() }
                    )
                )
                SettingsFieldRow(label: "保留的对话条数") {
                    Picker("保留的对话条数", selection: Bindable(settings).contextLimit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("40").tag(40)
                        Text("无限制").tag(0)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroup(title: "本地数据") {
                Text("这会清除访问密钥、设置和已保存的最近会话。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("清除所有本地数据", role: .destructive) {
                    providerState.clearAllLocalData()
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            settings.launchAtLogin = false
        }
    }
}

private struct AppearanceSettingsPage: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .appearance)
            SettingsCallout("选择 SpotAsk 的配色与阅读字号。下次打开提问窗口时生效。")
            SettingsGroup(title: "阅读") {
                SettingsFieldRow(label: "外观") {
                    Picker("外观", selection: Bindable(settings).appearance) {
                        Text("跟随系统").tag(AppearanceMode.system)
                        Text("浅色").tag(AppearanceMode.light)
                        Text("深色").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                }
                SettingsFieldRow(label: "字体大小") {
                    Picker("字体大小", selection: Bindable(settings).fontSize) {
                        Text("小").tag(FontSize.small)
                        Text("标准").tag(FontSize.standard)
                        Text("大").tag(FontSize.large)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

private struct SettingsPageHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(section.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(section.title)
                .font(.system(size: 27, weight: .bold))
        }
    }
}

private struct SettingsCallout: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 13) {
                content
            }
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct SettingsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .frame(width: 134, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
    }
}

@MainActor
@Observable
final class ProviderSettingsState {
    private let settings: AppSettings
    private let keyStore: any APIKeyStoring
    private let providerFactory: any ChatProviderFactory

    var apiKeyDraft = ""
    var status = ""
    var statusIsError = false
    var isTesting = false
    var endpointError: String?

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory
    ) {
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
    }

    func validateURL(_ value: String) {
        do {
            _ = try URLNormalizer.endpoint(from: value, useFullEndpoint: settings.useFullEndpoint)
            endpointError = nil
        } catch {
            endpointError = "请输入有效的服务地址。"
        }
    }

    func saveKey() {
        guard validateConfiguration() else { return }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setStatus("设置已保存", isError: false)
            return
        }

        do {
            try keyStore.saveAPIKey(key)
            apiKeyDraft = ""
            setStatus("访问密钥已保存", isError: false)
        } catch {
            setStatus("无法保存访问密钥", isError: true)
        }
    }

    func clearKey() {
        do {
            try keyStore.deleteAPIKey()
            apiKeyDraft = ""
            setStatus("访问密钥已清除", isError: false)
        } catch {
            setStatus("无法清除访问密钥", isError: true)
        }
    }

    func clearAllLocalData() {
        do {
            try keyStore.deleteAPIKey()
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.spotask.app")
            setStatus("本地数据已清除", isError: false)
        } catch {
            setStatus("无法清除本地数据", isError: true)
        }
    }

    func testConnection() {
        guard validateConfiguration() else { return }
        isTesting = true
        status = ""
        statusIsError = false

        Task {
            do {
                let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    try keyStore.saveAPIKey(key)
                    apiKeyDraft = ""
                }
                let provider = try providerFactory.makeProvider()
                try await provider.testConnection()
                setStatus("模型连接正常", isError: false)
            } catch let error as ChatError {
                setStatus(error.localizedDescription, isError: true)
            } catch {
                setStatus("连接失败", isError: true)
            }
            isTesting = false
        }
    }

    private func validateConfiguration() -> Bool {
        validateURL(settings.baseURL)
        guard endpointError == nil, !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setStatus("请输入模型名称", isError: true)
            }
            return false
        }
        return true
    }

    private func setStatus(_ value: String, isError: Bool) {
        status = value
        statusIsError = isError
    }
}
