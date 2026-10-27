import XCTest
@testable import SpotAsk

private final class InMemoryKeyStore: APIKeyStoring, @unchecked Sendable {
    private var keys: [UUID: String] = [:]
    var shouldFailOnSave = false
    var failOnProviderID: UUID?
    var failOnReadProviderID: UUID?
    var failOnSecondReadProviderID: UUID?
    var readCounts: [UUID: Int] = [:]
    func readAPIKey(for providerID: UUID) throws -> String? {
        readCounts[providerID, default: 0] += 1
        if failOnSecondReadProviderID == providerID && readCounts[providerID] == 2 {
            throw NSError(domain: "test", code: -3, userInfo: [NSLocalizedDescriptionKey: "Simulated second read failure"])
        }
        if failOnReadProviderID == providerID {
            throw NSError(domain: "test", code: -2, userInfo: [NSLocalizedDescriptionKey: "Simulated read failure"])
        }
        return keys[providerID]
    }

    func saveAPIKey(_ apiKey: String, for providerID: UUID) throws {
        if shouldFailOnSave || failOnProviderID == providerID {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated save failure"])
        }
        keys[providerID] = apiKey
    }

    func deleteAPIKey(for providerID: UUID) throws {
        keys.removeValue(forKey: providerID)
    }

    func deleteAllAPIKeys() throws {
        keys.removeAll()
    }
}

