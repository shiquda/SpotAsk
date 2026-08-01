import XCTest
@testable import SpotAsk

@MainActor
final class ProviderModelRegistryTests: XCTestCase {
    func testLegacyConfigurationMigratesOnceIntoVersionedCatalog() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://legacy.example/v1/chat/completions", forKey: "baseURL")
        defaults.set(true, forKey: "useFullEndpoint")
        defaults.set("legacy-model", forKey: "model")
        defaults.set(false, forKey: "streaming")
        defaults.set(45.0, forKey: "timeout")

        let migrated = AppSettings(defaults: defaults)
        let catalog = try XCTUnwrap(migrated.providerRegistry.catalog)
        let provider = try XCTUnwrap(catalog.providers.first)
        let model = try XCTUnwrap(catalog.models.first)

        XCTAssertEqual(catalog.schemaVersion, ProviderModelCatalog.currentSchemaVersion)
        XCTAssertEqual(provider.address, "https://legacy.example/v1/chat/completions")
        XCTAssertEqual(provider.addressMode, .fullEndpoint)
        XCTAssertEqual(provider.timeout, 45)
        XCTAssertEqual(model.displayName, "legacy-model")
        XCTAssertEqual(model.upstreamModelID, "legacy-model")
        XCTAssertFalse(model.isStreamingEnabled)
        XCTAssertEqual(model.source, .manual)
        XCTAssertEqual(catalog.selectedModelID, model.id)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.providerRegistry.catalog, catalog)
        XCTAssertEqual(reloaded.providerRegistry.pendingLegacyAPIKeyMigrationProviderID, provider.id)
    }

    func testLegacyKeyMigrationRetriesAgainstOriginalProviderAfterModelSelectionChanges() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initialSettings = AppSettings(defaults: defaults)
        let registry = initialSettings.providerRegistry
        let initialCatalog = try XCTUnwrap(registry.catalog)
        let originalProvider = try XCTUnwrap(initialCatalog.providers.first)
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let secondModel = try registry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: secondProvider.id, isStreamingEnabled: true)
        )
        let failingStore = RecordingLegacyKeyStore(error: TestKeyStoreError.migrationFailed)

        XCTAssertThrowsError(try initialSettings.migratePendingLegacyAPIKey(using: failingStore))
        XCTAssertEqual(failingStore.migratedProviderIDs, [originalProvider.id])
        XCTAssertEqual(registry.pendingLegacyAPIKeyMigrationProviderID, originalProvider.id)

        try registry.selectModel(id: secondModel.id)
        let reloadedSettings = AppSettings(defaults: defaults)
        let succeedingStore = RecordingLegacyKeyStore()

        try reloadedSettings.migratePendingLegacyAPIKey(using: succeedingStore)

        XCTAssertEqual(succeedingStore.migratedProviderIDs, [originalProvider.id])
        XCTAssertNil(reloadedSettings.providerRegistry.pendingLegacyAPIKeyMigrationProviderID)
        XCTAssertNil(AppSettings(defaults: defaults).providerRegistry.pendingLegacyAPIKeyMigrationProviderID)
    }

    func testSelectionAndDeleteFallbackRefreshLegacySettingsProjection() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let registry = settings.providerRegistry
        let originalCatalog = try XCTUnwrap(registry.catalog)
        let originalModel = try XCTUnwrap(originalCatalog.models.first)
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1/chat/completions", addressMode: .fullEndpoint, timeout: 25)
        )
        let secondModel = try registry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second-upstream", providerID: secondProvider.id, isStreamingEnabled: false)
        )

        try registry.selectModel(id: secondModel.id)

        XCTAssertEqual(settings.baseURL, secondProvider.address)
        XCTAssertTrue(settings.useFullEndpoint)
        XCTAssertEqual(settings.model, secondModel.upstreamModelID)
        XCTAssertFalse(settings.streaming)
        XCTAssertEqual(settings.timeout, secondProvider.timeout)

        try registry.deleteProvider(id: secondProvider.id, keyStore: RecordingProviderKeyStore())

        XCTAssertEqual(registry.catalog?.selectedModelID, originalModel.id)
        XCTAssertEqual(settings.baseURL, originalCatalog.providers[0].address)
        XCTAssertEqual(settings.useFullEndpoint, originalCatalog.providers[0].addressMode.usesFullEndpoint)
        XCTAssertEqual(settings.model, originalModel.upstreamModelID)
        XCTAssertEqual(settings.streaming, originalModel.isStreamingEnabled)
        XCTAssertEqual(settings.timeout, originalCatalog.providers[0].timeout)
    }

    func testCorruptCatalogIsPreservedAndCannotBeOverwritten() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corrupt = Data("not a catalog".utf8)
        defaults.set(corrupt, forKey: ProviderModelRegistry.defaultsKey)

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.catalogLoadError, .decodingFailed)
        XCTAssertThrowsError(
            try settings.providerRegistry.saveProvider(
                ProviderConfiguration(name: "Other", address: "https://example.com/v1", addressMode: .baseURL, timeout: 60)
            )
        ) { error in
            XCTAssertEqual(error as? ProviderModelRegistryError, .catalogUnavailable)
        }
        XCTAssertEqual(defaults.data(forKey: ProviderModelRegistry.defaultsKey), corrupt)
    }

    func testProviderWithoutModelIsAllowedButModelNeedsExistingProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )

        XCTAssertEqual(settings.providerRegistry.catalog?.providers.last, provider)
        XCTAssertThrowsError(
            try settings.providerRegistry.saveModel(
                ModelConfiguration(displayName: "Missing", upstreamModelID: "missing", providerID: UUID(), isStreamingEnabled: true)
            )
        ) { error in
            guard case .missingProvider = error as? ProviderModelRegistryError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try settings.providerRegistry.saveProvider(
                ProviderConfiguration(name: " ", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
            )
        ) { error in
            XCTAssertEqual(error as? ProviderModelRegistryError, .invalidProviderName)
        }
        XCTAssertThrowsError(
            try settings.providerRegistry.saveProvider(
                ProviderConfiguration(name: "Invalid", address: "not-a-url", addressMode: .baseURL, timeout: 30)
            )
        ) { error in
            XCTAssertEqual(error as? ProviderModelRegistryError, .invalidProviderAddress)
        }
    }

    func testProviderDeleteCascadesModelsAndUsesFirstRemainingModelAsFallback() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let registry = settings.providerRegistry
        let original = try XCTUnwrap(registry.catalog)
        let originalProvider = try XCTUnwrap(original.providers.first)
        let originalModel = try XCTUnwrap(original.models.first)
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let secondModel = try registry.saveModel(
            ModelConfiguration(displayName: "Second Model", upstreamModelID: "second-model", providerID: secondProvider.id, isStreamingEnabled: false)
        )
        let keyStore = RecordingProviderKeyStore()

        try registry.selectModel(id: originalModel.id)
        try registry.deleteProvider(id: originalProvider.id, keyStore: keyStore)

        XCTAssertEqual(registry.catalog?.providers.map(\.id), [secondProvider.id])
        XCTAssertEqual(registry.catalog?.models, [secondModel])
        XCTAssertEqual(registry.catalog?.selectedModelID, secondModel.id)
        XCTAssertEqual(keyStore.deletedProviderIDs, [originalProvider.id])
        XCTAssertThrowsError(try registry.deleteProvider(id: secondProvider.id, keyStore: keyStore)) { error in
            XCTAssertEqual(error as? ProviderModelRegistryError, .wouldLeaveNoSelectableModel)
        }
    }

    func testCatalogSaveNormalizesNewValuesAndKeepsTheirUUIDs() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let providerID = UUID()
        let provider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(id: providerID, name: "  Trimmed  ", address: " https://trimmed.example/v1 ", addressMode: .baseURL, timeout: 20)
        )
        let modelID = UUID()
        let model = try settings.providerRegistry.saveModel(
            ModelConfiguration(id: modelID, displayName: "  Friendly  ", upstreamModelID: " upstream-model ", providerID: providerID, isStreamingEnabled: true)
        )

        XCTAssertEqual(provider.id, providerID)
        XCTAssertEqual(provider.name, "Trimmed")
        XCTAssertEqual(model.id, modelID)
        XCTAssertEqual(model.displayName, "Friendly")
        XCTAssertEqual(model.upstreamModelID, "upstream-model")
        let persisted = try XCTUnwrap(defaults.data(forKey: ProviderModelRegistry.defaultsKey))
        XCTAssertEqual(try JSONDecoder().decode(ProviderModelCatalog.self, from: persisted), settings.providerRegistry.catalog)
    }

    func testFactoryResolvesSelectedModelWithItsProviderCredential() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let registry = settings.providerRegistry
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 25)
        )
        let secondModel = try registry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second-upstream", providerID: secondProvider.id, isStreamingEnabled: false)
        )
        try registry.selectModel(id: secondModel.id)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let keyStore = LocalAPIKeyStore(fileURL: directoryURL.appendingPathComponent("credentials.json"))
        try keyStore.saveAPIKey("other-provider-key", for: UUID())
        try keyStore.saveAPIKey("selected-provider-key", for: secondProvider.id)

        let target = try OpenAICompatibleProviderFactory(settings: settings, keyStore: keyStore).makeTargetSnapshot()

        XCTAssertEqual(target.providerID, secondProvider.id)
        XCTAssertEqual(target.modelID, secondModel.id)
        XCTAssertEqual(target.upstreamModelID, "second-upstream")
        XCTAssertEqual(target.apiKey, "selected-provider-key")
        XCTAssertEqual(target.endpoint.absoluteString, "https://second.example/v1/chat/completions")
        XCTAssertFalse(target.isStreamingEnabled)
        XCTAssertEqual(target.timeout, 25)
    }

    func testLoadedCatalogIsNormalizedAndPersisted() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = ProviderConfiguration(
            name: "  Provider  ",
            address: " https://example.com/v1 ",
            addressMode: .baseURL,
            timeout: 30
        )
        let model = ModelConfiguration(
            displayName: "  Model  ",
            upstreamModelID: " upstream ",
            providerID: provider.id,
            isStreamingEnabled: true
        )
        defaults.set(
            try JSONEncoder().encode(
                ProviderModelCatalog(providers: [provider], models: [model], selectedModelID: model.id)
            ),
            forKey: ProviderModelRegistry.defaultsKey
        )

        let settings = AppSettings(defaults: defaults)
        let loaded = try XCTUnwrap(settings.providerRegistry.catalog)

        XCTAssertEqual(loaded.providers[0].name, "Provider")
        XCTAssertEqual(loaded.providers[0].address, "https://example.com/v1")
        XCTAssertEqual(loaded.models[0].displayName, "Model")
        XCTAssertEqual(loaded.models[0].upstreamModelID, "upstream")
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProviderModelCatalog.self,
                from: XCTUnwrap(defaults.data(forKey: ProviderModelRegistry.defaultsKey))
            ),
            loaded
        )
    }

    func testModelCannotMoveBetweenProviders() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = AppSettings(defaults: defaults).providerRegistry
        let catalog = try XCTUnwrap(registry.catalog)
        var model = try XCTUnwrap(catalog.models.first)
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        model.providerID = secondProvider.id

        XCTAssertThrowsError(try registry.saveModel(model)) { error in
            XCTAssertEqual(error as? ProviderModelRegistryError, .modelProviderCannotChange(model.id))
        }
    }

    func testProviderDeleteFailureKeepsCatalog() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = AppSettings(defaults: defaults).providerRegistry
        let original = try XCTUnwrap(registry.catalog)
        let originalProvider = try XCTUnwrap(original.providers.first)
        let secondProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        _ = try registry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: secondProvider.id, isStreamingEnabled: true)
        )
        let beforeDelete = registry.catalog
        let keyStore = RecordingProviderKeyStore(deleteError: TestKeyStoreError.deleteFailed)

        XCTAssertThrowsError(try registry.deleteProvider(id: originalProvider.id, keyStore: keyStore))
        XCTAssertEqual(registry.catalog, beforeDelete)
    }

    func testLegacySchemaModelsDecodeAsManual() throws {
        let providerID = UUID()
        let modelID = UUID()
        let catalogData = Data("""
        {"schemaVersion":1,"providers":[{"id":"\(providerID.uuidString)","name":"Service","address":"https://example.com/v1","addressMode":"baseURL","timeout":30}],"models":[{"id":"\(modelID.uuidString)","displayName":"Model","upstreamModelID":"model","providerID":"\(providerID.uuidString)","isStreamingEnabled":true}],"selectedModelID":"\(modelID.uuidString)"}
        """.utf8)

        let catalog = try JSONDecoder().decode(ProviderModelCatalog.self, from: catalogData)

        XCTAssertEqual(catalog.models.first?.source, .manual)
    }

    func testReplacingDiscoveredModelsPreservesManualModelsAndOtherProviders() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = AppSettings(defaults: defaults).providerRegistry
        let catalog = try XCTUnwrap(registry.catalog)
        let provider = try XCTUnwrap(catalog.providers.first)
        let manual = try registry.saveModel(
            ModelConfiguration(displayName: "Pinned", upstreamModelID: "manual", providerID: provider.id, isStreamingEnabled: false)
        )
        let otherProvider = try registry.saveProvider(
            ProviderConfiguration(name: "Other", address: "https://other.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let otherModel = try registry.saveModel(
            ModelConfiguration(displayName: "Other", upstreamModelID: "other", providerID: otherProvider.id, isStreamingEnabled: true)
        )

        try registry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: [" z ", "manual", "a", "a", " "])

        let refreshed = try XCTUnwrap(registry.catalog)
        XCTAssertEqual(refreshed.models.first(where: { $0.id == manual.id }), manual)
        XCTAssertEqual(refreshed.models.first(where: { $0.id == otherModel.id }), otherModel)
        XCTAssertEqual(
            refreshed.models.filter { $0.providerID == provider.id && $0.source == .discovered }.map(\.upstreamModelID),
            ["a", "z"]
        )
        XCTAssertFalse(refreshed.models.contains { $0.providerID == provider.id && $0.source == .discovered && $0.upstreamModelID == "manual" })
    }

    func testEmptyRefreshRemovesDiscoveredModelsAndFallsBackFromActiveModel() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = AppSettings(defaults: defaults).providerRegistry
        let provider = try XCTUnwrap(registry.catalog?.providers.first)
        let manual = try XCTUnwrap(registry.catalog?.models.first)
        try registry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: ["discovered"])
        let discovered = try XCTUnwrap(registry.catalog?.models.first(where: { $0.source == .discovered }))
        try registry.selectModel(id: discovered.id)

        try registry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: [])

        XCTAssertEqual(registry.catalog?.models, [manual])
        XCTAssertEqual(registry.catalog?.selectedModelID, manual.id)
    }

    func testRefreshThatWouldLeaveNoModelIsAtomic() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = AppSettings(defaults: defaults).providerRegistry
        let provider = try XCTUnwrap(registry.catalog?.providers.first)
        let manual = try XCTUnwrap(registry.catalog?.models.first)
        try registry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: ["discovered"])
        try registry.deleteModel(id: manual.id)
        let beforeRefresh = registry.catalog

        XCTAssertThrowsError(try registry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: [])) { error in
            XCTAssertEqual(error as? ProviderModelRegistryError, .wouldLeaveNoSelectableModel)
        }
        XCTAssertEqual(registry.catalog, beforeRefresh)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ProviderModelRegistryTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

