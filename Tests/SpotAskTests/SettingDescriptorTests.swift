import XCTest
@testable import SpotAsk

@MainActor
final class SettingDescriptorTests: XCTestCase {
    @MainActor
    override func tearDown() async throws {
        try await super.tearDown()
        SettingRegistry.shared.resetToStandardSettings()
    }

    func testDeclarativeSinglePointSettingLifecycle() throws {
        let suite = "SettingDescriptorTests.Lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var changedValues: [String] = []
        let testKey = "testCustomFeatureFlag"

        // 1. Declare and register a new setting descriptor in a single place
        let customDescriptor = SettingDescriptors.string(
            key: testKey,
            defaultValue: "initialDefault",
            resetValue: "resetValue",
            onChanged: { _, newVal in
                changedValues.append(newVal)
            }
        )
        SettingRegistry.shared.register(customDescriptor)
        defer { SettingRegistry.shared.unregister(key: testKey) }

        // 2. Read default from AppSettings
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(customDescriptor.getValue(settings), "initialDefault")

        // 3. Mutate value and verify it saves to defaults and fires onChanged
        customDescriptor.setValue(settings, "userCustomized")
        customDescriptor.save(from: settings, to: defaults)
        XCTAssertEqual(defaults.string(forKey: testKey), "userCustomized")
        XCTAssertEqual(changedValues, ["userCustomized"])

        // 4. Verify export to backup
        let backup = try settings.makeConfigurationBackup()
        XCTAssertEqual(backup.general[testKey], .string("userCustomized"))

        // Encode and decode JSON
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)
        XCTAssertEqual(decoded.general[testKey], .string("userCustomized"))

        // 5. Verify import into a fresh AppSettings
        let destSuite = "SettingDescriptorTests.LifecycleDest.\(UUID().uuidString)"
        let destDefaults = UserDefaults(suiteName: destSuite)!
        defer { destDefaults.removePersistentDomain(forName: destSuite) }

        let destSettings = AppSettings(defaults: destDefaults)
        XCTAssertEqual(customDescriptor.getValue(destSettings), "initialDefault")
        try destSettings.applyConfigurationBackup(decoded)
        XCTAssertEqual(customDescriptor.getValue(destSettings), "userCustomized")
        XCTAssertEqual(destDefaults.string(forKey: testKey), "userCustomized")

