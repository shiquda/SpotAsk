import Foundation

struct ProviderTargetSnapshot: Equatable, Sendable {
    let modelID: UUID
    let providerID: UUID
    let endpoint: URL
    let apiKey: String
    let displayName: String
    let upstreamModelID: String
    let providerName: String
    let isStreamingEnabled: Bool
    let timeout: TimeInterval
    let format: ProviderFormat

    init(
        modelID: UUID,
        providerID: UUID,
        endpoint: URL,
        apiKey: String,
        displayName: String,
        upstreamModelID: String,
        providerName: String = "",
        isStreamingEnabled: Bool,
        timeout: TimeInterval,
        format: ProviderFormat = .openAICompatible
    ) {
        self.modelID = modelID
        self.providerID = providerID
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.displayName = displayName
        self.upstreamModelID = upstreamModelID
        self.providerName = providerName
        self.isStreamingEnabled = isStreamingEnabled
        self.timeout = timeout
        self.format = format
    }
}

protocol ProviderTargetResolving: Sendable {
    func resolve(
        catalog: ProviderModelCatalog,
        selectedModelID: UUID,
        apiKey: String?
    ) throws -> ProviderTargetSnapshot
}

struct ProviderTargetResolver: ProviderTargetResolving {
    func resolve(
        catalog: ProviderModelCatalog,
        selectedModelID: UUID,
        apiKey: String?
    ) throws -> ProviderTargetSnapshot {
        guard let model = catalog.models.first(where: { $0.id == selectedModelID }),
              let provider = catalog.providers.first(where: { $0.id == model.providerID }) else {
            throw ChatError.invalidConfiguration
        }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.missingAPIKey
        }
        return ProviderTargetSnapshot(
            modelID: model.id,
            providerID: provider.id,
            endpoint: try URLNormalizer.endpoint(
                from: provider.address,
                useFullEndpoint: provider.addressMode.usesFullEndpoint,
                format: provider.format
            ),
            apiKey: apiKey,
            displayName: model.displayName,
            upstreamModelID: model.upstreamModelID,
            providerName: provider.name,
            isStreamingEnabled: model.isStreamingEnabled,
            timeout: provider.timeout,
            format: provider.format
        )
    }
}