final class DataClearingAndBackupRollbackTests: XCTestCase {
    @MainActor
    func testClearAllLocalDataPurgesSessionsLogsAndResetsSettings() throws {
        let testBundleID = "com.spotask.test.\(UUID().uuidString)"
        let sessionStore = SessionStore(bundleIdentifier: testBundleID)
        let suiteName = "SpotAskDataClearingTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskDataClearingTest-\(UUID().uuidString).json")
        let diagnostics = DiagnosticLogStore(fileURL: diagnosticsURL)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? sessionStore.clear()
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }

        let settings = AppSettings(defaults: defaults, persistentDomainName: suiteName)
        let keyStore = InMemoryKeyStore()

        // 1. Setup session data
        let dummyMessage = ChatMessage(role: .user, content: "Hello", attachments: [])
        try sessionStore.save([dummyMessage])
        XCTAssertEqual(try sessionStore.load().count, 1)

        // 2. Setup key store
        let testProviderID = UUID()
        try keyStore.saveAPIKey("secret-api-key", for: testProviderID)
        try keyStore.saveAPIKey("proxy-pass", for: ProxyCredentialSlot.providerID)
        XCTAssertEqual(try keyStore.readAPIKey(for: testProviderID), "secret-api-key")

        // 3. Setup diagnostics in an isolated file, never the shared production log.
        diagnostics.setEnabled(true)
        diagnostics.record("Test diagnostic")
        XCTAssertTrue(diagnostics.exportedText().contains("Test diagnostic"))

        // 4. Setup settings
        settings.systemPrompt = "My custom system prompt"
        settings.contextLimit = 50
        settings.proxyEnabled = true
        settings.proxyHost = "127.0.0.1"

        var clearCallbackInvoked = false
        let generalState = GeneralSettingsState(
            settings: settings,
            keyStore: keyStore,
            sessionStore: sessionStore,
            diagnosticLogStore: diagnostics,
            onConfigurationImported: {},
            onClearAllData: {
                clearCallbackInvoked = true
            }
        )
        XCTAssertEqual(generalState.proxyPasswordDraft, "proxy-pass")

        // Execute clearAllLocalData
        generalState.clearAllLocalData()

        // Verify session cleared
        XCTAssertEqual(try sessionStore.load().count, 0)

        // Verify keys cleared
        XCTAssertNil(try keyStore.readAPIKey(for: testProviderID))
        XCTAssertNil(try keyStore.readAPIKey(for: ProxyCredentialSlot.providerID))

        // Verify callback
        XCTAssertTrue(clearCallbackInvoked)

        // Verify settings reset
        XCTAssertEqual(settings.systemPrompt, "")
        XCTAssertEqual(settings.contextLimit, 20)
        XCTAssertFalse(settings.proxyEnabled)
        XCTAssertEqual(generalState.proxyPasswordDraft, "")
        XCTAssertFalse(generalState.statusIsError)
        XCTAssertFalse(diagnostics.exportedText().contains("Test diagnostic"))
    }

    @MainActor
    func testClearAllLocalDataLeavesSpectatorStoresUntouched() throws {
        let fixtureSuite = "SpotAskClearFixture.\(UUID().uuidString)"
        let spectatorSuite = "SpotAskClearSpectator.\(UUID().uuidString)"
        let fixtureDefaults = UserDefaults(suiteName: fixtureSuite)!
        let spectatorDefaults = UserDefaults(suiteName: spectatorSuite)!
        let fixtureDiagnosticsURL = temporaryJSONURL()
        let spectatorDiagnosticsURL = temporaryJSONURL()
        let fixtureCredentialsURL = temporaryJSONURL()
        let spectatorCredentialsURL = temporaryJSONURL()
        let fixtureSession = SessionStore(bundleIdentifier: fixtureSuite)
        let spectatorSession = SessionStore(bundleIdentifier: spectatorSuite)
        defer {
            fixtureDefaults.removePersistentDomain(forName: fixtureSuite)
            spectatorDefaults.removePersistentDomain(forName: spectatorSuite)
            try? fixtureSession.clear()
            try? spectatorSession.clear()
            for url in [fixtureDiagnosticsURL, spectatorDiagnosticsURL, fixtureCredentialsURL, spectatorCredentialsURL] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let fixtureSettings = AppSettings(defaults: fixtureDefaults, persistentDomainName: fixtureSuite)
        let provider = ProviderConfiguration(
            name: "Custom Relay",
            address: "https://relay.example/v1",
            addressMode: .baseURL,
            timeout: 42
        )
        let model = ModelConfiguration(
            displayName: "Custom Model",
            upstreamModelID: "custom-model-id",
            providerID: provider.id,
            isStreamingEnabled: false
        )
        try fixtureSettings.providerRegistry.replaceCatalog(
            with: ProviderModelCatalog(providers: [provider], models: [model], selectedModelID: model.id)
        )
        fixtureSettings.systemPrompt = "Keep this custom prompt"

        let reloaded = AppSettings(defaults: fixtureDefaults, persistentDomainName: fixtureSuite)
        XCTAssertEqual(reloaded.systemPrompt, "Keep this custom prompt")
        let reloadedCatalog = try XCTUnwrap(reloaded.providerRegistry.catalog)
        XCTAssertEqual(reloadedCatalog.providers.map(\.name), ["Custom Relay"])
        XCTAssertEqual(reloadedCatalog.providers.map(\.address), ["https://relay.example/v1"])
        XCTAssertEqual(reloadedCatalog.models.map(\.upstreamModelID), ["custom-model-id"])
        XCTAssertEqual(reloadedCatalog.selectedModelID, model.id)

        let spectatorSettings = AppSettings(defaults: spectatorDefaults, persistentDomainName: spectatorSuite)
        let spectatorProvider = ProviderConfiguration(
            name: "Spectator Service",
            address: "https://spectator.example/v1",
            addressMode: .baseURL,
            timeout: 15
        )
        let spectatorModel = ModelConfiguration(
            displayName: "Spectator Model",
            upstreamModelID: "spectator-model",
            providerID: spectatorProvider.id,
            isStreamingEnabled: true
        )
        try spectatorSettings.providerRegistry.replaceCatalog(
            with: ProviderModelCatalog(
                providers: [spectatorProvider],
                models: [spectatorModel],
                selectedModelID: spectatorModel.id
            )
        )
        spectatorSettings.systemPrompt = "Spectator prompt must survive"

        let probeKey = "spotask.unregisteredProbe"
        fixtureDefaults.set("fixture-probe", forKey: probeKey)
        spectatorDefaults.set("spectator-probe", forKey: probeKey)
        for key in AppSettings.supplementalPersistentKeys {
            fixtureDefaults.set("fixture-\(key)", forKey: key)
            spectatorDefaults.set("spectator-\(key)", forKey: key)
        }
        fixtureDefaults.synchronize()
        spectatorDefaults.synchronize()

        try fixtureSession.save([ChatMessage(role: .user, content: "fixture", attachments: [])])
        try spectatorSession.save([ChatMessage(role: .user, content: "spectator", attachments: [])])
        let fixtureKeys = LocalAPIKeyStore(fileURL: fixtureCredentialsURL)
        let spectatorKeys = LocalAPIKeyStore(fileURL: spectatorCredentialsURL)
        try fixtureKeys.saveAPIKey("fixture-secret", for: provider.id)
        try spectatorKeys.saveAPIKey("spectator-secret", for: spectatorProvider.id)

        let fixtureLogs = DiagnosticLogStore(fileURL: fixtureDiagnosticsURL)
        let spectatorLogs = DiagnosticLogStore(fileURL: spectatorDiagnosticsURL)
        fixtureLogs.setEnabled(true)
        fixtureLogs.record("fixture diagnostic")
        spectatorLogs.setEnabled(true)
        spectatorLogs.record("spectator diagnostic must survive")
        let spectatorLogText = spectatorLogs.exportedText()

        let generalState = GeneralSettingsState(
            settings: fixtureSettings,
            keyStore: fixtureKeys,
            sessionStore: fixtureSession,
            diagnosticLogStore: fixtureLogs,
            onConfigurationImported: {}
        )
        generalState.clearAllLocalData()

        XCTAssertEqual(try fixtureSession.load().count, 0)
        XCTAssertNil(try fixtureKeys.readAPIKey(for: provider.id))
        XCTAssertFalse(fixtureLogs.exportedText().contains("fixture diagnostic"))
        XCTAssertEqual(fixtureSettings.systemPrompt, "")
        let clearedDomain = fixtureDefaults.persistentDomain(forName: fixtureSuite) ?? [:]
        XCTAssertNil(clearedDomain[probeKey])
        for key in AppSettings.supplementalPersistentKeys {
            XCTAssertNil(clearedDomain[key], "Clear left supplemental key \(key) in the fixture domain")
        }

        let clearedReload = AppSettings(defaults: fixtureDefaults, persistentDomainName: fixtureSuite)
        XCTAssertEqual(clearedReload.systemPrompt, "")
        let clearedCatalog = try XCTUnwrap(clearedReload.providerRegistry.catalog)
        XCTAssertEqual(clearedCatalog.providers.map(\.name), ["OpenAI Compatible"])
        XCTAssertEqual(clearedCatalog.models.map(\.upstreamModelID), ["gpt-6-luna"])
        XCTAssertFalse(clearedCatalog.providers.contains { $0.name == "Custom Relay" })

        XCTAssertEqual(spectatorDefaults.string(forKey: probeKey), "spectator-probe")
        for key in AppSettings.supplementalPersistentKeys {
            XCTAssertEqual(spectatorDefaults.string(forKey: key), "spectator-\(key)")
        }
        XCTAssertEqual(spectatorSettings.systemPrompt, "Spectator prompt must survive")
        XCTAssertEqual(spectatorSettings.providerRegistry.catalog?.providers.map(\.name), ["Spectator Service"])
        XCTAssertEqual(spectatorSettings.providerRegistry.catalog?.models.map(\.upstreamModelID), ["spectator-model"])
        XCTAssertEqual(try spectatorSession.load().first?.content, "spectator")
        XCTAssertEqual(try spectatorKeys.readAPIKey(for: spectatorProvider.id), "spectator-secret")
        XCTAssertEqual(spectatorLogs.exportedText(), spectatorLogText)
        XCTAssertFalse(generalState.statusIsError)
    }

    private func temporaryJSONURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskClearIsolation-\(UUID().uuidString).json")
    }

    @MainActor
    func testApplyConfigurationBackupRollsBackOnKeyStoreFailure() throws {
        let suiteName = "SpotAskRollbackTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let keyStore = InMemoryKeyStore()

        // Initial state
        settings.systemPrompt = "Original System Prompt"
        settings.contextLimit = 15

        let provider = ProviderConfiguration(
            name: "Initial Provider",
            address: "https://initial.com/v1",
            addressMode: .baseURL,
            timeout: 25
        )
        let model = ModelConfiguration(
            displayName: "Initial Model",
            upstreamModelID: "init-model",
            providerID: provider.id,
            isStreamingEnabled: true
        )
        let initialCatalog = ProviderModelCatalog(providers: [provider], models: [model], selectedModelID: model.id)
        try settings.providerRegistry.replaceCatalog(with: initialCatalog)

        // Create backup with new provider and API key
        let newProvider = ProviderConfiguration(
            name: "New Provider",
            address: "https://new.com/v1",
            addressMode: .baseURL,
            timeout: 45
        )
        let newModel = ModelConfiguration(
            displayName: "New Model",
            upstreamModelID: "new-model",
            providerID: newProvider.id,
            isStreamingEnabled: false
        )
        let newCatalog = ProviderModelCatalog(providers: [newProvider], models: [newModel], selectedModelID: newModel.id)

        var backup = SpotAskConfigBackup(
            general: .init(
                systemPrompt: "New Backup Prompt",
                contextLimit: 80,
                retainSession: true,
                clearInputOnClose: false,
                confirmBeforeStartingNewConversation: true,
                escapeStartsNewConversation: true,
                defaultExpandReasoning: true,
                renderMath: true,
                launchAtLogin: false,
                appearance: "system",
                fontSize: "standard",
                chatMessageStyle: "standard",
                interfaceZoomLevel: "standard",
                language: "system",
                hotKeyPreset: "optionSpace",
                keepWindowOnTop: false,
                showsMenuBarIcon: true
            ),
            promptPresetCatalog: PromptPreset.builtIn,
            quickActionCatalog: QuickAction.builtIn,
            shortcutConfiguration: InAppShortcutConfiguration(),
            providerCatalog: newCatalog
        )
        backup.apiKeys = [newProvider.id.uuidString: "new-secret-key"]

        // Configure keyStore to fail on save
        keyStore.shouldFailOnSave = true

        XCTAssertThrowsError(try settings.applyConfigurationBackup(backup, keyStore: keyStore))

        // Verify rollback: settings should match original values
        XCTAssertEqual(settings.systemPrompt, "Original System Prompt")
        XCTAssertEqual(settings.contextLimit, 15)
        XCTAssertEqual(settings.providerRegistry.catalog?.providers.first?.id, provider.id)
        XCTAssertEqual(settings.providerRegistry.catalog?.providers.first?.name, "Initial Provider")
    }

    @MainActor
    func testApplyConfigurationBackupPreValidatesInvalidCatalogWithoutModifyingSettings() throws {
        let suiteName = "SpotAskPreValidateTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let keyStore = InMemoryKeyStore()

        settings.systemPrompt = "Unchanged Prompt"
        settings.contextLimit = 22

        // Duplicate model ID invalidates catalog
        let provider = ProviderConfiguration(
            name: "Valid Provider",
            address: "https://valid.com/v1",
            addressMode: .baseURL,
            timeout: 30
        )
        let modelID = UUID()
        let invalidCatalog = ProviderModelCatalog(
            schemaVersion: ProviderModelCatalog.currentSchemaVersion,
            providers: [provider],
            models: [
                ModelConfiguration(id: modelID, displayName: "M1", upstreamModelID: "m1", providerID: provider.id, isStreamingEnabled: true),
                ModelConfiguration(id: modelID, displayName: "M2", upstreamModelID: "m2", providerID: provider.id, isStreamingEnabled: true)
            ],
            selectedModelID: modelID
        )

        let backup = SpotAskConfigBackup(
            general: .init(
                systemPrompt: "Should Not Apply",
                contextLimit: 99,
                retainSession: true,
                clearInputOnClose: false,
                confirmBeforeStartingNewConversation: true,
                escapeStartsNewConversation: true,
                defaultExpandReasoning: true,
                renderMath: true,
                launchAtLogin: false,
                appearance: "system",
                fontSize: "standard",
                chatMessageStyle: "standard",
                interfaceZoomLevel: "standard",
                language: "system",
                hotKeyPreset: "optionSpace",
                keepWindowOnTop: false,
                showsMenuBarIcon: true
            ),
            promptPresetCatalog: PromptPreset.builtIn,
            quickActionCatalog: QuickAction.builtIn,
            shortcutConfiguration: InAppShortcutConfiguration(),
            providerCatalog: invalidCatalog
        )

        XCTAssertThrowsError(try settings.applyConfigurationBackup(backup, keyStore: keyStore))

        XCTAssertEqual(settings.systemPrompt, "Unchanged Prompt")
        XCTAssertEqual(settings.contextLimit, 22)
    }
    @MainActor
    func testApplyConfigurationBackupRollsBackPartiallyWrittenKeys() throws {
        let suiteName = "SpotAskPartialKeyRollbackTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let keyStore = InMemoryKeyStore()

        settings.systemPrompt = "Original System Prompt"

        let provider1 = ProviderConfiguration(
            name: "Provider 1",
            address: "https://p1.com/v1",
            addressMode: .baseURL,
            timeout: 25
        )
        let provider2 = ProviderConfiguration(
            name: "Provider 2",
            address: "https://p2.com/v1",
            addressMode: .baseURL,
            timeout: 25
        )
        let model1 = ModelConfiguration(displayName: "M1", upstreamModelID: "m1", providerID: provider1.id, isStreamingEnabled: true)
        let model2 = ModelConfiguration(displayName: "M2", upstreamModelID: "m2", providerID: provider2.id, isStreamingEnabled: true)
        let initialCatalog = ProviderModelCatalog(providers: [provider1], models: [model1], selectedModelID: model1.id)
        try settings.providerRegistry.replaceCatalog(with: initialCatalog)

        // New backup with both provider 1 and provider 2
        let newCatalog = ProviderModelCatalog(providers: [provider1, provider2], models: [model1, model2], selectedModelID: model1.id)
        var backup = SpotAskConfigBackup(
            general: .init(
                systemPrompt: "New Backup Prompt",
                contextLimit: 80,
                retainSession: true,
                clearInputOnClose: false,
                confirmBeforeStartingNewConversation: true,
                escapeStartsNewConversation: true,
                defaultExpandReasoning: true,
                renderMath: true,
                launchAtLogin: false,
                appearance: "system",
                fontSize: "standard",
                chatMessageStyle: "standard",
                interfaceZoomLevel: "standard",
                language: "system",
                hotKeyPreset: "optionSpace",
                keepWindowOnTop: false,
                showsMenuBarIcon: true
            ),
            promptPresetCatalog: PromptPreset.builtIn,
            quickActionCatalog: QuickAction.builtIn,
            shortcutConfiguration: InAppShortcutConfiguration(),
            providerCatalog: newCatalog
        )
        backup.apiKeys = [
            provider1.id.uuidString: "key-1",
            provider2.id.uuidString: "key-2"
        ]

        // Fail only on provider 2: provider 1 will succeed on first iteration, then provider 2 will throw
        keyStore.failOnProviderID = provider2.id

        XCTAssertThrowsError(try settings.applyConfigurationBackup(backup, keyStore: keyStore))

        // Assert: provider 1's newly written key must NOT be left behind in keyStore!
        XCTAssertNil(try keyStore.readAPIKey(for: provider1.id))
        XCTAssertNil(try keyStore.readAPIKey(for: provider2.id))

        // Assert: settings rolled back
        XCTAssertEqual(settings.systemPrompt, "Original System Prompt")
        XCTAssertEqual(settings.providerRegistry.catalog?.providers.count, 1)
        XCTAssertEqual(settings.providerRegistry.catalog?.providers.first?.id, provider1.id)
    }
    @MainActor
    func testApplyConfigurationBackupReadFailureDoesNotDeleteExistingKey() throws {
        let suiteName = "SpotAskReadFailureRollbackTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let keyStore = InMemoryKeyStore()

        settings.systemPrompt = "Original System Prompt"

        let provider1 = ProviderConfiguration(
            name: "Provider 1",
            address: "https://p1.com/v1",
            addressMode: .baseURL,
            timeout: 25
        )
        let provider2 = ProviderConfiguration(
            name: "Provider 2",
            address: "https://p2.com/v1",
            addressMode: .baseURL,
            timeout: 25
        )
        let model1 = ModelConfiguration(displayName: "M1", upstreamModelID: "m1", providerID: provider1.id, isStreamingEnabled: true)
        let model2 = ModelConfiguration(displayName: "M2", upstreamModelID: "m2", providerID: provider2.id, isStreamingEnabled: true)
        let initialCatalog = ProviderModelCatalog(providers: [provider1, provider2], models: [model1, model2], selectedModelID: model1.id)
        try settings.providerRegistry.replaceCatalog(with: initialCatalog)

        // Store existing keys
        try keyStore.saveAPIKey("original-secret-1", for: provider1.id)
        try keyStore.saveAPIKey("original-secret-2", for: provider2.id)

        var backup = SpotAskConfigBackup(
            general: .init(
                systemPrompt: "New Backup Prompt",
                contextLimit: 80,
                retainSession: true,
                clearInputOnClose: false,
                confirmBeforeStartingNewConversation: true,
                escapeStartsNewConversation: true,
                defaultExpandReasoning: true,
                renderMath: true,
                launchAtLogin: false,
                appearance: "system",
                fontSize: "standard",
                chatMessageStyle: "standard",
                interfaceZoomLevel: "standard",
                language: "system",
                hotKeyPreset: "optionSpace",
                keepWindowOnTop: false,
                showsMenuBarIcon: true
            ),
            promptPresetCatalog: PromptPreset.builtIn,
            quickActionCatalog: QuickAction.builtIn,
            shortcutConfiguration: InAppShortcutConfiguration(),
            providerCatalog: initialCatalog
        )
        backup.apiKeys = [
            provider1.id.uuidString: "new-key-1",
            provider2.id.uuidString: "new-key-2"
        ]

        // Fail reading provider 2's existing key during applyConfigurationBackup (second read, after snapshot)
        keyStore.failOnSecondReadProviderID = provider2.id

        XCTAssertThrowsError(try settings.applyConfigurationBackup(backup, keyStore: keyStore))

        // Re-enable reads to verify persisted values
        keyStore.failOnSecondReadProviderID = nil

        // Provider 1 was touched and written, then rolled back to original-secret-1
        XCTAssertEqual(try keyStore.readAPIKey(for: provider1.id), "original-secret-1")
        // Provider 2 failed during read: must NOT have been treated as nil or deleted!
        XCTAssertEqual(try keyStore.readAPIKey(for: provider2.id), "original-secret-2")

        // Settings rolled back
        XCTAssertEqual(settings.systemPrompt, "Original System Prompt")
    }
}
