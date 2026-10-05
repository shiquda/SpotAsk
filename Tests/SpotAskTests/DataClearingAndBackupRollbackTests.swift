import XCTest
@testable import SpotAsk

private final class InMemoryKeyStore: APIKeyStoring, @unchecked Sendable {
    private var keys: [UUID: String] = [:]
    var shouldFailOnSave = false

    func readAPIKey(for providerID: UUID) throws -> String? {
        keys[providerID]
    }

    func saveAPIKey(_ apiKey: String, for providerID: UUID) throws {
        if shouldFailOnSave {
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
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? sessionStore.clear()
        }

        let settings = AppSettings(defaults: defaults)
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

        // 3. Setup diagnostics
        DiagnosticLogStore.shared.setEnabled(true)
        DiagnosticLogStore.shared.record("Test diagnostic")

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
}
