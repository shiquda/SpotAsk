import Foundation

enum SpotAskConfigBackupError: LocalizedError, Equatable {
    case catalogUnavailable
    case keyStoreUnavailable
    case unsupportedSchemaVersion(Int)
    case decodingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            L10n.string("settings.configCatalogUnavailable")
        case .keyStoreUnavailable:
            L10n.string("settings.configKeyStoreUnavailable")
        case let .unsupportedSchemaVersion(version):
            L10n.string("settings.configUnsupportedVersion", version)
        case .decodingFailed:
            L10n.string("settings.configDecodingFailed")
        case .encodingFailed:
            L10n.string("settings.configEncodingFailed")
        }
    }
}

/// A portable snapshot of SpotAsk's preferences. Access keys are optional so
/// an export can be shared without leaking credentials by default.
struct SpotAskConfigBackup: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var general: General
    var promptPresetCatalog: [PromptPreset]
    var quickActionCatalog: [QuickAction]?
    var shortcutConfiguration: InAppShortcutConfiguration
    var providerCatalog: ProviderModelCatalog
    var apiKeys: [String: String]?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        general: General,
        promptPresetCatalog: [PromptPreset],
        quickActionCatalog: [QuickAction]? = nil,
        shortcutConfiguration: InAppShortcutConfiguration,
        providerCatalog: ProviderModelCatalog,
        apiKeys: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.general = general
        self.promptPresetCatalog = promptPresetCatalog
        self.quickActionCatalog = quickActionCatalog
        self.shortcutConfiguration = shortcutConfiguration
        self.providerCatalog = providerCatalog
        self.apiKeys = apiKeys
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        general = try container.decode(General.self, forKey: .general)
        promptPresetCatalog = try container.decode([PromptPreset].self, forKey: .promptPresetCatalog)
        if let actions = try container.decodeIfPresent([QuickAction].self, forKey: .quickActionCatalog) {
            quickActionCatalog = actions
        } else if let legacyActions = try container.decodeIfPresent([QuickAction].self, forKey: .webQuickAskProviderCatalog) {
            quickActionCatalog = legacyActions
        } else {
            quickActionCatalog = nil
        }
        shortcutConfiguration = try container.decode(InAppShortcutConfiguration.self, forKey: .shortcutConfiguration)
        providerCatalog = try container.decode(ProviderModelCatalog.self, forKey: .providerCatalog)
        apiKeys = try container.decodeIfPresent([String: String].self, forKey: .apiKeys)
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(general, forKey: .general)
        try container.encode(promptPresetCatalog, forKey: .promptPresetCatalog)
        try container.encodeIfPresent(quickActionCatalog, forKey: .quickActionCatalog)
        try container.encode(shortcutConfiguration, forKey: .shortcutConfiguration)
        try container.encode(providerCatalog, forKey: .providerCatalog)
        try container.encodeIfPresent(apiKeys, forKey: .apiKeys)
    }

    struct General: Codable, Equatable, Sendable {
        var systemPrompt: String
        var contextLimit: Int
        var retainSession: Bool
        var clearInputOnClose: Bool
        var confirmBeforeStartingNewConversation: Bool
        var escapeStartsNewConversation: Bool
        var defaultExpandReasoning: Bool
        var renderMath: Bool?
        var launchAtLogin: Bool
        var appearance: String
        var fontSize: String
        var chatMessageStyle: String?
        var interfaceZoomLevel: String
        var language: String
        var hotKeyPreset: String
        var keepWindowOnTop: Bool
        var showsMenuBarIcon: Bool
        var automaticUpdateCheckEnabled: Bool?
        var proxyEnabled: Bool?
        var proxyType: String?
        var proxyHost: String?
        var proxyPort: Int?
        var proxyUsername: String?
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case general
        case promptPresetCatalog
        case quickActionCatalog
        case webQuickAskProviderCatalog
        case shortcutConfiguration
        case providerCatalog
        case apiKeys
    }
}
