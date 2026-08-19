import Foundation
import SwiftUI

// MARK: - Prompt Presets Settings

struct PromptPresetsSettingsPage: View {
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
            Image(systemName: preset.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
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
    @State private var symbolName: String
    @State private var instruction: String

    private static let availableSymbols: [String] = [
        "sparkles",
        "character.bubble",
        "doc.text.magnifyingglass",
        "list.bullet.rectangle",
        "pencil.and.scribble",
        "globe",
        "bubble.left.and.bubble.right",
        "link",
        "safari",
        "terminal",
        "chevron.left.forwardslash.chevron.right",
        "magnifyingglass",
        "bolt"
    ]

    init(preset: PromptPreset, onSave: @escaping (PromptPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _title = State(initialValue: preset.title)
        _symbolName = State(initialValue: PromptPreset.isValidSymbol(preset.customSymbolName) ? (preset.customSymbolName ?? PromptPreset.defaultSymbolName) : PromptPreset.defaultSymbolName)
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
                Text(L10n.string("externalAsk.iconLabel"))
                    .font(.headline)
                Picker(L10n.string("externalAsk.iconLabel"), selection: $symbolName) {
                    ForEach(Self.availableSymbols, id: \.self) { symbol in
                        Label(symbol, systemImage: symbol).tag(symbol)
                    }
                }
                .labelsHidden()
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
                    onSave(PromptPreset(id: preset.id, title: title, instruction: instruction, customSymbolName: symbolName))
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

