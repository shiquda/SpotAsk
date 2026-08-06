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
    let id: UUID
    var title: String
    var instruction: String
    let isBuiltIn: Bool
    var isEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case instruction
        case isBuiltIn
        case isEnabled
    }

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        instruction = try container.decode(String.self, forKey: .instruction)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
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

    /// The visual identity used when this prompt is applied. Custom prompts
    /// deliberately share the stable default symbol.
    var symbolName: String {
        switch id.uuidString.uppercased() {
        case "EF8CF35C-386A-4389-A137-C207E4DB11FD": "globe"
        case "1C85A324-65B3-4EBD-B2C4-0C6B072E284A": "pencil.and.scribble"
        case "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2": "text.alignleft"
        case "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248": "lightbulb"
        default: "sparkles"
        }
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

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        guard self != .system else { return .current }
        return Locale(identifier: rawValue)
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
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
        static let launchAtLogin = "launchAtLogin"
        static let appearance = "appearance"
        static let fontSize = "fontSize"
        static let interfaceZoomLevel = "interfaceZoomLevel"
        static let language = AppLanguage.defaultsKey
        static let hotKeyPreset = "hotKeyPreset"
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
    }

    private let defaults: UserDefaults
    private var inAppShortcutConfiguration: InAppShortcutConfiguration
    private var providerRegistryStorage: ProviderModelRegistry!
    var providerRegistry: ProviderModelRegistry { providerRegistryStorage }
    private var isApplyingCatalogProjection = false
    var catalogLoadError: ProviderModelCatalogLoadError? { providerRegistry.loadError }
    var baseURL: String { didSet { defaults.set(baseURL, forKey: Key.baseURL); updateSelectedProviderAddress() } }
    var useFullEndpoint: Bool { didSet { defaults.set(useFullEndpoint, forKey: Key.useFullEndpoint); updateSelectedProviderAddress() } }
    var model: String { didSet { defaults.set(model, forKey: Key.model); updateSelectedModel() } }
    var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) } }
    var streaming: Bool { didSet { defaults.set(streaming, forKey: Key.streaming); updateSelectedModel() } }
    var timeout: Double { didSet { defaults.set(timeout, forKey: Key.timeout); updateSelectedProviderTimeout() } }
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
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            NotificationCenter.default.post(name: .spotAskAppearanceChanged, object: self)
        }
    }
    var fontSize: FontSize { didSet { defaults.set(fontSize.rawValue, forKey: Key.fontSize) } }
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
    var selectionAssistantEnabled: Bool { didSet { defaults.set(selectionAssistantEnabled, forKey: Key.selectionAssistantEnabled) } }
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
        }
    }
    /// Whether a cross-app selection automatically shows the quick actions after
    /// `selectionAutoInvokeDelay` seconds. Defaults off so granting high-impact
    /// accessibility access remains an explicit user decision.
    var selectionAutoInvokeEnabled: Bool {
        didSet { defaults.set(selectionAutoInvokeEnabled, forKey: Key.selectionAutoInvokeEnabled) }
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

    var shortcutAssignments: [InAppShortcutAssignment] {
        inAppShortcutConfiguration.resolvedAssignments(for: enabledPromptPresets)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = defaults.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1"
        useFullEndpoint = defaults.object(forKey: Key.useFullEndpoint) as? Bool ?? false
        model = defaults.string(forKey: Key.model) ?? "gpt-5-mini"
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? "You are a helpful assistant."
        streaming = defaults.object(forKey: Key.streaming) as? Bool ?? true
        timeout = defaults.object(forKey: Key.timeout) as? Double ?? 60
        contextLimit = defaults.object(forKey: Key.contextLimit) as? Int ?? 20
        retainSession = defaults.bool(forKey: Key.retainSession)
        clearInputOnClose = defaults.object(forKey: Key.clearInputOnClose) as? Bool ?? false
        confirmBeforeStartingNewConversation = defaults.object(forKey: Key.confirmBeforeStartingNewConversation) as? Bool ?? true
        escapeStartsNewConversation = defaults.object(forKey: Key.escapeStartsNewConversation) as? Bool ?? false
        defaultExpandReasoning = defaults.object(forKey: Key.defaultExpandReasoning) as? Bool ?? false
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "system") ?? .system
        fontSize = FontSize(rawValue: defaults.string(forKey: Key.fontSize) ?? "standard") ?? .standard
        interfaceZoomLevel = InterfaceZoomLevel(rawValue: defaults.string(forKey: Key.interfaceZoomLevel) ?? "standard") ?? .standard
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "system") ?? .system
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKeyPreset) ?? "optionSpace") ?? .optionSpace
        selectionAssistantEnabled = defaults.object(forKey: Key.selectionAssistantEnabled) as? Bool ?? false
        selectionAssistantMode = SelectionAssistantMode(rawValue: defaults.string(forKey: Key.selectionAssistantMode) ?? "actionBar") ?? .actionBar
        selectionHotKeyPreset = SelectionHotKeyPreset(rawValue: defaults.string(forKey: Key.selectionHotKeyPreset) ?? "optionShiftSpace") ?? .optionShiftSpace
        selectionDefaultPromptID = UUID(uuidString: defaults.string(forKey: Key.selectionDefaultPromptID) ?? "") ?? PromptPreset.builtIn.first?.id
        selectionAssistantToggleShortcut = defaults.data(forKey: Key.selectionAssistantToggleShortcut).flatMap { try? JSONDecoder().decode(InAppShortcut.self, from: $0) }
        selectionAutoInvokeEnabled = defaults.object(forKey: Key.selectionAutoInvokeEnabled) as? Bool ?? false
        selectionAutoInvokeDelay = SelectionAutoInvokeDelay.normalized(
            defaults.object(forKey: Key.selectionAutoInvokeDelay) as? Double ?? SelectionAutoInvokeDelay.defaultValue
        )
        panelWidth = defaults.object(forKey: Key.panelWidth) as? Double ?? 720
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? 520
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        keepWindowOnTop = defaults.object(forKey: Key.keepWindowOnTop) as? Bool ?? false
        promptPresetCatalog = Self.loadPromptPresetCatalog(from: defaults)
        inAppShortcutConfiguration = Self.loadInAppShortcutConfiguration(from: defaults)
        providerRegistryStorage = ProviderModelRegistry(
            defaults: defaults,
            legacy: LegacyProviderConfiguration(
                baseURL: baseURL,
                useFullEndpoint: useFullEndpoint,
                model: model,
                streaming: streaming,
                timeout: timeout
            )
        )
        providerRegistryStorage.setCatalogChangeHandler { [weak self] in
            self?.applyCatalogProjection()
        }
        applyCatalogProjection()
        savePromptPresetCatalog()
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

        let savedPreset = PromptPreset(
            id: preset.id,
            title: title,
            instruction: instruction,
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
        inAppShortcutConfiguration.shortcut(for: target, presets: enabledPromptPresets)
    }

    func shortcutTarget(for shortcut: InAppShortcut) -> InAppShortcutTarget? {
        inAppShortcutConfiguration.target(for: shortcut, presets: enabledPromptPresets)
    }

    @discardableResult
    func assignShortcut(_ shortcut: InAppShortcut, to target: InAppShortcutTarget) -> InAppShortcutAssignmentError? {
        let error = inAppShortcutConfiguration.assign(shortcut, to: target, presets: enabledPromptPresets)
        if error == nil { saveInAppShortcutConfiguration() }
        return error
    }

    @discardableResult
    func removeShortcut(for target: InAppShortcutTarget) -> InAppShortcutAssignmentError? {
        let error = inAppShortcutConfiguration.removeShortcut(for: target, presets: enabledPromptPresets)
        if error == nil { saveInAppShortcutConfiguration() }
        return error
    }

    @discardableResult
    func resetShortcut(for target: InAppShortcutTarget) -> InAppShortcutAssignmentError? {
        let error = inAppShortcutConfiguration.resetShortcut(for: target, presets: enabledPromptPresets)
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
                launchAtLogin: launchAtLogin,
                appearance: appearance.rawValue,
                fontSize: fontSize.rawValue,
                interfaceZoomLevel: interfaceZoomLevel.rawValue,
                language: language.rawValue,
                hotKeyPreset: hotKeyPreset.rawValue,
                keepWindowOnTop: keepWindowOnTop,
                showsMenuBarIcon: showsMenuBarIcon
            ),
            promptPresetCatalog: promptPresetCatalog,
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
        launchAtLogin = general.launchAtLogin
        appearance = AppearanceMode(rawValue: general.appearance) ?? .system
        fontSize = FontSize(rawValue: general.fontSize) ?? .standard
        interfaceZoomLevel = InterfaceZoomLevel(rawValue: general.interfaceZoomLevel) ?? .standard
        language = AppLanguage(rawValue: general.language) ?? .system
        hotKeyPreset = HotKeyPreset(rawValue: general.hotKeyPreset) ?? .optionSpace
        keepWindowOnTop = general.keepWindowOnTop
        showsMenuBarIcon = general.showsMenuBarIcon

        promptPresetCatalog = Self.normalizedPromptPresetCatalog(backup.promptPresetCatalog)
        inAppShortcutConfiguration = backup.shortcutConfiguration
        saveInAppShortcutConfiguration()
        cleanUpShortcutAssignments()

        try providerRegistry.replaceCatalog(with: backup.providerCatalog)
        if let apiKeys = backup.apiKeys, let keyStore {
            let providerIDs = Set(providerRegistry.catalog?.providers.map(\.id) ?? [])
            for (rawID, key) in apiKeys {
                guard let providerID = UUID(uuidString: rawID),
                      providerIDs.contains(providerID) else { continue }
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
        // Disabled presets remain in the catalog so their user-selected
        // shortcuts can become available again when the preset is re-enabled.
        guard inAppShortcutConfiguration.cleanUp(for: promptPresetCatalog) else { return }
        saveInAppShortcutConfiguration()
    }

    private func applyCatalogProjection() {
        guard let catalog = providerRegistry.catalog,
              let selectedModel = catalog.models.first(where: { $0.id == catalog.selectedModelID }),
              let provider = catalog.providers.first(where: { $0.id == selectedModel.providerID }) else { return }
        isApplyingCatalogProjection = true
        baseURL = provider.address
        useFullEndpoint = provider.addressMode.usesFullEndpoint
        model = selectedModel.upstreamModelID
        streaming = selectedModel.isStreamingEnabled
        timeout = provider.timeout
        isApplyingCatalogProjection = false
    }

    // Existing settings controls still edit the selected catalog entries until
    // a dedicated Provider/Model management UI is added.
    private func updateSelectedProviderAddress() {
        guard !isApplyingCatalogProjection,
              let catalog = providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.id == catalog.selectedModelID }),
              var provider = catalog.providers.first(where: { $0.id == model.providerID }) else { return }
        provider.address = baseURL
        provider.addressMode = useFullEndpoint ? .fullEndpoint : .baseURL
        _ = try? providerRegistry.saveProvider(provider)
    }

    private func updateSelectedProviderTimeout() {
        guard !isApplyingCatalogProjection,
              let catalog = providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.id == catalog.selectedModelID }),
              var provider = catalog.providers.first(where: { $0.id == model.providerID }) else { return }
        provider.timeout = timeout
        _ = try? providerRegistry.saveProvider(provider)
    }

    private func updateSelectedModel() {
        guard !isApplyingCatalogProjection,
              let catalog = providerRegistry.catalog,
              var selected = catalog.models.first(where: { $0.id == catalog.selectedModelID }) else { return }
        let previousUpstreamModelID = selected.upstreamModelID
        selected.upstreamModelID = model
        if selected.displayName == previousUpstreamModelID || selected.displayName.isEmpty {
            selected.displayName = model
        }
        selected.isStreamingEnabled = streaming
        _ = try? providerRegistry.saveModel(selected)
    }
}
