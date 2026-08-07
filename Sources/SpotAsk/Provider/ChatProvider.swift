import Foundation

protocol ChatProvider: Sendable {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func testConnection() async throws
}

@MainActor
protocol ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot
    func makeTargetSnapshot(modelID: UUID) throws -> ProviderTargetSnapshot
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider
}

extension ChatProviderFactory {
    /// Default implementation keeps test factories that only model the
    /// catalog-default path compiling without repeating the override.
    func makeTargetSnapshot(modelID: UUID) throws -> ProviderTargetSnapshot {
        try makeTargetSnapshot()
    }
}

@MainActor
struct OpenAICompatibleProviderFactory: ChatProviderFactory {
    let settings: AppSettings
    let keyStore: any APIKeyStoring
    let resolver: any ProviderTargetResolving = ProviderTargetResolver()

    private var proxyPassword: String {
        (try? keyStore.readAPIKey(for: ProxyCredentialSlot.providerID)) ?? ""
    }

    private var proxyConfiguration: [String: Any]? {
        guard settings.proxyEnabled else { return nil }
        return ChatNetworking.proxyConfiguration(
            type: settings.proxyType,
            host: settings.proxyHost,
            port: settings.proxyPort,
            username: settings.proxyUsername,
            password: proxyPassword
        )
    }

    func makeProvider() throws -> any ChatProvider {
        try makeProvider(for: makeTargetSnapshot())
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        guard let catalog = settings.providerRegistry.catalog else {
            throw ChatError.invalidConfiguration
        }
        return try makeTargetSnapshot(modelID: catalog.selectedModelID)
    }

    func makeTargetSnapshot(modelID: UUID) throws -> ProviderTargetSnapshot {
        guard let catalog = settings.providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.id == modelID }) else {
            throw ChatError.invalidConfiguration
        }
        return try resolver.resolve(
            catalog: catalog,
            selectedModelID: model.id,
            apiKey: keyStore.readAPIKey(for: model.providerID)
        )
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        let urlSession = ChatNetworking.urlSession(proxyConfiguration: proxyConfiguration)
        switch target.format {
        case .openAICompatible:
            return OpenAICompatibleProvider(
                configuration: .init(
                    endpoint: target.endpoint,
                    apiKey: target.apiKey,
                    model: target.upstreamModelID,
                    timeout: target.timeout
                ),
                urlSession: urlSession
            )
        case .anthropic:
            return AnthropicProvider(
                configuration: .init(
                    endpoint: target.endpoint,
                    apiKey: target.apiKey,
                    model: target.upstreamModelID,
                    timeout: target.timeout
                ),
                urlSession: urlSession
            )
        }
    }
}
