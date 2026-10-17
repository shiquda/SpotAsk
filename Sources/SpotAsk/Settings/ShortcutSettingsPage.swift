import Foundation
import SwiftUI

// MARK: - In-app Shortcuts Settings Page

struct ShortcutSettingsPage: View {
    @Bindable var settings: AppSettings
    @State private var searchText = ""

    private let operations = InAppShortcutOperation.allCases

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesQuery(title: String, description: String? = nil, shortcut: InAppShortcut? = nil) -> Bool {
        guard !query.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(query) { return true }
        if let description, description.localizedCaseInsensitiveContains(query) { return true }
        if let shortcut {
            let fullText = InAppShortcutDisplay.text(for: shortcut)
            if fullText.localizedCaseInsensitiveContains(query) { return true }
            for label in InAppShortcutDisplay.labels(for: shortcut) {
                if label.localizedCaseInsensitiveContains(query) { return true }
            }
            if query == "cmd" || query == "command" {
                if shortcut.modifiers.contains(.command) { return true }
            }
            if query == "opt" || query == "option" || query == "alt" {
                if shortcut.modifiers.contains(.option) { return true }
            }
            if query == "shift" {
                if shortcut.modifiers.contains(.shift) { return true }
            }
            if query == "ctrl" || query == "control" {
                if shortcut.modifiers.contains(.control) { return true }
            }
            if query == "space" || query == "空格" {
                if shortcut.key == " " { return true }
            }
        }
        return false
    }

    // Filtered Global items
    private var globalSummonMatches: Bool {
        matchesQuery(
            title: L10n.string("settings.globalShortcut"),
            description: L10n.string("settings.globalShortcutDescription"),
            shortcut: settings.globalShortcut ?? settings.hotKeyPreset.shortcut
        )
    }

    private var selectionToggleMatches: Bool {
        matchesQuery(
            title: L10n.string("settings.selectionAssistantToggleShortcut"),
            description: L10n.string("settings.selectionAssistantToggleDescription"),
            shortcut: settings.selectionAssistantToggleShortcut
        )
    }

    private var hasGlobalMatches: Bool {
        globalSummonMatches || selectionToggleMatches
    }

    // Filtered Operations
    private var filteredOperations: [InAppShortcutOperation] {
        operations.filter { operation in
            matchesQuery(
                title: operation.title,
                description: operation.actionDescription,
                shortcut: settings.shortcut(for: .operation(operation))
            )
        }
    }

    // Filtered Prompt Presets
    private var filteredPromptPresets: [PromptPreset] {
        settings.enabledPromptPresets.filter { preset in
            matchesQuery(
                title: preset.title,
                description: preset.instruction,
                shortcut: settings.shortcut(for: .promptPreset(preset.id))
            )
        }
    }

    // Filtered Quick Actions
    private var filteredQuickActions: [QuickAction] {
        guard settings.externalAskEnabled else { return [] }
        return settings.enabledQuickActions.filter { action in
            matchesQuery(
                title: action.displayName,
                description: action.kind.template,
                shortcut: settings.shortcut(for: .quickAction(action.id))
            )
        }
    }

