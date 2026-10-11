import AppKit
import Foundation

@MainActor
protocol AnySettingDescriptor: Sendable {
    var key: String { get }
    func load(into settings: AppSettings, from defaults: UserDefaults)
    func save(from settings: AppSettings, to defaults: UserDefaults)
    func reset(in settings: AppSettings, defaults: UserDefaults)
    func exportValue(from settings: AppSettings, to general: inout SpotAskConfigBackup.General)
    func importValue(into settings: AppSettings, from general: SpotAskConfigBackup.General)
}

@MainActor
struct SettingDescriptor<Value: Equatable & Sendable>: AnySettingDescriptor {
    let key: String
    let backupKey: String?
    var effectiveBackupKey: String { backupKey ?? key }
    let defaultValue: Value
    let resetValue: Value
    let keyPath: ReferenceWritableKeyPath<AppSettings, Value>?
    let getter: ((AppSettings) -> Value)?
    let setter: ((AppSettings, Value) -> Void)?
    let readFromDefaults: (UserDefaults, String, Value) -> Value
    let writeToDefaults: (UserDefaults, String, Value) -> Void
    let removeFromDefaults: ((UserDefaults, String) -> Void)?
    let encodeToBackup: (Value) -> SettingBackupValue?
    let decodeFromBackup: (SettingBackupValue) -> Value?
    let onChanged: ((AppSettings, Value) -> Void)?

    init(
        key: String,
        backupKey: String? = nil,
        defaultValue: Value,
        resetValue: Value? = nil,
        keyPath: ReferenceWritableKeyPath<AppSettings, Value>? = nil,
        getter: ((AppSettings) -> Value)? = nil,
        setter: ((AppSettings, Value) -> Void)? = nil,
        readFromDefaults: @escaping (UserDefaults, String, Value) -> Value,
        writeToDefaults: @escaping (UserDefaults, String, Value) -> Void,
        removeFromDefaults: ((UserDefaults, String) -> Void)? = nil,
        encodeToBackup: @escaping (Value) -> SettingBackupValue?,
        decodeFromBackup: @escaping (SettingBackupValue) -> Value?,
        onChanged: ((AppSettings, Value) -> Void)? = nil
    ) {
        self.key = key
        self.backupKey = backupKey
        self.defaultValue = defaultValue
        self.resetValue = resetValue ?? defaultValue
        self.keyPath = keyPath
        self.getter = getter
        self.setter = setter
        self.readFromDefaults = readFromDefaults
        self.writeToDefaults = writeToDefaults
        self.removeFromDefaults = removeFromDefaults
        self.encodeToBackup = encodeToBackup
        self.decodeFromBackup = decodeFromBackup
        self.onChanged = onChanged
    }

    func getValue(_ settings: AppSettings) -> Value {
        if let keyPath { return settings[keyPath: keyPath] }
        if let getter { return getter(settings) }
        return (settings.dynamicSettingStorage[key] as? Value) ?? defaultValue
    }

    func setValue(_ settings: AppSettings, _ value: Value) {
        if let keyPath {
            settings[keyPath: keyPath] = value
            return
        }
        if let setter {
            setter(settings, value)
            return
        }
        settings.dynamicSettingStorage[key] = value
    }

    func load(into settings: AppSettings, from defaults: UserDefaults) {
        let loaded = readFromDefaults(defaults, key, defaultValue)
        setValue(settings, loaded)
    }

    func save(from settings: AppSettings, to defaults: UserDefaults) {
        let current = getValue(settings)
        writeToDefaults(defaults, key, current)
        onChanged?(settings, current)
    }

    func reset(in settings: AppSettings, defaults: UserDefaults) {
        if let removeFromDefaults {
            removeFromDefaults(defaults, key)
        } else {
            defaults.removeObject(forKey: key)
        }
        setValue(settings, resetValue)
        onChanged?(settings, resetValue)
    }

