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

enum ModelThinkingMode: String, Codable, CaseIterable, Equatable, Sendable {
    case providerDefault
    case disabled
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
}

enum RequestCompatibilityProfile: String, Codable, CaseIterable, Sendable {
    case genericOpenAI
    case openAI
    case azureOpenAI
    case deepSeek
    case qwen
    case kimi
    case zAI
    case mistral
    case xAI
    case openRouter
    case volcengineArk
    case siliconFlow
    case anthropic
}

enum ModelJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ModelJSONValue])
    case object([String: ModelJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ModelJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ModelJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

extension ModelJSONValue {
    static func wrapping(_ value: some Encodable) throws -> ModelJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(ModelJSONValue.self, from: data)
    }

    func merged(with other: ModelJSONValue) -> ModelJSONValue {
        switch (self, other) {
        case let (.object(lhs), .object(rhs)):
            var result = lhs
            for (key, value) in rhs {
                result[key] = result[key]?.merged(with: value) ?? value
            }
            return .object(result)
        default:
            return other
        }
    }
}

extension Dictionary where Key == String, Value == ModelJSONValue {
    mutating func mergeModelJSON(_ other: [String: ModelJSONValue]) {
        for (key, value) in other {
            self[key] = self[key]?.merged(with: value) ?? value
        }
    }
}

extension ModelThinkingMode {
    var openAIEffort: String? {
        switch self {
        case .providerDefault: nil
        case .disabled: "none"
        case .minimal: "minimal"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        case .max: "max"
        }
    }

    var budgetTokens: Int? {
        switch self {
        case .providerDefault, .disabled: nil
        case .minimal: 1_024
        case .low: 2_048
        case .medium: 4_096
        case .high: 8_192
        case .xhigh: 12_288
        case .max: 16_384
        }
    }

    var arkEffort: String? {
        switch self {
        case .providerDefault, .disabled: nil
        case .minimal, .low: "low"
        case .medium: "medium"
        case .high, .xhigh, .max: "high"
        }
    }
}

extension RequestCompatibilityProfile {
    /// Infers the request dialect for a model when the user has not pinned it.
    /// Platform gateways win over upstream model names because their request
    /// body is interpreted by the gateway, not by the upstream vendor.
    static func inferred(
        modelName: String,
        upstreamModelID: String,
        providerName: String = "",
        providerAddress: String = "",
        providerFormat: ProviderFormat = .openAICompatible
    ) -> Self {
        if providerFormat == .anthropic {
            return .anthropic
        }

        let providerText = normalizedInferenceText([providerName, providerAddress])
        if containsAny(providerText, ["openrouter"]) {
            return .openRouter
        }
        if containsAny(providerText, ["volcengine", "volc", "ark", "doubao", "火山", "方舟", "豆包"]) {
            return .volcengineArk
        }
        if containsAny(providerText, ["siliconflow", "siliconcloud", "silicon", "硅基流动"]) {
            return .siliconFlow
        }
        if containsAny(providerText, ["azure"]) {
            return .azureOpenAI
        }
        if !containsAny(providerText, ["openaicompatible", "通用openai"]),
           containsAny(providerText, ["openai", "chatgpt"]) {
            return .openAI
        }
        if containsAny(providerText, ["deepseek", "深度求索"]) {
            return .deepSeek
        }
        if containsAny(providerText, ["qwen", "dashscope", "bailian", "百炼", "通义"]) {
            return .qwen
        }
        if containsAny(providerText, ["kimi", "moonshot", "月之暗面"]) {
            return .kimi
        }
        if containsAny(providerText, ["z.ai", "zai", "zhipu", "chatglm", "bigmodel", "智谱"]) {
            return .zAI
        }
        if containsAny(providerText, ["mistral", "lechat"]) {
            return .mistral
        }
        if containsAny(providerText, ["xai", "grok"]) {
            return .xAI
        }

        let modelText = normalizedInferenceText([modelName, upstreamModelID])
        if containsAny(modelText, ["deepseek", "深度求索"]) {
            return .deepSeek
        }
        if containsAny(modelText, ["qwen", "通义"]) {
            return .qwen
        }
        if containsAny(modelText, ["kimi", "moonshot", "月之暗面"]) {
            return .kimi
        }
        if containsAny(modelText, ["glm", "zai", "zhipu", "chatglm", "智谱"]) {
            return .zAI
        }
        if containsAny(modelText, ["mistral", "codestral", "pixtral", "ministral"]) {
            return .mistral
        }
        if containsAny(modelText, ["grok", "xai"]) {
            return .xAI
        }
        if modelText.hasPrefix("gpt") || modelText.hasPrefix("openai") || modelText.hasPrefix("o1") || modelText.hasPrefix("o3") || modelText.hasPrefix("o4") {
            return .openAI
        }
        return .genericOpenAI
    }

    private static func normalizedInferenceText(_ values: [String]) -> String {
        values
            .joined(separator: " ")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func containsAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.contains(normalizedInferenceText([$0])) }
    }

    static let protectedStructuralKeys: Set<String> = ["model", "messages", "stream", "system"]
    static let reasoningControlKeys: Set<String> = [
        "reasoning_effort",
        "reasoning",
        "thinking",
        "enable_thinking",
        "thinking_budget",
        "preserve_thinking",
        "output_config",
        "thinking_strategy"
    ]

    func automaticReasoningParameters(for mode: ModelThinkingMode) -> [String: ModelJSONValue] {
        guard mode != .providerDefault else { return [:] }
        switch self {
        case .genericOpenAI, .openAI, .azureOpenAI, .mistral, .xAI:
            guard let effort = mode.openAIEffort else { return [:] }
            return ["reasoning_effort": .string(effort)]
        case .deepSeek:
            if mode == .disabled {
                return ["thinking": .object(["type": .string("disabled")])]
            }
            guard let effort = mode.openAIEffort else { return [:] }
            return [
                "thinking": .object(["type": .string("enabled")]),
                "reasoning_effort": .string(effort)
            ]
        case .qwen, .siliconFlow:
            if mode == .disabled {
                return ["enable_thinking": .bool(false)]
            }
            guard let budget = mode.budgetTokens else { return [:] }
            return [
                "enable_thinking": .bool(true),
                "thinking_budget": .number(Double(budget))
            ]
        case .kimi:
            guard let effort = mode.openAIEffort else { return [:] }
            return ["reasoning_effort": .string(effort)]
        case .zAI:
            if mode == .disabled {
                return ["thinking": .object(["type": .string("disabled")])]
            }
            guard let effort = mode.openAIEffort else { return [:] }
            return [
                "thinking": .object(["type": .string("enabled")]),
                "reasoning_effort": .string(effort)
            ]
        case .openRouter:
            if mode == .disabled {
                return ["reasoning": .object(["enabled": .bool(false)])]
            }
            guard let effort = mode.openAIEffort else { return [:] }
            return ["reasoning": .object(["enabled": .bool(true), "effort": .string(effort)])]
        case .volcengineArk:
            if mode == .disabled {
                return ["thinking": .object(["type": .string("disabled")])]
            }
            guard let effort = mode.arkEffort else { return [:] }
            return [
                "thinking": .object(["type": .string("enabled")]),
                "reasoning_effort": .string(effort)
            ]
        case .anthropic:
            if mode == .disabled {
                return ["thinking": .object(["type": .string("disabled")])]
            }
            let effort = mode == .minimal ? "low" : mode.openAIEffort
            guard let effort else { return [:] }
            return [
                "thinking": .object(["type": .string("adaptive")]),
                "output_config": .object(["effort": .string(effort)])
            ]
        }
    }
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
    var compatibilityProfile: RequestCompatibilityProfile
    var isCompatibilityProfileManuallySet: Bool
    var thinkingMode: ModelThinkingMode
    var extraRequestParameters: [String: ModelJSONValue]?

    init(
        id: UUID = UUID(),
        displayName: String,
        upstreamModelID: String,
        providerID: UUID,
        isStreamingEnabled: Bool,
        source: ModelConfigurationSource = .manual,
        compatibilityProfile: RequestCompatibilityProfile = .genericOpenAI,
        isCompatibilityProfileManuallySet: Bool? = nil,
        thinkingMode: ModelThinkingMode = .providerDefault,
        extraRequestParameters: [String: ModelJSONValue]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.upstreamModelID = upstreamModelID
        self.providerID = providerID
        self.isStreamingEnabled = isStreamingEnabled
        self.source = source
        self.compatibilityProfile = compatibilityProfile
        self.isCompatibilityProfileManuallySet = isCompatibilityProfileManuallySet ?? (compatibilityProfile != .genericOpenAI)
        self.thinkingMode = thinkingMode
        self.extraRequestParameters = extraRequestParameters
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case upstreamModelID
        case providerID
        case isStreamingEnabled
        case source
        case compatibilityProfile
        case isCompatibilityProfileManuallySet
        case thinkingMode
        case extraRequestParameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        upstreamModelID = try container.decode(String.self, forKey: .upstreamModelID)
        providerID = try container.decode(UUID.self, forKey: .providerID)
        isStreamingEnabled = try container.decode(Bool.self, forKey: .isStreamingEnabled)
        source = try container.decodeIfPresent(ModelConfigurationSource.self, forKey: .source) ?? .manual
        compatibilityProfile = try container.decodeIfPresent(RequestCompatibilityProfile.self, forKey: .compatibilityProfile) ?? .genericOpenAI
        isCompatibilityProfileManuallySet = try container.decodeIfPresent(Bool.self, forKey: .isCompatibilityProfileManuallySet) ?? false
        thinkingMode = try container.decodeIfPresent(ModelThinkingMode.self, forKey: .thinkingMode) ?? .providerDefault
        extraRequestParameters = try container.decodeIfPresent([String: ModelJSONValue].self, forKey: .extraRequestParameters)
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
