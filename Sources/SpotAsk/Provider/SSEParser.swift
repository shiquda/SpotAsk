import Foundation

/// Incremental SSE parser. Data is decoded only after a complete line arrives.
struct SSEParser: Sendable {
    private var pendingBytes = Data()

    mutating func feed(_ bytes: Data) throws -> [ChatStreamEvent] {
        pendingBytes.append(bytes)
        var events: [ChatStreamEvent] = []

        while let newline = pendingBytes.firstIndex(of: 0x0A) {
            var lineData = pendingBytes.prefix(upTo: newline)
            pendingBytes.removeSubrange(...newline)
            if lineData.last == 0x0D { lineData.removeLast() }
            guard !lineData.isEmpty else { continue }
            guard let line = String(data: lineData, encoding: .utf8) else { throw ChatError.decodingFailed }
            if line.hasPrefix(":") { continue }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty else { continue }
            if payload == "[DONE]" {
                events.append(.completed)
                continue
            }
            events.append(contentsOf: try parsePayload(String(payload)))
        }
        return events
    }

    mutating func finish() throws -> [ChatStreamEvent] {
        guard !pendingBytes.isEmpty else { return [] }
        pendingBytes.append(0x0A)
        return try feed(Data())
    }

    private func parsePayload(_ payload: String) throws -> [ChatStreamEvent] {
        guard let data = payload.data(using: .utf8) else { throw ChatError.decodingFailed }
        let response: StreamResponse
        do {
            response = try JSONDecoder().decode(StreamResponse.self, from: data)
        } catch {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw apiError.asChatError
            }
            throw ChatError.decodingFailed
        }
        var events: [ChatStreamEvent] = []
        if let content = response.choices.first?.delta.content, !content.isEmpty { events.append(.textDelta(content)) }
        if let usage = response.usage { events.append(.usage(.init(inputTokens: usage.promptTokens, outputTokens: usage.completionTokens))) }
        return events
    }
}

private struct StreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens" }
    }
    let choices: [Choice]
    let usage: Usage?
}

struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail?

    var asChatError: ChatError { .serverError(status: 0, message: error?.message) }
}