    func exportValue(from settings: AppSettings, to general: inout SpotAskConfigBackup.General) {
        let current = getValue(settings)
        if let backupVal = encodeToBackup(current) {
            general[effectiveBackupKey] = backupVal
        }
    }

    func importValue(into settings: AppSettings, from general: SpotAskConfigBackup.General) {
        guard let backupVal = general[effectiveBackupKey] ?? general[key], let val = decodeFromBackup(backupVal) else { return }
        setValue(settings, val)
        writeToDefaults(settings.defaults, key, val)
        onChanged?(settings, val)
    }
}

// MARK: - Factory Helpers

@MainActor
enum SettingDescriptors {
    static func bool(
        key: String,
        defaultValue: Bool,
        resetValue: Bool? = nil,
        keyPath: ReferenceWritableKeyPath<AppSettings, Bool>? = nil,
        onChanged: ((AppSettings, Bool) -> Void)? = nil
    ) -> SettingDescriptor<Bool> {
        SettingDescriptor<Bool>(
            key: key,
            defaultValue: defaultValue,
            resetValue: resetValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                defaults.object(forKey: k) as? Bool ?? def
            },
            writeToDefaults: { defaults, k, val in
                defaults.set(val, forKey: k)
            },
            encodeToBackup: { .bool($0) },
            decodeFromBackup: { $0.boolValue },
            onChanged: onChanged
        )
    }

    static func int(
        key: String,
        defaultValue: Int,
        resetValue: Int? = nil,
        keyPath: ReferenceWritableKeyPath<AppSettings, Int>? = nil,
        onChanged: ((AppSettings, Int) -> Void)? = nil
    ) -> SettingDescriptor<Int> {
        SettingDescriptor<Int>(
            key: key,
            defaultValue: defaultValue,
            resetValue: resetValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                defaults.object(forKey: k) as? Int ?? def
            },
            writeToDefaults: { defaults, k, val in
                defaults.set(val, forKey: k)
            },
            encodeToBackup: { .int($0) },
            decodeFromBackup: { $0.intValue },
            onChanged: onChanged
        )
    }

    static func double(
        key: String,
        defaultValue: Double,
        resetValue: Double? = nil,
        keyPath: ReferenceWritableKeyPath<AppSettings, Double>? = nil,
        normalize: ((Double) -> Double)? = nil,
        onChanged: ((AppSettings, Double) -> Void)? = nil
    ) -> SettingDescriptor<Double> {
        SettingDescriptor<Double>(
            key: key,
            defaultValue: defaultValue,
            resetValue: resetValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                let raw = defaults.object(forKey: k) as? Double ?? def
                return normalize?(raw) ?? raw
            },
            writeToDefaults: { defaults, k, val in
                let norm = normalize?(val) ?? val
                defaults.set(norm, forKey: k)
            },
            encodeToBackup: { .double($0) },
            decodeFromBackup: { $0.doubleValue },
            onChanged: onChanged
        )
    }

    static func optionalDouble(
        key: String,
        defaultValue: Double? = nil,
        getter: ((AppSettings) -> Double?)? = nil,
        setter: ((AppSettings, Double?) -> Void)? = nil,
        onChanged: ((AppSettings, Double?) -> Void)? = nil
    ) -> SettingDescriptor<Double?> {
        SettingDescriptor<Double?>(
            key: key,
            defaultValue: defaultValue,
            getter: getter,
            setter: setter,
            readFromDefaults: { defaults, k, _ in
                defaults.object(forKey: k) as? Double
            },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { val in val.map { .double($0) } },
            decodeFromBackup: { $0.doubleValue },
            onChanged: onChanged
        )
    }

    static func string(
        key: String,
        defaultValue: String,
        resetValue: String? = nil,
        keyPath: ReferenceWritableKeyPath<AppSettings, String>? = nil,
        onChanged: ((AppSettings, String) -> Void)? = nil
    ) -> SettingDescriptor<String> {
        SettingDescriptor<String>(
            key: key,
            defaultValue: defaultValue,
            resetValue: resetValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                defaults.string(forKey: k) ?? def
            },
            writeToDefaults: { defaults, k, val in
                defaults.set(val, forKey: k)
            },
            encodeToBackup: { .string($0) },
            decodeFromBackup: { $0.stringValue },
            onChanged: onChanged
        )
    }

    static func stringArray(
        key: String,
        defaultValue: [String] = [],
        keyPath: ReferenceWritableKeyPath<AppSettings, [String]>? = nil,
        onChanged: ((AppSettings, [String]) -> Void)? = nil
    ) -> SettingDescriptor<[String]> {
        SettingDescriptor<[String]>(
            key: key,
            defaultValue: defaultValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                defaults.stringArray(forKey: k) ?? def
            },
            writeToDefaults: { defaults, k, val in
                defaults.set(val, forKey: k)
            },
            encodeToBackup: { .stringArray($0) },
            decodeFromBackup: { $0.stringArrayValue },
            onChanged: onChanged
        )
    }

    static func rawRepresentable<E: RawRepresentable & Equatable & Sendable>(
        key: String,
        defaultValue: E,
        resetValue: E? = nil,
        backupKey: String? = nil,
        keyPath: ReferenceWritableKeyPath<AppSettings, E>? = nil,
        onChanged: ((AppSettings, E) -> Void)? = nil
    ) -> SettingDescriptor<E> where E.RawValue == String {
        SettingDescriptor<E>(
            key: key,
            backupKey: backupKey,
            defaultValue: defaultValue,
            resetValue: resetValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                defaults.string(forKey: k).flatMap(E.init(rawValue:)) ?? def
            },
            writeToDefaults: { defaults, k, val in
                defaults.set(val.rawValue, forKey: k)
            },
            encodeToBackup: { .string($0.rawValue) },
            decodeFromBackup: { $0.stringValue.flatMap(E.init(rawValue:)) },
            onChanged: onChanged
        )
    }

    static func uuid(
        key: String,
        defaultValue: UUID?,
        keyPath: ReferenceWritableKeyPath<AppSettings, UUID?>? = nil,
        onChanged: ((AppSettings, UUID?) -> Void)? = nil
    ) -> SettingDescriptor<UUID?> {
        SettingDescriptor<UUID?>(
            key: key,
            defaultValue: defaultValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                UUID(uuidString: defaults.string(forKey: k) ?? "") ?? def
            },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val.uuidString, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { val in val.map { .string($0.uuidString) } },
            decodeFromBackup: { $0.stringValue.flatMap(UUID.init(uuidString:)) },
            onChanged: onChanged
        )
    }

    static func codable<C: Codable & Equatable & Sendable>(
        key: String,
        defaultValue: C?,
        keyPath: ReferenceWritableKeyPath<AppSettings, C?>? = nil,
        onChanged: ((AppSettings, C?) -> Void)? = nil
    ) -> SettingDescriptor<C?> {
        SettingDescriptor<C?>(
            key: key,
            defaultValue: defaultValue,
            keyPath: keyPath,
            readFromDefaults: { defaults, k, def in
                defaults.data(forKey: k).flatMap { try? JSONDecoder().decode(C.self, from: $0) } ?? def
            },
            writeToDefaults: { defaults, k, val in
                if let val, let data = try? JSONEncoder().encode(val) {
                    defaults.set(data, forKey: k)
                } else {
                    defaults.removeObject(forKey: k)
                }
            },
            encodeToBackup: { val in
                val.flatMap { item in
                    (try? JSONEncoder().encode(item)).map { .data($0) }
                }
            },
            decodeFromBackup: { val in
                val.dataValue.flatMap { try? JSONDecoder().decode(C.self, from: $0) }
            },
            onChanged: onChanged
        )
    }
}

