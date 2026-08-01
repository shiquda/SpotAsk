import Foundation
import Observation

extension Notification.Name {
    static let spotAskMenuBarIconVisibilityChanged = Notification.Name("com.spotask.menu-bar-icon-visibility-changed")
}

struct PromptPreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var instruction: String
    let isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.isBuiltIn = isBuiltIn
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
            id: UUID(uuidString: "1C85A324-65B3-4EBD-B2C4-0C6B072E284A")!,
            title: L10n.string("preset.polish.title"),
            instruction: L10n.string("preset.polish.instruction"),
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2")!,
            title: L10n.string("preset.summarize.title"),
            instruction: L10n.string("preset.summarize.instruction"),
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248")!,
            title: L10n.string("preset.explainCode.title"),
            instruction: L10n.string("preset.explainCode.instruction"),
            isBuiltIn: true
        )
        ]
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
    }

    private let defaults: UserDefaults
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
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
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
    var customPromptPresets: [PromptPreset] {
        didSet { saveCustomPromptPresets() }
    }

    var promptPresets: [PromptPreset] {
        PromptPreset.builtIn + customPromptPresets
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
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "system") ?? .system
        fontSize = FontSize(rawValue: defaults.string(forKey: Key.fontSize) ?? "standard") ?? .standard
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "system") ?? .system
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKeyPreset) ?? "optionSpace") ?? .optionSpace
        panelWidth = defaults.object(forKey: Key.panelWidth) as? Double ?? 720
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? 520
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        keepWindowOnTop = defaults.object(forKey: Key.keepWindowOnTop) as? Bool ?? false
        customPromptPresets = Self.loadCustomPromptPresets(from: defaults)
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

        let savedPreset = PromptPreset(id: preset.id, title: title, instruction: instruction)
        if let index = customPromptPresets.firstIndex(where: { $0.id == preset.id }) {
            customPromptPresets[index] = savedPreset
        } else {
            customPromptPresets.append(savedPreset)
        }
        return true
    }

    func deleteCustomPromptPreset(id: UUID) {
        customPromptPresets.removeAll { $0.id == id }
    }

    private func saveCustomPromptPresets() {
        guard let data = try? JSONEncoder().encode(customPromptPresets) else { return }
        defaults.set(data, forKey: Key.customPromptPresets)
    }

    private static func loadCustomPromptPresets(from defaults: UserDefaults) -> [PromptPreset] {
        guard let data = defaults.data(forKey: Key.customPromptPresets),
              let presets = try? JSONDecoder().decode([PromptPreset].self, from: data) else {
            return []
        }
        return presets.filter { !$0.isBuiltIn }
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
