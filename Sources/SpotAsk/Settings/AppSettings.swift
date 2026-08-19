import Observation
import AppKit
import Foundation
import SwiftUI

extension Notification.Name {
    static let spotAskMenuBarIconVisibilityChanged = Notification.Name("com.spotask.menu-bar-icon-visibility-changed")
    static let spotAskAppearanceChanged = Notification.Name("com.spotask.appearance-changed")
    static let spotAskSelectionAssistantChanged = Notification.Name("com.spotask.selection-assistant-changed")
}

struct PromptPreset: Identifiable, Codable, Equatable, Sendable {
    static let defaultSymbolName: String = "sparkles"

    let id: UUID
    var title: String
    var instruction: String
    var customSymbolName: String?
    let isBuiltIn: Bool
    var isEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case instruction
        case customSymbolName
        case isBuiltIn
        case isEnabled
    }

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        customSymbolName: String? = nil,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.customSymbolName = isBuiltIn ? nil : (Self.isValidSymbol(customSymbolName) ? customSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        instruction = try container.decode(String.self, forKey: .instruction)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        let rawSymbol = try container.decodeIfPresent(String.self, forKey: .customSymbolName)
        customSymbolName = isBuiltIn ? nil : (Self.isValidSymbol(rawSymbol) ? rawSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        // Prompt presets saved before the catalog always remain enabled.
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    static var builtIn: [PromptPreset] {
        [
        PromptPreset(
            id: UUID(uuidString: "EF8CF35C-386A-4389-A137-C207E4DB11FD")!,
            title: L10n.string("preset.translate.title"),
            instruction: L10n.string("preset.translate.instruction"),
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248")!,
            title: L10n.string("preset.explain.title"),
            instruction: L10n.string("preset.explain.instruction"),
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2")!,
            title: L10n.string("preset.summarize.title"),
            instruction: L10n.string("preset.summarize.instruction"),
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "1C85A324-65B3-4EBD-B2C4-0C6B072E284A")!,
            title: L10n.string("preset.polish.title"),
            instruction: L10n.string("preset.polish.instruction"),
            isBuiltIn: true
        )
        ]
    }

    /// The visual identity used when this prompt is applied. Built-ins return
    /// their fixed symbols, while custom prompts use customSymbolName if valid,
    /// falling back to the default "sparkles" symbol.
    var symbolName: String {
        switch id.uuidString.uppercased() {
        case "EF8CF35C-386A-4389-A137-C207E4DB11FD": return "character.bubble"
        case "1C85A324-65B3-4EBD-B2C4-0C6B072E284A": return "pencil.and.scribble"
        case "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2": return "list.bullet.rectangle"
        case "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248": return "doc.text.magnifyingglass"
        default:
            if let customSymbolName, Self.isValidSymbol(customSymbolName) {
                return customSymbolName
            }
            return Self.defaultSymbolName
        }
    }

    static func isValidSymbol(_ symbolName: String?) -> Bool {
        guard let symbolName = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines), !symbolName.isEmpty else {
            return false
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    }
}

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionSpace
    case controlSpace
    case commandShiftSpace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .optionSpace: "Option + Space"
        case .controlSpace: "Control + Space"
        case .commandShiftSpace: "Command + Shift + Space"
        }
    }
}

enum SelectionAssistantMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case direct
    case actionBar

    var id: String { rawValue }
}

enum SelectionAutoInvokeScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case allApps
    case blacklist
    case whitelist

    var id: String { rawValue }
}

enum SelectionAutoInvokeDelay {
    static let minimum: Double = 0
    static let maximum: Double = 3
    static let step: Double = 0.05
    static let defaultValue: Double = 0.8

    static func normalized(_ value: Double) -> Double {
        let clamped = min(max(value, minimum), maximum)
        return (clamped / step).rounded() * step
    }
}

enum SelectionHotKeyPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case optionShiftSpace

    var id: String { rawValue }
    var title: String { "Option + Shift + Space" }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// The matching SwiftUI override. `nil` deliberately inherits the system
    /// appearance instead of pinning a view to the current system value.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The matching AppKit override for independently hosted windows.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply(to window: NSWindow) {
        window.appearance = nsAppearance
    }
}

enum FontSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    var id: String { rawValue }
}

enum ChatMessageStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case im

    var id: String { rawValue }
}

enum InterfaceZoomLevel: String, CaseIterable, Identifiable {
    case compact
    case standard
    case comfortable
    case large

    var id: String { rawValue }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact: .small
        case .standard: .large
        case .comfortable: .xLarge
        case .large: .xxLarge
        }
    }

    var displayScale: CGFloat {
        switch self {
        case .compact: 0.9
        case .standard: 1
        case .comfortable: 1.15
        case .large: 1.3
        }
    }

    static func adjusted(from current: InterfaceZoomLevel, by delta: Int) -> InterfaceZoomLevel {
        let levels = allCases
        let currentIndex = levels.firstIndex(of: current) ?? 1
        let targetIndex = min(max(currentIndex + delta, 0), levels.count - 1)
        return levels[targetIndex]
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case spanish = "es"
    case german = "de"
    case japanese = "ja"
    case french = "fr"
    case portuguese = "pt"
    case russian = "ru"

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    /// The language's name written in that language, so the language picker
    /// reads the same regardless of the current UI language.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .spanish: "Español"
        case .german: "Deutsch"
        case .japanese: "日本語"
        case .french: "Français"
        case .portuguese: "Português"
        case .russian: "Русский"
        }
    }

    var locale: Locale {
        guard self != .system else { return .current }
        return Locale(identifier: rawValue)
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }
}