// MARK: - SettingRegistry

@MainActor
final class SettingRegistry: Sendable {
    static let shared = SettingRegistry()

    private var isInitialized = false
    private var _descriptors: [any AnySettingDescriptor] = []
    private var descriptorsByKey: [String: any AnySettingDescriptor] = [:]

    var descriptors: [any AnySettingDescriptor] {
        registerStandardSettingsIfNeeded()
        return _descriptors
    }

    init() {}

    func registerStandardSettingsIfNeeded() {
        guard !isInitialized else { return }
        isInitialized = true
        registerStandardSettings()
    }

    func resetToStandardSettings() {
        _descriptors.removeAll()
        descriptorsByKey.removeAll()
        isInitialized = false
        registerStandardSettingsIfNeeded()
    }

    func register(_ descriptor: any AnySettingDescriptor) {
        registerStandardSettingsIfNeeded()
        _descriptors.removeAll { $0.key == descriptor.key }
        _descriptors.append(descriptor)
        descriptorsByKey[descriptor.key] = descriptor
    }

    func unregister(key: String) {
        _descriptors.removeAll { $0.key == key }
        descriptorsByKey.removeValue(forKey: key)
    }

    func descriptor(forKey key: String) -> (any AnySettingDescriptor)? {
        registerStandardSettingsIfNeeded()
        return descriptorsByKey[key]
    }

