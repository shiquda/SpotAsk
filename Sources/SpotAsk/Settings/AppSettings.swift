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

    var shortcut: InAppShortcut {
        switch self {
        case .optionSpace: InAppShortcut(key: " ", modifiers: .option)
        case .controlSpace: InAppShortcut(key: " ", modifiers: .control)
        case .commandShiftSpace: InAppShortcut(key: " ", modifiers: [.command, .shift])
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

enum UpdateDownloadSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case official
    case accelerated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: L10n.string("settings.updateSource.automatic")
        case .official: L10n.string("settings.updateSource.official")
        case .accelerated: L10n.string("settings.updateSource.accelerated")
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
        static let clipboardAssistedSelectionEnabled = "clipboardAssistedSelectionEnabled"
        static let clipboardAssistedSelectionAppIdentifiers = "clipboardAssistedSelectionAppIdentifiers"
        static let selectionActionBarShowsChatAction = "selectionActionBarShowsChatAction"
        static let selectionActionBarShowsLabels = "selectionActionBarShowsLabels"
        static let selectionActionBarShowsPrompts = "selectionActionBarShowsPrompts"
        static let selectionActionBarShowsExternalAsk = "selectionActionBarShowsExternalAsk"
        static let automaticUpdateCheckEnabled = "automaticUpdateCheckEnabled"
        static let updateDownloadSource = "updateDownloadSource"
        static let quickActionCatalog = "webQuickAskProviderCatalog"
        static let externalAskEnabled = "webQuickAskEnabled"
        static let removedBuiltInQuickActionIDs = "removedBuiltInQuickActionIDs"
    }

    let defaults: UserDefaults
    private var isInitializing = true
    var dynamicSettingStorage: [String: Any] = [:]
    private var inAppShortcutConfiguration: InAppShortcutConfiguration
    private var providerRegistryStorage: ProviderModelRegistry!
    var providerRegistry: ProviderModelRegistry { providerRegistryStorage }
    var catalogLoadError: ProviderModelCatalogLoadError? { providerRegistry.loadError }

    func saveSetting(_ key: String) {
        guard !isInitializing else { return }
        SettingRegistry.shared.descriptor(forKey: key)?.save(from: self, to: defaults)
    }

    subscript<T>(descriptor: SettingDescriptor<T>) -> T {
        get { descriptor.getValue(self) }
        set {
            descriptor.setValue(self, newValue)
            descriptor.save(from: self, to: defaults)
        }
    }

    static func register(_ descriptor: any AnySettingDescriptor) {
        SettingRegistry.shared.register(descriptor)
    }

    static func unregister(_ descriptor: any AnySettingDescriptor) {
        SettingRegistry.shared.unregister(key: descriptor.key)
    }

    static func resetToStandardSettings() {
        SettingRegistry.shared.resetToStandardSettings()
    }

    var systemPrompt: String = "You are a helpful assistant." { didSet { saveSetting("systemPrompt") } }
    var contextLimit: Int = 20 { didSet { saveSetting("contextLimit") } }
    var retainSession: Bool = false { didSet { saveSetting("retainSession") } }
    var clearInputOnClose: Bool = false { didSet { saveSetting("clearInputOnClose") } }
    var confirmBeforeStartingNewConversation: Bool = true {
        didSet { saveSetting("confirmBeforeStartingNewConversation") }
    }
    var escapeStartsNewConversation: Bool = false {
        didSet { saveSetting("escapeStartsNewConversation") }
    }
    var defaultExpandReasoning: Bool = false {
        didSet { saveSetting("defaultExpandReasoning") }
    }
    var renderMath: Bool = true { didSet { saveSetting("renderMath") } }
    var launchAtLogin: Bool = false { didSet { saveSetting("launchAtLogin") } }
    var silentLaunch: Bool = false { didSet { saveSetting("silentLaunch") } }
    var proxyEnabled: Bool = false { didSet { saveSetting("proxyEnabled") } }
    var proxyType: ProxyType = .http { didSet { saveSetting("proxyType") } }
    var proxyHost: String = "" { didSet { saveSetting("proxyHost") } }
    var proxyPort: Int = 1080 { didSet { saveSetting("proxyPort") } }
    var proxyUsername: String = "" { didSet { saveSetting("proxyUsername") } }
    var diagnosticsEnabled: Bool = false { didSet { saveSetting("diagnosticsEnabled") } }
    var appearance: AppearanceMode = .system { didSet { saveSetting("appearance") } }
    var fontSize: FontSize = .standard { didSet { saveSetting("fontSize") } }
    var chatMessageStyle: ChatMessageStyle = .standard { didSet { saveSetting("chatMessageStyle") } }
    var interfaceZoomLevel: InterfaceZoomLevel = .standard { didSet { saveSetting("interfaceZoomLevel") } }
    var language: AppLanguage = .system { didSet { saveSetting(AppLanguage.defaultsKey) } }
    var hotKeyPreset: HotKeyPreset = .optionSpace { didSet { saveSetting("hotKeyPreset") } }
    var globalShortcut: InAppShortcut? = nil { didSet { saveSetting("globalShortcut") } }
    var selectionAssistantEnabled: Bool = false { didSet { saveSetting("selectionAssistantEnabled") } }
    var selectionAssistantMode: SelectionAssistantMode = .actionBar { didSet { saveSetting("selectionAssistantMode") } }
    var selectionHotKeyPreset: SelectionHotKeyPreset = .optionShiftSpace { didSet { saveSetting("selectionHotKeyPreset") } }
    var selectionDefaultPromptID: UUID? = PromptPreset.builtIn.first?.id { didSet { saveSetting("selectionDefaultPromptID") } }
    var selectionAssistantToggleShortcut: InAppShortcut? = nil { didSet { saveSetting("selectionAssistantToggleShortcut") } }
    var selectionActionBarShowsChatAction: Bool = true { didSet { saveSetting("selectionActionBarShowsChatAction") } }
    var selectionActionBarShowsLabels: Bool = true { didSet { saveSetting("selectionActionBarShowsLabels") } }
    var selectionActionBarShowsPrompts: Bool = true { didSet { saveSetting("selectionActionBarShowsPrompts") } }
    var selectionActionBarShowsExternalAsk: Bool = true { didSet { saveSetting("selectionActionBarShowsExternalAsk") } }
    var automaticUpdateCheckEnabled: Bool = true { didSet { saveSetting("automaticUpdateCheckEnabled") } }
    var updateDownloadSource: UpdateDownloadSource = .automatic { didSet { saveSetting("updateDownloadSource") } }
    var selectionAutoInvokeEnabled: Bool = false { didSet { saveSetting("selectionAutoInvokeEnabled") } }
    var selectionAutoInvokeScope: SelectionAutoInvokeScope = .allApps { didSet { saveSetting("selectionAutoInvokeScope") } }
    var selectionAutoInvokeBlacklist: [String] = [] { didSet { saveSetting("selectionAutoInvokeBlacklist") } }
    var selectionAutoInvokeWhitelist: [String] = [] { didSet { saveSetting("selectionAutoInvokeWhitelist") } }
    var clipboardAssistedSelectionEnabled: Bool = false { didSet { saveSetting("clipboardAssistedSelectionEnabled") } }
    var clipboardAssistedSelectionAppIdentifiers: [String] = [] { didSet { saveSetting("clipboardAssistedSelectionAppIdentifiers") } }
    var selectionAutoInvokeDelay: Double = SelectionAutoInvokeDelay.defaultValue {
        didSet {
            let normalized = SelectionAutoInvokeDelay.normalized(selectionAutoInvokeDelay)
            if selectionAutoInvokeDelay != normalized {
                selectionAutoInvokeDelay = normalized
            } else {
                saveSetting("selectionAutoInvokeDelay")
            }
        }
    }

    /// Decides whether an automatic trigger may run in the given source app.
    /// Manual shortcuts are intentionally not affected by this filter.
    func allowsAutomaticInvoke(from source: SelectionSourceApplication?) -> Bool {
        guard let identifier = source?.selectionIdentifier else {
            return selectionAutoInvokeScope == .allApps
        }
        switch selectionAutoInvokeScope {
        case .allApps: return true
        case .blacklist: return !selectionAutoInvokeBlacklist.contains(identifier)
        case .whitelist: return selectionAutoInvokeWhitelist.contains(identifier)
        }
    }

    /// Decides whether a selection read from `source` may use the
    /// clipboard-assisted path. Both the switch and a listed app are required,
    /// so an app that is not listed always keeps the plain Accessibility read.
    func usesClipboardAssistedSelection(from source: SelectionSourceApplication?) -> Bool {
        guard clipboardAssistedSelectionEnabled, let identifier = source?.selectionIdentifier else {
            return false
        }
        return clipboardAssistedSelectionAppIdentifiers.contains(identifier)
    }

    var panelWidth: Double = 720 { didSet { saveSetting("panelWidth") } }
    var panelHeight: Double = 520 { didSet { saveSetting("panelHeight") } }
    var showsMenuBarIcon: Bool = true { didSet { saveSetting("showsMenuBarIcon") } }

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
    var keepWindowOnTop: Bool = false { didSet { saveSetting("keepWindowOnTop") } }
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

    private var removedBuiltInQuickActionIDs: Set<UUID>

    var quickActions: [QuickAction] {
        quickActionCatalog
    }

    /// Master switch for the External Ask feature. Defaults to on; when off,
    /// the chips strip, shortcut targets, and shortcut-settings rows all hide.
    /// Catalog data and shortcut assignments are preserved for re-enabling.
    var externalAskEnabled: Bool = true {
        didSet { saveSetting("webQuickAskEnabled") }
    }
    /// Off by default so an ordinary send stays a manual send.
    var decisionRoutingEnabled: Bool = false {
        didSet { saveSetting("decisionRoutingEnabled") }
    }

    var decisionRoutingProvider: DecisionProviderKind = .systemOne {
        didSet { saveSetting("decisionRoutingProvider") }
    }

    var decisionRoutingServiceURL: String = DecisionRoutingPolicy.defaultServiceURL {
        didSet { saveSetting("decisionRoutingServiceURL") }
    }

    var decisionRoutingModel: String = DecisionRoutingPolicy.defaultOfficialModel {
        didSet { saveSetting("decisionRoutingModel") }
    }

    var decisionRoutingConfirmationMode: DecisionConfirmationMode = .always {
        didSet { saveSetting("decisionRoutingConfirmationMode") }
    }

    var decisionRoutingConfidenceThreshold: Double = DecisionRoutingPolicy.defaultThreshold {
        didSet {
            let clamped = DecisionRoutingPolicy.normalizedThreshold(decisionRoutingConfidenceThreshold)
            if clamped != decisionRoutingConfidenceThreshold {
                decisionRoutingConfidenceThreshold = clamped
                return
            }
            saveSetting("decisionRoutingConfidenceThreshold")
        }
    }

    var decisionRoutingTimeoutSeconds: Double = DecisionRoutingPolicy.defaultTimeoutSeconds {
        didSet {
            let clamped = DecisionRoutingPolicy.normalizedTimeout(decisionRoutingTimeoutSeconds)
            if clamped != decisionRoutingTimeoutSeconds {
                decisionRoutingTimeoutSeconds = clamped
                return
            }
            saveSetting("decisionRoutingTimeoutSeconds")
        }
    }

    var decisionRoutingTimeoutAction: DecisionTimeoutAction = .manualSelection {
        didSet { saveSetting("decisionRoutingTimeoutAction") }
    }

    var decisionRoutingInAppDescription: String = "" {
        didSet { saveSetting("decisionRoutingInAppDescription") }
    }


    var enabledQuickActions: [QuickAction] {
        guard externalAskEnabled else { return [] }
        return quickActionCatalog.filter(\.isEnabled)
    }
    func decisionRoutingSettings() -> DecisionRoutingSettings {
        DecisionRoutingSettings(
            isEnabled: decisionRoutingEnabled,
            provider: decisionRoutingProvider,
            serviceURL: decisionRoutingServiceURL,
            model: decisionRoutingModel,
            confirmationMode: decisionRoutingConfirmationMode,
            confidenceThreshold: decisionRoutingConfidenceThreshold,
            timeoutSeconds: decisionRoutingTimeoutSeconds,
            timeoutAction: decisionRoutingTimeoutAction,
            inAppDescription: decisionRoutingInAppDescription
        )
    }

    func decisionRoutingCandidates() -> [DecisionRouteCandidate] {
        DecisionRouteCatalog.candidates(
            actions: enabledQuickActions,
            inAppDescription: decisionRoutingInAppDescription
        )
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
        promptPresetCatalog = Self.loadPromptPresetCatalog(from: defaults)
        removedBuiltInQuickActionIDs = Self.loadRemovedBuiltInQuickActionIDs(from: defaults)
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
        for descriptor in SettingRegistry.shared.descriptors {
            descriptor.load(into: self, from: defaults)
        }
        let shouldSaveMigratedDecisionService = migrateDecisionServiceIfNeeded()
        savePromptPresetCatalog()
        saveQuickActionCatalog()
        saveCustomPromptPresets()
        cleanUpShortcutAssignments()
        isInitializing = false
        if shouldSaveMigratedDecisionService {
            saveSetting("decisionRoutingServiceURL")
            saveSetting("decisionRoutingModel")
        }
    }

    private func migrateDecisionServiceIfNeeded() -> Bool {
        guard defaults.object(forKey: "decisionRoutingServiceURL") == nil else { return false }
        let migrated = DecisionRoutingMigration.serviceFields(
            hasStoredServiceURL: false,
            storedServiceURL: "",
            storedModel: "",
            legacyEndpoint: defaults.string(forKey: "decisionRoutingEndpoint"),
            legacyOfficialModel: defaults.string(forKey: "decisionRoutingOfficialModel"),
            legacyCustomURL: defaults.string(forKey: "decisionRoutingCustomBaseURL"),
            legacyCustomModel: defaults.string(forKey: "decisionRoutingCustomModel")
        )
        decisionRoutingServiceURL = migrated.serviceURL
        decisionRoutingModel = migrated.model
        if migrated.preferLegacyCustomCredential {
            defaults.set(true, forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        }
        return true
    }

    /// Missing key keeps the historical hot-key preset. Empty data is an
    /// explicit cleared shortcut and must not fall back to Option+Space.
    static func loadGlobalShortcut(from defaults: UserDefaults, hotKeyPreset: HotKeyPreset) -> InAppShortcut? {
        guard let data = defaults.data(forKey: Key.globalShortcut) else {
            return hotKeyPreset.shortcut
        }
        if data.isEmpty {
            return nil
        }
        return (try? JSONDecoder().decode(InAppShortcut.self, from: data)) ?? hotKeyPreset.shortcut
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
    func saveQuickAction(_ action: QuickAction) -> Bool {
        let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard QuickActionBuilder.validate(kind: action.kind).isValid else { return false }

        let isKnownBuiltIn = QuickAction.builtIn.contains { $0.id == action.id }
        let symbolName = QuickAction.isValidSymbol(action.symbolName) ? action.symbolName : QuickAction.defaultSymbolName
        let existing = quickActionCatalog.first { $0.id == action.id }
        let hasCustomDisplayName = isKnownBuiltIn
            && QuickAction.localizedTitle(for: action.id) != name
        let savedAction = QuickAction(
            id: action.id,
            name: name,
            kind: action.kind,
            symbolName: symbolName,
            isBuiltIn: isKnownBuiltIn,
            isEnabled: existing?.isEnabled ?? action.isEnabled,
            routingPurpose: action.routingPurpose,
            routingScenario: action.routingScenario,
            requiresConfirmationOnAutoRoute: action.requiresConfirmationOnAutoRoute,
            hasCustomDisplayName: hasCustomDisplayName
        )

        if let index = quickActionCatalog.firstIndex(where: { $0.id == action.id }) {
            quickActionCatalog[index] = savedAction
        } else if isKnownBuiltIn {
            return false
        } else {
            quickActionCatalog.append(savedAction)
        }
        if isKnownBuiltIn {
            removedBuiltInQuickActionIDs.remove(action.id)
            saveRemovedBuiltInQuickActionIDs()
        }
        return true
    }

    @discardableResult
    func saveCustomQuickAction(_ action: QuickAction) -> Bool {
        guard !action.isBuiltIn else { return false }
        guard !QuickAction.builtIn.contains(where: { $0.id == action.id }) else { return false }
        return saveQuickAction(action)
    }

    func deleteQuickAction(id: UUID) {
        if QuickAction.builtIn.contains(where: { $0.id == id }) {
            removedBuiltInQuickActionIDs.insert(id)
            saveRemovedBuiltInQuickActionIDs()
        }
        quickActionCatalog.removeAll { $0.id == id }
    }

    func deleteCustomQuickAction(id: UUID) {
        deleteQuickAction(id: id)
    }

    func setQuickActionEnabled(id: UUID, isEnabled: Bool) {
        guard let index = quickActionCatalog.firstIndex(where: { $0.id == id }) else { return }
        quickActionCatalog[index].isEnabled = isEnabled
    }
    func updateQuickActionRouting(
        id: UUID,
        purpose: String,
        scenario: String,
        requiresConfirmation: Bool
    ) {
        guard let index = quickActionCatalog.firstIndex(where: { $0.id == id }) else { return }
        quickActionCatalog[index].routingPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        quickActionCatalog[index].routingScenario = scenario.trimmingCharacters(in: .whitespacesAndNewlines)
        quickActionCatalog[index].requiresConfirmationOnAutoRoute = requiresConfirmation
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
        var general = SpotAskConfigBackup.General()
        for descriptor in SettingRegistry.shared.descriptors {
            descriptor.exportValue(from: self, to: &general)
        }
        var backup = SpotAskConfigBackup(
            general: general,
            promptPresetCatalog: promptPresetCatalog,
            quickActionCatalog: quickActionCatalog,
            removedBuiltInQuickActionIDs: removedBuiltInQuickActionIDs.isEmpty
                ? nil
                : removedBuiltInQuickActionIDs.sorted { $0.uuidString < $1.uuidString },
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
            for slot in DecisionCredentialSlot.all {
                if let key = try keyStore.readAPIKey(for: slot), !key.isEmpty {
                    apiKeys[slot.uuidString] = key
                }
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

        // Validate provider catalog before touching any settings
        _ = try ProviderModelRegistry.normalized(catalog: backup.providerCatalog)

        // Snapshot current configuration for atomic rollback on failure
        let snapshot = try makeConfigurationBackup(includeAccessKeys: keyStore != nil, keyStore: keyStore)
        var touchedKeySlots: [UUID: String?] = [:]

        do {
            for descriptor in SettingRegistry.shared.descriptors {
                descriptor.importValue(into: self, from: backup.general)
            }
            promptPresetCatalog = Self.normalizedPromptPresetCatalog(backup.promptPresetCatalog)
            if let quickActionCatalog = backup.quickActionCatalog {
                replaceQuickActionCatalog(
                    quickActionCatalog,
                    removedBuiltInQuickActionIDs: backup.removedBuiltInQuickActionIDs
                )
            }
            inAppShortcutConfiguration = backup.shortcutConfiguration
            saveInAppShortcutConfiguration()
            cleanUpShortcutAssignments()

            try providerRegistry.replaceCatalog(with: backup.providerCatalog)
            if let apiKeys = backup.apiKeys, let keyStore {
                let providerIDs = Set(providerRegistry.catalog?.providers.map(\.id) ?? [])
                for (rawID, key) in apiKeys {
                    guard let providerID = UUID(uuidString: rawID),
                          providerID == ProxyCredentialSlot.providerID
                            || providerIDs.contains(providerID)
                            || DecisionCredentialSlot.all.contains(providerID) else { continue }
                    if !touchedKeySlots.keys.contains(providerID) {
                        let original = try keyStore.readAPIKey(for: providerID)
                        touchedKeySlots[providerID] = original
                    }
                    try keyStore.saveAPIKey(key, for: providerID)
                }
            }
        } catch {
            let rollbackErrors = rollbackConfiguration(
                from: snapshot,
                touchedKeySlots: touchedKeySlots,
                keyStore: keyStore
            )
            if !rollbackErrors.isEmpty {
                throw SpotAskConfigBackupError.rollbackFailed(
                    originalErrorDescription: error.localizedDescription,
                    rollbackErrorDescriptions: rollbackErrors.map(\.localizedDescription)
                )
            }
            throw error
        }
    }

    @discardableResult
    private func rollbackConfiguration(
        from snapshot: SpotAskConfigBackup,
        touchedKeySlots: [UUID: String?] = [:],
        keyStore: (any APIKeyStoring)?
    ) -> [any Error] {
        var rollbackErrors: [any Error] = []
        for descriptor in SettingRegistry.shared.descriptors {
            descriptor.importValue(into: self, from: snapshot.general)
        }
        promptPresetCatalog = Self.normalizedPromptPresetCatalog(snapshot.promptPresetCatalog)
        if let quickActionCatalog = snapshot.quickActionCatalog {
            replaceQuickActionCatalog(
                quickActionCatalog,
                removedBuiltInQuickActionIDs: snapshot.removedBuiltInQuickActionIDs
            )
        }
        inAppShortcutConfiguration = snapshot.shortcutConfiguration
        saveInAppShortcutConfiguration()
        cleanUpShortcutAssignments()

        do {
            try providerRegistry.replaceCatalog(with: snapshot.providerCatalog)
        } catch {
            rollbackErrors.append(error)
        }

        if let keyStore {
            for (slot, original) in touchedKeySlots {
                do {
                    if let original {
                        try keyStore.saveAPIKey(original, for: slot)
                    } else {
                        try keyStore.deleteAPIKey(for: slot)
                    }
                } catch {
                    rollbackErrors.append(error)
                }
            }
        }
        return rollbackErrors
    }

    func resetToDefaults() {
        for descriptor in SettingRegistry.shared.descriptors {
            descriptor.reset(in: self, defaults: defaults)
        }
        defaults.removeObject(forKey: ProviderModelRegistry.defaultsKey)
        defaults.removeObject(forKey: ProviderModelRegistry.pendingLegacyAPIKeyMigrationProviderIDDefaultsKey)
        promptPresetCatalog = PromptPreset.builtIn
        quickActionCatalog = Self.loadQuickActionCatalog(from: defaults)
        inAppShortcutConfiguration = InAppShortcutConfiguration()
        let provider = ProviderConfiguration(
            name: "OpenAI Compatible",
            address: "https://api.openai.com/v1",
            addressMode: .baseURL,
            timeout: 60
        )
        let model = ModelConfiguration(
            displayName: "gpt-5-mini",
            upstreamModelID: "gpt-5-mini",
            providerID: provider.id,
            isStreamingEnabled: true
        )
        let defaultCatalog = ProviderModelCatalog(providers: [provider], models: [model], selectedModelID: model.id)
        try? providerRegistry.replaceCatalog(with: defaultCatalog)

        savePromptPresetCatalog()
        saveQuickActionCatalog()
        saveCustomPromptPresets()
        saveInAppShortcutConfiguration()
        cleanUpShortcutAssignments()
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

    private func saveRemovedBuiltInQuickActionIDs() {
        let values = removedBuiltInQuickActionIDs.map(\.uuidString).sorted()
        defaults.set(values, forKey: Key.removedBuiltInQuickActionIDs)
    }

    private static func loadRemovedBuiltInQuickActionIDs(from defaults: UserDefaults) -> Set<UUID> {
        let raw = defaults.stringArray(forKey: Key.removedBuiltInQuickActionIDs) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private static func loadQuickActionCatalog(from defaults: UserDefaults) -> [QuickAction] {
        let removed = loadRemovedBuiltInQuickActionIDs(from: defaults)
        guard let data = defaults.data(forKey: Key.quickActionCatalog),
              let catalog = try? JSONDecoder().decode([QuickAction].self, from: data) else {
            return normalizedQuickActionCatalog(QuickAction.builtIn, removedBuiltInIDs: removed)
        }
        return normalizedQuickActionCatalog(catalog, removedBuiltInIDs: removed)
    }

    private func replaceQuickActionCatalog(
        _ catalog: [QuickAction],
        removedBuiltInQuickActionIDs removed: [UUID]?
    ) {
        let removedIDs = Set(removed ?? [])
        removedBuiltInQuickActionIDs = removedIDs
        saveRemovedBuiltInQuickActionIDs()
        quickActionCatalog = Self.normalizedQuickActionCatalog(catalog, removedBuiltInIDs: removedIDs)
    }

    private static func normalizedQuickActionCatalog(
        _ catalog: [QuickAction],
        removedBuiltInIDs: Set<UUID> = []
    ) -> [QuickAction] {
        let builtIns = Dictionary(uniqueKeysWithValues: QuickAction.builtIn.map { ($0.id, $0) })
        var seenIDs = Set<UUID>()
        var normalized: [QuickAction] = []

        for action in catalog where seenIDs.insert(action.id).inserted {
            if let builtIn = builtIns[action.id] {
                let kind = QuickActionBuilder.validate(kind: action.kind).isValid ? action.kind : builtIn.kind
                let symbol = QuickAction.isValidSymbol(action.symbolName) ? action.symbolName : builtIn.symbolName
                normalized.append(QuickAction(
                    id: builtIn.id,
                    name: action.name,
                    kind: kind,
                    symbolName: symbol,
                    isBuiltIn: true,
                    isEnabled: action.isEnabled,
                    routingPurpose: action.routingPurpose,
                    routingScenario: action.routingScenario,
                    requiresConfirmationOnAutoRoute: action.requiresConfirmationOnAutoRoute,
                    hasCustomDisplayName: action.hasCustomDisplayName
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
                    isEnabled: action.isEnabled,
                    routingPurpose: action.routingPurpose,
                    routingScenario: action.routingScenario,
                    requiresConfirmationOnAutoRoute: action.requiresConfirmationOnAutoRoute
                ))
            }
        }

        for builtIn in QuickAction.builtIn where !removedBuiltInIDs.contains(builtIn.id) && seenIDs.insert(builtIn.id).inserted {
            normalized.append(builtIn)
        }
        return normalized
    }
}
