import XCTest
@testable import SpotAsk

@MainActor
final class ConfigBackupTests: XCTestCase {
    func testConfigurationBackupRoundTrip() throws {
        let sourceSuite = "ConfigBackupSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        source.defaultExpandReasoning = true
        source.renderMath = false
        source.chatMessageStyle = .im
        source.automaticUpdateCheckEnabled = false
        source.systemPrompt = "custom system prompt"
        source.contextLimit = 40
        source.proxyEnabled = true
        source.proxyType = .socks5
        source.proxyHost = "proxy.example.com"
        source.proxyPort = 7890
        source.proxyUsername = "backup-user"

        let provider = ProviderConfiguration(
            name: "Test Service",
            address: "https://example.com/v1",
            addressMode: .baseURL,
            timeout: 30
        )
        let model = ModelConfiguration(
            displayName: "Test Model",
            upstreamModelID: "test-model",
            providerID: provider.id,
            isStreamingEnabled: false
        )
        let catalog = ProviderModelCatalog(
            providers: [provider],
            models: [model],
            selectedModelID: model.id
        )
        try source.providerRegistry.replaceCatalog(with: catalog)
        XCTAssertTrue(source.saveCustomPromptPreset(PromptPreset(title: "My Preset", instruction: "Do it")))
        let customAction = QuickAction(
            name: "Custom Search",
            kind: .web(urlTemplate: "https://search.example.com/?q={query}"),
            symbolName: "magnifyingglass",
            isEnabled: true
        )
        XCTAssertTrue(source.saveCustomQuickAction(customAction))
        source.setQuickActionEnabled(id: QuickAction.BuiltInID.chatGPT, isEnabled: false)

        let backup = try source.makeConfigurationBackup()
        XCTAssertNil(backup.apiKeys)
        XCTAssertNotNil(backup.quickActionCatalog)
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)

        let destination = AppSettings(defaults: destinationDefaults)
        try destination.applyConfigurationBackup(decoded)