        // 6. Verify reset sets value to resetValue
        customDescriptor.reset(in: destSettings, defaults: destDefaults)
        XCTAssertEqual(customDescriptor.getValue(destSettings), "resetValue")
        XCTAssertNil(destDefaults.string(forKey: testKey))
    }

    func testAllStandardSettingsRegisteredAndExportable() throws {
        let descriptors = SettingRegistry.shared.descriptors
        XCTAssertGreaterThanOrEqual(descriptors.count, 50, "Expected at least 50 registered setting descriptors")

        let suite = "SettingDescriptorTests.AllSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let source = AppSettings(defaults: defaults)

        // Mutate a variety of settings across different types
        source.systemPrompt = "Custom Prompt 123"
        source.contextLimit = 42
        source.retainSession = true
        source.clearInputOnClose = true
        source.confirmBeforeStartingNewConversation = false
        source.escapeStartsNewConversation = true
        source.defaultExpandReasoning = true
        source.renderMath = false
        source.launchAtLogin = true
        source.silentLaunch = true
        source.proxyEnabled = true
        source.proxyType = .socks5
        source.proxyHost = "proxy.local"
        source.proxyPort = 9050
        source.proxyUsername = "test-proxy-user"
        source.diagnosticsEnabled = true
        source.appearance = .dark
        source.fontSize = .large
        source.chatMessageStyle = .im
        source.interfaceZoomLevel = .large
        source.language = .simplifiedChinese
        source.hotKeyPreset = .commandShiftSpace
        source.panelWidth = 800.0
        source.panelHeight = 600.0
        source.panelOrigin = CGPoint(x: 120.0, y: 240.0)
        source.keepWindowOnTop = true
        source.showsMenuBarIcon = false
        source.selectionAssistantEnabled = true
        source.selectionAssistantMode = .direct
        source.selectionHotKeyPreset = .optionShiftSpace
        source.selectionAutoInvokeEnabled = true
        source.selectionAutoInvokeDelay = 0.5
        source.selectionAutoInvokeScope = .whitelist
        source.selectionAutoInvokeBlacklist = ["com.apple.Safari"]
        source.selectionAutoInvokeWhitelist = ["com.apple.Notes"]
        source.clipboardAssistedSelectionEnabled = true
        source.clipboardAssistedSelectionAppIdentifiers = ["com.microsoft.VSCode"]
        source.selectionActionBarShowsChatAction = false
        source.selectionActionBarShowsLabels = false
        source.selectionActionBarShowsPrompts = false
        source.selectionActionBarShowsExternalAsk = false
        source.automaticUpdateCheckEnabled = false
        source.updateDownloadSource = .accelerated
        source.externalAskEnabled = false

        // Export backup
        let backup = try source.makeConfigurationBackup()

        // Verify key properties in backup.general
        XCTAssertEqual(backup.general.systemPrompt, "Custom Prompt 123")
        XCTAssertEqual(backup.general.contextLimit, 42)
        XCTAssertEqual(backup.general.retainSession, true)
        XCTAssertEqual(backup.general.clearInputOnClose, true)
        XCTAssertEqual(backup.general.confirmBeforeStartingNewConversation, false)
        XCTAssertEqual(backup.general.escapeStartsNewConversation, true)
        XCTAssertEqual(backup.general.defaultExpandReasoning, true)
        XCTAssertEqual(backup.general.renderMath, false)
        XCTAssertEqual(backup.general.launchAtLogin, true)
        XCTAssertEqual(backup.general["silentLaunch"]?.boolValue, true)
        XCTAssertEqual(backup.general.proxyEnabled, true)
        XCTAssertEqual(backup.general.proxyType, ProxyType.socks5.rawValue)
        XCTAssertEqual(backup.general.proxyHost, "proxy.local")
        XCTAssertEqual(backup.general.proxyPort, 9050)
        XCTAssertEqual(backup.general.proxyUsername, "test-proxy-user")
        XCTAssertEqual(backup.general.appearance, AppearanceMode.dark.rawValue)
        XCTAssertEqual(backup.general.fontSize, FontSize.large.rawValue)
        XCTAssertEqual(backup.general.chatMessageStyle, ChatMessageStyle.im.rawValue)
        XCTAssertEqual(backup.general.interfaceZoomLevel, InterfaceZoomLevel.large.rawValue)
        XCTAssertEqual(backup.general.language, AppLanguage.simplifiedChinese.rawValue)
        XCTAssertEqual(backup.general.hotKeyPreset, HotKeyPreset.commandShiftSpace.rawValue)
        XCTAssertEqual(backup.general["panelWidth"]?.doubleValue, 800.0)
        XCTAssertEqual(backup.general["panelHeight"]?.doubleValue, 600.0)
        XCTAssertEqual(backup.general.keepWindowOnTop, true)

        // Dynamic backup dictionary also contains all values
        XCTAssertEqual(backup.general["panelOriginX"]?.doubleValue, 120.0)
        XCTAssertEqual(backup.general["panelOriginY"]?.doubleValue, 240.0)
        XCTAssertEqual(backup.general["showsMenuBarIcon"]?.boolValue, false)
        XCTAssertEqual(backup.general["selectionAssistantEnabled"]?.boolValue, true)
        XCTAssertEqual(backup.general["selectionAutoInvokeBlacklist"]?.stringArrayValue, ["com.apple.Safari"])
        XCTAssertEqual(backup.general["selectionAutoInvokeWhitelist"]?.stringArrayValue, ["com.apple.Notes"])

        // JSON round-trip
        let encodedData = try JSONEncoder().encode(backup)
        let decodedBackup = try JSONDecoder().decode(SpotAskConfigBackup.self, from: encodedData)

        // Apply backup to clean destination
        let destSuite = "SettingDescriptorTests.AllSettingsDest.\(UUID().uuidString)"
        let destDefaults = UserDefaults(suiteName: destSuite)!
        defer { destDefaults.removePersistentDomain(forName: destSuite) }

        let destination = AppSettings(defaults: destDefaults)
        try destination.applyConfigurationBackup(decodedBackup)

        // Verify destination values match source
        XCTAssertEqual(destination.systemPrompt, "Custom Prompt 123")
        XCTAssertEqual(destination.contextLimit, 42)
        XCTAssertEqual(destination.retainSession, true)
        XCTAssertEqual(destination.clearInputOnClose, true)
        XCTAssertEqual(destination.confirmBeforeStartingNewConversation, false)
        XCTAssertEqual(destination.escapeStartsNewConversation, true)
        XCTAssertEqual(destination.defaultExpandReasoning, true)
        XCTAssertEqual(destination.renderMath, false)
        XCTAssertEqual(destination.launchAtLogin, true)
        XCTAssertEqual(destination.silentLaunch, true)
        XCTAssertEqual(destination.proxyEnabled, true)
        XCTAssertEqual(destination.proxyType, .socks5)
        XCTAssertEqual(destination.proxyHost, "proxy.local")
        XCTAssertEqual(destination.proxyPort, 9050)
        XCTAssertEqual(destination.proxyUsername, "test-proxy-user")
        XCTAssertEqual(destination.appearance, .dark)
        XCTAssertEqual(destination.fontSize, .large)
        XCTAssertEqual(destination.chatMessageStyle, .im)
        XCTAssertEqual(destination.interfaceZoomLevel, .large)
        XCTAssertEqual(destination.language, .simplifiedChinese)
        XCTAssertEqual(destination.hotKeyPreset, .commandShiftSpace)
        XCTAssertEqual(destination.panelWidth, 800.0)
        XCTAssertEqual(destination.panelHeight, 600.0)
        XCTAssertEqual(destination.panelOrigin, CGPoint(x: 120.0, y: 240.0))
        XCTAssertEqual(destination.keepWindowOnTop, true)
        XCTAssertEqual(destination.showsMenuBarIcon, false)
        XCTAssertEqual(destination.selectionAssistantEnabled, true)
        XCTAssertEqual(destination.selectionAssistantMode, .direct)
        XCTAssertEqual(destination.selectionHotKeyPreset, .optionShiftSpace)
        XCTAssertEqual(destination.selectionAutoInvokeEnabled, true)
        XCTAssertEqual(destination.selectionAutoInvokeDelay, 0.5)
        XCTAssertEqual(destination.selectionAutoInvokeScope, .whitelist)
        XCTAssertEqual(destination.selectionAutoInvokeBlacklist, ["com.apple.Safari"])
        XCTAssertEqual(destination.selectionAutoInvokeWhitelist, ["com.apple.Notes"])
        XCTAssertEqual(destination.clipboardAssistedSelectionEnabled, true)
        XCTAssertEqual(destination.clipboardAssistedSelectionAppIdentifiers, ["com.microsoft.VSCode"])
        XCTAssertEqual(destination.selectionActionBarShowsChatAction, false)
        XCTAssertEqual(destination.selectionActionBarShowsLabels, false)
        XCTAssertEqual(destination.selectionActionBarShowsPrompts, false)
        XCTAssertEqual(destination.selectionActionBarShowsExternalAsk, false)
        XCTAssertEqual(destination.automaticUpdateCheckEnabled, false)
        XCTAssertEqual(destination.updateDownloadSource, .accelerated)
        XCTAssertEqual(destination.externalAskEnabled, false)
    }
}
