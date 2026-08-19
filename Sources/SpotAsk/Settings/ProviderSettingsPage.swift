import AppKit
import Foundation
import SwiftUI

enum ProviderSettingsIcon {
    static let useForChat = "checkmark.circle"
}

// MARK: - Provider Settings Page

struct ProviderSettingsPage: View {
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
        .sheet(isPresented: $state.isModelSelectionPresented) {
            DiscoveredModelSelectionSheet(state: state)
        }
    }
}

// MARK: - Discovered Model Selection

private struct DiscoveredModelSelectionSheet: View {
    @Bindable var state: ProviderSettingsState

    private var discoveryProvider: ProviderConfiguration? {
        guard let providerID = state.selectedProviderID,
              let catalog = state.settings.providerRegistry.catalog else { return nil }
        return catalog.providers.first(where: { $0.id == providerID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("settings.modelSelectionTitle"))
                .font(.title2.weight(.semibold))
            Text(L10n.string("settings.modelSelectionDescription"))
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.discoveredModelCandidates, id: \.self) { modelID in
                        Toggle(isOn: Binding(
                            get: { state.selectedDiscoveredModelIDs.contains(modelID) },
                            set: { _ in state.toggleDiscoveredModel(modelID) }
                        )) {
                            HStack(spacing: 8) {
                                ProviderBrandIconView(
                                    slug: ProviderBrandIconMatcher.match(
                                        providerName: discoveryProvider?.name,
                                        address: discoveryProvider?.address,
                                        modelName: modelID
                                    ),
                                    size: 14,
                                    fallbackSymbol: "sparkles",
                                    fallbackColor: .secondary
                                )
                                Text(modelID)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180, maxHeight: 280)

            HStack {
                Button(L10n.string("settings.modelSelectionSelectAll")) {
                    state.selectAllDiscoveredModels()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(L10n.string("settings.cancel")) {
                    state.cancelModelSelection()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("settings.modelSelectionAdd")) {
                    state.applySelectedDiscoveredModels()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.selectedDiscoveredModelIDs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 380)
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
                        ProviderBrandIconView(
                            slug: ProviderBrandIconMatcher.match(
                                providerName: provider.name,
                                address: provider.address
                            ),
                            size: 14,
                            fallbackSymbol: "server.rack",
                            fallbackColor: .secondary
                        )
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
                                    Label(L10n.string("settings.useForChat"), systemImage: ProviderSettingsIcon.useForChat)
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
    @State private var isKeyVisible = false

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
                SettingsFieldRow(label: L10n.string("settings.providerFormat")) {
                    HStack(spacing: 0) {
                        Picker(L10n.string("settings.providerFormat"), selection: $state.draftProviderFormat) {
                            Text(L10n.string("settings.providerFormatOpenAI")).tag(ProviderFormat.openAICompatible)
                            Text(L10n.string("settings.providerFormatAnthropic")).tag(ProviderFormat.anthropic)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    .onChange(of: state.draftProviderFormat) { _, _ in
                        state.validateProviderURL(state.draftProviderAddress)
                        state.clearStatus()
                    }
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
                    HStack(spacing: 0) {
                        Picker(L10n.string("settings.addressMode"), selection: $state.draftProviderAddressMode) {
                            Text(L10n.string("settings.addressModeBaseURL")).tag(ProviderAddressMode.baseURL)
                            Text(L10n.string("settings.addressModeFullEndpoint")).tag(ProviderAddressMode.fullEndpoint)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
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

            if !isNew {
                SettingsGroup(title: L10n.string("settings.accessKey")) {
                    SettingsFieldRow(label: L10n.string("settings.accessKey")) {
                        ZStack(alignment: .trailing) {
                            Group {
                                if isKeyVisible {
                                    TextField(L10n.string("settings.accessKeyPlaceholder"), text: $state.apiKeyDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .textContentType(.none)
                                } else {
                                    SecureField(L10n.string("settings.accessKeyPlaceholder"), text: $state.apiKeyDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .textContentType(.password)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                isKeyVisible.toggle()
                            } label: {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.borderless)
                            .padding(.trailing, 6)
                            .help(L10n.string(isKeyVisible ? "settings.hideAccessKey" : "settings.showAccessKey"))
                            .accessibilityLabel(L10n.string(isKeyVisible ? "settings.hideAccessKey" : "settings.showAccessKey"))
                        }
                        .onChange(of: state.apiKeyDraft) { _, _ in
                            state.persistAPIKeyDraft()
                        }
                    }
                    Text(L10n.string("settings.accessKeyOnlyOnMac"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var parentProvider: ProviderConfiguration? {
        guard let catalog = state.settings.providerRegistry.catalog,
              let pid = state.newModelParentProviderID ?? state.selectedModel?.providerID,
              let provider = catalog.providers.first(where: { $0.id == pid }) else { return nil }
        return provider
    }

    private var parentProviderName: String {
        parentProvider?.name ?? ""
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
                        .onChange(of: state.draftModelDisplayName) { _, _ in
                            state.updateDraftModelCompatibilityProfileIfNeeded()
                            state.clearStatus()
                        }
                }
                SettingsFieldRow(label: L10n.string("settings.upstreamModelID")) {
                    TextField("gpt-5-mini", text: $state.draftModelUpstreamID)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: state.draftModelUpstreamID) { _, _ in
                            state.updateDraftModelCompatibilityProfileIfNeeded()
                            state.clearStatus()
                        }
                }
                SettingsFieldRow(label: L10n.string("settings.service")) {
                    HStack(spacing: 8) {
                        ProviderBrandIconView(
                            slug: parentProvider.flatMap { provider in
                                ProviderBrandIconMatcher.match(
                                    providerName: provider.name,
                                    address: provider.address
                                )
                            },
                            size: 13,
                            fallbackSymbol: "server.rack",
                            fallbackColor: .secondary
                        )
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
                SettingsFieldRow(label: L10n.string("settings.requestCompatibilityProfile")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker(
                            L10n.string("settings.requestCompatibilityProfile"),
                            selection: Binding(
                                get: { state.draftModelCompatibilityProfile },
                                set: { state.setDraftModelCompatibilityProfile($0) }
                            )
                        ) {
                            ForEach(RequestCompatibilityProfile.allCases, id: \.self) { profile in
                                Text(profile.settingsTitle).tag(profile)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Text(L10n.string("settings.requestCompatibilityProfileDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsFieldRow(label: L10n.string("settings.thinkingMode")) {
                    Picker(L10n.string("settings.thinkingMode"), selection: $state.draftModelThinkingMode) {
                        ForEach(ModelThinkingMode.allCases, id: \.self) { mode in
                            Text(mode.settingsTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: state.draftModelThinkingMode) { _, _ in state.clearStatus() }
                }
                SettingsFieldRow(label: L10n.string("settings.customRequestParameters")) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            L10n.string("settings.customRequestParametersPlaceholder"),
                            text: $state.draftModelExtraRequestParametersText,
                            axis: .vertical
                        )
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2...6)
                        .onChange(of: state.draftModelExtraRequestParametersText) { _, _ in state.clearStatus() }
                        if let error = state.draftExtraRequestParametersJSONError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Text(L10n.string("settings.customRequestParametersDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

private extension ModelThinkingMode {
    var settingsTitle: String {
        switch self {
        case .providerDefault: L10n.string("settings.thinkingModeProviderDefault")
        case .disabled: L10n.string("settings.thinkingModeDisabled")
        case .minimal: L10n.string("settings.thinkingModeMinimal")
        case .low: L10n.string("settings.thinkingModeLow")
        case .medium: L10n.string("settings.thinkingModeMedium")
        case .high: L10n.string("settings.thinkingModeHigh")
        case .xhigh: L10n.string("settings.thinkingModeXHigh")
        case .max: L10n.string("settings.thinkingModeMax")
        }
    }
}

private extension RequestCompatibilityProfile {
    var settingsTitle: String {
        switch self {
        case .genericOpenAI: L10n.string("settings.profileGenericOpenAI")
        case .openAI: L10n.string("settings.profileOpenAI")
        case .azureOpenAI: L10n.string("settings.profileAzureOpenAI")
        case .deepSeek: L10n.string("settings.profileDeepSeek")
        case .qwen: L10n.string("settings.profileQwen")
        case .kimi: L10n.string("settings.profileKimi")
        case .zAI: L10n.string("settings.profileZAI")
        case .mistral: L10n.string("settings.profileMistral")
        case .xAI: L10n.string("settings.profileXAI")
        case .openRouter: L10n.string("settings.profileOpenRouter")
        case .volcengineArk: L10n.string("settings.profileVolcengineArk")
        case .siliconFlow: L10n.string("settings.profileSiliconFlow")
        case .anthropic: L10n.string("settings.profileAnthropic")
        }
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
                if isExpanded {
                    state.collapseProvider(provider.id)
                } else {
                    state.toggleProviderExpansion(provider.id)
                }
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
                    ProviderBrandIconView(
                        slug: ProviderBrandIconMatcher.match(
                            providerName: provider.name,
                            address: provider.address
                        ),
                        size: 18,
                        fallbackSymbol: "server.rack",
                        fallbackColor: .secondary
                    )

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

    private var provider: ProviderConfiguration? {
        guard let catalog = state.settings.providerRegistry.catalog else { return nil }
        return catalog.providers.first(where: { $0.id == model.providerID })
    }

    private var isActive: Bool {
        state.activeModelID == model.id
    }

    private var isEditing: Bool {
        state.selectedModelID == model.id
    }

    private var isTesting: Bool {
        state.testingModelID == model.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.cyan)
                } else {
                    Button {
                        state.useModelForChat(model.id)
                    } label: {
                        Image(systemName: "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("settings.useForChat"))
                    .accessibilityLabel(L10n.string("settings.useForChat") + " " + model.displayName)
                }
            }
            .frame(width: 22, height: 22)

            Button {
                state.selectModel(model.id)
            } label: {
                HStack(spacing: 8) {
                    ProviderBrandIconView(
                        slug: ProviderBrandIconMatcher.match(
                            providerName: provider?.name,
                            address: provider?.address,
                            modelName: model.displayName,
                            upstreamModelID: model.upstreamModelID
                        ),
                        size: 14,
                        fallbackSymbol: "sparkles",
                        fallbackColor: .secondary
                    )
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

            Button {
                state.testConnection(modelID: model.id)
            } label: {
                Group {
                    if isTesting {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(state.isTesting)
            .help(L10n.string("settings.testModel"))
            .accessibilityLabel(L10n.string("settings.testModel") + " " + model.displayName)

            Button {
                state.selectModel(model.id)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(L10n.string("settings.editModel"))
            .accessibilityLabel(L10n.string("settings.editModel") + " " + model.displayName)

            Button(role: .destructive) {
                state.requestDeleteModel(model.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(L10n.string("settings.delete"))
            .accessibilityLabel(L10n.string("settings.delete") + " " + model.displayName)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isEditing ? Brand.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Brand.accent.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