    private var hasAnyMatches: Bool {
        hasGlobalMatches ||
        !filteredOperations.isEmpty ||
        !filteredPromptPresets.isEmpty ||
        !filteredQuickActions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(section: .shortcuts, settings: settings)
            Text(L10n.string("settings.shortcutsDescription"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Top Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(L10n.string("settings.shortcutSearchPlaceholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("status.dismiss"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }

            if !hasAnyMatches {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(L10n.string("settings.shortcutNoSearchResults"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.string("settings.shortcutNoSearchResultsDescription", searchText))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                // Group 1: Global System Wakeup
                if hasGlobalMatches {
                    SettingsGroup(
                        title: L10n.string("settings.shortcutGroupGlobal"),
                        documentation: DocumentationLinks.url(for: .shortcutsReference, language: settings.language)
                    ) {
                        if globalSummonMatches {
                            GlobalShortcutSettingsRow(settings: settings)
                        }
                        if globalSummonMatches && selectionToggleMatches {
                            Divider()
                        }
                        if selectionToggleMatches {
                            SelectionAssistantToggleShortcutRow(settings: settings)
                        }
                    }
                }

                // Group 2: In-Window Operations
                if !filteredOperations.isEmpty {
                    SettingsGroup(title: L10n.string("settings.shortcutGroupInWindow")) {
                        ForEach(filteredOperations) { operation in
                            ShortcutSettingsRow(
                                title: operation.title,
                                description: operation.actionDescription,
                                target: .operation(operation),
                                settings: settings
                            )
                            if operation != filteredOperations.last { Divider() }
                        }
                    }
                }

                // Group 3: Prompt Presets
                if !filteredPromptPresets.isEmpty {
                    SettingsGroup(title: L10n.string("settings.shortcutPrompts")) {
                        ForEach(filteredPromptPresets) { preset in
                            ShortcutSettingsRow(
                                title: preset.title,
                                description: preset.instruction,
                                target: .promptPreset(preset.id),
                                settings: settings
                            )
                            if preset.id != filteredPromptPresets.last?.id { Divider() }
                        }
                    }
                }

                // Group 4: External Ask
                if !filteredQuickActions.isEmpty {
                    SettingsGroup(title: L10n.string("settings.shortcutGroupExternal")) {
                        ForEach(filteredQuickActions) { action in
                            ShortcutSettingsRow(
                                title: action.displayName,
                                description: action.kind.template,
                                target: .quickAction(action.id),
                                settings: settings
                            )
                            if action.id != filteredQuickActions.last?.id { Divider() }
                        }
                    }
                }
            }

            // Restore All Defaults Button
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

// MARK: - Global Shortcut Settings Row

private struct GlobalShortcutSettingsRow: View {
    @Bindable var settings: AppSettings
    @State private var inlineConflict: ShortcutConflictInfo?

    private var activeConflict: ShortcutConflictInfo? {
        inlineConflict ?? settings.globalShortcutConflict()
    }

    private var currentShortcut: InAppShortcut? {
        settings.globalShortcut ?? settings.hotKeyPreset.shortcut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("settings.globalShortcut"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(L10n.string("settings.globalShortcutDescription"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShortcutRecorder(
                    shortcut: currentShortcut,
                    hasConflict: activeConflict != nil,
                    onRecord: assign,
                    onInvalid: {
                        StatusToastCenter.shared.show(L10n.string("settings.shortcutInvalid"), isError: true)
                    },
                    allowsSpace: true
                )
                .frame(width: 176, height: 28)
                .accessibilityLabel(L10n.string("settings.globalShortcut"))

                Button {
                    settings.globalShortcut = nil
                    inlineConflict = nil
                    StatusToastCenter.shared.show(L10n.string("settings.shortcutCleared"))
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .disabled(settings.globalShortcut == nil && settings.hotKeyPreset.shortcut == currentShortcut && currentShortcut == nil)
                .help(L10n.string("settings.clearShortcut"))
                .accessibilityLabel(L10n.string("settings.clearShortcut") + " " + L10n.string("settings.globalShortcut"))

                Button {
                    settings.globalShortcut = settings.hotKeyPreset.shortcut
                    inlineConflict = nil
                    StatusToastCenter.shared.show(L10n.string("settings.shortcutRestored"))
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.resetShortcut"))
                .accessibilityLabel(L10n.string("settings.resetShortcut") + " " + L10n.string("settings.globalShortcut"))
            }

            if let conflict = activeConflict {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(conflict.message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if activeConflict != nil {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: activeConflict != nil)
    }

    private func assign(_ shortcut: InAppShortcut) {
        if let conflict = settings.shortcutConflict(for: shortcut, excludingGlobal: true) {
            inlineConflict = conflict
            return
        }
        inlineConflict = nil
        settings.globalShortcut = shortcut
        StatusToastCenter.shared.show(L10n.string("settings.shortcutSaved"))
    }
}

// MARK: - Selection Assistant Toggle Shortcut Row

private struct SelectionAssistantToggleShortcutRow: View {
    @Bindable var settings: AppSettings
    @State private var inlineConflict: ShortcutConflictInfo?

    private var activeConflict: ShortcutConflictInfo? {
        inlineConflict ?? settings.selectionAssistantToggleShortcutConflict()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("settings.selectionAssistantToggleShortcut"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(L10n.string("settings.selectionAssistantToggleDescription"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShortcutRecorder(
                    shortcut: settings.selectionAssistantToggleShortcut,
                    hasConflict: activeConflict != nil,
                    onRecord: assign,
                    onInvalid: {
                        StatusToastCenter.shared.show(L10n.string("settings.shortcutInvalid"), isError: true)
                    }
                )
                .frame(width: 176, height: 28)
                .accessibilityLabel(L10n.string("settings.selectionAssistantToggleShortcut"))

                Button {
                    settings.selectionAssistantToggleShortcut = nil
                    inlineConflict = nil
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
                    inlineConflict = nil
                    StatusToastCenter.shared.show(L10n.string("settings.shortcutResetToUnset"))
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(settings.selectionAssistantToggleShortcut == nil)
                .help(L10n.string("settings.resetShortcutToUnset"))
                .accessibilityLabel(L10n.string("settings.resetShortcutToUnset"))
            }

            if let conflict = activeConflict {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(conflict.message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if activeConflict != nil {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: activeConflict != nil)
    }

    private func assign(_ shortcut: InAppShortcut) {
        if let conflict = settings.shortcutConflict(for: shortcut, excludingSelectionToggle: true) {
            inlineConflict = conflict
            return
        }
        inlineConflict = nil
        settings.selectionAssistantToggleShortcut = shortcut
        StatusToastCenter.shared.show(L10n.string("settings.shortcutSaved"))
    }
}

// MARK: - Shortcut Settings Row

private struct ShortcutSettingsRow: View {
    let title: String
    var description: String? = nil
    let target: InAppShortcutTarget
    @Bindable var settings: AppSettings
    @State private var inlineConflict: ShortcutConflictInfo?

    private var activeConflict: ShortcutConflictInfo? {
        inlineConflict ?? settings.shortcutConflict(for: target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShortcutRecorder(
                    shortcut: settings.shortcut(for: target),
                    hasConflict: activeConflict != nil,
                    onRecord: assign,
                    onInvalid: { show(L10n.string("settings.shortcutInvalid"), isError: true) }
                )
                .frame(width: 176, height: 28)
                .accessibilityLabel(title)

                Button {
                    inlineConflict = nil
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
                    inlineConflict = nil
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

            if let conflict = activeConflict {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(conflict.message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if activeConflict != nil {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: activeConflict != nil)
    }

    private func assign(_ shortcut: InAppShortcut) {
        if let conflict = settings.shortcutConflict(for: shortcut, excluding: target) {
            inlineConflict = conflict
            return
        }
        inlineConflict = nil
        switch settings.assignShortcut(shortcut, to: target) {
        case nil:
            show(L10n.string("settings.shortcutSaved"))
        case .unsupportedShortcut:
            show(L10n.string("settings.shortcutInvalid"), isError: true)
        case let .duplicateShortcut(existingTarget):
            let existingTitle = settings.targetTitle(for: existingTarget)
            inlineConflict = ShortcutConflictInfo(
                conflictingShortcut: shortcut,
                conflictSource: .inAppTarget(existingTarget, title: existingTitle),
                message: L10n.string("settings.shortcutConflictInApp", existingTitle)
            )
        case .unavailableTarget:
            show(L10n.string("settings.shortcutUnavailable"), isError: true)
        }
    }

    private func show(_ message: String, isError: Bool = false) {
        StatusToastCenter.shared.show(message, isError: isError)
    }
}
