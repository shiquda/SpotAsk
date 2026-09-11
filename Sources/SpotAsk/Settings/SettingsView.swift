import AppKit
import SwiftUI

enum SettingsSectionGroup: CaseIterable, Hashable, Identifiable {
    case core
    case automation
    case app

    var id: Self { self }

    var title: String {
        switch self {
        case .core: L10n.string("settings.groupCore")
        case .automation: L10n.string("settings.groupAutomation")
        case .app: L10n.string("settings.groupApp")
        }
    }
}

enum SettingsSection: CaseIterable, Hashable, Identifiable {
    case provider
    case prompts
    case externalAsk
    case selectionAssistant
    case shortcuts
    case general
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .provider: L10n.string("settings.provider")
        case .prompts: L10n.string("settings.prompts")
        case .externalAsk: L10n.string("settings.externalAsk")
        case .selectionAssistant: L10n.string("settings.selectionAssistant")
        case .shortcuts: L10n.string("settings.shortcuts")
        case .general: L10n.string("settings.general")
        case .appearance: L10n.string("settings.appearance")
        case .about: L10n.string("settings.about")
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .provider, .prompts, .externalAsk: .core
        case .selectionAssistant, .shortcuts: .automation
        case .general, .appearance, .about: .app
        }
    }

    /// Search terms describe the controls on each page, not just its title.
    /// The content index below supplies the group and field labels as well.
    var searchTerms: [String] {
        switch self {
        case .provider: ["service", "provider", "model", "models", "access key", "endpoint", "connection", "服务", "模型", "密钥", "地址"]
        case .prompts: ["prompt", "prompts", "instruction", "preset", "提示词", "指令"]
        case .externalAsk: ["external ask", "quick action", "web", "app", "terminal", "外部提问", "网页", "应用", "终端"]
        case .selectionAssistant: ["selection", "selected text", "accessibility", "application", "划词", "选中文字", "辅助功能", "应用"]
        case .shortcuts: ["shortcut", "keyboard", "command", "快捷键", "键盘"]
        case .general: ["behavior", "proxy", "diagnostics", "language", "launch", "window", "local data", "configuration", "行为", "代理", "诊断", "语言", "启动", "窗口", "数据", "配置"]
        case .appearance: ["appearance", "reading", "color", "font", "math", "style", "外观", "阅读", "颜色", "字体"]
        case .about: ["about", "version", "update", "documentation", "关于", "版本", "更新", "文档"]
        }
    }

    /// The settings window can be localized to Chinese or English while the
    /// query arrives in the other language, so the section filter carries the
    /// matching localized title in both languages. The content index below
    /// applies the same treatment to every group and field label.
    private var additionalSearchTitles: [String] {
        switch self {
        case .provider: ["服务设置", "Provider"]
        case .prompts: ["提示词", "Prompts"]
        case .externalAsk: ["外部提问", "External Ask"]
        case .selectionAssistant: ["划词助手", "Selection Assistant"]
        case .shortcuts: ["快捷键", "Shortcuts"]
        case .general: ["通用", "General"]
        case .appearance: ["外观", "Appearance"]
        case .about: ["关于", "About"]
        }
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return ([title, group.title] + searchTerms + additionalSearchTitles).contains { term in
            term.lowercased().contains(query)
        }
    }

    func moving(_ direction: SettingsSidebarNavigationDirection, within sections: [SettingsSection]) -> SettingsSection? {
        guard let index = sections.firstIndex(of: self) else { return nil }
        switch direction {
        case .up where index > sections.startIndex:
            return sections[sections.index(before: index)]
        case .down where index < sections.index(before: sections.endIndex):
            return sections[sections.index(after: index)]
        default:
            return nil
        }
    }

    var symbol: String {
        switch self {
        case .provider: "network"
        case .prompts: "text.badge.plus"
        case .externalAsk: "globe"
        case .selectionAssistant: "text.viewfinder"
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
        case .externalAsk: .blue
        case .selectionAssistant: .teal
        case .shortcuts: .orange
        case .general: .gray
        case .appearance: .indigo
        case .about: .purple
        }
    }

    /// LookAway-style icon tiles fade from a lighter tone at the top to a
    /// deeper tone at the bottom, which keeps the tiles vivid without reading
    /// as flat color blocks. Sections within one group stay in the same hue
    /// family so the sidebar reads as grouped gradients.
    var tintGradient: [Color] {
        switch self {
        case .provider: [Color(red: 0.45, green: 0.82, blue: 0.96), Color(red: 0.10, green: 0.55, blue: 0.78)]
        case .prompts: [Color(red: 0.45, green: 0.90, blue: 0.72), Color(red: 0.08, green: 0.62, blue: 0.45)]
        case .externalAsk: [Color(red: 0.48, green: 0.72, blue: 1.00), Color(red: 0.12, green: 0.42, blue: 0.92)]
        case .selectionAssistant: [Color(red: 0.40, green: 0.88, blue: 0.82), Color(red: 0.05, green: 0.60, blue: 0.60)]
        case .shortcuts: [Color(red: 1.00, green: 0.72, blue: 0.40), Color(red: 0.90, green: 0.45, blue: 0.10)]
        case .general: [Color(red: 0.72, green: 0.72, blue: 0.76), Color(red: 0.42, green: 0.42, blue: 0.48)]
        case .appearance: [Color(red: 0.68, green: 0.62, blue: 1.00), Color(red: 0.42, green: 0.32, blue: 0.88)]
        case .about: [Color(red: 0.82, green: 0.58, blue: 1.00), Color(red: 0.58, green: 0.25, blue: 0.85)]
        }
    }
}

