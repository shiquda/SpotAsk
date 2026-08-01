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

    func testSavingNewKeyTrimsWithoutReadingExistingKey() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)
        state.apiKeyDraft = "  replacement-key  \n"

        state.saveKey()

        XCTAssertEqual(keyStore.savedKeys, ["replacement-key"])
        XCTAssertEqual(keyStore.savedProviderIDs.count, 1)
        XCTAssertEqual(keyStore.readCount, 0)
        XCTAssertEqual(state.apiKeyDraft, "")
    }

    func testClearingKeyDoesNotReadItFirst() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)

        state.clearKey()

        XCTAssertEqual(keyStore.deleteCount, 1)
        XCTAssertEqual(keyStore.deletedProviderIDs.count, 1)
        XCTAssertEqual(keyStore.readCount, 0)
    }

    func testClearingAllDataDeletesEveryCredentialSlot() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)

        state.clearAllLocalData()

        XCTAssertEqual(keyStore.deleteAllCount, 1)
    }

    func testSavingAndClearingAfterProviderSwitchTargetsSelectedProvider() throws {
        let defaults = UserDefaults(suiteName: "ProviderSettingsStateTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let provider = try settings.providerRegistry.saveProvider(
            ProviderConfiguration(name: "Second", address: "https://second.example/v1", addressMode: .baseURL, timeout: 30)
        )
        let model = try settings.providerRegistry.saveModel(
            ModelConfiguration(displayName: "Second", upstreamModelID: "second", providerID: provider.id, isStreamingEnabled: true)
        )
        try settings.providerRegistry.selectModel(id: model.id)
        let keyStore = RecordingKeyStore()
        let state = ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: NoopProviderFactory()
        )
        state.apiKeyDraft = "second-key"

        state.saveKey()
        state.clearKey()

        XCTAssertEqual(keyStore.savedProviderIDs, [provider.id])
        XCTAssertEqual(keyStore.deletedProviderIDs, [provider.id])
    }

    private func makeState(keyStore: RecordingKeyStore) -> ProviderSettingsState {
        let defaults = UserDefaults(suiteName: "ProviderSettingsStateTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        return ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: NoopProviderFactory()
        )
    }
}

private final class RecordingKeyStore: APIKeyStoring, @unchecked Sendable {
    private(set) var readCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private(set) var deleteAllCount = 0
    private(set) var savedKeys: [String] = []
    private(set) var savedProviderIDs: [UUID] = []
    private(set) var deletedProviderIDs: [UUID] = []

    func readAPIKey(for providerID: UUID) throws -> String? {
        readCount += 1
        return nil
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
