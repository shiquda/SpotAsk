import XCTest
@testable import SpotAsk

@MainActor
final class ProviderSettingsStateTests: XCTestCase {
    func testOpeningSettingsStateDoesNotAccessSecretStore() {
        let keyStore = RecordingKeyStore()
        _ = makeState(keyStore: keyStore)

        XCTAssertEqual(keyStore.readCount, 0)
        XCTAssertEqual(keyStore.saveCount, 0)
        XCTAssertEqual(keyStore.deleteCount, 0)
    }

    func testInitAutoSelectsFirstProvider() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)

        XCTAssertNotNil(state.selectedProviderID)
        XCTAssertNil(state.selectedModelID)
        XCTAssertFalse(state.draftProviderName.isEmpty)
        XCTAssertFalse(state.isCreatingProvider)
    }

    func testSelectProviderPopulatesDraftFields() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 45)
        )
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.selectProvider(provider.id)

        XCTAssertEqual(state.selectedProviderID, provider.id)
        XCTAssertNil(state.selectedModelID)
        XCTAssertEqual(state.draftProviderName, "Second")
        XCTAssertEqual(state.draftProviderAddress, "https://second.example/v1")
        XCTAssertEqual(state.draftProviderAddressMode, .baseURL)
        XCTAssertEqual(state.draftProviderTimeout, 45)
    }

    func testSelectModelPopulatesDraftFields() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let catalog = try XCTUnwrap(settings.providerRegistry.catalog)
        let model = try XCTUnwrap(catalog.models.first)

        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.selectModel(model.id)

        XCTAssertEqual(state.selectedModelID, model.id)
        XCTAssertNil(state.selectedProviderID)
        XCTAssertEqual(state.draftModelDisplayName, model.displayName)
        XCTAssertEqual(state.draftModelUpstreamID, model.upstreamModelID)
        XCTAssertEqual(state.draftModelStreaming, model.isStreamingEnabled)
    }

    func testSavingNewKeyTargetsSelectedProvider() throws {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)
        state.apiKeyDraft = "  replacement-key  \n"

        state.saveKey()

        XCTAssertEqual(keyStore.savedKeys, ["replacement-key"])
        XCTAssertEqual(keyStore.savedProviderIDs.count, 1)
        XCTAssertEqual(keyStore.savedProviderIDs.first, state.selectedProviderID)
        XCTAssertEqual(keyStore.readCount, 0)
        XCTAssertEqual(state.apiKeyDraft, "")
    }

    func testSavingEmptyKeyShowsError() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)
        state.apiKeyDraft = ""

        state.saveKey()

        XCTAssertTrue(state.statusIsError)
        XCTAssertEqual(keyStore.saveCount, 0)
    }

    func testClearingKeyTargetsSelectedProvider() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)

        state.clearKey()

        XCTAssertEqual(keyStore.deleteCount, 1)
        XCTAssertEqual(keyStore.deletedProviderIDs.first, state.selectedProviderID)
        XCTAssertEqual(keyStore.readCount, 0)
    }

    func testClearingAllDataDeletesEveryCredentialSlot() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)

        state.clearAllLocalData()

        XCTAssertEqual(keyStore.deleteAllCount, 1)
    }

    func testSaveProviderCreatesNewEntry() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let initialProviderCount = settings.providerRegistry.catalog?.providers.count ?? 0
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.startNewProvider()
        state.draftProviderName = "New Provider"
        state.draftProviderAddress = "https://new.example.com/v1"
        state.draftProviderAddressMode = .baseURL
        state.draftProviderTimeout = 30
        state.saveProvider()

        XCTAssertFalse(state.isCreatingProvider)
        XCTAssertNotNil(state.selectedProviderID)
        XCTAssertEqual(state.draftProviderName, "New Provider")
        XCTAssertEqual(settings.providerRegistry.catalog?.providers.count, initialProviderCount + 1)
        let saved = try XCTUnwrap(settings.providerRegistry.catalog?.providers.last)
        XCTAssertEqual(saved.name, "New Provider")
    }

    func testSaveProviderUpdatesExistingEntry() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let originalProvider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.selectProvider(originalProvider.id)
        state.draftProviderName = "Updated Name"
        state.saveProvider()

        let updated = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        XCTAssertEqual(updated.name, "Updated Name")
        XCTAssertEqual(updated.id, originalProvider.id)
    }

    func testSaveProviderFailsWithEmptyName() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.startNewProvider()
        state.draftProviderName = ""
        state.draftProviderAddress = "https://new.example.com/v1"
        state.saveProvider()

        XCTAssertTrue(state.statusIsError)
        XCTAssertTrue(state.isCreatingProvider)
    }

    func testSaveModelCreatesNewEntry() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let initialModelCount = settings.providerRegistry.catalog?.models.count ?? 0
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.startNewModel(for: provider.id)
        state.draftModelDisplayName = "New Model"
        state.draftModelUpstreamID = "new-upstream"
        state.draftModelStreaming = false
        state.saveModel()

        XCTAssertFalse(state.isCreatingModel)
        XCTAssertNotNil(state.selectedModelID)
        XCTAssertEqual(settings.providerRegistry.catalog?.models.count, initialModelCount + 1)
        let saved = try XCTUnwrap(settings.providerRegistry.catalog?.models.last)
        XCTAssertEqual(saved.displayName, "New Model")
        XCTAssertEqual(saved.upstreamModelID, "new-upstream")
        XCTAssertEqual(saved.providerID, provider.id)
        XCTAssertFalse(saved.isStreamingEnabled)
    }

    func testSaveModelUpdatesExistingEntry() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let originalModel = try XCTUnwrap(settings.providerRegistry.catalog?.models.first)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.selectModel(originalModel.id)
        state.draftModelDisplayName = "Updated Model"
        state.saveModel()

        let updated = try XCTUnwrap(settings.providerRegistry.catalog?.models.first)
        XCTAssertEqual(updated.displayName, "Updated Model")
        XCTAssertEqual(updated.id, originalModel.id)
    }

    func testDeleteModelShowsConfirmation() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        _ = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Extra", upstreamModelID: "extra", providerID: provider.id, isStreamingEnabled: true)
        )
        let modelToDelete = try XCTUnwrap(settings.providerRegistry.catalog?.models.last)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.requestDeleteModel(modelToDelete.id)
        XCTAssertEqual(state.pendingDeleteModelID, modelToDelete.id)

        state.confirmDeleteModel()
        XCTAssertNil(state.pendingDeleteModelID)
        XCTAssertFalse(state.statusIsError)
        XCTAssertNil(settings.providerRegistry.catalog?.models.first(where: { $0.id == modelToDelete.id }))
    }

    func testDeleteProviderShowsConfirmation() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "ToDelete", address: "https://todelete.example/v1", addressMode: .baseURL, timeout: 30)
        )
        _ = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Backup", upstreamModelID: "backup", providerID: provider.id, isStreamingEnabled: true)
        )
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.requestDeleteProvider(provider.id)
        XCTAssertEqual(state.pendingDeleteProviderID, provider.id)

        state.confirmDeleteProvider()
        XCTAssertNil(state.pendingDeleteProviderID)
        XCTAssertNil(settings.providerRegistry.catalog?.providers.first(where: { $0.id == provider.id }))
    }

    func testURLEndpointValidation() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.draftProviderAddressMode = .baseURL
        state.validateProviderURL("https://valid.example.com/v1")
        XCTAssertNil(state.providerFieldError)

        state.validateProviderURL("not-a-url")
        XCTAssertNotNil(state.providerFieldError)

        state.validateProviderURL("")
        XCTAssertNil(state.providerFieldError) // Empty is not validated as error
    }

    func testProviderExpansionToggle() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        XCTAssertTrue(state.expandedProviderIDs.contains(provider.id),
                       "Selected provider should be expanded")

        state.toggleProviderExpansion(provider.id)
        XCTAssertFalse(state.expandedProviderIDs.contains(provider.id))

        state.toggleProviderExpansion(provider.id)
        XCTAssertTrue(state.expandedProviderIDs.contains(provider.id))
    }

    func testCancelEditingResetsToPreviousSelection() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.selectProvider(provider.id)
        let originalName = state.draftProviderName
        state.draftProviderName = "Changed"
        state.cancelEditing()

        XCTAssertEqual(state.draftProviderName, originalName)
        XCTAssertEqual(state.selectedProviderID, provider.id)
        XCTAssertFalse(state.isCreatingProvider)
    }

    func testSelectingModelExpandsParentProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let catalog = try XCTUnwrap(settings.providerRegistry.catalog)
        let model = try XCTUnwrap(catalog.models.first)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        // Collapse all first
        state.expandedProviderIDs.removeAll()

        state.selectModel(model.id)

        XCTAssertTrue(state.expandedProviderIDs.contains(model.providerID),
                      "Parent provider should be expanded when model is selected")
    }

    func testStatusClearOnDraftChange() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.status = "Error message"
        state.statusIsError = true
        state.clearStatus()

        XCTAssertTrue(state.status.isEmpty)
        XCTAssertFalse(state.statusIsError)
    }

    func testCanSaveProviderFlags() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.startNewProvider()
        state.draftProviderName = ""
        state.draftProviderAddress = ""
        XCTAssertFalse(state.canSaveProvider)

        state.draftProviderName = "Test"
        state.draftProviderAddress = ""
        XCTAssertFalse(state.canSaveProvider)

        state.draftProviderName = ""
        state.draftProviderAddress = "https://test.example/v1"
        XCTAssertFalse(state.canSaveProvider)

        state.draftProviderName = "Test"
        state.draftProviderAddress = "https://test.example/v1"
        XCTAssertTrue(state.canSaveProvider)
    }

    func testCanTestConnectionWithValidProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        // Auto-selected provider should have a model with valid URL in draft
        XCTAssertTrue(state.canTestConnection)
    }

    // MARK: - Model activation

    func testUseForChatActivatesModel() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )
        let catalog = try XCTUnwrap(settings.providerRegistry.catalog)
        // Create a second model so we can switch to it
        let provider = try XCTUnwrap(catalog.providers.first)
        let newModel = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: provider.id, isStreamingEnabled: true)
        )
        let originalActiveID = catalog.selectedModelID

        state.useModelForChat(newModel.id)

        XCTAssertEqual(settings.providerRegistry.catalog?.selectedModelID, newModel.id)
        XCTAssertNotEqual(settings.providerRegistry.catalog?.selectedModelID, originalActiveID)
        XCTAssertEqual(state.activeModelID, newModel.id,
                       "Observable activeModelID must reflect the new active model")
        XCTAssertFalse(state.statusIsError)
    }

    func testEditingSelectionDoesNotSwitchActiveModel() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )
        let catalog = try XCTUnwrap(settings.providerRegistry.catalog)
        let provider = try XCTUnwrap(catalog.providers.first)
        let newModel = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: provider.id, isStreamingEnabled: true)
        )
        let originalActiveID = catalog.selectedModelID

        // Selecting for editing must NOT change the active chat model
        state.selectModel(newModel.id)

        XCTAssertEqual(state.selectedModelID, newModel.id)
        XCTAssertEqual(settings.providerRegistry.catalog?.selectedModelID, originalActiveID,
                       "Editing selection must not switch active chat model")
    }

    func testDeleteActiveModelSyncsActiveModelID() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let catalog = try XCTUnwrap(settings.providerRegistry.catalog)
        let provider = try XCTUnwrap(catalog.providers.first)
        let secondModel = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: provider.id, isStreamingEnabled: true)
        )
        try settings.providerRegistry.selectModel(id: secondModel.id)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )
        XCTAssertEqual(state.activeModelID, secondModel.id)

        // Delete the currently active model; registry falls back to first remaining
        state.requestDeleteModel(secondModel.id)
        state.confirmDeleteModel()

        let fallbackID = settings.providerRegistry.catalog?.selectedModelID
        XCTAssertNotNil(fallbackID)
        XCTAssertNotEqual(fallbackID, secondModel.id, "Registry should have fallen back to another model")
        XCTAssertEqual(state.activeModelID, fallbackID,
                       "Observable activeModelID must match registry fallback after deleting active model")
    }

    func testDeleteProviderWithActiveModelSyncsActiveModelID() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let secondProvider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let secondModel = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: secondProvider.id, isStreamingEnabled: true)
        )
        try settings.providerRegistry.selectModel(id: secondModel.id)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )
        XCTAssertEqual(state.activeModelID, secondModel.id)

        // Delete the provider that owns the active model
        state.requestDeleteProvider(secondProvider.id)
        state.confirmDeleteProvider()

        let fallbackID = settings.providerRegistry.catalog?.selectedModelID
        XCTAssertNotNil(fallbackID)
        XCTAssertNotEqual(fallbackID, secondModel.id, "Registry should have fallen back after provider deletion")
        XCTAssertEqual(state.activeModelID, fallbackID,
                       "Observable activeModelID must match registry fallback after deleting active model's provider")
    }

    func testEditingSelectionResolvesAfterDeletingParentProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let secondProvider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let secondModel = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: secondProvider.id, isStreamingEnabled: true)
        )
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        // Select the second model for editing
        state.selectModel(secondModel.id)
        XCTAssertEqual(state.selectedModelID, secondModel.id)

        // Delete the provider that owns the editing selection
        state.requestDeleteProvider(secondProvider.id)
        state.confirmDeleteProvider()

        // Editing selection must not dangle — it must be valid in the current catalog
        if let editingID = state.selectedModelID {
            XCTAssertTrue(
                settings.providerRegistry.catalog?.models.contains(where: { $0.id == editingID }) ?? false,
                "Editing selectedModelID must reference a model that still exists in the catalog"
            )
        } else if let providerID = state.selectedProviderID {
            XCTAssertTrue(
                settings.providerRegistry.catalog?.providers.contains(where: { $0.id == providerID }) ?? false,
                "Editing selectedProviderID must reference a provider that still exists in the catalog"
            )
        }
        // activeModelID must also be valid
        if let activeID = state.activeModelID {
            XCTAssertTrue(
                settings.providerRegistry.catalog?.models.contains(where: { $0.id == activeID }) ?? false,
                "activeModelID must reference a model that still exists in the catalog"
            )
        }
    }

    // MARK: - canSaveProvider URL validation

    func testCanSaveProviderBlocksInvalidURLForNewProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.startNewProvider()
        state.draftProviderName = "Test"
        state.draftProviderAddress = "not-a-valid-url"
        state.validateProviderURL("not-a-valid-url")

        XCTAssertNotNil(state.providerFieldError)
        XCTAssertFalse(state.canSaveProvider, "Invalid URL must disable save even for new providers")
    }

    // MARK: - Connection test with draft values

    func testConnectionTestUsesDraftValues() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let catalog = try XCTUnwrap(settings.providerRegistry.catalog)
        let provider = try XCTUnwrap(catalog.providers.first)

        // Create a RecordingProviderFactory that captures the target
        let recordingFactory = RecordingProviderFactory()
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: recordingFactory
        )

        state.selectProvider(provider.id)
        // Set draft values that differ from catalog
        state.draftProviderAddress = "https://draft.example.com/v1"
        state.draftProviderAddressMode = .baseURL
        state.draftProviderTimeout = 88
        state.apiKeyDraft = "draft-test-key"
        state.testConnection()

        // Wait for async testConnection to complete
        let expectation = XCTestExpectation(description: "connection test completes")
        Task {
            // Poll until test completes or timeout
            var attempts = 0
            while state.isTesting && attempts < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                attempts += 1
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        let captured = recordingFactory.capturedTarget
        XCTAssertNotNil(captured, "Factory should have received a target from testConnection")
        if let captured {
            XCTAssertEqual(captured.endpoint.absoluteString, "https://draft.example.com/v1/chat/completions",
                           "Endpoint should use draft address")
            XCTAssertEqual(captured.timeout, 88, "Timeout should use draft value")
            XCTAssertEqual(captured.providerID, provider.id, "Provider ID should match selected provider")
            XCTAssertEqual(captured.apiKey, "draft-test-key", "API key should use draft")
        }
    }

    func testConnectionTestWithoutKeyShowsMissingAPIKeyError() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(),
            providerFactory: NoopProviderFactory()
        )

        state.apiKeyDraft = ""  // No key
        state.testConnection()

        // Wait for async testConnection to complete
        let expectation = XCTestExpectation(description: "connection test completes")
        Task {
            var attempts = 0
            while state.isTesting && attempts < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                attempts += 1
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(state.statusIsError, "Should show error when no API key provided")
        XCTAssertTrue(state.status.contains("key") || state.status.contains("Key") || state.status.contains("密钥"),
                      "Error message should indicate missing key, got: \(state.status)")
    }

    func testRefreshModelsShowsLoadingThenAddsDiscoveredModelsWithoutChangingDraft() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let discovery = StubModelDiscovery(result: .success([" service-model ", "service-model"]))
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: discovery
        )
        state.draftProviderName = "Unsaved name"

        state.refreshModels()

        XCTAssertEqual(state.modelRefreshStatus, .loading)
        await waitForModelRefresh(state)
        XCTAssertEqual(state.modelRefreshStatus, .success(1))
        XCTAssertEqual(state.draftProviderName, "Unsaved name")
        XCTAssertEqual(discovery.callCount, 1)
        XCTAssertEqual(
            settings.providerRegistry.catalog?.models.first(where: { $0.providerID == provider.id && $0.source == .discovered })?.upstreamModelID,
            "service-model"
        )
    }

    func testRefreshFailureLeavesCatalogUntouched() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        try settings.providerRegistry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: ["existing"])
        let beforeRefresh = settings.providerRegistry.catalog
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: StubModelDiscovery(result: .failure(URLError(.cannotConnectToHost)))
        )

        state.refreshModels()
        await waitForModelRefresh(state)

        XCTAssertEqual(state.modelRefreshStatus, .failed)
        XCTAssertEqual(settings.providerRegistry.catalog, beforeRefresh)
    }

    func testRefreshWithoutAccessKeyDoesNotCallService() async throws {
        let discovery = StubModelDiscovery(result: .success(["unused"]))
        let state = makeState(keyStore: RecordingKeyStore(), modelDiscovery: discovery)

        state.refreshModels()
        await waitForModelRefresh(state)

        XCTAssertEqual(state.modelRefreshStatus, .missingAccessKey)
        XCTAssertEqual(discovery.callCount, 0)
    }

    func testFullEndpointDoesNotSendModelRefreshRequest() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        var provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        provider.address = "https://example.com/v1/chat/completions"
        provider.addressMode = .fullEndpoint
        try settings.providerRegistry.saveProvider(provider)
        let discovery = StubModelDiscovery(result: .success(["unused"]))
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: discovery
        )

        state.refreshModels()
        await Task.yield()

        XCTAssertFalse(state.canRefreshModels)
        XCTAssertEqual(state.modelRefreshStatus, .unavailable)
        XCTAssertEqual(discovery.callCount, 0)
    }

    func testCancelledRefreshKeepsCatalogAndReportsStoppedState() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let beforeRefresh = settings.providerRegistry.catalog
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: StubModelDiscovery(result: .failure(CancellationError()))
        )

        state.refreshModels()
        await waitForModelRefresh(state)

        XCTAssertEqual(state.modelRefreshStatus, .cancelled)
        XCTAssertEqual(settings.providerRegistry.catalog, beforeRefresh)
    }

    func testSwitchingProvidersKeepsNewRefreshOwnedByTheNewProvider() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let firstProvider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let secondProvider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let discovery = ControlledModelDiscovery()
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: discovery
        )

        state.refreshModels()
        let firstCallStarted = await discovery.waitForCallCount(1)
        XCTAssertTrue(firstCallStarted)
        state.selectProvider(secondProvider.id)
        state.refreshModels()
        let secondCallStarted = await discovery.waitForCallCount(2)
        XCTAssertTrue(secondCallStarted)

        await discovery.resume(call: 0, returning: ["stale-model"])
        await Task.yield()
        XCTAssertTrue(state.isRefreshingModels)

        state.cancelModelRefresh()
        XCTAssertEqual(state.modelRefreshStatus, .cancelled)
        await discovery.resume(call: 1, returning: ["current-model"])
        await Task.yield()

        XCTAssertEqual(state.modelRefreshStatus, .cancelled)
        XCTAssertFalse(settings.providerRegistry.catalog?.models.contains {
            $0.providerID == firstProvider.id && $0.upstreamModelID == "stale-model"
        } ?? true)
        XCTAssertFalse(settings.providerRegistry.catalog?.models.contains {
            $0.providerID == secondProvider.id && $0.upstreamModelID == "current-model"
        } ?? true)
    }

    func testSavingProviderConfigurationInvalidatesItsInFlightRefresh() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        let discovery = ControlledModelDiscovery()
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: discovery
        )

        state.refreshModels()
        let refreshStarted = await discovery.waitForCallCount(1)
        XCTAssertTrue(refreshStarted)
        state.draftProviderAddress = "https://new.example/v1"
        state.validateProviderURL(state.draftProviderAddress)
        state.saveProvider()
        await discovery.resume(call: 0, returning: ["stale-model"])
        await Task.yield()

        XCTAssertEqual(
            settings.providerRegistry.catalog?.providers.first(where: { $0.id == provider.id })?.address,
            "https://new.example/v1"
        )
        XCTAssertFalse(settings.providerRegistry.catalog?.models.contains {
            $0.providerID == provider.id && $0.upstreamModelID == "stale-model"
        } ?? true)
        XCTAssertFalse(state.isRefreshingModels)
    }

    func testRefreshFallbackSynchronizesActiveModelMirror() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let provider = try XCTUnwrap(settings.providerRegistry.catalog?.providers.first)
        try settings.providerRegistry.replaceDiscoveredModels(for: provider.id, upstreamModelIDs: ["temporary"])
        let discovered = try XCTUnwrap(settings.providerRegistry.catalog?.models.first { $0.source == .discovered })
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: RecordingKeyStore(apiKey: "saved-key"),
            providerFactory: NoopProviderFactory(),
            modelDiscovery: StubModelDiscovery(result: .success([]))
        )
        state.useModelForChat(discovered.id)

        state.refreshModels()
        await waitForModelRefresh(state)

        XCTAssertNotEqual(settings.providerRegistry.catalog?.selectedModelID, discovered.id)
        XCTAssertEqual(state.activeModelID, settings.providerRegistry.catalog?.selectedModelID)
    }

    // MARK: - Helpers

    private func makeState(
        keyStore: RecordingKeyStore,
        modelDiscovery: any ProviderModelDiscovering = StubModelDiscovery(result: .success([]))
    ) -> ProviderSettingsState {
        let defaults = UserDefaults(suiteName: "ProviderSettingsStateTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        return ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: NoopProviderFactory(),
            modelDiscovery: modelDiscovery
        )
    }

    private func waitForModelRefresh(_ state: ProviderSettingsState) async {
        for _ in 0 ..< 100 {
            if !state.isRefreshingModels { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for model refresh")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ProviderSettingsStateTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

private final class RecordingKeyStore: APIKeyStoring, @unchecked Sendable {
    private let apiKey: String?
    private(set) var readCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private(set) var deleteAllCount = 0
    private(set) var savedKeys: [String] = []
    private(set) var savedProviderIDs: [UUID] = []
    private(set) var deletedProviderIDs: [UUID] = []

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func readAPIKey(for providerID: UUID) throws -> String? {
        readCount += 1
        return apiKey
    }

    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        saveCount += 1
        savedKeys.append(key)
        savedProviderIDs.append(providerID)
    }

    func deleteAPIKey(for providerID: UUID) throws {
        deleteCount += 1
        deletedProviderIDs.append(providerID)
    }

    func deleteAllAPIKeys() throws { deleteAllCount += 1 }
}

private final class StubModelDiscovery: ProviderModelDiscovering, @unchecked Sendable {
    private let result: Result<[String], Error>
    private(set) var callCount = 0

    init(result: Result<[String], Error>) {
        self.result = result
    }

    func models(for provider: ProviderConfiguration, apiKey: String) async throws -> [String] {
        callCount += 1
        return try result.get()
    }
}

private actor ControlledModelDiscovery: ProviderModelDiscovering {
    private struct PendingCall {
        let continuation: CheckedContinuation<[String], Error>
    }

    private var pendingCalls: [PendingCall] = []

    func models(for provider: ProviderConfiguration, apiKey: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            pendingCalls.append(PendingCall(continuation: continuation))
        }
    }

    func waitForCallCount(_ expectedCount: Int) async -> Bool {
        for _ in 0 ..< 100 {
            if pendingCalls.count >= expectedCount { return true }
            await Task.yield()
        }
        return false
    }

    func resume(call index: Int, returning models: [String]) {
        pendingCalls[index].continuation.resume(returning: models)
    }
}

@MainActor
private struct NoopProviderFactory: ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider {
        NoopProvider()
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        NoopProvider()
    }
}

private struct NoopProvider: ChatProvider {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func testConnection() async throws {}
}

@MainActor
private final class RecordingProviderFactory: ChatProviderFactory {
    private(set) var capturedTarget: ProviderTargetSnapshot?

    func makeProvider() throws -> any ChatProvider {
        NoopProvider()
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        capturedTarget = target
        return NoopProvider()
    }
}
