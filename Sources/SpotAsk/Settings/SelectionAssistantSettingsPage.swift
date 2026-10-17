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
            SettingsGroup(
                title: L10n.string("settings.selectionAssistant"),
                documentation: DocumentationLinks.url(for: .selectionAssistant, language: settings.language)
            ) {
                SettingsToggleRow(label: L10n.string("settings.selectionAssistantEnabled"), isOn: Bindable(settings).selectionAssistantEnabled)
                    .onChange(of: settings.selectionAssistantEnabled) { _, enabled in
                        if enabled {
                            permissionCoordinator.requestPermissionFromSettings()
                        }
                    }
                if settings.selectionAssistantEnabled {
                    SettingsFieldRow(label: L10n.string("settings.selectionAssistantPermissionStatus")) {
                        Text(permissionStatusTitle)
                            .foregroundStyle(permissionStatusColor)
                    }
                    Text(permissionStatusDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if permissionCoordinator.status != .allowed {
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
                        SettingsToggleRow(
                            label: L10n.string("settings.selectionAssistantActionChat"),
                            isOn: Bindable(settings).selectionActionBarShowsChatAction
                        )
                        SettingsToggleRow(
                            label: L10n.string("settings.selectionAssistantActionPrompts"),
                            isOn: Bindable(settings).selectionActionBarShowsPrompts
                        )
                        SettingsToggleRow(
                            label: L10n.string("settings.selectionAssistantActionExternalAsk"),
                            isOn: Bindable(settings).selectionActionBarShowsExternalAsk
                        )
                        SettingsToggleRow(
                            label: L10n.string("settings.selectionAssistantCollapseOverflow"),
                            isOn: Bindable(settings).selectionActionBarCollapseOverflow
                        )
                        Text(L10n.string("settings.selectionAssistantCollapseOverflowDescription"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        livePreviewStageCard
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
                                SelectionApplicationPicker(
                                    selectedIdentifiers: autoInvokeSelectedIdentifiers,
                                    labels: .autoInvoke,
                                    onChange: setAutoInvokeSelectedIdentifiers
                                )
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
            if settings.selectionAssistantEnabled {
                SettingsGroup(
                    title: L10n.string("settings.selectionAssistantClipboardAssisted"),
                    documentation: DocumentationLinks.url(for: .selectionAssistant, language: settings.language)
                ) {
                    Text(L10n.string("settings.selectionAssistantClipboardAssistedDescription"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    SettingsToggleRow(
                        label: L10n.string("settings.selectionAssistantClipboardAssistedEnabled"),
                        isOn: Bindable(settings).clipboardAssistedSelectionEnabled
                    )
                    if settings.clipboardAssistedSelectionEnabled {
                        SelectionApplicationPicker(
                            selectedIdentifiers: settings.clipboardAssistedSelectionAppIdentifiers,
                            labels: .clipboardAssisted,
                            onChange: { settings.clipboardAssistedSelectionAppIdentifiers = $0 }
                        )
                    }
                }
            }
        }
    }

    private var permissionStatusTitle: String {
        switch permissionCoordinator.status {
        case .allowed:
            L10n.string("settings.selectionAssistantPermissionAllowed")
        case .notAllowed:
            L10n.string("settings.selectionAssistantPermissionNotAllowed")
        case .needsReauthorization:
            L10n.string("settings.selectionAssistantPermissionNeedsReauthorization")
        }
    }

    private var showsActionBarCrowdingHint: Bool {
        !settings.selectionActionBarCollapseOverflow && (settings.selectionActionBarShowsChatAction ? 1 : 0) + settings.enabledPromptPresets.count + settings.enabledQuickActions.count > 4
    }

    /// A dedicated Live Preview stage card with centered immersive canvas.
    /// The Action Bar is dynamically rendered 1:1 using the actual AppKit HUD view,
    /// immediately reflecting toggle switches and ordering changes.
    private var livePreviewStageCard: some View {
        let content = SelectionActionBarContent.resolve(from: settings)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(L10n.string("settings.selectionAssistantActionBarLivePreview"), systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                    Text(L10n.string("settings.selectionAssistantActionBarLiveBadge"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.primary.opacity(0.04), in: Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                if content.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "cursorarrow.and.square.on.square.dashed")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                        Text(L10n.string("settings.selectionAssistantActionBarPreviewEmpty"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 26)
                } else {
                    SelectionActionBarPreview(layout: content.layout)
                        .frame(width: content.layout.size.width, height: content.layout.size.height)
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                        .padding(.vertical, 22)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 88)

            if content.layout.showsMoreButton {
                let overflowCount = content.layout.overflowPresets.count + content.layout.overflowExternalAsks.count
                HStack(spacing: 5) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.string("settings.selectionAssistantActionBarOverflowNote", overflowCount))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if showsActionBarCrowdingHint {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(L10n.string("settings.selectionAssistantActionBarCrowdingHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var autoInvokeSelectedIdentifiers: [String] {
        switch settings.selectionAutoInvokeScope {
        case .allApps: []
        case .blacklist: settings.selectionAutoInvokeBlacklist
        case .whitelist: settings.selectionAutoInvokeWhitelist
        }
    }

    private func setAutoInvokeSelectedIdentifiers(_ identifiers: [String]) {
        switch settings.selectionAutoInvokeScope {
        case .allApps: break
        case .blacklist: settings.selectionAutoInvokeBlacklist = identifiers
        case .whitelist: settings.selectionAutoInvokeWhitelist = identifiers
        }
    }

    private var permissionStatusDescription: String {
        switch permissionCoordinator.status {
        case .needsReauthorization:
            L10n.string("settings.selectionAssistantPermissionNeedsReauthorizationDescription")
        case .allowed, .notAllowed:
            L10n.string("settings.selectionAssistantPermissionDescription")
        }
    }

    private var permissionStatusColor: Color {
        switch permissionCoordinator.status {
        case .allowed:
            .green
        case .needsReauthorization:
            .orange
        case .notAllowed:
            .secondary
        }
    }
}

private struct SelectionApplicationOption: Identifiable, Hashable {
    let identifier: String
    let displayName: String

    var id: String { identifier }
}

private struct SelectionApplicationPickerLabels {
    let field: String
    let chooseApps: String
    let clear: String
    let refresh: String
    let selectedCount: (Int) -> String

    static var autoInvoke: Self {
        Self(
            field: L10n.string("settings.selectionAssistantAutoShowApps"),
            chooseApps: L10n.string("settings.selectionAssistantAutoShowChooseApps"),
            clear: L10n.string("settings.selectionAssistantAutoShowClear"),
            refresh: L10n.string("settings.selectionAssistantAutoShowRefresh"),
            selectedCount: { L10n.string("settings.selectionAssistantAutoShowSelectedCount", $0) }
        )
    }

    static var clipboardAssisted: Self {
        Self(
            field: L10n.string("settings.selectionAssistantClipboardAssistedApps"),
            chooseApps: L10n.string("settings.selectionAssistantClipboardAssistedChooseApps"),
            clear: L10n.string("settings.selectionAssistantClipboardAssistedClear"),
            refresh: L10n.string("settings.selectionAssistantClipboardAssistedRefresh"),
            selectedCount: { L10n.string("settings.selectionAssistantClipboardAssistedSelectedCount", $0) }
        )
    }
}

private struct SelectionApplicationPicker: View {
    let selectedIdentifiers: [String]
    let labels: SelectionApplicationPickerLabels
    let onChange: ([String]) -> Void

    @State private var applications: [SelectionApplicationOption] = []
    @State private var refreshToken = 0
    @State private var isPickerPresented = false
    @State private var searchText = ""

    var body: some View {
        SettingsFieldRow(label: labels.field) {
            HStack(spacing: 10) {
                Text(labels.selectedCount(selectedIdentifiers.count))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Button {
                    searchText = ""
                    refreshToken += 1
                    isPickerPresented = true
                } label: {
                    Label(labels.chooseApps, systemImage: "app.badge.checkmark")
                }
                .buttonStyle(.bordered)

                if !selectedIdentifiers.isEmpty {
                    Button(labels.clear) {
                        onChange([])
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    refreshToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(labels.refresh)
                .accessibilityLabel(labels.refresh)
            }
        }
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            SelectionApplicationSearchPopover(
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
        onChange(identifiers)
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

private struct SelectionApplicationSearchPopover: View {
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

/// Hosts the overlay's own AppKit content view in Settings. `actions: nil`
/// keeps the bar inert there: it looks and hovers exactly like the real one,
/// but pressing a preview button does nothing.
private struct SelectionActionBarPreview: NSViewRepresentable {
    let layout: SelectionActionBarLayout

    func makeNSView(context: Context) -> SelectionActionBarContentView {
        SelectionActionBarContentView(layout: layout, actions: nil)
    }

    func updateNSView(_ nsView: SelectionActionBarContentView, context: Context) {
        nsView.update(layout: layout, actions: nil)
    }
}

