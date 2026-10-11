import Foundation
import SwiftUI

// MARK: - External Ask Settings Page

struct ExternalAskSettingsPage: View {
    @Bindable var settings: AppSettings
    let keyStore: any APIKeyStoring
    @State private var editorAction: QuickAction?
    @State private var deletingAction: QuickAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .externalAsk, settings: settings)
            SettingsCallout(L10n.string("settings.externalAskDescription"))

            externalAskToggle

            SettingsGroup(
                title: L10n.string("settings.externalAsk"),
                documentation: DocumentationLinks.url(for: .externalAsk, language: settings.language)
            ) {
                HStack {
                    Text(L10n.string("settings.promptCatalogDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editorAction = QuickAction(
                            name: "",
                            kind: .web(urlTemplate: ""),
                            symbolName: QuickAction.defaultSymbolName,
                            isBuiltIn: false,
                            isEnabled: true
                        )
                    } label: {
                        Label(L10n.string("settings.new"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: 6) {
                    ForEach(Array(settings.quickActions.enumerated()), id: \.element.id) { index, action in
                        quickActionCard {
                            QuickActionRow(
                                action: action,
                                settings: settings,
                                position: index + 1,
                                totalCount: settings.quickActions.count,
                                onMoveUp: index > 0 ? { moveAction(id: action.id, by: -1) } : nil,
                                onMoveDown: index + 1 < settings.quickActions.count ? { moveAction(id: action.id, by: 1) } : nil,
                                onEdit: { editorAction = action },
                                onDelete: { deletingAction = action }
                            )
                        }
                    }
                }
            }

            DecisionRoutingSettingsSection(settings: settings, keyStore: keyStore)
        }
        .sheet(item: $editorAction) { action in
            QuickActionEditor(action: action) { savedAction in
                guard settings.saveQuickAction(savedAction) else { return }
                editorAction = nil
            }
        }
        .alert(
            L10n.string("externalAsk.deleteTitle"),
            isPresented: Binding(
                get: { deletingAction != nil },
                set: { if !$0 { deletingAction = nil } }
            )
        ) {
            Button(L10n.string("settings.cancel"), role: .cancel) {
                deletingAction = nil
            }
            Button(L10n.string("settings.delete"), role: .destructive) {
                if let deletingAction {
                    settings.deleteQuickAction(id: deletingAction.id)
                }
                deletingAction = nil
            }
        } message: {
            Text(L10n.string("externalAsk.deleteMessage", deletingAction?.displayName ?? ""))
        }
    }

    private func quickActionCard<Content: View>(
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

    private func moveAction(id: UUID, by offset: Int) {
        settings.moveQuickAction(id: id, by: offset)
    }

    /// Own switch card, not a checkbox inside the channel catalog.
    private var externalAskToggle: some View {
        SettingsToggleRow(
            label: L10n.string("settings.externalAskEnabled"),
            isOn: $settings.externalAskEnabled
        )
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@MainActor
private struct QuickActionRow: View {
    let action: QuickAction
    let settings: AppSettings
    let position: Int
    let totalCount: Int
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            QuickActionReorderControls(
                title: action.displayName,
                position: position,
                totalCount: totalCount,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            ProviderBrandIconView(
                slug: action.brandIconSlug,
                size: 16,
                fallbackSymbol: action.symbolName
            )
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(action.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(action.kind.template)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.edit"))
                .accessibilityLabel(L10n.string("settings.edit") + " " + action.displayName)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.delete"))
                .accessibilityLabel(L10n.string("settings.delete") + " " + action.displayName)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { action.isEnabled },
                        set: { settings.setQuickActionEnabled(id: action.id, isEnabled: $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(L10n.string("settings.promptEnabled") + " " + action.displayName)
            }
        }
    }
}

private struct QuickActionReorderControls: View {
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

private enum ActionKindOption: String, CaseIterable, Identifiable {
    case web
    case uriScheme
    case terminal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .web:
            L10n.string("externalAsk.kind.web")
        case .uriScheme:
            L10n.string("externalAsk.kind.uriScheme")
        case .terminal:
            L10n.string("externalAsk.kind.terminal")
        }
    }
}

private struct QuickActionEditor: View {
    let action: QuickAction
    let onSave: (QuickAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedKindOption: ActionKindOption
    @State private var template: String
    @State private var symbolName: String
    @State private var purpose: String
    @State private var scenario: String
    @State private var requiresConfirmation: Bool

    private var symbolChoices: [String] {
        if QuickAction.availableSymbols.contains(symbolName) {
            return QuickAction.availableSymbols
        }
        return [symbolName] + QuickAction.availableSymbols
    }

    init(action: QuickAction, onSave: @escaping (QuickAction) -> Void) {
        self.action = action
        self.onSave = onSave
        _name = State(initialValue: action.displayName)
        _template = State(initialValue: action.kind.template)
        let kindOption: ActionKindOption
        switch action.kind {
        case .web: kindOption = .web
        case .uriScheme: kindOption = .uriScheme
        case .terminal: kindOption = .terminal
        }
        _selectedKindOption = State(initialValue: kindOption)
        _symbolName = State(initialValue: QuickAction.isValidSymbol(action.symbolName) ? action.symbolName : QuickAction.defaultSymbolName)
        _purpose = State(initialValue: action.routingPurpose)
        _scenario = State(initialValue: action.routingScenario)
        _requiresConfirmation = State(initialValue: action.requiresConfirmationOnAutoRoute)
    }

    private var currentKind: QuickActionKind {
        switch selectedKindOption {
        case .web:
            .web(urlTemplate: template)
        case .uriScheme:
            .uriScheme(urlTemplate: template)
        case .terminal:
            .terminal(commandTemplate: template)
        }
    }

    private var validationStatus: QuickActionTemplateValidation {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .empty }
        return QuickActionBuilder.validate(kind: currentKind)
    }

    private var validationErrorMessage: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return L10n.string("externalAsk.validation.nameRequired")
        }
        switch QuickActionBuilder.validate(kind: currentKind) {
        case .valid:
            return nil
        case .empty:
            switch selectedKindOption {
            case .web:
                return L10n.string("externalAsk.validation.webLinkRequired")
            case .uriScheme:
                return L10n.string("externalAsk.validation.uriLinkRequired")
            case .terminal:
                return L10n.string("externalAsk.validation.commandRequired")
            }
        case .missingQueryPlaceholder:
            return L10n.string("externalAsk.validation.queryPlaceholderRequired")
        case .invalidURL:
            return L10n.string("externalAsk.validation.invalidLink")
        }
    }

    private var validationWarningMessage: String? {
        guard validationErrorMessage == nil else { return nil }
        if selectedKindOption == .web && !QuickActionBuilder.isHTTPScheme(template) {
            return L10n.string("externalAsk.validation.nonHTTPSWarning")
        }
        return nil
    }

    private var templateLabel: String {
        switch selectedKindOption {
        case .web:
            L10n.string("externalAsk.webLinkLabel")
        case .uriScheme:
            L10n.string("externalAsk.uriLinkLabel")
        case .terminal:
            L10n.string("externalAsk.commandLabel")
        }
    }

    private var templatePlaceholder: String {
        switch selectedKindOption {
        case .web:
            L10n.string("externalAsk.webLinkPlaceholder")
        case .uriScheme:
            L10n.string("externalAsk.uriLinkPlaceholder")
        case .terminal:
            L10n.string("externalAsk.commandPlaceholder")
        }
    }

    private var templateHint: String {
        L10n.string("externalAsk.templateHint")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(action.name.isEmpty && !action.isBuiltIn ? L10n.string("externalAsk.new") : L10n.string("settings.edit"))
                    .font(.title2.weight(.semibold))

                SettingsGroup(title: L10n.string("settings.externalAsk")) {
                    SettingsFieldRow(label: L10n.string("externalAsk.typeLabel")) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Picker(L10n.string("externalAsk.typeLabel"), selection: $selectedKindOption) {
                                ForEach(ActionKindOption.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    SettingsFieldRow(label: L10n.string("externalAsk.nameLabel")) {
                        styledInputField(L10n.string("externalAsk.namePlaceholder"), text: $name)
                    }

                    SettingsFieldRow(label: templateLabel) {
                        styledInputField(templatePlaceholder, text: $template)
                    }
                    Text(templateHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 148)
                        .padding(.top, -6)

                    SettingsFieldRow(label: L10n.string("externalAsk.iconLabel")) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Picker(L10n.string("externalAsk.iconLabel"), selection: $symbolName) {
                                ForEach(symbolChoices, id: \.self) { symbol in
                                    Label(QuickAction.localizedSymbolLabel(for: symbol), systemImage: symbol)
                                        .tag(symbol)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }

                SettingsGroup(title: L10n.string("decisionRouting.editChannel")) {
                    Text(L10n.string("decisionRouting.editChannelNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsFieldRow(label: L10n.string("decisionRouting.purpose")) {
                        styledInputField(L10n.string("decisionRouting.purposePlaceholder"), text: $purpose)
                    }

                    SettingsFieldRow(label: L10n.string("decisionRouting.scenario")) {
                        styledInputField(L10n.string("decisionRouting.scenarioPlaceholder"), text: $scenario)
                    }

                    Divider()

                    SettingsToggleRow(
                        label: L10n.string("decisionRouting.forceConfirm"),
                        description: L10n.string("decisionRouting.forceConfirmDescription"),
                        isOn: $requiresConfirmation
                    )
                }
            }
            .padding(20)

            Divider()
            HStack(spacing: 10) {
                if let error = validationErrorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let warning = validationWarningMessage {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(L10n.string("settings.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("settings.save")) {
                    onSave(
                        QuickAction(
                            id: action.id,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: currentKind,
                            symbolName: symbolName,
                            isBuiltIn: action.isBuiltIn,
                            isEnabled: action.isEnabled,
                            routingPurpose: purpose,
                            routingScenario: scenario,
                            requiresConfirmationOnAutoRoute: requiresConfirmation
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationStatus != .valid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 560)
    }

    private func styledInputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120, idealWidth: 200, maxWidth: .infinity)
    }
}