private enum TestKeyStoreError: Error {
    case deleteFailed
    case migrationFailed
}

private final class RecordingLegacyKeyStore: LegacyAPIKeyMigrating, @unchecked Sendable {
    private let error: Error?
    private(set) var migratedProviderIDs: [UUID] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func readAPIKey(for providerID: UUID) throws -> String? { nil }
    func saveAPIKey(_ key: String, for providerID: UUID) throws {}
    func deleteAPIKey(for providerID: UUID) throws {}
    func deleteAllAPIKeys() throws {}
    func migrateLegacyAPIKey(to providerID: UUID) throws {
        migratedProviderIDs.append(providerID)
        if let error { throw error }
    }
}

private final class RecordingProviderKeyStore: APIKeyStoring, @unchecked Sendable {
    private let deleteError: Error?
    private(set) var deletedProviderIDs: [UUID] = []

    init(deleteError: Error? = nil) {
        self.deleteError = deleteError
    }

    func readAPIKey(for providerID: UUID) throws -> String? { nil }
    func saveAPIKey(_ key: String, for providerID: UUID) throws {}
    func deleteAPIKey(for providerID: UUID) throws {
        if let deleteError { throw deleteError }
        deletedProviderIDs.append(providerID)
    }
    func deleteAllAPIKeys() throws {}
}
