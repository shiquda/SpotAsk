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

    init(id: UUID = UUID(), role: ChatRole, content: String, createdAt: Date = .now, state: MessageState = .complete) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.state = state
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
        case .invalidConfiguration: "请检查服务设置。"
        case .invalidURL: "服务地址无效。"
        case .missingAPIKey: "请先保存访问密钥。"
        case .unauthorized: "访问密钥无效或服务未授权。"
        case .rateLimited: "请求过于频繁，请稍后重试。"
        case let .serverError(status, _): "服务器返回 \(status)。"
        case .invalidResponse: "服务器返回了无效响应。"
        case .decodingFailed: "服务返回内容异常，请稍后重试。"
        case .networkUnavailable: "网络连接不可用。"
        case .timeout: "请求超时。"
        case .cancelled: "请求已取消。"
        }
    }

    var detail: String? {
        if case let .serverError(_, message) = self { return message }
        return nil
    }
}
