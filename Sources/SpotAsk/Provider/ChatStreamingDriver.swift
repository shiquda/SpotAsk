import Foundation

private final class ChatStreamingOperations: @unchecked Sendable {
    let makeRequest: () throws -> URLRequest
    let decodeNonStreaming: (Data) throws -> [ChatStreamEvent]
    let decodePayload: (String) throws -> [ChatStreamEvent]
    let mapUnexpectedError: (Error) -> Error

    init(
        makeRequest: @escaping () throws -> URLRequest,
        decodeNonStreaming: @escaping (Data) throws -> [ChatStreamEvent],
        decodePayload: @escaping (String) throws -> [ChatStreamEvent],
        mapUnexpectedError: @escaping (Error) -> Error
    ) {
        self.makeRequest = makeRequest
        self.decodeNonStreaming = decodeNonStreaming
        self.decodePayload = decodePayload
        self.mapUnexpectedError = mapUnexpectedError
    }
}

enum ChatStreamingDriver {
    static func stream(
        transport: HTTPChatTransport,
        makeRequest: @escaping () throws -> URLRequest,
        decodeNonStreaming: @escaping (Data) throws -> [ChatStreamEvent],
        decodePayload: @escaping (String) throws -> [ChatStreamEvent],
        mapUnexpectedError: @escaping (Error) -> Error
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let operations = ChatStreamingOperations(
            makeRequest: makeRequest,
            decodeNonStreaming: decodeNonStreaming,
            decodePayload: decodePayload,
            mapUnexpectedError: mapUnexpectedError
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try operations.makeRequest()
                    let (bytes, response) = try await transport.streamingResponse(for: request)
                    guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
                        let data = try await ChatHTTP.collect(bytes)
                        for event in try operations.decodeNonStreaming(data) {
                            continuation.yield(event)
                        }
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    var parser = SSEPayloadParser()
                    var receivedCompletion = false
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for payload in try parser.feed(Data([byte])) {
                            let events = payload == "[DONE]" ? [ChatStreamEvent.completed] : try operations.decodePayload(payload)
                            for event in events {
                                if case .completed = event { receivedCompletion = true }
                                continuation.yield(event)
                            }
                        }
                    }
                    for payload in try parser.finish() {
                        let events = payload == "[DONE]" ? [ChatStreamEvent.completed] : try operations.decodePayload(payload)
                        for event in events {
                            if case .completed = event { receivedCompletion = true }
                            continuation.yield(event)
                        }
                    }
                    if !receivedCompletion { continuation.yield(.completed) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatError.cancelled)
                } catch let error as ChatError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: ChatHTTP.mapURLError(error))
                } catch {
                    continuation.finish(throwing: operations.mapUnexpectedError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct SSEPayloadParser: Sendable {
    private var pendingBytes = Data()

    mutating func feed(_ bytes: Data) throws -> [String] {
        pendingBytes.append(bytes)
        var payloads: [String] = []
        while let newline = pendingBytes.firstIndex(of: 0x0A) {
            var lineData = pendingBytes.prefix(upTo: newline)
            pendingBytes.removeSubrange(...newline)
            if lineData.last == 0x0D { lineData.removeLast() }
            guard !lineData.isEmpty else { continue }
            guard let line = String(data: lineData, encoding: .utf8) else { throw ChatError.decodingFailed }
            if line.hasPrefix(":") { continue }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if !payload.isEmpty { payloads.append(String(payload)) }
        }
        return payloads
    }

    mutating func finish() throws -> [String] {
        guard !pendingBytes.isEmpty else { return [] }
        pendingBytes.append(0x0A)
        return try feed(Data())
    }
}
