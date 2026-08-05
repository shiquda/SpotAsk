import Foundation

struct ProviderTargetSnapshot: Equatable, Sendable {
    let modelID: UUID
    let providerID: UUID
    let endpoint: URL
    let apiKey: String
    let displayName: String
    let upstreamModelID: String
    let isStreamingEnabled: Bool
    let timeout: TimeInterval
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
            endpoint: try URLNormalizer.endpoint(from: provider.address, useFullEndpoint: provider.addressMode.usesFullEndpoint),
            apiKey: apiKey,
            displayName: model.displayName,
            upstreamModelID: model.upstreamModelID,
            isStreamingEnabled: model.isStreamingEnabled,
            timeout: provider.timeout
        )
    }
}
