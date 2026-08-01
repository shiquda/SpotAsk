import Foundation

protocol ChatProvider: Sendable {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func testConnection() async throws
}

@MainActor
protocol ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider
}

@MainActor
struct OpenAICompatibleProviderFactory: ChatProviderFactory {
    let settings: AppSettings
    let keyStore: any APIKeyStoring
    let resolver: any ProviderTargetResolving = ProviderTargetResolver()

    func makeProvider() throws -> any ChatProvider {
        try makeProvider(for: makeTargetSnapshot())
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        guard let catalog = settings.providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.id == catalog.selectedModelID }) else {
            throw ChatError.invalidConfiguration
        }
        return try resolver.resolve(
            catalog: catalog,
            selectedModelID: model.id,
            apiKey: keyStore.readAPIKey(for: model.providerID)
        )
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        return OpenAICompatibleProvider(
            configuration: .init(
                endpoint: target.endpoint,
                apiKey: target.apiKey,
                model: target.upstreamModelID,
                timeout: target.timeout
            ),
            urlSession: .shared
        )
    }
}
