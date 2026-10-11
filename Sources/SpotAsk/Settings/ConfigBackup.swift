import Foundation

enum SpotAskConfigBackupError: LocalizedError, Equatable {
    case catalogUnavailable
    case keyStoreUnavailable
    case unsupportedSchemaVersion(Int)
    case decodingFailed
    case encodingFailed
    case rollbackFailed(originalErrorDescription: String, rollbackErrorDescriptions: [String])
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
        case let .rollbackFailed(orig, rollbacks):
            "\(orig) (Rollback failed: \(rollbacks.joined(separator: ", ")))"
        }
    }
}

enum SettingBackupValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case stringArray([String])
    case data(Data)

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self { return Int(v) }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var stringArrayValue: [String]? {
        if case .stringArray(let v) = self { return v }
        return nil
    }

    var dataValue: Data? {
        if case .data(let v) = self { return v }
        return nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([String].self) {
            self = .stringArray(a)
        } else if let data = try? container.decode(Data.self) {
            self = .data(data)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported SettingBackupValue")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .stringArray(let a): try container.encode(a)
        case .data(let data): try container.encode(data)
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
    var removedBuiltInQuickActionIDs: [UUID]?
    var shortcutConfiguration: InAppShortcutConfiguration
    var providerCatalog: ProviderModelCatalog
    var apiKeys: [String: String]?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        general: General,
        promptPresetCatalog: [PromptPreset],
        quickActionCatalog: [QuickAction]? = nil,
        removedBuiltInQuickActionIDs: [UUID]? = nil,
        shortcutConfiguration: InAppShortcutConfiguration,
        providerCatalog: ProviderModelCatalog,
        apiKeys: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.general = general
        self.promptPresetCatalog = promptPresetCatalog
        self.quickActionCatalog = quickActionCatalog
        self.removedBuiltInQuickActionIDs = removedBuiltInQuickActionIDs
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
        } else if let legacyProviders = try container.decodeIfPresent([QuickAction].self, forKey: .webQuickAskProviderCatalog) {
            quickActionCatalog = legacyProviders
        } else {
            quickActionCatalog = nil
        }
        removedBuiltInQuickActionIDs = try container.decodeIfPresent([UUID].self, forKey: .removedBuiltInQuickActionIDs)
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
        try container.encodeIfPresent(removedBuiltInQuickActionIDs, forKey: .removedBuiltInQuickActionIDs)
        try container.encode(shortcutConfiguration, forKey: .shortcutConfiguration)
        try container.encode(providerCatalog, forKey: .providerCatalog)
        try container.encodeIfPresent(apiKeys, forKey: .apiKeys)
    }

    struct General: Codable, Equatable, Sendable {
        private(set) var rawValues: [String: SettingBackupValue] = [:]

        subscript(key: String) -> SettingBackupValue? {
            get { rawValues[key] }
            set { rawValues[key] = newValue }
        }

        init(rawValues: [String: SettingBackupValue] = [:]) {
            self.rawValues = rawValues
        }

        init(
            systemPrompt: String = "You are a helpful assistant.",
            contextLimit: Int = 20,
            retainSession: Bool = false,
            clearInputOnClose: Bool = false,
            confirmBeforeStartingNewConversation: Bool = true,
            escapeStartsNewConversation: Bool = false,
            defaultExpandReasoning: Bool = false,
            renderMath: Bool? = true,
            launchAtLogin: Bool = false,
            appearance: String = "system",
            fontSize: String = "standard",
            chatMessageStyle: String? = "standard",
            interfaceZoomLevel: String = "standard",
            language: String = "system",
            hotKeyPreset: String = "optionSpace",
            keepWindowOnTop: Bool = false,
            showsMenuBarIcon: Bool = true,
            automaticUpdateCheckEnabled: Bool? = true,
            updateDownloadSource: String? = "automatic",
            proxyEnabled: Bool? = false,
            proxyType: String? = "http",
            proxyHost: String? = "",
            proxyPort: Int? = 1080,
            proxyUsername: String? = ""
        ) {
            rawValues["systemPrompt"] = .string(systemPrompt)
            rawValues["contextLimit"] = .int(contextLimit)
            rawValues["retainSession"] = .bool(retainSession)
            rawValues["clearInputOnClose"] = .bool(clearInputOnClose)
            rawValues["confirmBeforeStartingNewConversation"] = .bool(confirmBeforeStartingNewConversation)
            rawValues["escapeStartsNewConversation"] = .bool(escapeStartsNewConversation)
            rawValues["defaultExpandReasoning"] = .bool(defaultExpandReasoning)
            if let renderMath { rawValues["renderMath"] = .bool(renderMath) }
            rawValues["launchAtLogin"] = .bool(launchAtLogin)
            rawValues["appearance"] = .string(appearance)
            rawValues["fontSize"] = .string(fontSize)
            if let chatMessageStyle { rawValues["chatMessageStyle"] = .string(chatMessageStyle) }
            rawValues["interfaceZoomLevel"] = .string(interfaceZoomLevel)
            rawValues["language"] = .string(language)
            rawValues["hotKeyPreset"] = .string(hotKeyPreset)
            rawValues["keepWindowOnTop"] = .bool(keepWindowOnTop)
            rawValues["showsMenuBarIcon"] = .bool(showsMenuBarIcon)
            if let automaticUpdateCheckEnabled { rawValues["automaticUpdateCheckEnabled"] = .bool(automaticUpdateCheckEnabled) }
            if let updateDownloadSource { rawValues["updateDownloadSource"] = .string(updateDownloadSource) }
            if let proxyEnabled { rawValues["proxyEnabled"] = .bool(proxyEnabled) }
            if let proxyType { rawValues["proxyType"] = .string(proxyType) }
            if let proxyHost { rawValues["proxyHost"] = .string(proxyHost) }
            if let proxyPort { rawValues["proxyPort"] = .int(proxyPort) }
            if let proxyUsername { rawValues["proxyUsername"] = .string(proxyUsername) }
        }

        var systemPrompt: String {
            get { rawValues["systemPrompt"]?.stringValue ?? "You are a helpful assistant." }
            set { rawValues["systemPrompt"] = .string(newValue) }
        }
        var contextLimit: Int {
            get { rawValues["contextLimit"]?.intValue ?? 20 }
            set { rawValues["contextLimit"] = .int(newValue) }
        }
        var retainSession: Bool {
            get { rawValues["retainSession"]?.boolValue ?? false }
            set { rawValues["retainSession"] = .bool(newValue) }
        }
        var clearInputOnClose: Bool {
            get { rawValues["clearInputOnClose"]?.boolValue ?? false }
            set { rawValues["clearInputOnClose"] = .bool(newValue) }
        }
        var confirmBeforeStartingNewConversation: Bool {
            get { rawValues["confirmBeforeStartingNewConversation"]?.boolValue ?? true }
            set { rawValues["confirmBeforeStartingNewConversation"] = .bool(newValue) }
        }
        var escapeStartsNewConversation: Bool {
            get { rawValues["escapeStartsNewConversation"]?.boolValue ?? false }
            set { rawValues["escapeStartsNewConversation"] = .bool(newValue) }
        }
        var defaultExpandReasoning: Bool {
            get { rawValues["defaultExpandReasoning"]?.boolValue ?? false }
            set { rawValues["defaultExpandReasoning"] = .bool(newValue) }
        }
        var renderMath: Bool? {
            get { rawValues["renderMath"]?.boolValue }
            set {
                if let newValue { rawValues["renderMath"] = .bool(newValue) }
                else { rawValues.removeValue(forKey: "renderMath") }
            }
        }
        var launchAtLogin: Bool {
            get { rawValues["launchAtLogin"]?.boolValue ?? false }
            set { rawValues["launchAtLogin"] = .bool(newValue) }
        }
        var appearance: String {
            get { rawValues["appearance"]?.stringValue ?? "system" }
            set { rawValues["appearance"] = .string(newValue) }
        }
        var fontSize: String {
            get { rawValues["fontSize"]?.stringValue ?? "standard" }
            set { rawValues["fontSize"] = .string(newValue) }
        }
        var chatMessageStyle: String? {
            get { rawValues["chatMessageStyle"]?.stringValue }
            set {
                if let newValue { rawValues["chatMessageStyle"] = .string(newValue) }
                else { rawValues.removeValue(forKey: "chatMessageStyle") }
            }
        }
        var interfaceZoomLevel: String {
            get { rawValues["interfaceZoomLevel"]?.stringValue ?? "standard" }
            set { rawValues["interfaceZoomLevel"] = .string(newValue) }
        }
        var language: String {
            get { rawValues["language"]?.stringValue ?? "system" }
            set { rawValues["language"] = .string(newValue) }
        }
        var hotKeyPreset: String {
            get { rawValues["hotKeyPreset"]?.stringValue ?? "optionSpace" }
            set { rawValues["hotKeyPreset"] = .string(newValue) }
        }
        var keepWindowOnTop: Bool {
            get { rawValues["keepWindowOnTop"]?.boolValue ?? false }
            set { rawValues["keepWindowOnTop"] = .bool(newValue) }
        }
        var showsMenuBarIcon: Bool {
            get { rawValues["showsMenuBarIcon"]?.boolValue ?? true }
            set { rawValues["showsMenuBarIcon"] = .bool(newValue) }
        }
        var automaticUpdateCheckEnabled: Bool? {
            get { rawValues["automaticUpdateCheckEnabled"]?.boolValue }
            set {
                if let newValue { rawValues["automaticUpdateCheckEnabled"] = .bool(newValue) }
                else { rawValues.removeValue(forKey: "automaticUpdateCheckEnabled") }
            }
        }
        var updateDownloadSource: String? {
            get { rawValues["updateDownloadSource"]?.stringValue }
            set {
                if let newValue { rawValues["updateDownloadSource"] = .string(newValue) }
                else { rawValues.removeValue(forKey: "updateDownloadSource") }
            }
        }
        var proxyEnabled: Bool? {
            get { rawValues["proxyEnabled"]?.boolValue }
            set {
                if let newValue { rawValues["proxyEnabled"] = .bool(newValue) }
                else { rawValues.removeValue(forKey: "proxyEnabled") }
            }
        }
        var proxyType: String? {
            get { rawValues["proxyType"]?.stringValue }
            set {
                if let newValue { rawValues["proxyType"] = .string(newValue) }
                else { rawValues.removeValue(forKey: "proxyType") }
            }
        }
        var proxyHost: String? {
            get { rawValues["proxyHost"]?.stringValue }
            set {
                if let newValue { rawValues["proxyHost"] = .string(newValue) }
                else { rawValues.removeValue(forKey: "proxyHost") }
            }
        }
        var proxyPort: Int? {
            get { rawValues["proxyPort"]?.intValue }
            set {
                if let newValue { rawValues["proxyPort"] = .int(newValue) }
                else { rawValues.removeValue(forKey: "proxyPort") }
            }
        }
        var proxyUsername: String? {
            get { rawValues["proxyUsername"]?.stringValue }
            set {
                if let newValue { rawValues["proxyUsername"] = .string(newValue) }
                else { rawValues.removeValue(forKey: "proxyUsername") }
            }
        }

        private struct DynamicCodingKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var values: [String: SettingBackupValue] = [:]
            for key in container.allKeys {
                if let val = try? container.decode(SettingBackupValue.self, forKey: key) {
                    values[key.stringValue] = val
                }
            }
            self.rawValues = values
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in rawValues.sorted(by: { $0.key < $1.key }) {
                if let key = DynamicCodingKey(stringValue: k) {
                    try container.encode(v, forKey: key)
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case general
        case promptPresetCatalog
        case quickActionCatalog
        case removedBuiltInQuickActionIDs
        case webQuickAskProviderCatalog
        case shortcutConfiguration
        case providerCatalog
        case apiKeys
    }
}