        XCTAssertTrue(destination.defaultExpandReasoning)
        XCTAssertFalse(destination.renderMath)
        XCTAssertEqual(destination.chatMessageStyle, .im)
        XCTAssertFalse(destination.automaticUpdateCheckEnabled)
        XCTAssertEqual(destination.systemPrompt, "custom system prompt")
        XCTAssertEqual(destination.contextLimit, 40)
        XCTAssertTrue(destination.proxyEnabled)
        XCTAssertEqual(destination.proxyType, .socks5)
        XCTAssertEqual(destination.proxyHost, "proxy.example.com")
        XCTAssertEqual(destination.proxyPort, 7890)
        XCTAssertEqual(destination.proxyUsername, "backup-user")
        XCTAssertEqual(destination.providerRegistry.catalog, catalog)
        XCTAssertEqual(destination.promptPresets.first(where: { $0.title == "My Preset" })?.instruction, "Do it")
        XCTAssertEqual(destination.quickActions.first(where: { $0.id == customAction.id })?.name, "Custom Search")
        XCTAssertEqual(destination.quickActions.first(where: { $0.id == QuickAction.BuiltInID.chatGPT })?.isEnabled, false)
        XCTAssertEqual(destination.quickActions.first(where: { $0.id == QuickAction.BuiltInID.grok })?.isEnabled, true)
    }

    func testBackupOmitsStoredAccessKeys() throws {
        let suite = "ConfigBackupKeys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: credentialsURL) }

        let settings = AppSettings(defaults: defaults)
        let provider = settings.providerRegistry.catalog?.providers.first
        let providerID = try XCTUnwrap(provider?.id)
        let keyStore = LocalAPIKeyStore(fileURL: credentialsURL)
        try keyStore.saveAPIKey("super-secret-key", for: providerID)

        let json = String(data: try JSONEncoder().encode(settings.makeConfigurationBackup()), encoding: .utf8)

        XCTAssertFalse(try XCTUnwrap(json).contains("super-secret-key"))
        XCTAssertFalse(try XCTUnwrap(json).contains("\"apiKeys\""))
    }

    func testBackupCanIncludeAndRestoreAccessKeysWhenRequested() throws {
        let sourceSuite = "ConfigBackupIncludeKeysSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupIncludeKeysDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }
        let sourceCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupIncludeSource-\(UUID().uuidString).json")
        let destinationCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupIncludeDestination-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: sourceCredentialsURL)
            try? FileManager.default.removeItem(at: destinationCredentialsURL)
        }

        let source = AppSettings(defaults: sourceDefaults)
        let provider = try XCTUnwrap(source.providerRegistry.catalog?.providers.first)
        let sourceKeyStore = LocalAPIKeyStore(fileURL: sourceCredentialsURL)
        try sourceKeyStore.saveAPIKey("exported-secret", for: provider.id)

        let backup = try source.makeConfigurationBackup(includeAccessKeys: true, keyStore: sourceKeyStore)
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)

        XCTAssertEqual(decoded.apiKeys?[provider.id.uuidString], "exported-secret")

        let destination = AppSettings(defaults: destinationDefaults)
        let destinationKeyStore = LocalAPIKeyStore(fileURL: destinationCredentialsURL)
        try destination.applyConfigurationBackup(decoded, keyStore: destinationKeyStore)
        XCTAssertEqual(try destinationKeyStore.readAPIKey(for: provider.id), "exported-secret")
    }

    func testImportedProviderStateImmediatelyShowsRestoredKeyAndModels() throws {
        let sourceSuite = "ConfigBackupProviderStateSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupProviderStateDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }
        let credentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupProviderState-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: credentialsURL) }

        let provider = ProviderConfiguration(
            name: "Imported Service",
            address: "https://example.com/v1",
            addressMode: .baseURL,
            timeout: 30
        )
        let models = ["first-model", "second-model"].map {
            ModelConfiguration(
                displayName: $0,
                upstreamModelID: $0,
                providerID: provider.id,
                isStreamingEnabled: true
            )
        }
        let source = AppSettings(defaults: sourceDefaults)
        try source.providerRegistry.replaceCatalog(
            with: ProviderModelCatalog(
                providers: [provider],
                models: models,
                selectedModelID: models[1].id
            )
        )
        let keyStore = LocalAPIKeyStore(fileURL: credentialsURL)
        try keyStore.saveAPIKey("restored-key", for: provider.id)
        let backup = try source.makeConfigurationBackup(includeAccessKeys: true, keyStore: keyStore)

        let destination = AppSettings(defaults: destinationDefaults)
        try destination.applyConfigurationBackup(backup, keyStore: keyStore)
        let state = ProviderSettingsState(
            settings: destination,
            keyStore: keyStore,
            providerFactory: ConfigBackupProviderFactoryStub()
        )

        XCTAssertEqual(state.selectedProviderID, provider.id)
        XCTAssertEqual(state.apiKeyDraft, "restored-key")
        XCTAssertEqual(
            state.modelsForProvider(provider.id).map { $0.upstreamModelID },
            ["first-model", "second-model"]
        )
        XCTAssertEqual(destination.providerRegistry.catalog?.selectedModelID, models[1].id)
    }

    func testApplyingUnsupportedBackupVersionFails() throws {
        let sourceSuite = "ConfigBackupVersionSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupVersionDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        let backup = try source.makeConfigurationBackup()
        let futureBackup = SpotAskConfigBackup(
            schemaVersion: 99,
            general: backup.general,
            promptPresetCatalog: backup.promptPresetCatalog,
            shortcutConfiguration: backup.shortcutConfiguration,
            providerCatalog: backup.providerCatalog
        )

        XCTAssertThrowsError(try AppSettings(defaults: destinationDefaults).applyConfigurationBackup(futureBackup)) { error in
            XCTAssertEqual(error as? SpotAskConfigBackupError, .unsupportedSchemaVersion(99))
        }
    }
    func testQuickActionCatalogAndShortcutsRoundTrip() throws {
        let sourceSuite = "ConfigBackupQuickActionSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupQuickActionDest.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        let customAction = QuickAction(
            name: "Perplexity",
            kind: .web(urlTemplate: "https://perplexity.ai/?q={query}"),
            symbolName: "sparkle",
            isEnabled: true
        )
        XCTAssertTrue(source.saveCustomQuickAction(customAction))
        // Reorder: Move custom action up
        XCTAssertTrue(source.moveQuickAction(id: customAction.id, by: -1))
        // Disable Grok
        source.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: false)

        // Assign shortcut to custom quick action target
        let customTarget = InAppShortcutTarget.quickAction(customAction.id)
        let customShortcut = InAppShortcut.command("p")
        XCTAssertNil(source.assignShortcut(customShortcut, to: customTarget))
        XCTAssertEqual(source.shortcut(for: customTarget), customShortcut)

        let backup = try source.makeConfigurationBackup()
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)

        let destination = AppSettings(defaults: destinationDefaults)
        try destination.applyConfigurationBackup(decoded)

        // Verify order and enabled status restored
        let restoredActions = destination.quickActions
        XCTAssertEqual(restoredActions.count, 3)
        XCTAssertEqual(restoredActions[0].id, QuickAction.BuiltInID.chatGPT)
        XCTAssertEqual(restoredActions[1].id, customAction.id)
        XCTAssertEqual(restoredActions[1].name, "Perplexity")
        XCTAssertEqual(restoredActions[1].kind, .web(urlTemplate: "https://perplexity.ai/?q={query}"))
        XCTAssertTrue(restoredActions[1].isEnabled)
        XCTAssertEqual(restoredActions[2].id, QuickAction.BuiltInID.grok)
        XCTAssertFalse(restoredActions[2].isEnabled)

        // Verify shortcut restored
        XCTAssertEqual(destination.shortcut(for: customTarget), customShortcut)
        XCTAssertEqual(destination.shortcutTarget(for: customShortcut), customTarget)
    }

    func testImportingBackupWithTamperedBuiltInRestoresOfficialDefinition() throws {
        let destinationSuite = "ConfigBackupTamperedDest.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let tamperedChatGPT = QuickAction(
            id: QuickAction.BuiltInID.chatGPT,
            name: "Tampered ChatGPT",
            kind: .web(urlTemplate: "https://evil.com/?q={query}"),
            symbolName: "trash",
            isBuiltIn: false,
            isEnabled: false
        )
        let tamperedGrok = QuickAction(
            id: QuickAction.BuiltInID.grok,
            name: "Tampered Grok",
            kind: .web(urlTemplate: "https://malicious.com/?q={query}"),
            symbolName: "gear",
            isBuiltIn: false,
            isEnabled: true
        )

        let provider = ProviderConfiguration(
            name: "Test Service",
            address: "https://example.com/v1",
            addressMode: .baseURL,
            timeout: 30
        )
        let model = ModelConfiguration(
            displayName: "Test Model",
            upstreamModelID: "test-model",
            providerID: provider.id,
            isStreamingEnabled: false
        )
        let backup = SpotAskConfigBackup(
            general: .init(
                systemPrompt: "test",
                contextLimit: 10,
                retainSession: false,
                clearInputOnClose: false,
                confirmBeforeStartingNewConversation: true,
                escapeStartsNewConversation: false,
                defaultExpandReasoning: false,
                renderMath: true,
                launchAtLogin: false,
                appearance: "system",
                fontSize: "standard",
                chatMessageStyle: "standard",
                interfaceZoomLevel: "standard",
                language: "system",
                hotKeyPreset: "optionSpace",
                keepWindowOnTop: false,
                showsMenuBarIcon: true,
                automaticUpdateCheckEnabled: true,
                proxyEnabled: false,
                proxyType: "http",
                proxyHost: "",
                proxyPort: 1080,
                proxyUsername: ""
            ),
            promptPresetCatalog: PromptPreset.builtIn,
            quickActionCatalog: [tamperedGrok, tamperedChatGPT],
            shortcutConfiguration: InAppShortcutConfiguration(),
            providerCatalog: ProviderModelCatalog(providers: [provider], models: [model], selectedModelID: model.id)
        )

        let destination = AppSettings(defaults: destinationDefaults)
        try destination.applyConfigurationBackup(backup)

        let actions = destination.quickActions
        XCTAssertEqual(actions.count, 2)

        // Order preserved from backup (Grok first, ChatGPT second)
        let grok = actions[0]
        XCTAssertEqual(grok.id, QuickAction.BuiltInID.grok)
        XCTAssertTrue(grok.isBuiltIn)
        XCTAssertEqual(grok.kind, .web(urlTemplate: "https://grok.com/?q={query}"))
        XCTAssertEqual(grok.symbolName, "sparkles")
        XCTAssertTrue(grok.isEnabled)

        let chatGPT = actions[1]
        XCTAssertEqual(chatGPT.id, QuickAction.BuiltInID.chatGPT)
        XCTAssertTrue(chatGPT.isBuiltIn)
        XCTAssertEqual(chatGPT.kind, .web(urlTemplate: "https://chatgpt.com/?q={query}"))
        XCTAssertEqual(chatGPT.symbolName, "bubble.left.and.bubble.right")
        XCTAssertFalse(chatGPT.isEnabled)
    }

    func testLegacySchema1JSONWithoutQuickActionsDecodesAndDoesNotOverwriteExistingCatalog() throws {
        let destinationSuite = "ConfigBackupLegacyDest.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        // Set up custom action in destination before import
        let destination = AppSettings(defaults: destinationDefaults)
        let existingCustom = QuickAction(
            name: "Existing Search",
            kind: .web(urlTemplate: "https://existing.example.com/?q={query}"),
            symbolName: "globe",
            isEnabled: true
        )
        XCTAssertTrue(destination.saveCustomQuickAction(existingCustom))
        destination.setQuickActionEnabled(id: QuickAction.BuiltInID.chatGPT, isEnabled: false)

        let provider = ProviderConfiguration(
            name: "Test Service",
            address: "https://example.com/v1",
            addressMode: .baseURL,
            timeout: 30
        )
        let model = ModelConfiguration(
            displayName: "Test Model",
            upstreamModelID: "test-model",
            providerID: provider.id,
            isStreamingEnabled: false
        )

        // Construct legacy Schema 1 JSON without `quickActionCatalog`
        let legacyJSON: [String: Any] = [
            "schemaVersion": 1,
            "general": [
                "systemPrompt": "legacy prompt",
                "contextLimit": 15,
                "retainSession": true,
                "clearInputOnClose": true,
                "confirmBeforeStartingNewConversation": false,
                "escapeStartsNewConversation": true,
                "defaultExpandReasoning": true,
                "renderMath": false,
                "launchAtLogin": true,
                "appearance": "dark",
                "fontSize": "large",
                "chatMessageStyle": "im",
                "interfaceZoomLevel": "large",
                "language": "zh-Hans",
                "hotKeyPreset": "commandSpace",
                "keepWindowOnTop": true,
                "showsMenuBarIcon": false,
                "automaticUpdateCheckEnabled": false,
                "proxyEnabled": false,
                "proxyType": "http",
                "proxyHost": "",
                "proxyPort": 1080,
                "proxyUsername": ""
            ],
            "promptPresetCatalog": try JSONSerialization.jsonObject(with: JSONEncoder().encode(PromptPreset.builtIn)),
            "shortcutConfiguration": try JSONSerialization.jsonObject(with: JSONEncoder().encode(InAppShortcutConfiguration())),
            "providerCatalog": try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProviderModelCatalog(
                providers: [provider],
                models: [model],
                selectedModelID: model.id
            )))
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)

        XCTAssertNil(decoded.quickActionCatalog)
        XCTAssertEqual(decoded.general.systemPrompt, "legacy prompt")

        // Import legacy backup
        try destination.applyConfigurationBackup(decoded)

        // General settings should be updated
        XCTAssertEqual(destination.systemPrompt, "legacy prompt")
        XCTAssertEqual(destination.contextLimit, 15)

        // Existing Quick Action catalog must NOT be overwritten or reset to built-in defaults
        let currentActions = destination.quickActions
        XCTAssertTrue(currentActions.contains(where: { $0.id == existingCustom.id }))
        XCTAssertEqual(currentActions.first(where: { $0.id == QuickAction.BuiltInID.chatGPT })?.isEnabled, false)
    }
}

@MainActor
private struct ConfigBackupProviderFactoryStub: ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider {
        throw ChatError.invalidConfiguration
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        throw ChatError.invalidConfiguration
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        throw ChatError.invalidConfiguration
    }
}
