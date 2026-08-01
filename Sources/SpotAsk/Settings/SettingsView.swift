import Observation
import ServiceManagement
import SwiftUI

enum SettingsSection: CaseIterable, Hashable, Identifiable {
    case provider
    case prompts
    case general
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .provider: L10n.string("settings.provider")
        case .prompts: L10n.string("settings.prompts")
        case .general: L10n.string("settings.general")
        case .appearance: L10n.string("settings.appearance")
        case .about: L10n.string("settings.about")
        }
    }

    var symbol: String {
        switch self {
        case .provider: "network"
        case .prompts: "text.badge.plus"
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .provider: .cyan
        case .prompts: .mint
        case .general: .gray
        case .appearance: .indigo
        case .about: .blue
        }
    }
}

struct SettingsView: View {
    let settings: AppSettings

    @State private var selectedSection: SettingsSection = .provider
    @State private var providerState: ProviderSettingsState
    @State private var updateState = AppUpdateState()

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
                    case .about:
                        AboutSettingsPage(updateState: updateState)
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
            Text(L10n.string("settings.title"))
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
            SettingsCallout(L10n.string("settings.providerDescription"))

            SettingsGroup(title: L10n.string("settings.connection")) {
                SettingsFieldRow(label: settings.useFullEndpoint ? L10n.string("settings.fullEndpoint") : L10n.string("settings.endpoint")) {
                    TextField("https://api.openai.com/v1", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.baseURL) { _, value in state.validateURL(value) }
                }
                SettingsToggleRow(label: L10n.string("settings.endpointIncludesPath"), isOn: $settings.useFullEndpoint)
                    .onChange(of: settings.useFullEndpoint) { _, _ in state.validateURL(settings.baseURL) }
                if let endpointError = state.endpointError {
                    Text(endpointError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 148)
                }
                Divider()
                SettingsFieldRow(label: L10n.string("settings.model")) {
                    TextField("gpt-5-mini", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsToggleRow(label: L10n.string("settings.streaming"), isOn: $settings.streaming)
                SettingsFieldRow(label: L10n.string("settings.responseTimeout")) {
                    Stepper(L10n.string("settings.seconds", Int(settings.timeout)), value: $settings.timeout, in: 10...300, step: 10)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.string("settings.seconds", Int(settings.timeout)))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroup(title: L10n.string("settings.accessKey")) {
                SettingsFieldRow(label: L10n.string("settings.accessKey")) {
                    SecureField(L10n.string("settings.accessKeyPlaceholder"), text: $state.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                Text(L10n.string("settings.accessKeyOnlyOnMac"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 148)
                Divider()
                HStack(spacing: 10) {
                    Button(L10n.string("settings.saveAccessKey")) { state.saveKey() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                    Button(L10n.string("settings.testConnection")) { state.testConnection() }
                        .disabled(state.isTesting)
                    Button(L10n.string("settings.clearAccessKey"), role: .destructive) { state.clearKey() }
                    Spacer()
                    if state.isTesting { ProgressView().controlSize(.small) }
                    if !state.status.isEmpty {
                        Text(state.status)
                            .font(.caption)
                            .foregroundStyle(state.statusIsError ? .red : .green)
                    }
                }
            }

            SettingsGroup(title: L10n.string("settings.customInstruction")) {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 76)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel(L10n.string("settings.customInstruction"))
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
            SettingsCallout(L10n.string("settings.promptsDescription"))

            SettingsGroup(title: L10n.string("settings.savedPrompts")) {
                ForEach(PromptPreset.builtIn) { preset in
                    PromptPresetRow(preset: preset) {
                        settings.systemPrompt = preset.instruction
                    }
                    if preset.id != PromptPreset.builtIn.last?.id { Divider() }
                }
            }

            SettingsGroup(title: L10n.string("settings.customPrompts")) {
                HStack {
                    Text(L10n.string("settings.customPromptsDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editorPreset = PromptPreset(title: "", instruction: "")
                    } label: {
                        Label(L10n.string("settings.new"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if settings.customPromptPresets.isEmpty {
                    Text(L10n.string("settings.customPromptEmpty"))
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
                Button(L10n.string("settings.defaultInstruction"), action: onSetDefault)
                    .buttonStyle(.borderless)
                    .help(L10n.string("settings.defaultInstruction"))
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("settings.edit"))
                    .accessibilityLabel(L10n.string("settings.edit") + " " + preset.title)
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("settings.delete"))
                    .accessibilityLabel(L10n.string("settings.delete") + " " + preset.title)
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
            Text(preset.title.isEmpty ? L10n.string("settings.newPrompt") : L10n.string("settings.editPrompt"))
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.name"))
                    .font(.headline)
                TextField(L10n.string("settings.namePlaceholder"), text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.promptContent"))
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
                Button(L10n.string("settings.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("settings.save")) {
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
            SettingsCallout(L10n.string("settings.generalDescription"))

            SettingsGroup(title: L10n.string("settings.language")) {
                SettingsFieldRow(label: L10n.string("settings.language")) {
                    Picker(L10n.string("settings.language"), selection: Bindable(settings).language) {
                        Text(L10n.string("language.system")).tag(AppLanguage.system)
                        Text(L10n.string("language.simplifiedChinese")).tag(AppLanguage.simplifiedChinese)
                        Text(L10n.string("language.english")).tag(AppLanguage.english)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroup(title: L10n.string("settings.behavior")) {
                SettingsFieldRow(label: L10n.string("settings.globalShortcut")) {
                    Picker(L10n.string("settings.globalShortcut"), selection: Bindable(settings).hotKeyPreset) {
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
                SettingsToggleRow(label: L10n.string("settings.launchAtLogin"), isOn: Bindable(settings).launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                SettingsToggleRow(label: L10n.string("settings.restoreSession"), isOn: Bindable(settings).retainSession)
                SettingsToggleRow(label: L10n.string("settings.clearInputOnClose"), isOn: Bindable(settings).clearInputOnClose)
                SettingsToggleRow(
                    label: L10n.string("settings.windowOnTop"),
                    isOn: Binding(
                        get: { settings.keepWindowOnTop },
                        set: { _ in SpotAskCommandCenter.shared.toggleWindowOnTop() }
                    )
                )
                SettingsFieldRow(label: L10n.string("settings.contextLimit")) {
                    Picker(L10n.string("settings.contextLimit"), selection: Bindable(settings).contextLimit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("40").tag(40)
                        Text(L10n.string("settings.unlimited")).tag(0)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroup(title: L10n.string("settings.localData")) {
                Text(L10n.string("settings.localDataDescription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.string("settings.clearAllLocalData"), role: .destructive) {
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
            SettingsCallout(L10n.string("settings.readingDescription"))
            SettingsGroup(title: L10n.string("settings.reading")) {
                SettingsFieldRow(label: L10n.string("settings.appearance")) {
                    Picker(L10n.string("settings.appearance"), selection: Bindable(settings).appearance) {
                        Text(L10n.string("appearance.system")).tag(AppearanceMode.system)
                        Text(L10n.string("appearance.light")).tag(AppearanceMode.light)
                        Text(L10n.string("appearance.dark")).tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                }
                SettingsFieldRow(label: L10n.string("settings.fontSize")) {
                    Picker(L10n.string("settings.fontSize"), selection: Bindable(settings).fontSize) {
                        Text(L10n.string("font.small")).tag(FontSize.small)
                        Text(L10n.string("font.standard")).tag(FontSize.standard)
                        Text(L10n.string("font.large")).tag(FontSize.large)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

private struct AboutSettingsPage: View {
    let updateState: AppUpdateState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .about)
            SettingsCallout(L10n.string("settings.aboutDescription"))

            SettingsGroup(title: "SpotAsk") {
                SettingsFieldRow(label: L10n.string("settings.version")) {
                    Text(AppVersion.current.description)
                        .textSelection(.enabled)
                }
                Divider()
                SettingsFieldRow(label: L10n.string("settings.source")) {
                    Link(AppUpdateChecker.sourceURL.absoluteString, destination: AppUpdateChecker.sourceURL)
                        .textSelection(.enabled)
                }
            }

            SettingsGroup(title: L10n.string("settings.updates")) {
                HStack(spacing: 10) {
                    Button {
                        updateState.checkForUpdate()
                    } label: {
                        Label(L10n.string("settings.checkForUpdates"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(updateState.isChecking)

                    if case .updateAvailable = updateState.status {
                        Link(destination: AppUpdateChecker.downloadURL) {
                            Label(L10n.string("settings.downloadUpdate"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if updateState.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
        }
    }

    private var statusText: String? {
        switch updateState.status {
        case .idle:
            nil
        case .checking:
            L10n.string("settings.checkingForUpdates")
        case .upToDate:
            L10n.string("settings.upToDate")
        case let .updateAvailable(update):
            L10n.string("settings.updateAvailable", update.version.description)
        case .unavailable:
            L10n.string("settings.updateCheckUnavailable")
        }
    }

    private var statusColor: Color {
        switch updateState.status {
        case .unavailable:
            .red
        default:
            .secondary
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
            endpointError = L10n.string("settings.endpointInvalid")
        }
    }

    func saveKey() {
        guard validateConfiguration() else { return }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setStatus(L10n.string("settings.saveSuccess"), isError: false)
            return
        }

        do {
            try keyStore.saveAPIKey(key)
            apiKeyDraft = ""
            setStatus(L10n.string("settings.saveKeySuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.saveKeyFailure"), isError: true)
        }
    }

    func clearKey() {
        do {
            try keyStore.deleteAPIKey()
            apiKeyDraft = ""
            setStatus(L10n.string("settings.clearKeySuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.clearKeyFailure"), isError: true)
        }
    }

    func clearAllLocalData() {
        do {
            try keyStore.deleteAPIKey()
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.spotask.app")
            setStatus(L10n.string("settings.resetSuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.resetFailure"), isError: true)
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
                setStatus(L10n.string("settings.modelConnectionSuccess"), isError: false)
            } catch let error as ChatError {
                setStatus(error.localizedDescription, isError: true)
            } catch {
                setStatus(L10n.string("settings.testFailure"), isError: true)
            }
            isTesting = false
        }
    }

    private func validateConfiguration() -> Bool {
        validateURL(settings.baseURL)
        guard endpointError == nil, !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setStatus(L10n.string("settings.modelRequired"), isError: true)
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