struct SettingsGroupTarget: Hashable {
    let section: SettingsSection
    let anchor: String
}

struct SettingsSearchResult: Identifiable, Hashable {
    let target: SettingsGroupTarget
    let title: String
    let sectionTitle: String
    let matchPriority: Int

    var id: SettingsGroupTarget { target }
}

enum SettingsSearchIndex {
    private struct Entry {
        let section: SettingsSection
        let titleKey: String
        let labelKeys: [String]
    }

    // Keep this list beside the settings pages: labels are localization keys,
    // so search follows the language currently shown by the settings window.
    // Only groups that always render on their page belong here — conditional
    // groups such as the model detail form (no model selected by default) must
    // not be exposed, or a result click would scroll to nothing.
    private static let entries: [Entry] = [
        Entry(section: .provider, titleKey: "settings.providerInfo", labelKeys: ["settings.providerName", "settings.providerFormat", "settings.serviceAddress", "settings.addressMode", "settings.responseTimeout"]),
        Entry(section: .provider, titleKey: "settings.accessKey", labelKeys: ["settings.accessKey"]),
        Entry(section: .provider, titleKey: "settings.availableModels", labelKeys: ["settings.modelRefreshDescription"]),
        Entry(section: .prompts, titleKey: "settings.savedPrompts", labelKeys: ["settings.promptCatalogDescription"]),
        Entry(section: .prompts, titleKey: "settings.customInstruction", labelKeys: ["settings.customInstruction"]),
        Entry(section: .externalAsk, titleKey: "settings.externalAsk", labelKeys: ["settings.externalAskEnabled", "settings.promptCatalogDescription"]),
        Entry(section: .selectionAssistant, titleKey: "settings.selectionAssistant", labelKeys: ["settings.selectionAssistantEnabled", "settings.selectionAssistantPermissionStatus", "settings.selectionAssistantMode", "settings.selectionAssistantAutoShow", "settings.selectionAssistantActionLabels", "settings.selectionAssistantActionPrompts", "settings.selectionAssistantActionExternalAsk", "settings.selectionAssistantAutoShowScope", "settings.selectionAssistantAutoShowDelay", "settings.selectionAssistantDefaultAction", "settings.selectionAssistantAutoShowApps"]),
        Entry(section: .shortcuts, titleKey: "settings.shortcutActions", labelKeys: ["settings.selectionAssistantToggleShortcut"]),
        Entry(section: .shortcuts, titleKey: "settings.shortcutPrompts", labelKeys: ["settings.promptCatalogDescription"]),
        Entry(section: .shortcuts, titleKey: "settings.externalAsk", labelKeys: ["settings.externalAsk"]),
        Entry(section: .general, titleKey: "settings.language", labelKeys: ["settings.language"]),
        Entry(section: .general, titleKey: "settings.behavior", labelKeys: ["settings.globalShortcut", "settings.launchAtLogin", "settings.silentLaunch", "settings.showMenuBarIcon", "settings.restoreSession", "settings.clearInputOnClose", "settings.confirmBeforeStartingNewConversation", "settings.escapeStartsNewConversation", "settings.defaultExpandReasoning", "settings.windowOnTop", "settings.contextLimit"]),
        Entry(section: .general, titleKey: "settings.proxy", labelKeys: ["settings.proxyEnabled", "settings.proxyType", "settings.proxyHost", "settings.proxyPort", "settings.proxyUsername", "settings.proxyPassword"]),
        Entry(section: .general, titleKey: "settings.diagnostics", labelKeys: ["settings.diagnosticsEnabled"]),
        Entry(section: .general, titleKey: "settings.localData", labelKeys: ["settings.localDataDescription"]),
        Entry(section: .general, titleKey: "settings.configuration", labelKeys: ["settings.configurationDescription"]),
        Entry(section: .appearance, titleKey: "settings.reading", labelKeys: ["settings.appearance", "settings.chatMessageStyle", "settings.renderMath", "settings.fontSize"]),
        Entry(section: .about, titleKey: "SpotAsk", labelKeys: ["settings.version", "settings.source", "settings.userGuide"]),
        Entry(section: .about, titleKey: "settings.updates", labelKeys: ["settings.autoCheckForUpdates", "settings.checkForUpdates"])
    ]

