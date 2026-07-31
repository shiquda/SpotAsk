import Foundation

protocol ChatProvider: Sendable {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func testConnection() async throws
}

@MainActor
protocol ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider
}

@MainActor
struct OpenAICompatibleProviderFactory: ChatProviderFactory {
    let settings: AppSettings
    let keyStore: any APIKeyStoring

    func makeProvider() throws -> any ChatProvider {
        let endpoint = try URLNormalizer.endpoint(from: settings.baseURL, useFullEndpoint: settings.useFullEndpoint)
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatError.invalidConfiguration }
        guard let key = try keyStore.readAPIKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.missingAPIKey
        }
        return OpenAICompatibleProvider(
            configuration: .init(endpoint: endpoint, apiKey: key, model: settings.model, timeout: settings.timeout),
            urlSession: .shared
        )
    }
}
