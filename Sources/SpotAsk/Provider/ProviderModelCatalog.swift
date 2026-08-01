import Foundation

enum ProviderAddressMode: String, Codable, CaseIterable, Sendable {
    case baseURL
    case fullEndpoint

    var usesFullEndpoint: Bool { self == .fullEndpoint }
}

struct ProviderConfiguration: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var address: String
    var addressMode: ProviderAddressMode
    var timeout: TimeInterval

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        addressMode: ProviderAddressMode,
        timeout: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.addressMode = addressMode
        self.timeout = timeout
    }
}

struct ModelConfiguration: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var upstreamModelID: String
    var providerID: UUID
    var isStreamingEnabled: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        upstreamModelID: String,
        providerID: UUID,
        isStreamingEnabled: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.upstreamModelID = upstreamModelID
        self.providerID = providerID
        self.isStreamingEnabled = isStreamingEnabled
    }
}

struct ProviderModelCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var providers: [ProviderConfiguration]
    var models: [ModelConfiguration]
    var selectedModelID: UUID

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        providers: [ProviderConfiguration],
        models: [ModelConfiguration],
        selectedModelID: UUID
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.models = models
        self.selectedModelID = selectedModelID
    }
}