enum ProxyType: String, CaseIterable, Identifiable, Codable, Sendable {
    case http
    case socks5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: L10n.string("settings.proxyTypeHTTP")
        case .socks5: L10n.string("settings.proxyTypeSOCKS5")
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let baseURL = "baseURL"
        static let useFullEndpoint = "useFullEndpoint"
        static let model = "model"
        static let systemPrompt = "systemPrompt"
        static let streaming = "streaming"
        static let timeout = "timeout"
        static let contextLimit = "contextLimit"
        static let retainSession = "retainSession"
        static let clearInputOnClose = "clearInputOnClose"
        static let confirmBeforeStartingNewConversation = "confirmBeforeStartingNewConversation"
        static let escapeStartsNewConversation = "escapeStartsNewConversation"
        static let defaultExpandReasoning = "defaultExpandReasoning"
        static let renderMath = "renderMath"
        static let launchAtLogin = "launchAtLogin"
        static let silentLaunch = "silentLaunch"
        static let proxyEnabled = "proxyEnabled"
        static let proxyType = "proxyType"
        static let proxyHost = "proxyHost"
        static let proxyPort = "proxyPort"
        static let proxyUsername = "proxyUsername"
        static let diagnosticsEnabled = "diagnosticsEnabled"
        static let appearance = "appearance"
        static let fontSize = "fontSize"
        static let chatMessageStyle = "chatMessageStyle"
        static let interfaceZoomLevel = "interfaceZoomLevel"
        static let language = AppLanguage.defaultsKey
        static let hotKeyPreset = "hotKeyPreset"
        static let globalShortcut = "globalShortcut"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let panelOriginX = "panelOriginX"
        static let panelOriginY = "panelOriginY"
        static let keepWindowOnTop = "keepWindowOnTop"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let customPromptPresets = "customPromptPresets"
        static let promptPresetCatalog = "promptPresetCatalog"
        static let inAppShortcutConfiguration = "inAppShortcutConfiguration"
        static let selectionAssistantEnabled = "selectionAssistantEnabled"
        static let selectionAssistantMode = "selectionAssistantMode"
        static let selectionHotKeyPreset = "selectionHotKeyPreset"
        static let selectionDefaultPromptID = "selectionDefaultPromptID"
        static let selectionAssistantToggleShortcut = "selectionAssistantToggleShortcut"
        static let selectionAutoInvokeEnabled = "selectionAutoInvokeEnabled"
        static let selectionAutoInvokeDelay = "selectionAutoInvokeDelay"
        static let selectionAutoInvokeScope = "selectionAutoInvokeScope"
        static let selectionAutoInvokeBlacklist = "selectionAutoInvokeBlacklist"
        static let selectionAutoInvokeWhitelist = "selectionAutoInvokeWhitelist"
        static let selectionActionBarShowsLabels = "selectionActionBarShowsLabels"
        static let automaticUpdateCheckEnabled = "automaticUpdateCheckEnabled"
        static let quickActionCatalog = "webQuickAskProviderCatalog"
        static let externalAskEnabled = "webQuickAskEnabled"
    }

    private let defaults: UserDefaults
    private var inAppShortcutConfiguration: InAppShortcutConfiguration
    private var providerRegistryStorage: ProviderModelRegistry!
    var providerRegistry: ProviderModelRegistry { providerRegistryStorage }
    var catalogLoadError: ProviderModelCatalogLoadError? { providerRegistry.loadError }
    var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) } }
    var contextLimit: Int { didSet { defaults.set(contextLimit, forKey: Key.contextLimit) } }
    var retainSession: Bool { didSet { defaults.set(retainSession, forKey: Key.retainSession) } }
    var clearInputOnClose: Bool { didSet { defaults.set(clearInputOnClose, forKey: Key.clearInputOnClose) } }
    var confirmBeforeStartingNewConversation: Bool {
        didSet { defaults.set(confirmBeforeStartingNewConversation, forKey: Key.confirmBeforeStartingNewConversation) }
    }
    var escapeStartsNewConversation: Bool {
        didSet { defaults.set(escapeStartsNewConversation, forKey: Key.escapeStartsNewConversation) }
    }
    var defaultExpandReasoning: Bool {
        didSet { defaults.set(defaultExpandReasoning, forKey: Key.defaultExpandReasoning) }
    }
    var renderMath: Bool { didSet { defaults.set(renderMath, forKey: Key.renderMath) } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    var silentLaunch: Bool { didSet { defaults.set(silentLaunch, forKey: Key.silentLaunch) } }
    var proxyEnabled: Bool { didSet { defaults.set(proxyEnabled, forKey: Key.proxyEnabled) } }
    var proxyType: ProxyType { didSet { defaults.set(proxyType.rawValue, forKey: Key.proxyType) } }
    var proxyHost: String { didSet { defaults.set(proxyHost, forKey: Key.proxyHost) } }
    var proxyPort: Int { didSet { defaults.set(proxyPort, forKey: Key.proxyPort) } }
    var proxyUsername: String { didSet { defaults.set(proxyUsername, forKey: Key.proxyUsername) } }
    var diagnosticsEnabled: Bool {
        didSet {
            defaults.set(diagnosticsEnabled, forKey: Key.diagnosticsEnabled)
            DiagnosticLogStore.shared.setEnabled(diagnosticsEnabled)
        }
    }
    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            NotificationCenter.default.post(name: .spotAskAppearanceChanged, object: self)
        }
    }
    var fontSize: FontSize { didSet { defaults.set(fontSize.rawValue, forKey: Key.fontSize) } }
    var chatMessageStyle: ChatMessageStyle { didSet { defaults.set(chatMessageStyle.rawValue, forKey: Key.chatMessageStyle) } }
    var interfaceZoomLevel: InterfaceZoomLevel {
        didSet { defaults.set(interfaceZoomLevel.rawValue, forKey: Key.interfaceZoomLevel) }
    }
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            NotificationCenter.default.post(name: .spotAskLanguageChanged, object: nil)
        }
    }
    var hotKeyPreset: HotKeyPreset { didSet { defaults.set(hotKeyPreset.rawValue, forKey: Key.hotKeyPreset) } }
    var globalShortcut: InAppShortcut? {
        didSet {
            if let globalShortcut,
               let data = try? JSONEncoder().encode(globalShortcut) {
                defaults.set(data, forKey: Key.globalShortcut)
            } else {
                defaults.removeObject(forKey: Key.globalShortcut)
            }
            NotificationCenter.default.post(name: .spotAskHotKeyChanged, object: nil)
        }
    }
    var selectionAssistantEnabled: Bool {
        didSet {
            defaults.set(selectionAssistantEnabled, forKey: Key.selectionAssistantEnabled)
            NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
        }
    }
    var selectionAssistantMode: SelectionAssistantMode { didSet { defaults.set(selectionAssistantMode.rawValue, forKey: Key.selectionAssistantMode) } }
    var selectionHotKeyPreset: SelectionHotKeyPreset { didSet { defaults.set(selectionHotKeyPreset.rawValue, forKey: Key.selectionHotKeyPreset) } }
    var selectionDefaultPromptID: UUID? {
        didSet {
            if let selectionDefaultPromptID { defaults.set(selectionDefaultPromptID.uuidString, forKey: Key.selectionDefaultPromptID) }
            else { defaults.removeObject(forKey: Key.selectionDefaultPromptID) }
        }
    }
    var selectionAssistantToggleShortcut: InAppShortcut? {
        didSet {
            if let selectionAssistantToggleShortcut,
               let data = try? JSONEncoder().encode(selectionAssistantToggleShortcut) {
                defaults.set(data, forKey: Key.selectionAssistantToggleShortcut)
            } else {
                defaults.removeObject(forKey: Key.selectionAssistantToggleShortcut)
            }
            NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
        }
    }
    var selectionActionBarShowsLabels: Bool { didSet { defaults.set(selectionActionBarShowsLabels, forKey: Key.selectionActionBarShowsLabels) } }
    var automaticUpdateCheckEnabled: Bool {
        didSet { defaults.set(automaticUpdateCheckEnabled, forKey: Key.automaticUpdateCheckEnabled) }
    }
    /// Whether a cross-app selection automatically shows the quick actions after
    /// `selectionAutoInvokeDelay` seconds. Defaults off so granting high-impact
    /// accessibility access remains an explicit user decision.
    var selectionAutoInvokeEnabled: Bool {
        didSet {
            defaults.set(selectionAutoInvokeEnabled, forKey: Key.selectionAutoInvokeEnabled)
            NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
        }
    }
    var selectionAutoInvokeScope: SelectionAutoInvokeScope {
        didSet { defaults.set(selectionAutoInvokeScope.rawValue, forKey: Key.selectionAutoInvokeScope) }
    }
    var selectionAutoInvokeBlacklist: [String] {
        didSet { defaults.set(selectionAutoInvokeBlacklist, forKey: Key.selectionAutoInvokeBlacklist) }
    }
    var selectionAutoInvokeWhitelist: [String] {
        didSet { defaults.set(selectionAutoInvokeWhitelist, forKey: Key.selectionAutoInvokeWhitelist) }
    }
    /// Seconds between the selection settling and the quick actions appearing.
    var selectionAutoInvokeDelay: Double {
        didSet {
            let normalized = SelectionAutoInvokeDelay.normalized(selectionAutoInvokeDelay)
            if selectionAutoInvokeDelay != normalized {
                selectionAutoInvokeDelay = normalized
            } else {
                defaults.set(selectionAutoInvokeDelay, forKey: Key.selectionAutoInvokeDelay)
            }
        }
    }

    /// Decides whether an automatic trigger may run in the given source app.
    /// Manual shortcuts are intentionally not affected by this filter.
    func allowsAutomaticInvoke(from source: SelectionSourceApplication?) -> Bool {
        guard let identifier = source?.bundleIdentifier ?? source?.localizedName, !identifier.isEmpty else {
            return selectionAutoInvokeScope == .allApps
        }
        switch selectionAutoInvokeScope {
        case .allApps: return true
        case .blacklist: return !selectionAutoInvokeBlacklist.contains(identifier)
        case .whitelist: return selectionAutoInvokeWhitelist.contains(identifier)
        }
    }

    var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: Key.panelWidth) } }
    var panelHeight: Double { didSet { defaults.set(panelHeight, forKey: Key.panelHeight) } }
    var showsMenuBarIcon: Bool {
        didSet {
            defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon)
            NotificationCenter.default.post(name: .spotAskMenuBarIconVisibilityChanged, object: self)
        }
    }

    /// Last window position, remembered across launches. Nil until the window
    /// has been shown once, or after the saved spot falls off every screen.
    var panelOrigin: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Key.panelOriginX) as? Double,
                  let y = defaults.object(forKey: Key.panelOriginY) as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.panelOriginX)
                defaults.removeObject(forKey: Key.panelOriginY)
                return
            }
            defaults.set(newValue.x, forKey: Key.panelOriginX)
            defaults.set(newValue.y, forKey: Key.panelOriginY)
        }
    }
    var keepWindowOnTop: Bool { didSet { defaults.set(keepWindowOnTop, forKey: Key.keepWindowOnTop) } }
    private var promptPresetCatalog: [PromptPreset] {
        didSet {
            savePromptPresetCatalog()
            saveCustomPromptPresets()
            cleanUpShortcutAssignments()
        }
    }

    var promptPresets: [PromptPreset] {
        promptPresetCatalog
    }

    var enabledPromptPresets: [PromptPreset] {
        promptPresetCatalog.filter(\.isEnabled)
    }

    var customPromptPresets: [PromptPreset] {
        promptPresetCatalog.filter { !$0.isBuiltIn }
    }

    private var quickActionCatalog: [QuickAction] {
        didSet {
            saveQuickActionCatalog()
            cleanUpShortcutAssignments()
        }
    }

    var quickActions: [QuickAction] {
        quickActionCatalog
    }

    /// Master switch for the External Ask feature. Defaults to on; when off,
    /// the chips strip, shortcut targets, and shortcut-settings rows all hide.
    /// Catalog data and shortcut assignments are preserved for re-enabling.
    var externalAskEnabled: Bool {
        didSet { defaults.set(externalAskEnabled, forKey: Key.externalAskEnabled) }
    }

    var enabledQuickActions: [QuickAction] {
        guard externalAskEnabled else { return [] }
        return quickActionCatalog.filter(\.isEnabled)
    }

    var customQuickActions: [QuickAction] {
        quickActionCatalog.filter { !$0.isBuiltIn }
    }

    var shortcutAssignments: [InAppShortcutAssignment] {
        inAppShortcutConfiguration.resolvedAssignments(
            for: enabledPromptPresets,
            actions: enabledQuickActions
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? "You are a helpful assistant."
        contextLimit = defaults.object(forKey: Key.contextLimit) as? Int ?? 20
        retainSession = defaults.bool(forKey: Key.retainSession)
        clearInputOnClose = defaults.object(forKey: Key.clearInputOnClose) as? Bool ?? false
        confirmBeforeStartingNewConversation = defaults.object(forKey: Key.confirmBeforeStartingNewConversation) as? Bool ?? true
        escapeStartsNewConversation = defaults.object(forKey: Key.escapeStartsNewConversation) as? Bool ?? false
        defaultExpandReasoning = defaults.object(forKey: Key.defaultExpandReasoning) as? Bool ?? false
        renderMath = defaults.object(forKey: Key.renderMath) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        silentLaunch = defaults.object(forKey: Key.silentLaunch) as? Bool ?? false
        proxyEnabled = defaults.object(forKey: Key.proxyEnabled) as? Bool ?? false
        proxyType = ProxyType(rawValue: defaults.string(forKey: Key.proxyType) ?? "") ?? .http
        proxyHost = defaults.string(forKey: Key.proxyHost) ?? ""
        proxyPort = defaults.object(forKey: Key.proxyPort) as? Int ?? 1080
        proxyUsername = defaults.string(forKey: Key.proxyUsername) ?? ""
        diagnosticsEnabled = defaults.object(forKey: Key.diagnosticsEnabled) as? Bool ?? false
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "system") ?? .system
        fontSize = FontSize(rawValue: defaults.string(forKey: Key.fontSize) ?? "standard") ?? .standard
        chatMessageStyle = ChatMessageStyle(rawValue: defaults.string(forKey: Key.chatMessageStyle) ?? "") ?? .standard
        interfaceZoomLevel = InterfaceZoomLevel(rawValue: defaults.string(forKey: Key.interfaceZoomLevel) ?? "standard") ?? .standard
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "system") ?? .system
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKeyPreset) ?? "optionSpace") ?? .optionSpace
        globalShortcut = defaults.data(forKey: Key.globalShortcut).flatMap {
            try? JSONDecoder().decode(InAppShortcut.self, from: $0)
        }
        selectionAssistantEnabled = defaults.object(forKey: Key.selectionAssistantEnabled) as? Bool ?? false
        selectionAssistantMode = SelectionAssistantMode(rawValue: defaults.string(forKey: Key.selectionAssistantMode) ?? "actionBar") ?? .actionBar
        selectionHotKeyPreset = SelectionHotKeyPreset(rawValue: defaults.string(forKey: Key.selectionHotKeyPreset) ?? "optionShiftSpace") ?? .optionShiftSpace
        selectionDefaultPromptID = UUID(uuidString: defaults.string(forKey: Key.selectionDefaultPromptID) ?? "") ?? PromptPreset.builtIn.first?.id
        selectionAssistantToggleShortcut = defaults.data(forKey: Key.selectionAssistantToggleShortcut).flatMap { try? JSONDecoder().decode(InAppShortcut.self, from: $0) }
        selectionAutoInvokeEnabled = defaults.object(forKey: Key.selectionAutoInvokeEnabled) as? Bool ?? false
        selectionAutoInvokeScope = SelectionAutoInvokeScope(rawValue: defaults.string(forKey: Key.selectionAutoInvokeScope) ?? "") ?? .allApps
        selectionAutoInvokeBlacklist = defaults.stringArray(forKey: Key.selectionAutoInvokeBlacklist) ?? []
        selectionAutoInvokeWhitelist = defaults.stringArray(forKey: Key.selectionAutoInvokeWhitelist) ?? []
        selectionActionBarShowsLabels = defaults.object(forKey: Key.selectionActionBarShowsLabels) as? Bool ?? true
        automaticUpdateCheckEnabled = defaults.object(forKey: Key.automaticUpdateCheckEnabled) as? Bool ?? true
        selectionAutoInvokeDelay = SelectionAutoInvokeDelay.normalized(
            defaults.object(forKey: Key.selectionAutoInvokeDelay) as? Double ?? SelectionAutoInvokeDelay.defaultValue
        )
        panelWidth = defaults.object(forKey: Key.panelWidth) as? Double ?? 720
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? 520
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        keepWindowOnTop = defaults.object(forKey: Key.keepWindowOnTop) as? Bool ?? false
        externalAskEnabled = defaults.object(forKey: Key.externalAskEnabled) as? Bool ?? true
        promptPresetCatalog = Self.loadPromptPresetCatalog(from: defaults)
        quickActionCatalog = Self.loadQuickActionCatalog(from: defaults)
        inAppShortcutConfiguration = Self.loadInAppShortcutConfiguration(from: defaults)
        providerRegistryStorage = ProviderModelRegistry(
            defaults: defaults,
            legacy: LegacyProviderConfiguration(
                baseURL: defaults.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1",
                useFullEndpoint: defaults.object(forKey: Key.useFullEndpoint) as? Bool ?? false,
                model: defaults.string(forKey: Key.model) ?? "gpt-5-mini",
                streaming: defaults.object(forKey: Key.streaming) as? Bool ?? true,
                timeout: defaults.object(forKey: Key.timeout) as? Double ?? 60
            )
        )
        savePromptPresetCatalog()
        saveQuickActionCatalog()
        saveCustomPromptPresets()
        cleanUpShortcutAssignments()
    }

    func migratePendingLegacyAPIKey(using keyStore: any LegacyAPIKeyMigrating) throws {
        guard let providerID = providerRegistry.pendingLegacyAPIKeyMigrationProviderID else { return }
        try keyStore.migrateLegacyAPIKey(to: providerID)
        providerRegistry.completeLegacyAPIKeyMigration(to: providerID)
    }

    @discardableResult
    func saveCustomPromptPreset(_ preset: PromptPreset) -> Bool {
        guard !preset.isBuiltIn else { return false }
        let title = preset.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = preset.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !instruction.isEmpty else { return false }

        let customSymbolName = (preset.customSymbolName.flatMap { PromptPreset.isValidSymbol($0) ? $0.trimmingCharacters(in: .whitespacesAndNewlines) : nil })
        let savedPreset = PromptPreset(
            id: preset.id,
            title: title,
            instruction: instruction,
            customSymbolName: customSymbolName,
            isEnabled: promptPresetCatalog.first(where: { $0.id == preset.id })?.isEnabled ?? preset.isEnabled
        )
        if let index = promptPresetCatalog.firstIndex(where: { $0.id == preset.id && !$0.isBuiltIn }) {
            promptPresetCatalog[index] = savedPreset
        } else {
            promptPresetCatalog.append(savedPreset)
        }
        return true
    }

    func deleteCustomPromptPreset(id: UUID) {
        promptPresetCatalog.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    func setPromptPresetEnabled(id: UUID, isEnabled: Bool) {
        guard let index = promptPresetCatalog.firstIndex(where: { $0.id == id }) else { return }
        promptPresetCatalog[index].isEnabled = isEnabled
    }

    @discardableResult
    func movePromptPreset(id: UUID, by offset: Int) -> Bool {
        guard offset == -1 || offset == 1,
              let sourceIndex = promptPresetCatalog.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let destinationIndex = sourceIndex + offset
        guard promptPresetCatalog.indices.contains(destinationIndex) else { return false }

        var reorderedPresets = promptPresetCatalog
        reorderedPresets.swapAt(sourceIndex, destinationIndex)
        promptPresetCatalog = reorderedPresets
        return true
    }

    func enabledPromptPreset(id: UUID) -> PromptPreset? {
        promptPresetCatalog.first(where: { $0.id == id && $0.isEnabled })
    }

    @discardableResult
    func saveCustomQuickAction(_ action: QuickAction) -> Bool {
        guard !action.isBuiltIn else { return false }
        let builtInIDs = Set(QuickAction.builtIn.map(\.id))
        guard !builtInIDs.contains(action.id) else { return false }

        let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard QuickActionBuilder.validate(kind: action.kind).isValid else { return false }

        let symbolName = QuickAction.isValidSymbol(action.symbolName) ? action.symbolName : QuickAction.defaultSymbolName
        let isEnabled = quickActionCatalog.first(where: { $0.id == action.id })?.isEnabled ?? action.isEnabled

        let savedAction = QuickAction(
            id: action.id,
            name: name,
            kind: action.kind,
            symbolName: symbolName,
            isBuiltIn: false,
            isEnabled: isEnabled
        )

        if let index = quickActionCatalog.firstIndex(where: { $0.id == action.id && !$0.isBuiltIn }) {
            quickActionCatalog[index] = savedAction
        } else {
            quickActionCatalog.append(savedAction)
        }
        return true
    }

    func deleteCustomQuickAction(id: UUID) {
        quickActionCatalog.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    func setQuickActionEnabled(id: UUID, isEnabled: Bool) {
        guard let index = quickActionCatalog.firstIndex(where: { $0.id == id }) else { return }
        quickActionCatalog[index].isEnabled = isEnabled
    }

    @discardableResult
    func moveQuickAction(id: UUID, by offset: Int) -> Bool {
        guard offset == -1 || offset == 1,
              let sourceIndex = quickActionCatalog.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let destinationIndex = sourceIndex + offset
        guard quickActionCatalog.indices.contains(destinationIndex) else { return false }

        var reorderedActions = quickActionCatalog
        reorderedActions.swapAt(sourceIndex, destinationIndex)
        quickActionCatalog = reorderedActions
        return true
    }

    func enabledQuickAction(id: UUID) -> QuickAction? {
        quickActionCatalog.first(where: { $0.id == id && $0.isEnabled })
    }

    func selectionPromptPreset() -> PromptPreset? {
        if let selectionDefaultPromptID, let preset = enabledPromptPreset(id: selectionDefaultPromptID) { return preset }
        return enabledPromptPresets.first
    }

    /// Resolves catalog entries to their current value and enabled state while
    /// retaining compatibility with an already-buffered legacy action whose
    /// custom preset was never written to this installation's catalog.
    func promptPresetAllowedForUse(_ preset: PromptPreset) -> PromptPreset? {
        guard let catalogPreset = promptPresetCatalog.first(where: { $0.id == preset.id }) else {
            return preset
        }
        return catalogPreset.isEnabled ? catalogPreset : nil
    }

    func shortcut(for target: InAppShortcutTarget) -> InAppShortcut? {
        inAppShortcutConfiguration.shortcut(
            for: target,
            presets: enabledPromptPresets,
            actions: enabledQuickActions
        )
    }

    func shortcutTarget(for shortcut: InAppShortcut) -> InAppShortcutTarget? {
        inAppShortcutConfiguration.target(
            for: shortcut,
            presets: enabledPromptPresets,
            actions: enabledQuickActions
        )
    }

    @discardableResult
    func assignShortcut(_ shortcut: InAppShortcut, to target: InAppShortcutTarget) -> InAppShortcutAssignmentError? {
        let error = inAppShortcutConfiguration.assign(
            shortcut,
            to: target,
            presets: enabledPromptPresets,
            actions: enabledQuickActions
        )
        if error == nil { saveInAppShortcutConfiguration() }
        return error
    }

    @discardableResult
    func removeShortcut(for target: InAppShortcutTarget) -> InAppShortcutAssignmentError? {
        let error = inAppShortcutConfiguration.removeShortcut(
            for: target,
            presets: enabledPromptPresets,
            actions: enabledQuickActions
        )
        if error == nil { saveInAppShortcutConfiguration() }
        return error
    }

    @discardableResult
    func resetShortcut(for target: InAppShortcutTarget) -> InAppShortcutAssignmentError? {
        let error = inAppShortcutConfiguration.resetShortcut(
            for: target,
            presets: enabledPromptPresets,
            actions: enabledQuickActions
        )
        if error == nil { saveInAppShortcutConfiguration() }
        return error
    }

    func resetAllShortcuts() {
        inAppShortcutConfiguration.resetAll()
        saveInAppShortcutConfiguration()
    }

    func makeConfigurationBackup(
        includeAccessKeys: Bool = false,
        keyStore: (any APIKeyStoring)? = nil
    ) throws -> SpotAskConfigBackup {
        guard let providerCatalog = providerRegistry.catalog else {
            throw SpotAskConfigBackupError.catalogUnavailable
        }
        var backup = SpotAskConfigBackup(
            general: .init(
                systemPrompt: systemPrompt,
                contextLimit: contextLimit,
                retainSession: retainSession,
                clearInputOnClose: clearInputOnClose,
                confirmBeforeStartingNewConversation: confirmBeforeStartingNewConversation,
                escapeStartsNewConversation: escapeStartsNewConversation,
                defaultExpandReasoning: defaultExpandReasoning,
                renderMath: renderMath,
                launchAtLogin: launchAtLogin,
                appearance: appearance.rawValue,
                fontSize: fontSize.rawValue,
                chatMessageStyle: chatMessageStyle.rawValue,
                interfaceZoomLevel: interfaceZoomLevel.rawValue,
                language: language.rawValue,
                hotKeyPreset: hotKeyPreset.rawValue,
                keepWindowOnTop: keepWindowOnTop,
                showsMenuBarIcon: showsMenuBarIcon,
                automaticUpdateCheckEnabled: automaticUpdateCheckEnabled,
                proxyEnabled: proxyEnabled,
                proxyType: proxyType.rawValue,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUsername: proxyUsername
            ),
            promptPresetCatalog: promptPresetCatalog,
            quickActionCatalog: quickActionCatalog,
            shortcutConfiguration: inAppShortcutConfiguration,
            providerCatalog: providerCatalog
        )
        if includeAccessKeys {
            guard let keyStore else {
                throw SpotAskConfigBackupError.keyStoreUnavailable
            }
            var apiKeys: [String: String] = [:]
            for provider in providerCatalog.providers {
                if let key = try keyStore.readAPIKey(for: provider.id), !key.isEmpty {
                    apiKeys[provider.id.uuidString] = key
                }
            }
            if let proxyPassword = try keyStore.readAPIKey(for: ProxyCredentialSlot.providerID),
               !proxyPassword.isEmpty {
                apiKeys[ProxyCredentialSlot.providerID.uuidString] = proxyPassword
            }
            backup.apiKeys = apiKeys
        }
        return backup
    }

    func applyConfigurationBackup(
        _ backup: SpotAskConfigBackup,
        keyStore: (any APIKeyStoring)? = nil
    ) throws {
        guard backup.schemaVersion == SpotAskConfigBackup.currentSchemaVersion else {
            throw SpotAskConfigBackupError.unsupportedSchemaVersion(backup.schemaVersion)
        }

        let general = backup.general
        systemPrompt = general.systemPrompt
        contextLimit = general.contextLimit
        retainSession = general.retainSession
        clearInputOnClose = general.clearInputOnClose
        confirmBeforeStartingNewConversation = general.confirmBeforeStartingNewConversation
        escapeStartsNewConversation = general.escapeStartsNewConversation
        defaultExpandReasoning = general.defaultExpandReasoning
        renderMath = general.renderMath ?? true
        launchAtLogin = general.launchAtLogin
        appearance = AppearanceMode(rawValue: general.appearance) ?? .system
        fontSize = FontSize(rawValue: general.fontSize) ?? .standard
        chatMessageStyle = ChatMessageStyle(rawValue: general.chatMessageStyle ?? "") ?? .standard
        interfaceZoomLevel = InterfaceZoomLevel(rawValue: general.interfaceZoomLevel) ?? .standard
        language = AppLanguage(rawValue: general.language) ?? .system
        hotKeyPreset = HotKeyPreset(rawValue: general.hotKeyPreset) ?? .optionSpace
        keepWindowOnTop = general.keepWindowOnTop
        showsMenuBarIcon = general.showsMenuBarIcon
        if let automaticUpdateCheckEnabled = general.automaticUpdateCheckEnabled {
            self.automaticUpdateCheckEnabled = automaticUpdateCheckEnabled
        }
        if let proxyEnabled = general.proxyEnabled { self.proxyEnabled = proxyEnabled }
        if let proxyType = general.proxyType, let type = ProxyType(rawValue: proxyType) { self.proxyType = type }
        if let proxyHost = general.proxyHost { self.proxyHost = proxyHost }
        if let proxyPort = general.proxyPort { self.proxyPort = proxyPort }
        if let proxyUsername = general.proxyUsername { self.proxyUsername = proxyUsername }

        promptPresetCatalog = Self.normalizedPromptPresetCatalog(backup.promptPresetCatalog)
        if let quickActionCatalog = backup.quickActionCatalog {
            self.quickActionCatalog = Self.normalizedQuickActionCatalog(quickActionCatalog)
        }
        inAppShortcutConfiguration = backup.shortcutConfiguration
        saveInAppShortcutConfiguration()
        cleanUpShortcutAssignments()

        try providerRegistry.replaceCatalog(with: backup.providerCatalog)
        if let apiKeys = backup.apiKeys, let keyStore {
            let providerIDs = Set(providerRegistry.catalog?.providers.map(\.id) ?? [])
            for (rawID, key) in apiKeys {
                guard let providerID = UUID(uuidString: rawID),
                      providerID == ProxyCredentialSlot.providerID || providerIDs.contains(providerID) else { continue }
                try keyStore.saveAPIKey(key, for: providerID)
            }
        }
    }

    private func saveCustomPromptPresets() {
        guard let data = try? JSONEncoder().encode(customPromptPresets) else { return }
        defaults.set(data, forKey: Key.customPromptPresets)
    }

    private func savePromptPresetCatalog() {
        guard let data = try? JSONEncoder().encode(promptPresetCatalog) else { return }
        defaults.set(data, forKey: Key.promptPresetCatalog)
    }

    private static func loadPromptPresetCatalog(from defaults: UserDefaults) -> [PromptPreset] {
        let legacyCustomPresets = loadCustomPromptPresets(from: defaults)
        guard let data = defaults.data(forKey: Key.promptPresetCatalog),
              let catalog = try? JSONDecoder().decode([PromptPreset].self, from: data) else {
            return normalizedPromptPresetCatalog(PromptPreset.builtIn + legacyCustomPresets)
        }
        return normalizedPromptPresetCatalog(catalog, legacyCustomPresets: legacyCustomPresets)
    }

    private static func normalizedPromptPresetCatalog(
        _ catalog: [PromptPreset],
        legacyCustomPresets: [PromptPreset] = []
    ) -> [PromptPreset] {
        let builtIns = Dictionary(uniqueKeysWithValues: PromptPreset.builtIn.map { ($0.id, $0) })
        var seenIDs = Set<UUID>()
        var normalized: [PromptPreset] = []

        for preset in catalog where seenIDs.insert(preset.id).inserted {
            if let builtIn = builtIns[preset.id] {
                normalized.append(PromptPreset(
                    id: builtIn.id,
                    title: builtIn.title,
                    instruction: builtIn.instruction,
                    isBuiltIn: true,
                    isEnabled: preset.isEnabled
                ))
            } else if !preset.isBuiltIn {
                normalized.append(preset)
            }
        }

        for builtIn in PromptPreset.builtIn where seenIDs.insert(builtIn.id).inserted {
            normalized.append(builtIn)
        }
        for preset in legacyCustomPresets where seenIDs.insert(preset.id).inserted {
            normalized.append(preset)
        }
        return normalized
    }

    private static func loadCustomPromptPresets(from defaults: UserDefaults) -> [PromptPreset] {
        guard let data = defaults.data(forKey: Key.customPromptPresets),
              let presets = try? JSONDecoder().decode([PromptPreset].self, from: data) else {
            return []
        }
        return presets.filter { !$0.isBuiltIn }
    }

    private static func loadInAppShortcutConfiguration(from defaults: UserDefaults) -> InAppShortcutConfiguration {
        guard let data = defaults.data(forKey: Key.inAppShortcutConfiguration),
              let configuration = try? JSONDecoder().decode(InAppShortcutConfiguration.self, from: data) else {
            // Existing installations have no shortcut payload. Their current
            // hard-coded command behavior is represented by derived defaults.
            return InAppShortcutConfiguration()
        }
        return configuration
    }

    private func saveInAppShortcutConfiguration() {
        guard let data = try? JSONEncoder().encode(inAppShortcutConfiguration) else { return }
        defaults.set(data, forKey: Key.inAppShortcutConfiguration)
    }

    private func cleanUpShortcutAssignments() {
        // Disabled presets and providers remain in the catalog so their user-selected
        // shortcuts can become available again when they are re-enabled.
        guard inAppShortcutConfiguration.cleanUp(
            for: promptPresetCatalog,
            actions: quickActionCatalog
        ) else { return }
        saveInAppShortcutConfiguration()
    }

    private func saveQuickActionCatalog() {
        guard let data = try? JSONEncoder().encode(quickActionCatalog) else { return }
        defaults.set(data, forKey: Key.quickActionCatalog)
    }

    private static func loadQuickActionCatalog(from defaults: UserDefaults) -> [QuickAction] {
        guard let data = defaults.data(forKey: Key.quickActionCatalog),
              let catalog = try? JSONDecoder().decode([QuickAction].self, from: data) else {
            return normalizedQuickActionCatalog(QuickAction.builtIn)
        }
        return normalizedQuickActionCatalog(catalog)
    }

    private static func normalizedQuickActionCatalog(
        _ catalog: [QuickAction]
    ) -> [QuickAction] {
        let builtIns = Dictionary(uniqueKeysWithValues: QuickAction.builtIn.map { ($0.id, $0) })
        var seenIDs = Set<UUID>()
        var normalized: [QuickAction] = []

        for action in catalog where seenIDs.insert(action.id).inserted {
            if let builtIn = builtIns[action.id] {
                normalized.append(QuickAction(
                    id: builtIn.id,
                    name: builtIn.name,
                    kind: builtIn.kind,
                    symbolName: builtIn.symbolName,
                    isBuiltIn: true,
                    isEnabled: action.isEnabled
                ))
            } else if !action.isBuiltIn {
                let symbol = QuickAction.isValidSymbol(action.symbolName)
                    ? action.symbolName
                    : QuickAction.defaultSymbolName
                normalized.append(QuickAction(
                    id: action.id,
                    name: action.name,
                    kind: action.kind,
                    symbolName: symbol,
                    isBuiltIn: false,
                    isEnabled: action.isEnabled
                ))
            }
        }

        for builtIn in QuickAction.builtIn where seenIDs.insert(builtIn.id).inserted {
            normalized.append(builtIn)
        }
        return normalized
    }
}