    /// Settings can be displayed in Chinese or English while the query arrives
    /// in the other language, so titles and labels are matched against the
    /// current UI language plus both fallback locales.
    private static let searchableLanguages: [AppLanguage] = [.simplifiedChinese, .english]

    static func results(
        for searchText: String,
        include: ((SettingsSection, String) -> Bool)? = nil
    ) -> [SettingsSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        let currentLanguage = AppLanguage.current
        let languages = ([currentLanguage] + searchableLanguages).reduce(into: [AppLanguage]()) { list, language in
            if !list.contains(language) { list.append(language) }
        }
        let rankedResults: [(offset: Int, result: SettingsSearchResult)] = entries.enumerated().compactMap { offset, entry in
            let title = entry.titleKey == "SpotAsk" ? "SpotAsk" : L10n.string(entry.titleKey)
            guard include?(entry.section, title) ?? true else { return nil }
            let sectionTitle = entry.section.title
            let titleCandidates = Set(
                languages.map { (entry.titleKey == "SpotAsk" ? "SpotAsk" : L10n.string(entry.titleKey, language: $0)).lowercased() }
            )
            let descriptionCandidates = Set(
                languages.flatMap { language in entry.labelKeys.map { L10n.string($0, language: language).lowercased() } }
            )
            let matchPriority: Int
            if titleCandidates.contains(where: { $0.contains(query) }) {
                matchPriority = 0
            } else if sectionTitle.lowercased().contains(query) {
                matchPriority = 1
            } else if descriptionCandidates.contains(where: { $0.contains(query) }) {
                matchPriority = 2
            } else {
                return nil
            }
            let result = SettingsSearchResult(
                target: SettingsGroupTarget(section: entry.section, anchor: title),
                title: title,
                sectionTitle: sectionTitle,
                matchPriority: matchPriority
            )
            return (offset, result)
        }
        return rankedResults
            .sorted { lhs, rhs in
                if lhs.result.matchPriority != rhs.result.matchPriority {
                    return lhs.result.matchPriority < rhs.result.matchPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.result)
    }
}


struct SettingsView: View {
    let settings: AppSettings
    let accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator
    private let accessibilitySettingsOpener: any AccessibilityPermissionSettingsOpening

    private let settingsWindowProvider: (() -> NSWindow?)?
    @State private var selectedSection: SettingsSection = .provider
    @State private var providerState: ProviderSettingsState
    @State private var generalState: GeneralSettingsState
    @State private var updateState = AppUpdateState()
    @State private var searchText = ""
    @State private var pendingGroupTarget: SettingsGroupTarget?

    private var searchResults: [SettingsSearchResult] {
        SettingsSearchIndex.results(for: searchText, include: isSearchResultReachable)
    }

    private var visibleSections: [SettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(SettingsSection.allCases) }

        // The sidebar section filter and the content index must agree. A field
        // label can match even when it is not listed in section.searchTerms;
        // keep that result's destination visible so cross-section navigation
        // cannot fall back to the first unrelated page.
        let indexedSections = searchResults.map(\.target.section)
        let sections = SettingsSection.allCases.filter {
            $0.matches(searchText: query) || indexedSections.contains($0)
        }
        return sections
    }