    func registerStandardSettings() {
        register(SettingDescriptors.string(
            key: "systemPrompt",
            defaultValue: "You are a helpful assistant.",
            resetValue: "",
            keyPath: \.systemPrompt
        ))
        register(SettingDescriptors.int(
            key: "contextLimit",
            defaultValue: 20,
            keyPath: \.contextLimit
        ))
        register(SettingDescriptors.bool(
            key: "retainSession",
            defaultValue: false,
            resetValue: true,
            keyPath: \.retainSession
        ))
        register(SettingDescriptors.bool(
            key: "clearInputOnClose",
            defaultValue: false,
            keyPath: \.clearInputOnClose
        ))
        register(SettingDescriptors.bool(
            key: "confirmBeforeStartingNewConversation",
            defaultValue: true,
            keyPath: \.confirmBeforeStartingNewConversation
        ))
        register(SettingDescriptors.bool(
            key: "escapeStartsNewConversation",
            defaultValue: false,
            resetValue: true,
            keyPath: \.escapeStartsNewConversation
        ))
        register(SettingDescriptors.bool(
            key: "defaultExpandReasoning",
            defaultValue: false,
            keyPath: \.defaultExpandReasoning
        ))
        register(SettingDescriptors.bool(
            key: "renderMath",
            defaultValue: true,
            keyPath: \.renderMath
        ))
        register(SettingDescriptors.bool(
            key: "launchAtLogin",
            defaultValue: false,
            keyPath: \.launchAtLogin
        ))
        register(SettingDescriptors.bool(
            key: "silentLaunch",
            defaultValue: false,
            keyPath: \.silentLaunch
        ))
        register(SettingDescriptors.bool(
            key: "proxyEnabled",
            defaultValue: false,
            keyPath: \.proxyEnabled
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "proxyType",
            defaultValue: ProxyType.http,
            keyPath: \.proxyType
        ))
        register(SettingDescriptors.string(
            key: "proxyHost",
            defaultValue: "",
            keyPath: \.proxyHost
        ))
        register(SettingDescriptors.int(
            key: "proxyPort",
            defaultValue: 1080,
            keyPath: \.proxyPort
        ))
        register(SettingDescriptors.string(
            key: "proxyUsername",
            defaultValue: "",
            keyPath: \.proxyUsername
        ))
        register(SettingDescriptors.bool(
            key: "diagnosticsEnabled",
            defaultValue: false,
            keyPath: \.diagnosticsEnabled,
            onChanged: { _, enabled in
                DiagnosticLogStore.shared.setEnabled(enabled)
            }
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "appearance",
            defaultValue: AppearanceMode.system,
            keyPath: \.appearance,
            onChanged: { settings, _ in
                NotificationCenter.default.post(name: .spotAskAppearanceChanged, object: settings)
            }
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "fontSize",
            defaultValue: FontSize.standard,
            keyPath: \.fontSize
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "chatMessageStyle",
            defaultValue: ChatMessageStyle.standard,
            keyPath: \.chatMessageStyle
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "interfaceZoomLevel",
            defaultValue: InterfaceZoomLevel.standard,
            keyPath: \.interfaceZoomLevel
        ))
        register(SettingDescriptors.rawRepresentable(
            key: AppLanguage.defaultsKey,
            defaultValue: AppLanguage.system,
            backupKey: "language",
            keyPath: \.language,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskLanguageChanged, object: nil)
            }
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "hotKeyPreset",
            defaultValue: HotKeyPreset.optionSpace,
            keyPath: \.hotKeyPreset
        ))
        register(SettingDescriptor<InAppShortcut?>(
            key: "globalShortcut",
            defaultValue: nil,
            keyPath: \.globalShortcut,
            readFromDefaults: { defaults, k, _ in
                AppSettings.loadGlobalShortcut(
                    from: defaults,
                    hotKeyPreset: defaults.string(forKey: "hotKeyPreset").flatMap(HotKeyPreset.init(rawValue:)) ?? .optionSpace
                )
            },
            writeToDefaults: { defaults, k, val in
                if let val {
                    if let data = try? JSONEncoder().encode(val) {
                        defaults.set(data, forKey: k)
                    }
                } else {
                    defaults.set(Data(), forKey: k)
                }
            },
            removeFromDefaults: { defaults, k in
                defaults.removeObject(forKey: k)
            },
            encodeToBackup: { val in
                val.flatMap { item in (try? JSONEncoder().encode(item)).map { .data($0) } }
            },
            decodeFromBackup: { val in
                val.dataValue.flatMap { try? JSONDecoder().decode(InAppShortcut.self, from: $0) }
            },
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskHotKeyChanged, object: nil)
            }
        ))
        register(SettingDescriptors.double(
            key: "panelWidth",
            defaultValue: 720.0,
            keyPath: \.panelWidth
        ))
        register(SettingDescriptors.double(
            key: "panelHeight",
            defaultValue: 520.0,
            keyPath: \.panelHeight
        ))
        register(SettingDescriptor<Double?>(
            key: "panelOriginX",
            defaultValue: nil,
            getter: { $0.panelOrigin.map { Double($0.x) } },
            setter: { settings, val in
                if let val {
                    let currentY = settings.panelOrigin?.y ?? 0
                    settings.panelOrigin = CGPoint(x: CGFloat(val), y: currentY)
                } else {
                    settings.panelOrigin = nil
                }
            },
            readFromDefaults: { defaults, k, _ in defaults.object(forKey: k) as? Double },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { $0.map { .double($0) } },
            decodeFromBackup: { $0.doubleValue }
        ))
        register(SettingDescriptor<Double?>(
            key: "panelOriginY",
            defaultValue: nil,
            getter: { $0.panelOrigin.map { Double($0.y) } },
            setter: { settings, val in
                if let val {
                    let currentX = settings.panelOrigin?.x ?? 0
                    settings.panelOrigin = CGPoint(x: currentX, y: CGFloat(val))
                } else {
                    settings.panelOrigin = nil
                }
            },
            readFromDefaults: { defaults, k, _ in defaults.object(forKey: k) as? Double },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { $0.map { .double($0) } },
            decodeFromBackup: { $0.doubleValue }
        ))
        register(SettingDescriptors.bool(
            key: "keepWindowOnTop",
            defaultValue: false,
            keyPath: \.keepWindowOnTop
        ))
        register(SettingDescriptors.bool(
            key: "showsMenuBarIcon",
            defaultValue: true,
            keyPath: \.showsMenuBarIcon,
            onChanged: { settings, _ in
                NotificationCenter.default.post(name: .spotAskMenuBarIconVisibilityChanged, object: settings)
            }
        ))
        register(SettingDescriptors.bool(
            key: "selectionAssistantEnabled",
            defaultValue: false,
            keyPath: \.selectionAssistantEnabled,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
            }
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "selectionAssistantMode",
            defaultValue: SelectionAssistantMode.actionBar,
            keyPath: \.selectionAssistantMode
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "selectionHotKeyPreset",
            defaultValue: SelectionHotKeyPreset.optionShiftSpace,
            keyPath: \.selectionHotKeyPreset
        ))
        register(SettingDescriptors.uuid(
            key: "selectionDefaultPromptID",
            defaultValue: PromptPreset.builtIn.first?.id,
            keyPath: \.selectionDefaultPromptID
        ))
        register(SettingDescriptors.codable(
            key: "selectionAssistantToggleShortcut",
            defaultValue: nil,
            keyPath: \.selectionAssistantToggleShortcut,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
            }
        ))
        register(SettingDescriptors.bool(
            key: "selectionAutoInvokeEnabled",
            defaultValue: false,
            keyPath: \.selectionAutoInvokeEnabled,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
            }
        ))
        register(SettingDescriptors.double(
            key: "selectionAutoInvokeDelay",
            defaultValue: SelectionAutoInvokeDelay.defaultValue,
            keyPath: \.selectionAutoInvokeDelay,
            normalize: SelectionAutoInvokeDelay.normalized
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "selectionAutoInvokeScope",
            defaultValue: SelectionAutoInvokeScope.allApps,
            keyPath: \.selectionAutoInvokeScope
        ))
        register(SettingDescriptors.stringArray(
            key: "selectionAutoInvokeBlacklist",
            defaultValue: [],
            keyPath: \.selectionAutoInvokeBlacklist
        ))
        register(SettingDescriptors.stringArray(
            key: "selectionAutoInvokeWhitelist",
            defaultValue: [],
            keyPath: \.selectionAutoInvokeWhitelist
        ))
        register(SettingDescriptors.bool(
            key: "clipboardAssistedSelectionEnabled",
            defaultValue: false,
            keyPath: \.clipboardAssistedSelectionEnabled,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
            }
        ))
        register(SettingDescriptors.stringArray(
            key: "clipboardAssistedSelectionAppIdentifiers",
            defaultValue: [],
            keyPath: \.clipboardAssistedSelectionAppIdentifiers,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
            }
        ))
        register(SettingDescriptors.bool(
            key: "selectionActionBarShowsChatAction",
            defaultValue: true,
            keyPath: \.selectionActionBarShowsChatAction,
            onChanged: { _, _ in
                NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
            }
        ))
        register(SettingDescriptors.bool(
            key: "selectionActionBarShowsLabels",
            defaultValue: true,
            keyPath: \.selectionActionBarShowsLabels
        ))
        register(SettingDescriptors.bool(
            key: "selectionActionBarShowsPrompts",
            defaultValue: true,
            keyPath: \.selectionActionBarShowsPrompts
        ))
        register(SettingDescriptors.bool(
            key: "selectionActionBarShowsExternalAsk",
            defaultValue: true,
            keyPath: \.selectionActionBarShowsExternalAsk
        ))
        register(SettingDescriptors.bool(
            key: "automaticUpdateCheckEnabled",
            defaultValue: true,
            keyPath: \.automaticUpdateCheckEnabled
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "updateDownloadSource",
            defaultValue: UpdateDownloadSource.automatic,
            keyPath: \.updateDownloadSource
        ))
        register(SettingDescriptors.bool(
            key: "webQuickAskEnabled",
            defaultValue: true,
            keyPath: \.externalAskEnabled
        ))
        register(SettingDescriptors.bool(
            key: "decisionRoutingEnabled",
            defaultValue: false,
            keyPath: \.decisionRoutingEnabled
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "decisionRoutingEndpoint",
            defaultValue: DecisionEndpointKind.official,
            keyPath: \.decisionRoutingEndpoint
        ))
        register(SettingDescriptors.string(
            key: "decisionRoutingOfficialModel",
            defaultValue: DecisionRoutingPolicy.defaultOfficialModel,
            keyPath: \.decisionRoutingOfficialModel
        ))
        register(SettingDescriptors.string(
            key: "decisionRoutingCustomBaseURL",
            defaultValue: "",
            keyPath: \.decisionRoutingCustomBaseURL
        ))
        register(SettingDescriptors.string(
            key: "decisionRoutingCustomModel",
            defaultValue: "",
            keyPath: \.decisionRoutingCustomModel
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "decisionRoutingConfirmationMode",
            defaultValue: DecisionConfirmationMode.always,
            keyPath: \.decisionRoutingConfirmationMode
        ))
        register(SettingDescriptors.double(
            key: "decisionRoutingConfidenceThreshold",
            defaultValue: DecisionRoutingPolicy.defaultThreshold,
            keyPath: \.decisionRoutingConfidenceThreshold,
            normalize: DecisionRoutingPolicy.normalizedThreshold
        ))
        register(SettingDescriptors.double(
            key: "decisionRoutingTimeoutSeconds",
            defaultValue: DecisionRoutingPolicy.defaultTimeoutSeconds,
            keyPath: \.decisionRoutingTimeoutSeconds,
            normalize: DecisionRoutingPolicy.normalizedTimeout
        ))
        register(SettingDescriptors.rawRepresentable(
            key: "decisionRoutingTimeoutAction",
            defaultValue: DecisionTimeoutAction.manualSelection,
            keyPath: \.decisionRoutingTimeoutAction
        ))
        register(SettingDescriptors.string(
            key: "decisionRoutingInAppDescription",
            defaultValue: "",
            keyPath: \.decisionRoutingInAppDescription
        ))

        // Legacy provider keys (managed via ProviderModelRegistry)
        register(SettingDescriptors.string(
            key: "baseURL",
            defaultValue: "https://api.openai.com/v1"
        ))
        register(SettingDescriptors.bool(
            key: "useFullEndpoint",
            defaultValue: false
        ))
        register(SettingDescriptors.string(
            key: "model",
            defaultValue: "gpt-5-mini"
        ))
        register(SettingDescriptors.bool(
            key: "streaming",
            defaultValue: true
        ))
        register(SettingDescriptors.double(
            key: "timeout",
            defaultValue: 60.0
        ))

        // Catalog keys (managed via dedicated catalogs, cleared on reset)
        register(SettingDescriptor<Data?>(
            key: "customPromptPresets",
            defaultValue: nil,
            readFromDefaults: { defaults, k, _ in defaults.data(forKey: k) },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { _ in nil },
            decodeFromBackup: { _ in nil }
        ))
        register(SettingDescriptor<Data?>(
            key: "promptPresetCatalog",
            defaultValue: nil,
            readFromDefaults: { defaults, k, _ in defaults.data(forKey: k) },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { _ in nil },
            decodeFromBackup: { _ in nil }
        ))
        register(SettingDescriptor<Data?>(
            key: "webQuickAskProviderCatalog",
            defaultValue: nil,
            readFromDefaults: { defaults, k, _ in defaults.data(forKey: k) },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { _ in nil },
            decodeFromBackup: { _ in nil }
        ))
        register(SettingDescriptor<Data?>(
            key: "inAppShortcutConfiguration",
            defaultValue: nil,
            readFromDefaults: { defaults, k, _ in defaults.data(forKey: k) },
            writeToDefaults: { defaults, k, val in
                if let val { defaults.set(val, forKey: k) }
                else { defaults.removeObject(forKey: k) }
            },
            encodeToBackup: { _ in nil },
            decodeFromBackup: { _ in nil }
        ))
    }
}
