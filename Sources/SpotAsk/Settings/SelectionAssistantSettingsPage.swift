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
                        SelectionActionBarLivePreviewCard(settings: settings)
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
    /// Uses `SelectionActionBarLivePreviewCard` for rich interactive drag-and-drop customization.
    private var livePreviewStageCard: some View {
        SelectionActionBarLivePreviewCard(settings: settings)
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

/// Interactive Live Preview Stage Card that allows users to:
/// 1. Drag and drop primary items to reorder them in the Action Bar.
/// 2. Drag items onto '···' to fold into the secondary menu.
/// 3. Click '···' to expand the secondary menu dropdown.
/// 4. Drag or click items in the expanded secondary menu to return them to the Action Bar.
/// 5. Display auxiliary instruction text explaining the drag-and-drop capability.
struct SelectionActionBarLivePreviewCard: View {
    @Bindable var settings: AppSettings
    @State private var isSecondaryMenuExpanded = false
    @State private var draggingItemID: String? = nil
    @State private var dragCurrentTranslation: CGSize = .zero
    @State private var dragStartIndex: Int? = nil
    @State private var currentDropTargetIndex: Int? = nil
    @State private var isDraggingToSecondary = false
    @State private var isOverMoreButton = false
    @State private var hoveredItemID: String? = nil
    @State private var hoveredSecondaryID: String? = nil

    @State private var draggingSecondaryItemID: String? = nil
    @State private var secondaryDragTranslation: CGSize = .zero
    @State private var isDraggingToPrimary = false

    private var content: SelectionActionBarContent {
        SelectionActionBarContent.resolve(from: settings)
    }

    private var isCustomized: Bool {
        settings.selectionActionBarCustomized
    }

    private var showsActionBarCrowdingHint: Bool {
        !settings.selectionActionBarCollapseOverflow && content.primaryItems.count > 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            canvasArea
            footerHints
        }
        .padding(14)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Label(L10n.string("settings.selectionAssistantActionBarLivePreview"), systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if isCustomized {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        settings.resetActionBarCustomization()
                        isSecondaryMenuExpanded = false
                    }
                } label: {
                    Text(L10n.string("settings.selectionAssistantResetOrder"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }

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
    }

    private var canvasArea: some View {
        ZStack(alignment: .top) {
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
                VStack(spacing: 8) {
                    actionBarPill
                        .padding(.top, 20)
                        .padding(.bottom, isSecondaryMenuExpanded ? 4 : 20)
                        .padding(.horizontal, 16)

                    if isSecondaryMenuExpanded {
                        secondaryMenuDropdown
                            .padding(.bottom, 16)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                            ))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 88)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isSecondaryMenuExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: content.primaryItems.map(\.id))
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: content.secondaryItems.map(\.id))
    }

    private var actionBarPill: some View {
        HStack(spacing: 2) {
            ForEach(Array(content.primaryItems.enumerated()), id: \.element.id) { index, item in
                primaryItemView(item: item, index: index)
            }

            if content.layout.showsMoreButton || settings.selectionActionBarCollapseOverflow {
                moreButtonView
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDraggingToPrimary ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDraggingToPrimary ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isDraggingToPrimary ? 1.5 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private func siblingShiftOffset(for index: Int) -> CGFloat {
        guard let draggingID = draggingItemID,
              let startIndex = dragStartIndex,
              let targetIndex = currentDropTargetIndex,
              !isDraggingToSecondary,
              index < content.primaryItems.count,
              draggingID != content.primaryItems[index].id else {
            return 0
        }
        let itemWidth: CGFloat = (content.showsLabels) ? 60 : 32
        if startIndex < targetIndex {
            if index > startIndex && index <= targetIndex {
                return -itemWidth
            }
        } else if startIndex > targetIndex {
            if index >= targetIndex && index < startIndex {
                return itemWidth
            }
        }
        return 0
    }

    private func primaryItemView(item: SelectionActionBarItem, index: Int) -> some View {
        let isDragging = draggingItemID == item.id
        let isHovered = hoveredItemID == item.id
        let horizontalShift = siblingShiftOffset(for: index)

        return HStack(spacing: 5) {
            ProviderBrandIconView(
                slug: item.brandSlug,
                size: content.showsLabels ? 13 : 15,
                fallbackSymbol: item.symbolName
            )

            if content.showsLabels && !item.isChat {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }

            if isDragging && isDraggingToSecondary {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, (content.showsLabels && !item.isChat) ? 8 : 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDragging ? (isDraggingToSecondary ? Color.accentColor.opacity(0.25) : Color.accentColor.opacity(0.18)) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isDragging ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .offset(
            x: isDragging ? dragCurrentTranslation.width : horizontalShift,
            y: isDragging ? dragCurrentTranslation.height : 0
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: horizontalShift)
        .scaleEffect(isDragging ? 1.08 : 1.0)
        .shadow(color: isDragging ? Color.black.opacity(0.2) : Color.clear, radius: 6, x: 0, y: 3)
        .zIndex(isDragging ? 100 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredItemID = isHovered ? item.id : nil
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragStartIndex == nil {
                        dragStartIndex = index
                        currentDropTargetIndex = index
                    }
                    draggingItemID = item.id
                    dragCurrentTranslation = value.translation

                    let itemWidth: CGFloat = (content.showsLabels && !item.isChat) ? 60 : 32
                    let remainingItemsToRight = max(0, (content.primaryItems.count - 1) - index)
                    let distanceToMoreButton = CGFloat(remainingItemsToRight) * itemWidth + 28

                    let isDownward = value.translation.height > 24
                    let isRightwardToMore = (content.layout.showsMoreButton || settings.selectionActionBarCollapseOverflow)
                        && value.translation.width > distanceToMoreButton && abs(value.translation.height) < 24

                    if settings.selectionActionBarCollapseOverflow && (isDownward || isRightwardToMore) {
                        isDraggingToSecondary = true
                        isOverMoreButton = isRightwardToMore
                        currentDropTargetIndex = nil
                        if !isSecondaryMenuExpanded && value.translation.height > 20 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSecondaryMenuExpanded = true
                            }
                        }
                    } else {
                        isDraggingToSecondary = false
                        isOverMoreButton = false

                        guard let startIndex = dragStartIndex else { return }
                        let threshold = itemWidth * 0.45
                        let dragX = value.translation.width
                        let shift: Int
                        if dragX > threshold {
                            shift = Int((dragX - threshold) / itemWidth) + 1
                        } else if dragX < -threshold {
                            shift = -Int((-dragX - threshold) / itemWidth) - 1
                        } else {
                            shift = 0
                        }
                        let target = min(max(0, startIndex + shift), content.primaryItems.count - 1)
                        if target != currentDropTargetIndex {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                currentDropTargetIndex = target
                            }
                        }
                    }
                }
                .onEnded { value in
                    if isDraggingToSecondary {
                        settings.moveActionBarItemToSecondary(id: item.id)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSecondaryMenuExpanded = true
                        }
                    } else if let target = currentDropTargetIndex, let start = dragStartIndex, target != start {
                        settings.reorderActionBarItem(id: item.id, toIndex: target)
                    }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        draggingItemID = nil
                        dragCurrentTranslation = .zero
                        dragStartIndex = nil
                        currentDropTargetIndex = nil
                        isDraggingToSecondary = false
                        isOverMoreButton = false
                    }
                }
        )
        .contextMenu {
            if settings.selectionActionBarCollapseOverflow {
                Button {
                    settings.moveActionBarItemToSecondary(id: item.id)
                    withAnimation {
                        isSecondaryMenuExpanded = true
                    }
                } label: {
                    Label(L10n.string("settings.selectionAssistantMoveToSecondaryMenu"), systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }
            if index > 0 {
                Button {
                    settings.reorderActionBarItem(id: item.id, toIndex: index - 1)
                } label: {
                    Label(L10n.string("settings.moveUp"), systemImage: "arrow.left")
                }
            }
            if index < content.primaryItems.count - 1 {
                Button {
                    settings.reorderActionBarItem(id: item.id, toIndex: index + 1)
                } label: {
                    Label(L10n.string("settings.moveDown"), systemImage: "arrow.right")
                }
            }
        }
    }

    private var moreButtonView: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isSecondaryMenuExpanded.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)

                if !content.secondaryItems.isEmpty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .padding(3)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOverMoreButton ? Color.accentColor.opacity(0.25) : (isSecondaryMenuExpanded ? Color.primary.opacity(0.12) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isOverMoreButton ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(L10n.string("selection.actionBar.more"))
    }

    private var secondaryMenuDropdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.string("settings.selectionAssistantSecondaryMenuTitle"), systemImage: "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation {
                        isSecondaryMenuExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)

            Divider()
                .padding(.horizontal, 8)

            if isDraggingToSecondary {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.string("settings.selectionAssistantDropToSecondaryHint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
            }

            if content.secondaryItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(L10n.string("settings.selectionAssistantSecondaryMenuEmpty"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 3) {
                    ForEach(content.secondaryItems) { item in
                        secondaryItemRow(item: item)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDraggingToSecondary ? Color.accentColor.opacity(0.06) : Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isDraggingToSecondary ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isDraggingToSecondary ? 1.5 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
    }

    private func secondaryItemRow(item: SelectionActionBarItem) -> some View {
        let isHovered = hoveredSecondaryID == item.id
        let isDraggingThis = draggingSecondaryItemID == item.id

        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            ProviderBrandIconView(
                slug: item.brandSlug,
                size: 13,
                fallbackSymbol: item.symbolName
            )

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation {
                    settings.moveActionBarItemToPrimary(id: item.id)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 11))
                    Text(L10n.string("settings.selectionAssistantMoveToActionBar"))
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDraggingThis ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isDraggingThis ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .offset(isDraggingThis ? secondaryDragTranslation : .zero)
        .scaleEffect(isDraggingThis ? 1.05 : 1.0)
        .zIndex(isDraggingThis ? 100 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredSecondaryID = isHovered ? item.id : nil
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    draggingSecondaryItemID = item.id
                    secondaryDragTranslation = value.translation
                    if value.translation.height < -24 {
                        isDraggingToPrimary = true
                    } else {
                        isDraggingToPrimary = false
                    }
                }
                .onEnded { value in
                    if isDraggingToPrimary || value.translation.height < -24 {
                        settings.moveActionBarItemToPrimary(id: item.id)
                    }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        draggingSecondaryItemID = nil
                        secondaryDragTranslation = .zero
                        isDraggingToPrimary = false
                    }
                }
        )
        .contextMenu {
            Button {
                settings.moveActionBarItemToPrimary(id: item.id)
            } label: {
                Label(L10n.string("settings.selectionAssistantMoveToActionBar"), systemImage: "arrow.up.circle")
            }
        }
    }
    private var footerHints: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(settings.selectionActionBarCollapseOverflow
                     ? L10n.string("settings.selectionAssistantActionBarDragHintWithOverflow")
                     : L10n.string("settings.selectionAssistantActionBarDragHintNoOverflow"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if showsActionBarCrowdingHint {
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
    }
}

