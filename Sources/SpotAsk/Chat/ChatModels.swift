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
    /// Model-supplied reasoning, kept separate from the answer sent in later requests.
    var reasoningContent: String?
    let createdAt: Date
    var state: MessageState
    /// Timestamp when model reasoning stopped updating, before the answer began.
    /// Kept separate from `completedAt` so the header can stop at the right point.
    var reasoningCompletedAt: Date?
    /// The user-facing model name selected when this answer was requested.
    var modelDisplayName: String?
    /// Kept so completed answers can show their actual request duration.
    var completedAt: Date?
    /// Provider name captured when the answer was requested. Used only for
    /// icon matching; older sessions decode it as nil.
    var providerName: String?
    let appliedPresetTitle: String?
    /// SF Symbol captured when the one-shot prompt was sent. Existing
    /// sessions without this field continue to use the stable fallback.
    let appliedPresetSymbolName: String?
    /// Context attached to a user question. Images keep binary data; documents
    /// and code are normalized to text. Not persisted to the session file.
    var attachments: [ChatAttachment]

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoningContent: String? = nil,
        createdAt: Date = .now,
        state: MessageState = .complete,
        reasoningCompletedAt: Date? = nil,
        modelDisplayName: String? = nil,
        completedAt: Date? = nil,
        attachments: [ChatAttachment] = [],
        appliedPresetTitle: String? = nil,
        appliedPresetSymbolName: String? = nil,
        providerName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.createdAt = createdAt
        self.state = state
        self.reasoningCompletedAt = reasoningCompletedAt
        self.modelDisplayName = modelDisplayName
        self.completedAt = completedAt
        self.attachments = attachments
        self.appliedPresetTitle = appliedPresetTitle
        self.appliedPresetSymbolName = appliedPresetSymbolName
        self.providerName = providerName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case reasoningContent
        case createdAt
        case state
        case reasoningCompletedAt
        case modelDisplayName
        case completedAt
        case providerName
        case appliedPresetTitle
        case appliedPresetSymbolName
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        state = try container.decodeIfPresent(MessageState.self, forKey: .state) ?? .complete
        reasoningCompletedAt = try container.decodeIfPresent(Date.self, forKey: .reasoningCompletedAt)
        modelDisplayName = try container.decodeIfPresent(String.self, forKey: .modelDisplayName)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        appliedPresetTitle = try container.decodeIfPresent(String.self, forKey: .appliedPresetTitle)
        appliedPresetSymbolName = try container.decodeIfPresent(String.self, forKey: .appliedPresetSymbolName)
        // Older session files have no attachments key; decode them as empty.
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
    }

    var appliedPresetIcon: String {
        appliedPresetSymbolName ?? "sparkles"
    }

    var responseDuration: TimeInterval? {
        guard let completedAt else { return nil }
        return max(0, completedAt.timeIntervalSince(createdAt))
    }

    var reasoningDuration: TimeInterval? {
        guard let reasoningCompletedAt else { return nil }
        return max(0, reasoningCompletedAt.timeIntervalSince(createdAt))
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
    case reasoningDelta(String)
    case answerDelta(String)
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
    case unauthorized(message: String?)
    case rateLimited(message: String?)
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
        case let .unauthorized(message): Self.message(L10n.string("error.unauthorized"), detail: message)
        case let .rateLimited(message): Self.message(L10n.string("error.rateLimited"), detail: message)
        case let .serverError(status, message): Self.message(L10n.string("error.serverError", status), detail: message)
        case .invalidResponse: L10n.string("error.invalidResponse")
        case .decodingFailed: L10n.string("error.decodingFailed")
        case .networkUnavailable: L10n.string("error.networkUnavailable")
        case .timeout: L10n.string("error.timeout")
        case .cancelled: L10n.string("error.cancelled")
        }
    }

    var detail: String? {
        switch self {
        case let .unauthorized(message), let .rateLimited(message), let .serverError(_, message):
            message
        default:
            nil
        }
    }

    private static func message(_ base: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return base }
        return "\(base)\n\(detail)"
    }
}
