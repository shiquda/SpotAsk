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
        XCTAssertEqual(keyStore.readCount, 0)
        XCTAssertEqual(state.apiKeyDraft, "")
    }

    func testClearingKeyDoesNotReadItFirst() {
        let keyStore = RecordingKeyStore()
        let state = makeState(keyStore: keyStore)

        state.clearKey()

        XCTAssertEqual(keyStore.deleteCount, 1)
        XCTAssertEqual(keyStore.readCount, 0)
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
    private(set) var savedKeys: [String] = []

    func readAPIKey() throws -> String? {
        readCount += 1
        return nil
    }

    func saveAPIKey(_ key: String) throws {
        saveCount += 1
        savedKeys.append(key)
    }

    func deleteAPIKey() throws {
        deleteCount += 1
    }
}

@MainActor
private struct NoopProviderFactory: ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider {
        NoopProvider()
    }
}

private struct NoopProvider: ChatProvider {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func testConnection() async throws {}
}
