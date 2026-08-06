import Foundation

enum ProviderAddressMode: String, Codable, CaseIterable, Sendable {
    case baseURL
    case fullEndpoint

    var usesFullEndpoint: Bool { self == .fullEndpoint }
}

/// Wire format used when talking to a Service. OpenAI-compatible keeps the
/// chat-completions convention; Anthropic uses the official Messages API.
enum ProviderFormat: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case anthropic
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
    var format: ProviderFormat

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        addressMode: ProviderAddressMode,
        timeout: TimeInterval,
        format: ProviderFormat = .openAICompatible
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.addressMode = addressMode
        self.timeout = timeout
        self.format = format
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case addressMode
        case timeout
        case format
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        addressMode = try container.decode(ProviderAddressMode.self, forKey: .addressMode)
        timeout = try container.decode(TimeInterval.self, forKey: .timeout)
        format = try container.decodeIfPresent(ProviderFormat.self, forKey: .format) ?? .openAICompatible
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
