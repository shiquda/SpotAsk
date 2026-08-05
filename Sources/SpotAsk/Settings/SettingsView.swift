import AppKit
import Observation
import ServiceManagement
import Foundation
import SwiftUI

enum SettingsSection: CaseIterable, Hashable, Identifiable {
    case provider
    case prompts
    case shortcuts
    case general
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .provider: L10n.string("settings.provider")
        case .prompts: L10n.string("settings.prompts")
        case .shortcuts: L10n.string("settings.shortcuts")
        case .general: L10n.string("settings.general")
        case .appearance: L10n.string("settings.appearance")
        case .about: L10n.string("settings.about")
        }
    }

    var symbol: String {
        switch self {
        case .provider: "network"
        case .prompts: "text.badge.plus"
        case .shortcuts: "command"
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .provider: .cyan
        case .prompts: .mint
        case .shortcuts: .orange
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
        providerFactory: any ChatProviderFactory,
        initialSection: SettingsSection = .provider
    ) {
        self.settings = settings
        _selectedSection = State(initialValue: initialSection)
        _providerState = State(initialValue: ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: providerFactory
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedSection, settings: settings)
            Divider()
            Group {
                switch selectedSection {
                case .provider:
                    ProviderSettingsPage(settings: settings, state: providerState)
                case .prompts:
                    ScrollView {
                        PromptPresetsSettingsPage(settings: settings)
                    }
                case .shortcuts:
                    ScrollView {
                        ShortcutSettingsPage(settings: settings)
                    }
                case .general:
                    ScrollView {
                        GeneralSettingsPage(settings: settings, providerState: providerState)
                    }
                case .appearance:
                    AppearanceSettingsPage(settings: settings)
                case .about:
                    AboutSettingsPage(updateState: updateState, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 860, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    let settings: AppSettings

    var body: some View {
        let _ = settings.language  // observe so sidebar re-renders on language change

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
                    .contentShape(Rectangle())
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

// MARK: - Provider Settings Page

private struct ProviderSettingsPage: View {
    @Bindable var settings: AppSettings
    @Bindable var state: ProviderSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let catalogError = settings.catalogLoadError {
                CatalogErrorBanner(error: catalogError)
            }

            SettingsPageHeader(section: .provider, settings: settings)
            SettingsCallout(L10n.string("settings.providerDescription"))

            ProviderSettingsList(state: state)
        }
        .alert(L10n.string("settings.deleteProviderTitle"), isPresented: Binding(
            get: { state.pendingDeleteProviderID != nil },
            set: { if !$0 { state.pendingDeleteProviderID = nil } }
        )) {
            Button(L10n.string("settings.cancel"), role: .cancel) {
                state.pendingDeleteProviderID = nil
            }
            Button(L10n.string("settings.delete"), role: .destructive) {
                state.confirmDeleteProvider()
            }
        } message: {
            Text(L10n.string("settings.deleteProviderMessage"))
        }
        .alert(L10n.string("settings.deleteModelTitle"), isPresented: Binding(
            get: { state.pendingDeleteModelID != nil },
            set: { if !$0 { state.pendingDeleteModelID = nil } }
        )) {
            Button(L10n.string("settings.cancel"), role: .cancel) {
                state.pendingDeleteModelID = nil
            }
            Button(L10n.string("settings.delete"), role: .destructive) {
                state.confirmDeleteModel()
            }
        } message: {
            Text(L10n.string("settings.deleteModelMessage"))
        }
    }
}

// MARK: - Catalog Error Banner

private struct CatalogErrorBanner: View {
    let error: ProviderModelCatalogLoadError

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("settings.catalogCorruptTitle"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.string("settings.catalogCorruptMessage"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Provider/Model Tree

private struct ProviderModelTree: View {
    @Bindable var state: ProviderSettingsState
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L10n.string("settings.services"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    state.startNewProvider()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.addProvider"))
                .accessibilityLabel(L10n.string("settings.addProvider"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if state.providers.isEmpty {
                Text(L10n.string("settings.noServices"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(state.providers) { provider in
                            ProviderTreeRow(
                                provider: provider,
                                models: state.modelsForProvider(provider.id),
                                isExpanded: state.expandedProviderIDs.contains(provider.id),
                                isSelected: state.selectedProviderID == provider.id && state.selectedModelID == nil,
                                activeModelID: state.activeModelID,
                                selectedModelID: state.selectedModelID,
                                onSelectProvider: { state.selectProvider(provider.id) },
                                onToggleExpand: { state.toggleProviderExpansion(provider.id) },
                                onSelectModel: { state.selectModel($0) },
                                onUseForChat: { state.useModelForChat($0) },
                                onDeleteModel: { state.requestDeleteModel($0) },
                                onAddModel: { state.startNewModel(for: provider.id) },
                                onDeleteProvider: { state.requestDeleteProvider(provider.id) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ProviderTreeRow: View {
    let provider: ProviderConfiguration
    let models: [ModelConfiguration]
    let isExpanded: Bool
    let isSelected: Bool
    let activeModelID: UUID?
    let selectedModelID: UUID?
    let onSelectProvider: () -> Void
    let onToggleExpand: () -> Void
    let onSelectModel: (UUID) -> Void
    let onUseForChat: (UUID) -> Void
    let onDeleteModel: (UUID) -> Void
    let onAddModel: () -> Void
    let onDeleteProvider: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider header row
            HStack(spacing: 4) {
                Button {
                    onToggleExpand()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(isExpanded
                    ? L10n.string("settings.collapseProvider", provider.name)
                    : L10n.string("settings.expandProvider", provider.name))
                .accessibilityLabel(isExpanded
                    ? L10n.string("settings.collapseProvider", provider.name)
                    : L10n.string("settings.expandProvider", provider.name))

                Button {
                    onSelectProvider()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(provider.name)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        onAddModel()
                    } label: {
                        Label(L10n.string("settings.addModel"), systemImage: "plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeleteProvider()
                    } label: {
                        Label(L10n.string("settings.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18, height: 18)
                .help(L10n.string("settings.providerActions", provider.name))
                .accessibilityLabel(L10n.string("settings.providerActions", provider.name))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.primary.opacity(0.08) : .clear)

            // Model rows (when expanded)
            if isExpanded {
                ForEach(models) { model in
                    HStack(spacing: 4) {
                        Spacer().frame(width: 16) // indent
                        Button {
                            onSelectModel(model.id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .frame(width: 4, height: 4)
                                    .foregroundStyle(model.id == activeModelID ? Color.cyan : .secondary.opacity(0.4))
                                Text(model.displayName)
                                    .font(.system(size: 12.5, weight: selectedModelID == model.id ? .semibold : .regular))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if model.source == .discovered {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .help(L10n.string("settings.discoveredModel"))
                                        .accessibilityLabel(L10n.string("settings.discoveredModel"))
                                }
                                if model.id == activeModelID {
                                    Text(L10n.string("settings.active"))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.cyan)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            if model.id != activeModelID {
                                Button {
                                    onUseForChat(model.id)
                                } label: {
                                    Label(L10n.string("settings.useForChat"), systemImage: "bubble.left.and.bubble.right")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                onDeleteModel(model.id)
                            } label: {
                                Label(L10n.string("settings.delete"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 16, height: 16)
                        .help(L10n.string("settings.modelActions", model.displayName))
                        .accessibilityLabel(L10n.string("settings.modelActions", model.displayName))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedModelID == model.id ? Color.primary.opacity(0.08) : .clear)
                }

                // "Add Model" row
                Button {
                    onAddModel()
                } label: {
                    HStack(spacing: 6) {
                        Spacer().frame(width: 16)
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text(L10n.string("settings.addModel"))
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Provider/Model Detail Panel

private struct ProviderModelDetail: View {
    @Bindable var state: ProviderSettingsState
    let settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if state.isCreatingProvider {
                    ProviderDetailForm(state: state, isNew: true)
                } else if state.selectedProviderID != nil, state.selectedModelID == nil {
                    ProviderDetailForm(state: state, isNew: false)
                } else if state.isCreatingModel {
                    ModelDetailForm(state: state, isNew: true)
                } else if state.selectedModelID != nil {
                    ModelDetailForm(state: state, isNew: false)
                } else {
                    EmptySelectionView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

private struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(L10n.string("settings.selectProviderOrModel"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Provider Detail Form

private struct ProviderDetailForm: View {
    @Bindable var state: ProviderSettingsState
    let isNew: Bool
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
                HStack {
                    Text(isNew ? L10n.string("settings.newProvider") : L10n.string("settings.editProvider"))
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    if !isNew {
                        Button(role: .destructive) {
                            if let id = state.selectedProviderID {
                                state.requestDeleteProvider(id)
                            }
                        } label: {
                            Label(L10n.string("settings.delete"), systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            SettingsGroup(title: L10n.string("settings.providerInfo")) {
                SettingsFieldRow(label: L10n.string("settings.providerName")) {
                    TextField(L10n.string("settings.providerNamePlaceholder"), text: $state.draftProviderName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: state.draftProviderName) { _, _ in state.clearStatus() }
                }
                SettingsFieldRow(label: L10n.string("settings.serviceAddress")) {
                    TextField("https://api.example.com/v1", text: $state.draftProviderAddress)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: state.draftProviderAddress) { _, value in state.validateProviderURL(value) }
                }
                if let error = state.providerFieldError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                SettingsFieldRow(label: L10n.string("settings.addressMode")) {
                    Picker(L10n.string("settings.addressMode"), selection: $state.draftProviderAddressMode) {
                        Text(L10n.string("settings.addressModeBaseURL")).tag(ProviderAddressMode.baseURL)
                        Text(L10n.string("settings.addressModeFullEndpoint")).tag(ProviderAddressMode.fullEndpoint)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: state.draftProviderAddressMode) { _, _ in
                        state.validateProviderURL(state.draftProviderAddress)
                    }
                }
                SettingsFieldRow(label: L10n.string("settings.responseTimeout")) {
                    HStack(spacing: 8) {
                        Stepper(L10n.string("settings.seconds", Int(state.draftProviderTimeout)), value: $state.draftProviderTimeout, in: 10...300, step: 10)
                            .labelsHidden()
                        Text(L10n.string("settings.seconds", Int(state.draftProviderTimeout)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !isNew, state.selectedProviderSupportsModelRefresh {
                SettingsGroup(title: L10n.string("settings.availableModels")) {
                    Text(L10n.string("settings.modelRefreshDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            state.refreshModels()
                        } label: {
                            Label(L10n.string("settings.refreshModels"), systemImage: "arrow.clockwise")
                        }
                        .disabled(!state.canRefreshModels || state.isRefreshingModels)

                        if state.isRefreshingModels {
                            ProgressView().controlSize(.small)
                            Button(L10n.string("settings.stopRefresh")) {
                                state.cancelModelRefresh()
                            }
                        }
                        if let status = state.modelRefreshStatusText {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(state.modelRefreshStatusIsError ? .red : .green)
                        }
                    }
                }
            }

            if !isNew {
                SettingsGroup(title: L10n.string("settings.accessKey")) {
                    SettingsFieldRow(label: L10n.string("settings.accessKey")) {
                        SecureField(L10n.string("settings.accessKeyPlaceholder"), text: $state.apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                    }
                    Text(L10n.string("settings.accessKeyOnlyOnMac"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Button(L10n.string("settings.saveAccessKey")) { state.saveKey() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut("s")
                            Button(L10n.string("settings.testConnection")) { state.testConnection() }
                                .disabled(state.isTesting || !state.canTestConnection)
                            Button(L10n.string("settings.clearAccessKey"), role: .destructive) { state.clearKey() }
                            Spacer()
                            if state.isTesting { ProgressView().controlSize(.small) }
                            if !state.status.isEmpty {
                                Text(state.status)
                                    .font(.caption)
                                    .foregroundStyle(state.statusIsError ? .red : .green)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Button(L10n.string("settings.saveAccessKey")) { state.saveKey() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut("s")
                            Button(L10n.string("settings.testConnection")) { state.testConnection() }
                                .disabled(state.isTesting || !state.canTestConnection)
                            Button(L10n.string("settings.clearAccessKey"), role: .destructive) { state.clearKey() }
                            if state.isTesting { ProgressView().controlSize(.small) }
                            if !state.status.isEmpty {
                                Text(state.status)
                                    .font(.caption)
                                    .foregroundStyle(state.statusIsError ? .red : .green)
                            }
                        }
                    }
                }
            }

            // Save / Cancel buttons
            HStack {
                Spacer()
                if isNew {
                    Button(L10n.string("settings.cancel")) {
                        state.cancelEditing()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(isNew ? L10n.string("settings.create") : L10n.string("settings.save")) {
                    state.saveProvider()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canSaveProvider)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Model Detail Form

private struct ModelDetailForm: View {
    @Bindable var state: ProviderSettingsState
    let isNew: Bool
    var showsHeader = true

    private var parentProviderName: String {
        guard let catalog = state.settings.providerRegistry.catalog,
              let pid = state.newModelParentProviderID ?? state.selectedModel?.providerID,
              let provider = catalog.providers.first(where: { $0.id == pid }) else {
            return ""
        }
        return provider.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
                HStack {
                    Text(isNew ? L10n.string("settings.newModel") : L10n.string("settings.editModel"))
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    if !isNew {
                        Button(role: .destructive) {
                            if let id = state.selectedModelID {
                                state.requestDeleteModel(id)
                            }
                        } label: {
                            Label(L10n.string("settings.delete"), systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            SettingsGroup(title: L10n.string("settings.modelInfo")) {
                SettingsFieldRow(label: L10n.string("settings.displayName")) {
                    TextField(L10n.string("settings.displayNamePlaceholder"), text: $state.draftModelDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: state.draftModelDisplayName) { _, _ in state.clearStatus() }
                }
                SettingsFieldRow(label: L10n.string("settings.upstreamModelID")) {
                    TextField("gpt-5-mini", text: $state.draftModelUpstreamID)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: state.draftModelUpstreamID) { _, _ in state.clearStatus() }
                }
                SettingsFieldRow(label: L10n.string("settings.service")) {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(parentProviderName)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                if state.selectedModel?.source == .discovered {
                    Text(L10n.string("settings.discoveredModelHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsToggleRow(label: L10n.string("settings.streaming"), isOn: $state.draftModelStreaming)
            }

            // Show active indicator or "Use for Chat" button
            if let activeID = state.activeModelID {
                if activeID == state.selectedModelID {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.cyan)
                            .font(.system(size: 12))
                        Text(L10n.string("settings.currentlyActiveModel"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else if !isNew, let modelID = state.selectedModelID {
                    HStack {
                        Button {
                            state.useModelForChat(modelID)
                        } label: {
                            Label(L10n.string("settings.useForChat"), systemImage: "bubble.left.and.bubble.right")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(L10n.string("settings.useForChat"))
                        if !state.status.isEmpty {
                            Text(state.status)
                                .font(.caption)
                                .foregroundStyle(state.statusIsError ? .red : .secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                if isNew {
                    Button(L10n.string("settings.cancel")) {
                        state.cancelEditing()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(isNew ? L10n.string("settings.create") : L10n.string("settings.save")) {
                    state.saveModel()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canSaveModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Provider Settings List

private struct ProviderSettingsList: View {
    @Bindable var state: ProviderSettingsState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if state.isCreatingProvider {
                    NewProviderCard(state: state)
                }

                if state.providers.isEmpty, !state.isCreatingProvider {
                    Text(L10n.string("settings.noServices"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else {
                    ForEach(state.providers) { provider in
                        ProviderCard(
                            state: state,
                            provider: provider,
                            models: state.modelsForProvider(provider.id)
                        )
                    }
                }

                Button {
                    state.startNewProvider()
                } label: {
                    Label(L10n.string("settings.addProvider"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }
}

private struct NewProviderCard: View {
    @Bindable var state: ProviderSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L10n.string("settings.newProvider"), systemImage: "server.rack")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ProviderDetailForm(state: state, isNew: true, showsHeader: false)
                .padding(16)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct ProviderCard: View {
    @Bindable var state: ProviderSettingsState
    let provider: ProviderConfiguration
    let models: [ModelConfiguration]

    private var isEditingProvider: Bool {
        state.selectedProviderID == provider.id
    }

    private var isEditingModel: Bool {
        if state.isCreatingModel, state.newModelParentProviderID == provider.id { return true }
        if let model = state.selectedModel, model.providerID == provider.id { return true }
        return false
    }

    private var isExpanded: Bool {
        state.expandedProviderIDs.contains(provider.id) || isEditingProvider || isEditingModel
    }

    private var activeModel: ModelConfiguration? {
        models.first { $0.id == state.activeModelID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    if isEditingProvider {
                        ProviderDetailForm(state: state, isNew: false, showsHeader: false)
                    }

                    modelsSection

                    if isEditingModel {
                        ModelDetailForm(state: state, isNew: state.isCreatingModel, showsHeader: false)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("settings.model"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(models) { model in
                ProviderModelRow(state: state, model: model)
            }

            Button {
                state.startNewModel(for: provider.id)
            } label: {
                Label(L10n.string("settings.addModel"), systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                if isEditingProvider || isEditingModel {
                    state.cancelEditing()
                }
                state.toggleProviderExpansion(provider.id)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isExpanded
                ? L10n.string("settings.collapseProvider", provider.name)
                : L10n.string("settings.expandProvider", provider.name))
            .accessibilityLabel(isExpanded
                ? L10n.string("settings.collapseProvider", provider.name)
                : L10n.string("settings.expandProvider", provider.name))

            Button {
                state.selectProvider(provider.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            if activeModel != nil {
                                Text(L10n.string("settings.active"))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }

                        Text(provider.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    state.selectProvider(provider.id)
                } label: {
                    Label(L10n.string("settings.editProvider"), systemImage: "pencil")
                }
                Button {
                    state.startNewModel(for: provider.id)
                } label: {
                    Label(L10n.string("settings.addModel"), systemImage: "plus")
                }
                Divider()
                Button(role: .destructive) {
                    state.requestDeleteProvider(provider.id)
                } label: {
                    Label(L10n.string("settings.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help(L10n.string("settings.providerActions", provider.name))
            .accessibilityLabel(L10n.string("settings.providerActions", provider.name))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isExpanded ? Color.primary.opacity(0.06) : .clear)
    }
}

private struct ProviderModelRow: View {
    @Bindable var state: ProviderSettingsState
    let model: ModelConfiguration

    private var isActive: Bool {
        state.activeModelID == model.id
    }

    private var isEditing: Bool {
        state.selectedModelID == model.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                state.selectModel(model.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? Color.cyan : .secondary.opacity(0.5))

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(model.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if model.source == .discovered {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .help(L10n.string("settings.discoveredModel"))
                                    .accessibilityLabel(L10n.string("settings.discoveredModel"))
                            }
                        }

                        Text(model.upstreamModelID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if isActive {
                        Text(L10n.string("settings.active"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isActive {
                Button {
                    state.useModelForChat(model.id)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.useForChat"))
                .accessibilityLabel(L10n.string("settings.useForChat") + " " + model.displayName)
            }

            Menu {
                Button {
                    state.selectModel(model.id)
                } label: {
                    Label(L10n.string("settings.editModel"), systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    state.requestDeleteModel(model.id)
                } label: {
                    Label(L10n.string("settings.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help(L10n.string("settings.modelActions", model.displayName))
            .accessibilityLabel(L10n.string("settings.modelActions", model.displayName))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isEditing ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Prompt Presets Settings

private struct PromptPresetsSettingsPage: View {
    @Bindable var settings: AppSettings
    @State private var editorPreset: PromptPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .prompts, settings: settings)
            SettingsCallout(L10n.string("settings.promptsDescription"))

            SettingsGroup(title: L10n.string("settings.savedPrompts")) {
                HStack {
                    Text(L10n.string("settings.promptCatalogDescription"))
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

                VStack(spacing: 6) {
                    ForEach(Array(settings.promptPresets.enumerated()), id: \.element.id) { index, preset in
                        promptPresetCard {
                            PromptPresetRow(
                                preset: preset,
                                settings: settings,
                                position: index + 1,
                                totalCount: settings.promptPresets.count,
                                onMoveUp: index > 0 ? { movePromptPreset(id: preset.id, by: -1) } : nil,
                                onMoveDown: index + 1 < settings.promptPresets.count ? { movePromptPreset(id: preset.id, by: 1) } : nil,
                                onEdit: preset.isBuiltIn ? nil : { editorPreset = preset },
                                onDelete: preset.isBuiltIn ? nil : { settings.deleteCustomPromptPreset(id: preset.id) }
                            )
                        }
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
        .sheet(item: $editorPreset) { preset in
            PromptPresetEditor(preset: preset) { savedPreset in
                guard settings.saveCustomPromptPreset(savedPreset) else { return }
                editorPreset = nil
            }
        }
    }

    private func promptPresetCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func movePromptPreset(id: UUID, by offset: Int) {
        settings.movePromptPreset(id: id, by: offset)
    }
}

@MainActor
private struct PromptPresetRow: View {
    let preset: PromptPreset
    @Bindable var settings: AppSettings
    let position: Int
    let totalCount: Int
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            PromptPresetReorderControls(
                title: preset.title,
                position: position,
                totalCount: totalCount,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
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
            HStack(spacing: 6) {
                if let onEdit, let onDelete {
                    Menu {
                        Button(action: onEdit) {
                            Label(L10n.string("settings.edit"), systemImage: "pencil")
                        }
                        Button(role: .destructive, action: onDelete) {
                            Label(L10n.string("settings.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .help(L10n.string("settings.edit") + " / " + L10n.string("settings.delete"))
                    .accessibilityLabel(L10n.string("settings.edit") + " / " + L10n.string("settings.delete") + " " + preset.title)
                } else {
                    Color.clear
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
                Toggle(
                    "",
                    isOn: Binding(
                        get: { preset.isEnabled },
                        set: { settings.setPromptPresetEnabled(id: preset.id, isEnabled: $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(L10n.string("settings.promptEnabled") + " " + preset.title)
            }
        }
    }
}

private struct PromptPresetReorderControls: View {
    let title: String
    let position: Int
    let totalCount: Int
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            reorderButton(
                systemImage: "chevron.up",
                title: L10n.string("settings.moveUp"),
                action: onMoveUp
            )
            reorderButton(
                systemImage: "chevron.down",
                title: L10n.string("settings.moveDown"),
                action: onMoveDown
            )
        }
        .frame(width: 46)
    }

    private func reorderButton(
        systemImage: String,
        title: String,
        action: (() -> Void)?
    ) -> some View {
        Button(action: { action?() }) {
            Image(systemName: systemImage)
                .frame(width: 20, height: 24)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(action == nil)
        .help(title + " " + self.title)
        .accessibilityLabel(title + " " + self.title)
        .accessibilityHint(L10n.string("settings.promptPosition", position, totalCount))
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

// MARK: - In-app Shortcuts Settings

private struct ShortcutSettingsPage: View {
    @Bindable var settings: AppSettings
    @State private var feedback: String?

    private let operations = InAppShortcutOperation.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(section: .shortcuts, settings: settings)
            Text(L10n.string("settings.shortcutsDescription"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            SettingsGroup(title: L10n.string("settings.shortcutActions")) {
                ForEach(operations) { operation in
                    ShortcutSettingsRow(
                        title: operation.title,
                        target: .operation(operation),
                        settings: settings,
                        feedback: $feedback
                    )
                    if operation != operations.last { Divider() }
                }
            }

            SettingsGroup(title: L10n.string("settings.shortcutPrompts")) {
                ForEach(settings.enabledPromptPresets) { preset in
                    ShortcutSettingsRow(
                        title: preset.title,
                        target: .promptPreset(preset.id),
                        settings: settings,
                        feedback: $feedback
                    )
                    if preset.id != settings.enabledPromptPresets.last?.id { Divider() }
                }
            }

            HStack {
                Spacer()
                Button {
                    settings.resetAllShortcuts()
                    feedback = L10n.string("settings.shortcutsRestored")
                } label: {
                    Label(L10n.string("settings.resetAllShortcuts"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct ShortcutSettingsRow: View {
    let title: String
    let target: InAppShortcutTarget
    @Bindable var settings: AppSettings
    @Binding var feedback: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorder(
                shortcut: settings.shortcut(for: target),
                onRecord: assign,
                onInvalid: { feedback = L10n.string("settings.shortcutInvalid") }
            )
            .frame(width: 176, height: 28)
            .accessibilityLabel(title)

            Button {
                guard settings.removeShortcut(for: target) == nil else { return }
                feedback = L10n.string("settings.shortcutCleared")
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(settings.shortcut(for: target) == nil)
            .help(L10n.string("settings.clearShortcut"))
            .accessibilityLabel(L10n.string("settings.clearShortcut") + " " + title)

            Button {
                guard settings.resetShortcut(for: target) == nil else { return }
                feedback = L10n.string("settings.shortcutRestored")
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("settings.resetShortcut"))
            .accessibilityLabel(L10n.string("settings.resetShortcut") + " " + title)
        }
    }

    private func assign(_ shortcut: InAppShortcut) {
        switch settings.assignShortcut(shortcut, to: target) {
        case nil:
            feedback = L10n.string("settings.shortcutSaved")
        case .unsupportedShortcut:
            feedback = L10n.string("settings.shortcutInvalid")
        case let .duplicateShortcut(existingTarget):
            feedback = L10n.string("settings.shortcutDuplicate", targetTitle(existingTarget))
        case .unavailableTarget:
            feedback = L10n.string("settings.shortcutUnavailable")
        }
    }

    private func targetTitle(_ target: InAppShortcutTarget) -> String {
        switch target {
        case let .operation(operation):
            operation.title
        case let .promptPreset(id):
            settings.promptPresets.first(where: { $0.id == id })?.title ?? L10n.string("settings.shortcuts")
        }
    }
}

private extension InAppShortcutOperation {
    var title: String {
        switch self {
        case .focusInput: L10n.string("shortcut.focusInput")
        case .regenerateOrRetry: L10n.string("shortcut.regenerateOrRetry")
        case .copyAnswer: L10n.string("shortcut.copyAnswer")
        case .toggleWindowOnTop: L10n.string("shortcut.toggleWindowOnTop")
        case .showSettings: L10n.string("shortcut.showSettings")
        case .newConversation: L10n.string("shortcut.newConversation")
        case .sendOrCancel: L10n.string("shortcut.sendOrCancel")
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: InAppShortcut?
    let onRecord: (InAppShortcut) -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.setAccessibilityRole(.textField)
        field.onRecord = onRecord
        field.onInvalid = onInvalid
        return field
    }

    func updateNSView(_ field: ShortcutRecorderField, context: Context) {
        field.stringValue = InAppShortcutDisplay.text(for: shortcut)
        field.onRecord = onRecord
        field.onInvalid = onInvalid
    }
}

private final class ShortcutRecorderField: NSTextField {
    var onRecord: ((InAppShortcut) -> Void)?
    var onInvalid: (() -> Void)?
    private var monitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        alignment = .center
        font = .systemFont(ofSize: 12, weight: .medium)
        focusRingType = .default
        lineBreakMode = .byTruncatingMiddle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            removeMonitor()
            removeWindowObservers()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        removeWindowObservers()
        guard let window else { return }
        windowObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.installMonitorIfNeeded()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeMonitor()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeMonitor()
                }
            }
        ]
        installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil, window?.isKeyWindow == true else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  ShortcutRecorderCaptureEligibility.shouldCapture(
                      isRecorderWindowKey: self.window?.isKeyWindow == true,
                      isActiveWindowRecorderWindow: NSApp.keyWindow === self.window,
                      isRecorderFirstResponder: self.window?.firstResponder === self
                  ) else { return event }
            self.keyDown(with: event)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        guard let shortcut = shortcut(from: event) else {
            onInvalid?()
            NSSound.beep()
            return
        }
        onRecord?(shortcut)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }

    private func shortcut(from event: NSEvent) -> InAppShortcut? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var shortcutModifiers: InAppShortcutModifiers = []
        if modifiers.contains(.command) { shortcutModifiers.insert(.command) }
        if modifiers.contains(.shift) { shortcutModifiers.insert(.shift) }
        if modifiers.contains(.option) { shortcutModifiers.insert(.option) }
        if modifiers.contains(.control) { shortcutModifiers.insert(.control) }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let shortcut = InAppShortcut(key: key, modifiers: shortcutModifiers)
        return shortcut.isSupported ? shortcut : nil
    }
}

enum ShortcutRecorderCaptureEligibility {
    static func shouldCapture(
        isRecorderWindowKey: Bool,
        isActiveWindowRecorderWindow: Bool,
        isRecorderFirstResponder: Bool
    ) -> Bool {
        isRecorderWindowKey && isActiveWindowRecorderWindow && isRecorderFirstResponder
    }
}

// MARK: - General Settings Page

private struct GeneralSettingsPage: View {
    let settings: AppSettings
    let providerState: ProviderSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .general, settings: settings)
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
                SettingsToggleRow(label: L10n.string("settings.showMenuBarIcon"), isOn: Bindable(settings).showsMenuBarIcon)
                SettingsToggleRow(label: L10n.string("settings.restoreSession"), isOn: Bindable(settings).retainSession)
                SettingsToggleRow(label: L10n.string("settings.clearInputOnClose"), isOn: Bindable(settings).clearInputOnClose)
                SettingsToggleRow(label: L10n.string("settings.confirmBeforeStartingNewConversation"), isOn: Bindable(settings).confirmBeforeStartingNewConversation)
                SettingsToggleRow(label: L10n.string("settings.escapeStartsNewConversation"), isOn: Bindable(settings).escapeStartsNewConversation)
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

// MARK: - Appearance Settings Page

private struct AppearanceSettingsPage: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .appearance, settings: settings)
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

// MARK: - About Settings Page

private struct AboutSettingsPage: View {
    let updateState: AppUpdateState
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .about, settings: settings)
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

// MARK: - Reusable Settings Components

private struct SettingsPageHeader: View {
    let section: SettingsSection
    let settings: AppSettings

    var body: some View {
        let _ = settings.language  // observe so header re-renders on language change

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label/control row that lays out horizontally when the panel is wide enough
/// for the fixed 134pt label column, and stacks the label above the control when
/// it is not. The horizontal candidate demands at least 400pt so every row in a
/// given column makes the same choice, keeping the Service editor visually uniform.
private struct SettingsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    private var wideForm: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .frame(width: 134, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stackedForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideForm
                .frame(minWidth: 400)
            stackedForm
        }
    }
}

private struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    private var toggle: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(label)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                Text(label)
                    .frame(width: 134, alignment: .leading)
                toggle
            }
            .frame(minWidth: 400)

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                toggle
            }
        }
    }
}

// MARK: - Provider Settings State

@MainActor
@Observable
final class ProviderSettingsState {
    let settings: AppSettings
    private let keyStore: any APIKeyStoring
    private let providerFactory: any ChatProviderFactory
    private let modelDiscovery: any ProviderModelDiscovering
    private var modelRefreshTask: Task<Void, Never>?
    private var modelRefreshGeneration = 0

    // MARK: Selection state

    var selectedProviderID: UUID?
    var selectedModelID: UUID?
    var expandedProviderIDs: Set<UUID> = []
    /// Observable mirror of the registry's selectedModelID so the tree
    /// and detail re-render when the active model changes.
    var activeModelID: UUID?

    // MARK: Provider draft

    var draftProviderName = ""
    var draftProviderAddress = ""
    var draftProviderAddressMode: ProviderAddressMode = .baseURL
    var draftProviderTimeout: Double = 60

    // MARK: Model draft

    var draftModelDisplayName = ""
    var draftModelUpstreamID = ""
    var draftModelStreaming = true

    // MARK: Create/edit mode

    var isCreatingProvider = false
    var isCreatingModel = false
    var newModelParentProviderID: UUID?

    // MARK: Access key

    var apiKeyDraft = ""

    // MARK: Status

    var status = ""
    var statusIsError = false
    var isTesting = false
    var providerFieldError: String?
    var modelRefreshStatus: ModelRefreshStatus = .idle

    // MARK: Delete confirmation

    var pendingDeleteProviderID: UUID?
    var pendingDeleteModelID: UUID?

    // MARK: Computed properties

    var providers: [ProviderConfiguration] {
        settings.providerRegistry.catalog?.providers ?? []
    }

    var selectedModel: ModelConfiguration? {
        guard let id = selectedModelID,
              let catalog = settings.providerRegistry.catalog else { return nil }
        return catalog.models.first(where: { $0.id == id })
    }

    func modelsForProvider(_ providerID: UUID) -> [ModelConfiguration] {
        settings.providerRegistry.catalog?.models.filter { $0.providerID == providerID } ?? []
    }

    var canSaveProvider: Bool {
        let name = draftProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !address.isEmpty && providerFieldError == nil
    }

    var canSaveModel: Bool {
        let displayName = draftModelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamID = draftModelUpstreamID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !displayName.isEmpty && !upstreamID.isEmpty
    }

    var canTestConnection: Bool {
        guard let pid = selectedProviderID,
              let catalog = settings.providerRegistry.catalog,
              catalog.models.contains(where: { $0.providerID == pid }) else { return false }
        let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return !address.isEmpty
            && providerFieldError == nil
            && (try? URLNormalizer.endpoint(from: address, useFullEndpoint: draftProviderAddressMode.usesFullEndpoint)) != nil
    }

    var selectedProviderSupportsModelRefresh: Bool {
        guard let providerID = selectedProviderID,
              let provider = settings.providerRegistry.catalog?.providers.first(where: { $0.id == providerID }) else {
            return false
        }
        return provider.addressMode == .baseURL
    }

    var canRefreshModels: Bool {
        selectedProviderSupportsModelRefresh && !isRefreshingModels
    }

    var isRefreshingModels: Bool {
        if case .loading = modelRefreshStatus { return true }
        return false
    }

    var modelRefreshStatusText: String? {
        switch modelRefreshStatus {
        case .idle, .loading: return nil
        case let .success(count): return L10n.string("settings.modelRefreshSuccess", count)
        case .missingAccessKey: return L10n.string("settings.modelRefreshNeedsKey")
        case .cancelled: return L10n.string("settings.modelRefreshCancelled")
        case .failed: return L10n.string("settings.modelRefreshFailed")
        case .unavailable: return L10n.string("settings.modelRefreshUnavailable")
        }
    }

    var modelRefreshStatusIsError: Bool {
        switch modelRefreshStatus {
        case .missingAccessKey, .failed: true
        case .idle, .loading, .success, .cancelled, .unavailable: false
        }
    }

    // MARK: Init

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        modelDiscovery: any ProviderModelDiscovering = OpenAICompatibleModelDiscovery()
    ) {
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
        self.modelDiscovery = modelDiscovery
        self.activeModelID = settings.providerRegistry.catalog?.selectedModelID

        // Auto-select first provider on init
        if let firstProvider = settings.providerRegistry.catalog?.providers.first {
            selectProvider(firstProvider.id)
        }
    }

    // MARK: Selection

    func selectProvider(_ id: UUID) {
        guard let catalog = settings.providerRegistry.catalog,
              let provider = catalog.providers.first(where: { $0.id == id }) else { return }

        invalidateModelRefresh()
        cancelEditing()
        selectedProviderID = id
        selectedModelID = nil
        expandedProviderIDs.insert(id)

        draftProviderName = provider.name
        draftProviderAddress = provider.address
        draftProviderAddressMode = provider.addressMode
        draftProviderTimeout = provider.timeout

        draftModelDisplayName = ""
        draftModelUpstreamID = ""
        draftModelStreaming = true

        apiKeyDraft = ""
        status = ""
        statusIsError = false
        providerFieldError = validateProviderAddress(provider.address)
    }

    func selectModel(_ id: UUID) {
        guard let catalog = settings.providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.id == id }),
              catalog.providers.contains(where: { $0.id == model.providerID }) else { return }

        invalidateModelRefresh()
        cancelEditing()
        selectedModelID = id
        selectedProviderID = nil
        expandedProviderIDs.insert(model.providerID)

        draftModelDisplayName = model.displayName
        draftModelUpstreamID = model.upstreamModelID
        draftModelStreaming = model.isStreamingEnabled

        draftProviderName = ""
        draftProviderAddress = ""
        draftProviderAddressMode = .baseURL
        draftProviderTimeout = 60

        apiKeyDraft = ""
        status = ""
        statusIsError = false
        providerFieldError = nil
    }

    func toggleProviderExpansion(_ id: UUID) {
        if expandedProviderIDs.contains(id) {
            expandedProviderIDs.remove(id)
        } else {
            expandedProviderIDs.insert(id)
        }
    }

    // MARK: Create

    func startNewProvider() {
        invalidateModelRefresh()
        cancelEditing()
        isCreatingProvider = true
        selectedProviderID = nil
        selectedModelID = nil

        draftProviderName = ""
        draftProviderAddress = ""
        draftProviderAddressMode = .baseURL
        draftProviderTimeout = 60
        apiKeyDraft = ""
        status = ""
        statusIsError = false
        providerFieldError = nil
    }

    func startNewModel(for providerID: UUID) {
        invalidateModelRefresh()
        cancelEditing()
        isCreatingModel = true
        newModelParentProviderID = providerID
        selectedModelID = nil
        selectedProviderID = nil
        expandedProviderIDs.insert(providerID)

        draftModelDisplayName = ""
        draftModelUpstreamID = ""
        draftModelStreaming = true
        status = ""
        statusIsError = false
        providerFieldError = nil
    }

    func cancelEditing() {
        isCreatingProvider = false
        isCreatingModel = false
        newModelParentProviderID = nil
        status = ""
        statusIsError = false
        providerFieldError = nil
        apiKeyDraft = ""

        // Restore draft from current selection without re-triggering selection
        if let pid = selectedProviderID,
           let catalog = settings.providerRegistry.catalog,
           let provider = catalog.providers.first(where: { $0.id == pid }) {
            draftProviderName = provider.name
            draftProviderAddress = provider.address
            draftProviderAddressMode = provider.addressMode
            draftProviderTimeout = provider.timeout
            draftModelDisplayName = ""
            draftModelUpstreamID = ""
            draftModelStreaming = true
        } else if let mid = selectedModelID,
                  let catalog = settings.providerRegistry.catalog,
                  let model = catalog.models.first(where: { $0.id == mid }) {
            draftModelDisplayName = model.displayName
            draftModelUpstreamID = model.upstreamModelID
            draftModelStreaming = model.isStreamingEnabled
            draftProviderName = ""
            draftProviderAddress = ""
            draftProviderAddressMode = .baseURL
            draftProviderTimeout = 60
        } else {
            selectedProviderID = nil
            selectedModelID = nil
            draftProviderName = ""
            draftProviderAddress = ""
            draftProviderAddressMode = .baseURL
            draftProviderTimeout = 60
            draftModelDisplayName = ""
            draftModelUpstreamID = ""
            draftModelStreaming = true
        }
    }

    // MARK: Save

    func saveProvider() {
        let name = draftProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            setStatus(L10n.string("settings.providerNameRequired"), isError: true)
            return
        }
        guard !address.isEmpty else {
            setStatus(L10n.string("settings.providerAddressRequired"), isError: true)
            return
        }
        guard providerFieldError == nil else { return }

        invalidateModelRefresh()
        do {
            let id = isCreatingProvider ? UUID() : (selectedProviderID ?? UUID())
            let provider = ProviderConfiguration(
                id: id,
                name: name,
                address: address,
                addressMode: draftProviderAddressMode,
                timeout: draftProviderTimeout
            )
            let saved = try settings.providerRegistry.saveProvider(provider)
            isCreatingProvider = false
            selectProvider(saved.id)
            setStatus(L10n.string("settings.providerSaved"), isError: false)
        } catch {
            setStatus(L10n.string("settings.providerSaveFailed"), isError: true)
        }
    }

    func saveModel() {
        let displayName = draftModelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamID = draftModelUpstreamID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !displayName.isEmpty else {
            setStatus(L10n.string("settings.modelDisplayNameRequired"), isError: true)
            return
        }
        guard !upstreamID.isEmpty else {
            setStatus(L10n.string("settings.modelUpstreamIDRequired"), isError: true)
            return
        }

        do {
            let id = isCreatingModel ? UUID() : (selectedModelID ?? UUID())
            let providerID: UUID
            if isCreatingModel, let parentID = newModelParentProviderID {
                providerID = parentID
            } else if let existing = selectedModel {
                providerID = existing.providerID
            } else {
                setStatus(L10n.string("settings.modelProviderRequired"), isError: true)
                return
            }

            let model = ModelConfiguration(
                id: id,
                displayName: displayName,
                upstreamModelID: upstreamID,
                providerID: providerID,
                isStreamingEnabled: draftModelStreaming,
                source: .manual
            )
            let saved = try settings.providerRegistry.saveModel(model)
            isCreatingModel = false
            newModelParentProviderID = nil
            selectModel(saved.id)
            setStatus(L10n.string("settings.modelSaved"), isError: false)
        } catch {
            setStatus(L10n.string("settings.modelSaveFailed"), isError: true)
        }
    }

    /// Set a model as the active chat model without switching editing context.
    func useModelForChat(_ id: UUID) {
        do {
            try settings.providerRegistry.selectModel(id: id)
            syncActiveModelID()
            setStatus(L10n.string("settings.modelActivated"), isError: false)
        } catch {
            setStatus(L10n.string("settings.modelActivateFailed"), isError: true)
        }
    }

    // MARK: Delete

    func requestDeleteProvider(_ id: UUID) {
        pendingDeleteProviderID = id
    }

    func requestDeleteModel(_ id: UUID) {
        pendingDeleteModelID = id
    }

    func confirmDeleteProvider() {
        guard let id = pendingDeleteProviderID else { return }
        pendingDeleteProviderID = nil
        if selectedProviderID == id {
            invalidateModelRefresh()
        }

        // Capture affected editing selection before the provider
        // (and its models) are removed from the catalog.
        let wasEditingThisProvider = (selectedProviderID == id)
        let modelOwnedByThisProvider: UUID? = {
            if let mid = selectedModelID,
               let catalog = settings.providerRegistry.catalog,
               let model = catalog.models.first(where: { $0.id == mid }),
               model.providerID == id {
                return mid
            }
            return nil
        }()

        do {
            try settings.providerRegistry.deleteProvider(id: id, keyStore: keyStore)
            syncActiveModelID()

            if wasEditingThisProvider || modelOwnedByThisProvider != nil {
                if let catalog = settings.providerRegistry.catalog,
                   let newModel = catalog.models.first(where: { $0.id == catalog.selectedModelID }) {
                    selectModel(newModel.id)
                } else if let firstProvider = settings.providerRegistry.catalog?.providers.first {
                    selectProvider(firstProvider.id)
                }
            }
            setStatus(L10n.string("settings.providerDeleted"), isError: false)
        } catch let error as ProviderModelRegistryError {
            switch error {
            case .wouldLeaveNoSelectableModel:
                setStatus(L10n.string("settings.cannotDeleteLastProvider"), isError: true)
            default:
                setStatus(L10n.string("settings.providerDeleteFailed"), isError: true)
            }
        } catch {
            setStatus(L10n.string("settings.providerDeleteFailed"), isError: true)
        }
    }

    func confirmDeleteModel() {
        guard let id = pendingDeleteModelID else { return }
        pendingDeleteModelID = nil
        do {
            try settings.providerRegistry.deleteModel(id: id)
            syncActiveModelID()
            if selectedModelID == id {
                if let catalog = settings.providerRegistry.catalog,
                   let newModel = catalog.models.first(where: { $0.id == catalog.selectedModelID }) {
                    selectModel(newModel.id)
                } else if let firstProvider = settings.providerRegistry.catalog?.providers.first {
                    selectProvider(firstProvider.id)
                }
            }
            setStatus(L10n.string("settings.modelDeleted"), isError: false)
        } catch let error as ProviderModelRegistryError {
            switch error {
            case .wouldLeaveNoSelectableModel:
                setStatus(L10n.string("settings.cannotDeleteLastModel"), isError: true)
            default:
                setStatus(L10n.string("settings.modelDeleteFailed"), isError: true)
            }
        } catch {
            setStatus(L10n.string("settings.modelDeleteFailed"), isError: true)
        }
    }

    // MARK: Access key

    func saveKey() {
        guard let providerID = selectedProviderID else { return }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setStatus(L10n.string("settings.keyEmpty"), isError: true)
            return
        }
        do {
            try keyStore.saveAPIKey(key, for: providerID)
            apiKeyDraft = ""
            setStatus(L10n.string("settings.saveKeySuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.saveKeyFailure"), isError: true)
        }
    }

    func clearKey() {
        guard let providerID = selectedProviderID else { return }
        do {
            try keyStore.deleteAPIKey(for: providerID)
            apiKeyDraft = ""
            setStatus(L10n.string("settings.clearKeySuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.clearKeyFailure"), isError: true)
        }
    }

    func testConnection() {
        guard let providerID = selectedProviderID,
              let catalog = settings.providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.providerID == providerID }) else { return }

        isTesting = true
        status = ""
        statusIsError = false

        Task {
            do {
                let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                let mode = draftProviderAddressMode
                let timeout = draftProviderTimeout

                // Save draft key if provided, then read back the stored key
                let draftKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !draftKey.isEmpty {
                    try keyStore.saveAPIKey(draftKey, for: providerID)
                    apiKeyDraft = ""
                }
                let storedKey = try keyStore.readAPIKey(for: providerID)

                // Require an API key before constructing the target
                guard let apiKey = (storedKey ?? (draftKey.isEmpty ? nil : draftKey)),
                      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatError.missingAPIKey
                }

                let endpoint = try URLNormalizer.endpoint(
                    from: address,
                    useFullEndpoint: mode.usesFullEndpoint
                )
                let target = ProviderTargetSnapshot(
                    modelID: model.id,
                    providerID: providerID,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    upstreamModelID: model.upstreamModelID,
                    isStreamingEnabled: model.isStreamingEnabled,
                    timeout: timeout
                )
                let chatProvider = try providerFactory.makeProvider(for: target)
                try await chatProvider.testConnection()
                setStatus(L10n.string("settings.modelConnectionSuccess"), isError: false)
            } catch let error as ChatError {
                setStatus(error.localizedDescription, isError: true)
            } catch {
                setStatus(L10n.string("settings.testFailure"), isError: true)
            }
            isTesting = false
        }
    }

    // MARK: Model discovery

    func refreshModels() {
        guard let providerID = selectedProviderID,
              let provider = settings.providerRegistry.catalog?.providers.first(where: { $0.id == providerID }) else {
            return
        }
        guard provider.addressMode == .baseURL else {
            modelRefreshStatus = .unavailable
            return
        }

        invalidateModelRefresh(status: .loading)
        let generation = modelRefreshGeneration
        let keyStore = keyStore
        let modelDiscovery = modelDiscovery
        let registry = settings.providerRegistry
        modelRefreshTask = Task { [weak self] in
            do {
                guard let apiKey = try keyStore.readAPIKey(for: providerID),
                      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProviderModelDiscoveryError.missingAPIKey
                }
                let upstreamModelIDs = try await modelDiscovery.models(for: provider, apiKey: apiKey)
                try Task.checkCancellation()
                guard let self, self.modelRefreshGeneration == generation else { return }
                try registry.replaceDiscoveredModels(for: providerID, upstreamModelIDs: upstreamModelIDs)
                self.syncActiveModelID()
                let discoveredModelCount = registry.catalog?.models.filter {
                    $0.providerID == providerID && $0.source == .discovered
                }.count ?? 0
                self.modelRefreshStatus = .success(discoveredModelCount)
            } catch let error as ProviderModelDiscoveryError {
                guard let self, self.modelRefreshGeneration == generation else { return }
                switch error {
                case .missingAPIKey:
                    self.modelRefreshStatus = .missingAccessKey
                case .unavailableForFullEndpoint:
                    self.modelRefreshStatus = .unavailable
                case .cancelled:
                    self.modelRefreshStatus = .cancelled
                case .invalidResponse, .unsuccessfulStatus, .networkUnavailable, .timeout:
                    self.modelRefreshStatus = .failed
                }
            } catch is CancellationError {
                guard let self, self.modelRefreshGeneration == generation else { return }
                self.modelRefreshStatus = .cancelled
            } catch {
                guard let self, self.modelRefreshGeneration == generation else { return }
                self.modelRefreshStatus = .failed
            }
            if let self, self.modelRefreshGeneration == generation {
                self.modelRefreshTask = nil
            }
        }
    }

    func cancelModelRefresh() {
        invalidateModelRefresh(status: .cancelled)
    }

    // MARK: Validation

    func validateProviderURL(_ value: String) {
        providerFieldError = validateProviderAddress(value)
    }

    private func validateProviderAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try URLNormalizer.endpoint(from: trimmed, useFullEndpoint: draftProviderAddressMode.usesFullEndpoint)
            return nil
        } catch {
            return L10n.string("settings.endpointInvalid")
        }
    }

    private func invalidateModelRefresh(status: ModelRefreshStatus = .idle) {
        modelRefreshGeneration &+= 1
        modelRefreshTask?.cancel()
        modelRefreshTask = nil
        modelRefreshStatus = status
    }

    func clearStatus() {
        status = ""
        statusIsError = false
    }

    private func syncActiveModelID() {
        activeModelID = settings.providerRegistry.catalog?.selectedModelID
    }

    // MARK: Global data clear

    func clearAllLocalData() {
        do {
            try keyStore.deleteAllAPIKeys()
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.spotask.app")
            setStatus(L10n.string("settings.resetSuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.resetFailure"), isError: true)
        }
    }

    // MARK: Private

    private func setStatus(_ value: String, isError: Bool) {
        status = value
        statusIsError = isError
    }
}
