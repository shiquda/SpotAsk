import Foundation

enum ChatRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

enum MessageState: String, Codable, Equatable, Sendable {
    case complete
    case streaming
    case cancelled
    case failed
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let createdAt: Date
    var state: MessageState
    let appliedPresetTitle: String?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = .now,
        state: MessageState = .complete,
        appliedPresetTitle: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.state = state
        self.appliedPresetTitle = appliedPresetTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case state
        case appliedPresetTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        state = try container.decode(MessageState.self, forKey: .state)
        appliedPresetTitle = try container.decodeIfPresent(String.self, forKey: .appliedPresetTitle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(appliedPresetTitle, forKey: .appliedPresetTitle)
    }
}

struct ChatRequest: Sendable, Equatable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool

    init(model: String, messages: [ChatMessage], stream: Bool = true) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

struct InputOutputUsage: Equatable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
}

enum ChatStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case completed
    case usage(InputOutputUsage)
}

enum GenerationState: Equatable, Sendable {
    case idle
    case connecting
    case streaming
    case cancelled
    case failed
}

enum ChatError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case invalidURL
    case missingAPIKey
    case unauthorized
    case rateLimited
    case serverError(status: Int, message: String?)
    case invalidResponse
    case decodingFailed
    case networkUnavailable
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: L10n.string("error.invalidConfiguration")
        case .invalidURL: L10n.string("error.invalidURL")
        case .missingAPIKey: L10n.string("error.missingAPIKey")
        case .unauthorized: L10n.string("error.unauthorized")
        case .rateLimited: L10n.string("error.rateLimited")
        case let .serverError(status, _): L10n.string("error.serverError", status)
        case .invalidResponse: L10n.string("error.invalidResponse")
        case .decodingFailed: L10n.string("error.decodingFailed")
        case .networkUnavailable: L10n.string("error.networkUnavailable")
        case .timeout: L10n.string("error.timeout")
        case .cancelled: L10n.string("error.cancelled")
        }
    }

    var detail: String? {
        if case let .serverError(_, message) = self { return message }
        return nil
    }
}
