import Observation
import AppKit
import Foundation
import SwiftUI

extension Notification.Name {
    static let spotAskMenuBarIconVisibilityChanged = Notification.Name("com.spotask.menu-bar-icon-visibility-changed")
    static let spotAskAppearanceChanged = Notification.Name("com.spotask.appearance-changed")
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

enum PromptPresetOrder {
    static func targetIndex(
        in orderedRowMidYs: [CGFloat],
        currentIndex: Int,
        pointerY: CGFloat,
        hysteresis: CGFloat
    ) -> Int? {
        guard orderedRowMidYs.indices.contains(currentIndex) else { return nil }
        let threshold = max(0, hysteresis)

        if pointerY < orderedRowMidYs[currentIndex] - threshold {
            return orderedRowMidYs.firstIndex { pointerY < $0 - threshold } ?? 0
        }
        if pointerY > orderedRowMidYs[currentIndex] + threshold {
            return orderedRowMidYs.lastIndex { pointerY > $0 + threshold }
                ?? orderedRowMidYs.count - 1
        }
        return currentIndex
    }

    static func moving(
        _ presets: [PromptPreset],
        id: UUID,
        to targetIndex: Int
    ) -> [PromptPreset] {
        guard let sourceIndex = presets.firstIndex(where: { $0.id == id }) else { return presets }
        let destinationIndex = min(max(targetIndex, 0), presets.count - 1)
        guard sourceIndex != destinationIndex else { return presets }

        var reordered = presets
        let preset = reordered.remove(at: sourceIndex)
        reordered.insert(preset, at: destinationIndex)
        return reordered
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
        static let launchAtLogin = "launchAtLogin"
        static let appearance = "appearance"
        static let fontSize = "fontSize"
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
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            NotificationCenter.default.post(name: .spotAskAppearanceChanged, object: self)
        }
    }
    var fontSize: FontSize { didSet { defaults.set(fontSize.rawValue, forKey: Key.fontSize) } }
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            NotificationCenter.default.post(name: .spotAskLanguageChanged, object: nil)
        }
    }
    var hotKeyPreset: HotKeyPreset { didSet { defaults.set(hotKeyPreset.rawValue, forKey: Key.hotKeyPreset) } }
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
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "system") ?? .system
        fontSize = FontSize(rawValue: defaults.string(forKey: Key.fontSize) ?? "standard") ?? .standard
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "system") ?? .system
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKeyPreset) ?? "optionSpace") ?? .optionSpace
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

    func movePromptPreset(id: UUID, before destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = promptPresetCatalog.firstIndex(where: { $0.id == id }),
              let destinationIndex = promptPresetCatalog.firstIndex(where: { $0.id == destinationID }) else { return }
        let preset = promptPresetCatalog.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        promptPresetCatalog.insert(preset, at: insertionIndex)
    }

    /// Applies a completed reorder in one catalog update. Callers can freely
    /// stage transient drag positions without writing UserDefaults until the
    /// final order is known.
    func commitPromptPresetOrder(_ orderedIDs: [UUID]) {
        guard orderedIDs.count == promptPresetCatalog.count,
              Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(promptPresetCatalog.map(\.id)),
              orderedIDs != promptPresetCatalog.map(\.id) else { return }

        let presetsByID = Dictionary(uniqueKeysWithValues: promptPresetCatalog.map { ($0.id, $0) })
        promptPresetCatalog = orderedIDs.compactMap { presetsByID[$0] }
    }

    func enabledPromptPreset(id: UUID) -> PromptPreset? {
        promptPresetCatalog.first(where: { $0.id == id && $0.isEnabled })
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
        guard inAppShortcutConfiguration.cleanUp(for: enabledPromptPresets) else { return }
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
