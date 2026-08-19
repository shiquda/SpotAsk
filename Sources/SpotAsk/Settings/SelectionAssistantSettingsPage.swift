import AppKit
import Foundation
import SwiftUI

struct SelectionAssistantSettingsPage: View {
    let settings: AppSettings
    let permissionCoordinator: AccessibilityPermissionCoordinator
    let settingsOpener: any AccessibilityPermissionSettingsOpening
    let onOpenShortcuts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .selectionAssistant, settings: settings)
            SettingsCallout(L10n.string("settings.selectionAssistantDescription"))
            SettingsGroup(title: L10n.string("settings.selectionAssistant")) {
                SettingsToggleRow(label: L10n.string("settings.selectionAssistantEnabled"), isOn: Bindable(settings).selectionAssistantEnabled)
                    .onChange(of: settings.selectionAssistantEnabled) { _, enabled in
                        if enabled {
                            permissionCoordinator.requestPermissionFromSettings()
                        }
                    }
                if settings.selectionAssistantEnabled {
                    SettingsFieldRow(label: L10n.string("settings.selectionAssistantPermissionStatus")) {
                        Text(permissionCoordinator.status == .allowed
                             ? L10n.string("settings.selectionAssistantPermissionAllowed")
                             : L10n.string("settings.selectionAssistantPermissionNotAllowed"))
                        .foregroundStyle(permissionCoordinator.status == .allowed ? .green : .secondary)
                    }
                    Text(L10n.string("settings.selectionAssistantPermissionDescription"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if permissionCoordinator.status == .notAllowed {
                            Button(L10n.string("settings.selectionAssistantPermissionAuthorize")) {
                                permissionCoordinator.requestPermissionFromSettings()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button(L10n.string("selection.permissionOpenSettings")) {
                            settingsOpener.openAccessibilitySettings()
                        }
                        Button(L10n.string("settings.selectionAssistantPermissionRefresh")) {
                            permissionCoordinator.refresh()
                        }
                    }
                    SettingsFieldRow(label: L10n.string("settings.selectionAssistantMode")) {
                        Picker(L10n.string("settings.selectionAssistantMode"), selection: Bindable(settings).selectionAssistantMode) {
                            Text(L10n.string("settings.selectionAssistantModeDirect")).tag(SelectionAssistantMode.direct)
                            Text(L10n.string("settings.selectionAssistantModeActionBar")).tag(SelectionAssistantMode.actionBar)
                        }
                        .labelsHidden()
                    }
                    if settings.selectionAssistantMode == .actionBar {
                        SettingsToggleRow(label: L10n.string("settings.selectionAssistantAutoShow"), isOn: Bindable(settings).selectionAutoInvokeEnabled)
                        SettingsToggleRow(label: L10n.string("settings.selectionAssistantActionLabels"), isOn: Bindable(settings).selectionActionBarShowsLabels)
                        if settings.selectionAutoInvokeEnabled {
                            SettingsFieldRow(label: L10n.string("settings.selectionAssistantAutoShowScope")) {
                                Picker(L10n.string("settings.selectionAssistantAutoShowScope"), selection: Bindable(settings).selectionAutoInvokeScope) {
                                    Text(L10n.string("settings.selectionAssistantAutoShowScopeAll")).tag(SelectionAutoInvokeScope.allApps)
                                    Text(L10n.string("settings.selectionAssistantAutoShowScopeBlacklist")).tag(SelectionAutoInvokeScope.blacklist)
                                    Text(L10n.string("settings.selectionAssistantAutoShowScopeWhitelist")).tag(SelectionAutoInvokeScope.whitelist)
                                }
                                .labelsHidden()
                            }
                            if settings.selectionAutoInvokeScope != .allApps {
                                Text(settings.selectionAutoInvokeScope == .blacklist
                                     ? L10n.string("settings.selectionAssistantAutoShowBlacklistDescription")
                                     : L10n.string("settings.selectionAssistantAutoShowWhitelistDescription"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                SelectionAutoInvokeApplicationPicker(settings: settings, scope: settings.selectionAutoInvokeScope)
                            }
                            SettingsFieldRow(label: L10n.string("settings.selectionAssistantAutoShowDelay")) {
                                HStack(spacing: 10) {
                                    Slider(
                                        value: Bindable(settings).selectionAutoInvokeDelay,
                                        in: SelectionAutoInvokeDelay.minimum...SelectionAutoInvokeDelay.maximum,
                                        step: SelectionAutoInvokeDelay.step
                                    )
                                    .frame(width: 180)
                                    TextField(
                                        "",
                                        value: Bindable(settings).selectionAutoInvokeDelay,
                                        format: .number.precision(.fractionLength(2))
                                    )
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 56)
                                    Text(L10n.string("settings.selectionAssistantAutoShowDelayUnit"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button(action: onOpenShortcuts) {
                        Label(L10n.string("settings.selectionAssistantConfigureShortcut"), systemImage: "command")
                    }
                    .buttonStyle(.bordered)
                    if settings.selectionAssistantMode == .direct {
                        SettingsFieldRow(label: L10n.string("settings.selectionAssistantDefaultAction")) {
                            Picker(L10n.string("settings.selectionAssistantDefaultAction"), selection: Binding(
                                get: { settings.selectionDefaultPromptID ?? settings.enabledPromptPresets.first?.id },
                                set: { settings.selectionDefaultPromptID = $0 }
                            )) {
                                ForEach(settings.enabledPromptPresets) { preset in Text(preset.title).tag(Optional(preset.id)) }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
        }
    }

}

private struct SelectionApplicationOption: Identifiable, Hashable {
    let identifier: String
    let displayName: String

    var id: String { identifier }
}

private struct SelectionAutoInvokeApplicationPicker: View {
    let settings: AppSettings
    let scope: SelectionAutoInvokeScope

    @State private var applications: [SelectionApplicationOption] = []
    @State private var refreshToken = 0
    @State private var isPickerPresented = false
    @State private var searchText = ""

    private var selectedIdentifiers: [String] {
        switch scope {
        case .allApps: []
        case .blacklist: settings.selectionAutoInvokeBlacklist
        case .whitelist: settings.selectionAutoInvokeWhitelist
        }
    }

    var body: some View {
        SettingsFieldRow(label: L10n.string("settings.selectionAssistantAutoShowApps")) {
            HStack(spacing: 10) {
                Text(L10n.string("settings.selectionAssistantAutoShowSelectedCount", selectedIdentifiers.count))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Button {
                    searchText = ""
                    refreshToken += 1
                    isPickerPresented = true
                } label: {
                    Label(L10n.string("settings.selectionAssistantAutoShowChooseApps"), systemImage: "app.badge.checkmark")
                }
                .buttonStyle(.bordered)

                if !selectedIdentifiers.isEmpty {
                    Button(L10n.string("settings.selectionAssistantAutoShowClear")) {
                        setSelectedIdentifiers([])
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    refreshToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.selectionAssistantAutoShowRefresh"))
                .accessibilityLabel(L10n.string("settings.selectionAssistantAutoShowRefresh"))
            }
        }
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            SelectionAutoInvokeApplicationSearchPopover(
                applications: applications,
                selectedIdentifiers: selectedIdentifiers,
                searchText: $searchText,
                onToggle: toggle
            )
        }
        .task(id: refreshToken) {
            applications = Self.loadRunningApplications()
        }
    }

    private func toggle(_ identifier: String) {
        var identifiers = selectedIdentifiers
        if let index = identifiers.firstIndex(of: identifier) {
            identifiers.remove(at: index)
        } else {
            identifiers.append(identifier)
        }
        setSelectedIdentifiers(identifiers)
    }

    private func setSelectedIdentifiers(_ identifiers: [String]) {
        switch scope {
        case .allApps: break
        case .blacklist: settings.selectionAutoInvokeBlacklist = identifiers
        case .whitelist: settings.selectionAutoInvokeWhitelist = identifiers
        }
    }

    private static func loadRunningApplications() -> [SelectionApplicationOption] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownProcessIdentifier
        }
        let options = running.compactMap { application -> SelectionApplicationOption? in
            guard let name = application.localizedName, !name.isEmpty,
                  let identifier = application.bundleIdentifier ?? application.localizedName,
                  !identifier.isEmpty else {
                return nil
            }
            return SelectionApplicationOption(identifier: identifier, displayName: name)
        }
        var seen = Set<String>()
        return options
            .filter { seen.insert($0.identifier).inserted }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

private struct SelectionAutoInvokeApplicationSearchPopover: View {
    let applications: [SelectionApplicationOption]
    let selectedIdentifiers: [String]
    @Binding var searchText: String
    let onToggle: (String) -> Void

    private var visibleApplications: [SelectionApplicationOption] {
        let currentIdentifiers = Set(applications.map(\.identifier))
        let missingSelected = selectedIdentifiers
            .filter { !currentIdentifiers.contains($0) }
            .map { SelectionApplicationOption(identifier: $0, displayName: $0) }
        return (missingSelected + applications).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var filteredApplications: [SelectionApplicationOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleApplications }
        return visibleApplications.filter { application in
            application.displayName.localizedCaseInsensitiveContains(query)
                || application.identifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.string("settings.selectionAssistantAutoShowSearchPlaceholder"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.string("settings.selectionAssistantAutoShowSearchPlaceholder"))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("settings.selectionAssistantAutoShowSearchClear"))
                    .accessibilityLabel(L10n.string("settings.selectionAssistantAutoShowSearchClear"))
                }
            }
            .padding(12)

            Divider()

            if filteredApplications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text(applications.isEmpty
                         ? L10n.string("settings.selectionAssistantAutoShowNoApps")
                         : L10n.string("settings.selectionAssistantAutoShowSearchNoResults"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredApplications) { application in
                            Toggle(isOn: Binding(
                                get: { selectedIdentifiers.contains(application.identifier) },
                                set: { _ in onToggle(application.identifier) }
                            )) {
                                Text(application.displayName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)

                            if application.id != filteredApplications.last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 320, height: 380)
    }
}

