import Foundation

enum ProviderAddressMode: String, Codable, CaseIterable, Sendable {
    case baseURL
    case fullEndpoint

    var usesFullEndpoint: Bool { self == .fullEndpoint }
}

enum ModelConfigurationSource: String, Codable, Equatable, Sendable {
    case manual
    case discovered
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
    var source: ModelConfigurationSource

    init(
        id: UUID = UUID(),
        displayName: String,
        upstreamModelID: String,
        providerID: UUID,
        isStreamingEnabled: Bool,
        source: ModelConfigurationSource = .manual
    ) {
        self.id = id
        self.displayName = displayName
        self.upstreamModelID = upstreamModelID
        self.providerID = providerID
        self.isStreamingEnabled = isStreamingEnabled
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case upstreamModelID
        case providerID
        case isStreamingEnabled
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        upstreamModelID = try container.decode(String.self, forKey: .upstreamModelID)
        providerID = try container.decode(UUID.self, forKey: .providerID)
        isStreamingEnabled = try container.decode(Bool.self, forKey: .isStreamingEnabled)
        source = try container.decodeIfPresent(ModelConfigurationSource.self, forKey: .source) ?? .manual
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
