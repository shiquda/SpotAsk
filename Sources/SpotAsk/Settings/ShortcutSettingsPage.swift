import Foundation
import SwiftUI

// MARK: - In-app Shortcuts Settings

struct ShortcutSettingsPage: View {
    @Bindable var settings: AppSettings

    private let operations = InAppShortcutOperation.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(section: .shortcuts, settings: settings)
            Text(L10n.string("settings.shortcutsDescription"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsGroup(title: L10n.string("settings.shortcutActions")) {
                SelectionAssistantToggleShortcutRow(settings: settings)
                Divider()
                ForEach(operations) { operation in
                    ShortcutSettingsRow(
                        title: operation.title,
                        target: .operation(operation),
                        settings: settings
                    )
                    if operation != operations.last { Divider() }
                }
            }

            SettingsGroup(title: L10n.string("settings.shortcutPrompts")) {
                ForEach(settings.enabledPromptPresets) { preset in
                    ShortcutSettingsRow(
                        title: preset.title,
                        target: .promptPreset(preset.id),
                        settings: settings
                    )
                    if preset.id != settings.enabledPromptPresets.last?.id { Divider() }
                }
            }

            HStack {
                Spacer()
                Button {
                    settings.resetAllShortcuts()
                    StatusToastCenter.shared.show(L10n.string("settings.shortcutsRestored"))
                } label: {
                    Label(L10n.string("settings.resetAllShortcuts"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct SelectionAssistantToggleShortcutRow: View {
    @Bindable var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.string("settings.selectionAssistantToggleShortcut"))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorder(
                shortcut: settings.selectionAssistantToggleShortcut,
                onRecord: { shortcut in
                    settings.selectionAssistantToggleShortcut = shortcut
                    StatusToastCenter.shared.show(L10n.string("settings.shortcutSaved"))
                },
                onInvalid: { StatusToastCenter.shared.show(L10n.string("settings.shortcutInvalid"), isError: true) }
            )
            .frame(width: 176, height: 28)
            .accessibilityLabel(L10n.string("settings.selectionAssistantToggleShortcut"))

            Button {
                settings.selectionAssistantToggleShortcut = nil
                StatusToastCenter.shared.show(L10n.string("settings.shortcutCleared"))
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(settings.selectionAssistantToggleShortcut == nil)
            .help(L10n.string("settings.clearShortcut"))
            .accessibilityLabel(L10n.string("settings.clearShortcut"))

            Button {
                settings.selectionAssistantToggleShortcut = nil
                StatusToastCenter.shared.show(L10n.string("settings.shortcutResetToUnset"))
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(settings.selectionAssistantToggleShortcut == nil)
            .help(L10n.string("settings.resetShortcutToUnset"))
            .accessibilityLabel(L10n.string("settings.resetShortcutToUnset"))
        }
    }
}

private struct ShortcutSettingsRow: View {
    let title: String
    let target: InAppShortcutTarget
    @Bindable var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorder(
                shortcut: settings.shortcut(for: target),
                onRecord: assign,
                onInvalid: { show(L10n.string("settings.shortcutInvalid"), isError: true) }
            )
            .frame(width: 176, height: 28)
            .accessibilityLabel(title)

            Button {
                if settings.removeShortcut(for: target) == nil {
                    show(L10n.string("settings.shortcutCleared"))
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(settings.shortcut(for: target) == nil)
            .help(L10n.string("settings.clearShortcut"))
            .accessibilityLabel(L10n.string("settings.clearShortcut") + " " + title)

            Button {
                if settings.resetShortcut(for: target) == nil {
                    show(L10n.string("settings.shortcutRestored"))
                }
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
            show(L10n.string("settings.shortcutSaved"))
        case .unsupportedShortcut:
            show(L10n.string("settings.shortcutInvalid"), isError: true)
        case let .duplicateShortcut(existingTarget):
            show(L10n.string("settings.shortcutDuplicate", targetTitle(existingTarget)), isError: true)
        case .unavailableTarget:
            show(L10n.string("settings.shortcutUnavailable"), isError: true)
        }
    }

    private func show(_ message: String, isError: Bool = false) {
        StatusToastCenter.shared.show(message, isError: isError)
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
        case .zoomIn: L10n.string("shortcut.zoomIn")
        case .zoomOut: L10n.string("shortcut.zoomOut")
        }
    }
}