    private var resolvedSelection: SettingsSection {
        guard visibleSections.contains(selectedSection) else {
            return visibleSections.first ?? selectedSection
        }
        return selectedSection
    }

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator = AccessibilityPermissionCoordinator(),
        accessibilitySettingsOpener: any AccessibilityPermissionSettingsOpening = MacOSAccessibilityPermissionSettingsOpener(),
        initialSection: SettingsSection = .provider,
        settingsWindowProvider: (() -> NSWindow?)? = nil
    ) {
        self.settings = settings
        self.accessibilityPermissionCoordinator = accessibilityPermissionCoordinator
        self.accessibilitySettingsOpener = accessibilitySettingsOpener
        self.settingsWindowProvider = settingsWindowProvider
        _selectedSection = State(initialValue: initialSection)
        let providerState = ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: providerFactory
        )
        _providerState = State(initialValue: providerState)
        _generalState = State(initialValue: GeneralSettingsState(
            settings: settings,
            keyStore: keyStore,
            settingsWindowProvider: settingsWindowProvider,
            onConfigurationImported: { providerState.reloadCatalogSelection() }
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: $selectedSection,
                searchText: $searchText,
                settings: settings,
                visibleSections: visibleSections,
                searchResults: searchResults,
                onSelectResult: { result in
                    selectedSection = result.target.section
                    pendingGroupTarget = result.target
                }
            )
            Divider()
            Group {
                switch resolvedSelection {
                case .provider:
                    ProviderSettingsPage(
                        settings: settings,
                        state: providerState,
                        searchTarget: pendingGroupTarget,
                        onSearchTargetConsumed: { pendingGroupTarget = nil }
                    )
                case .prompts:
                    SettingsPageScrollView(
                        section: .prompts,
                        pendingTarget: $pendingGroupTarget
                    ) {
                        PromptPresetsSettingsPage(settings: settings)
                    }
                case .externalAsk:
                    SettingsPageScrollView(
                        section: .externalAsk,
                        pendingTarget: $pendingGroupTarget
                    ) {
                        ExternalAskSettingsPage(settings: settings)
                    }
                case .selectionAssistant:
                    SettingsPageScrollView(
                        section: .selectionAssistant,
                        pendingTarget: $pendingGroupTarget
                    ) {
                        SelectionAssistantSettingsPage(
                            settings: settings,
                            permissionCoordinator: accessibilityPermissionCoordinator,
                            settingsOpener: accessibilitySettingsOpener,
                            onOpenShortcuts: { selectedSection = .shortcuts }
                        )
                    }
                case .shortcuts:
                    SettingsPageScrollView(
                        section: .shortcuts,
                        pendingTarget: $pendingGroupTarget
                    ) {
                        ShortcutSettingsPage(settings: settings)
                    }
                case .general:
                    SettingsPageScrollView(
                        section: .general,
                        pendingTarget: $pendingGroupTarget
                    ) {
                        GeneralSettingsPage(settings: settings, generalState: generalState)
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
        .environment(\.dynamicTypeSize, settings.interfaceZoomLevel.dynamicTypeSize)
        .overlay(alignment: .topTrailing) {
            StatusToastOverlay()
                .padding(.top, 36)
        }
    }

    /// The available-models group only renders when the selected provider
    /// supports model refresh; everything else in the index always renders on
    /// its page, so every exposed result can actually scroll somewhere.
    private func isSearchResultReachable(section: SettingsSection, anchor: String) -> Bool {
        if section == .provider, anchor == L10n.string("settings.availableModels") {
            return providerState.selectedProviderSupportsModelRefresh
        }
        return true
    }
}

private struct SettingsPageScrollView<Content: View>: View {
    let section: SettingsSection
    @Binding var pendingTarget: SettingsGroupTarget?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onAppear {
                scrollIfNeeded(using: proxy)
            }
            .onChange(of: pendingTarget) { _, _ in
                scrollIfNeeded(using: proxy)
            }
        }
        .id(section)
    }

    private func scrollIfNeeded(using proxy: ScrollViewProxy) {
        guard let target = pendingTarget, target.section == section else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(target.anchor, anchor: .top)
            pendingTarget = nil
        }
    }
}

