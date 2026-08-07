import Foundation
import XCTest
@testable import SpotAsk

final class OpenAICompatibleProviderTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testUnauthorizedResponseKeepsServerDetail() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = Data(#"{"error":{"message":"Invalid API key provided"}}"#.utf8)
            return (response, body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let provider = OpenAICompatibleProvider(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "bad-key",
                model: "model",
                timeout: 5
            ),
            urlSession: session
        )

        do {
            try await provider.testConnection()
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? ChatError, .unauthorized(message: "Invalid API key provided"))
        }
    }

    func testTextOnlyRequestKeepsStringContent() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: [DONE]\n\n".utf8))
        }
        let provider = OpenAICompatibleProvider(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "key",
                model: "model",
                timeout: 5
            ),
            urlSession: makeSession()
        )

        for try await _ in provider.stream(
            request: ChatRequest(model: "model", messages: [ChatMessage(role: .user, content: "hello")], stream: true)
        ) {}

        let request = try XCTUnwrap(capturedRequest)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(bodyData(of: request))) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, "hello")
    }

    func testImageAttachmentBecomesContentArray() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: [DONE]\n\n".utf8))
        }
        let provider = OpenAICompatibleProvider(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "key",
                model: "model",
                timeout: 5
            ),
            urlSession: makeSession()
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let attachment = ChatAttachment(
            filename: "shot.png",
            mimeType: "image/png",
            byteCount: 4,
            payload: .image(data: imageData)
        )

        for try await _ in provider.stream(
            request: ChatRequest(
                model: "model",
                messages: [ChatMessage(role: .user, content: "what is this?", attachments: [attachment])],
                stream: true
            )
        ) {}

        let request = try XCTUnwrap(capturedRequest)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(bodyData(of: request))) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        let imagePart = content[0]
        XCTAssertEqual(imagePart["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,\(imageData.base64EncodedString())")

        let textPart = content[1]
        XCTAssertEqual(textPart["type"] as? String, "text")
        XCTAssertEqual(textPart["text"] as? String, "what is this?")
    }

    func testTextAttachmentSendsExtractedText() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: [DONE]\n\n".utf8))
        }
        let provider = OpenAICompatibleProvider(
            configuration: .init(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                apiKey: "key",
                model: "model",
                timeout: 5
            ),
            urlSession: makeSession()
        )
        let attachment = ChatAttachment(
            filename: "notes.md",
            mimeType: "text/plain",
            byteCount: 11,
            payload: .text(text: "# Notes\nbody", originalKind: .text)
        )

        for try await _ in provider.stream(
            request: ChatRequest(
                model: "model",
                messages: [ChatMessage(role: .user, content: "summarize", attachments: [attachment])],
                stream: true
            )
        ) {}

        let request = try XCTUnwrap(capturedRequest)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(bodyData(of: request))) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        let textPart = content[0]
        XCTAssertEqual(textPart["type"] as? String, "text")
        let sent = try XCTUnwrap(textPart["text"] as? String)
        XCTAssertTrue(sent.contains("notes.md"))
        XCTAssertTrue(sent.contains("# Notes\nbody"))
        XCTAssertFalse(sent.contains("\\("))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return session
    }

    private func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class AnthropicProviderTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testStreamingUsesMessagesAPIHeadersAndPayload() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = Data("data: {\"type\":\"message_stop\"}\n\n".utf8)
            return (response, body)
        }
        let provider = AnthropicProvider(
            configuration: .init(
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKey: "anthropic-key",
                model: "claude-3-5-sonnet",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        var events: [ChatStreamEvent] = []
        for try await event in provider.stream(
            request: ChatRequest(
                model: "claude-3-5-sonnet",
                messages: [
                    ChatMessage(role: .system, content: "You are helpful."),
                    ChatMessage(role: .user, content: "Hi"),
                    ChatMessage(role: .assistant, content: "Hello")
                ],
                stream: true
            )
        ) {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.completed))
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(bodyData(of: request))) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "claude-3-5-sonnet")
        XCTAssertEqual(body?["max_tokens"] as? Int, 8192)
        XCTAssertEqual(body?["system"] as? String, "You are helpful.")
        XCTAssertEqual(body?["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body?["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "Hi"], ["role": "assistant", "content": "Hello"]])
    }

    func testTextAttachmentBecomesContentBlocks() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: {\"type\":\"message_stop\"}\n\n".utf8))
        }
        let provider = AnthropicProvider(
            configuration: .init(
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKey: "key",
                model: "claude",
                timeout: 30
            ),
            urlSession: makeSession()
        )
        let attachment = ChatAttachment(
            filename: "notes.md",
            mimeType: "text/plain",
            byteCount: 11,
            payload: .text(text: "# Notes\nbody", originalKind: .text)
        )

        for try await _ in provider.stream(
            request: ChatRequest(
                model: "claude",
                messages: [ChatMessage(role: .user, content: "summarize", attachments: [attachment])],
                stream: true
            )
        ) {}

        let request = try XCTUnwrap(capturedRequest)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(bodyData(of: request))) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        let textBlock = content[0]
        XCTAssertEqual(textBlock["type"] as? String, "text")
        let sent = try XCTUnwrap(textBlock["text"] as? String)
        XCTAssertTrue(sent.contains("notes.md"))
        XCTAssertTrue(sent.contains("# Notes\nbody"))
        XCTAssertFalse(sent.contains("\\("))
    }

    func testStreamingYieldsThinkingAndAnswerDeltas() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = Data("""
            data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"first"}}
            data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" second"}}
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}
            data: {"type":"message_stop"}

            """.utf8)
            return (response, body)
        }
        let provider = AnthropicProvider(
            configuration: .init(
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKey: "key",
                model: "claude",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        var events: [ChatStreamEvent] = []
        for try await event in provider.stream(
            request: ChatRequest(model: "claude", messages: [ChatMessage(role: .user, content: "Hi")], stream: true)
        ) {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.reasoningDelta("first")))
        XCTAssertTrue(events.contains(.reasoningDelta(" second")))
        XCTAssertTrue(events.contains(.answerDelta("Hello")))
        XCTAssertTrue(events.contains(.usage(.init(inputTokens: nil, outputTokens: 12))))
        XCTAssertTrue(events.contains(.completed))
    }

    func testNonStreamingResponseYieldsThinkingThenAnswer() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Data(#"{"content":[{"type":"thinking","thinking":"chain"},{"type":"text","text":"answer"}]}"#.utf8)
            return (response, body)
        }
        let provider = AnthropicProvider(
            configuration: .init(
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKey: "key",
                model: "claude",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        var events: [ChatStreamEvent] = []
        for try await event in provider.stream(
            request: ChatRequest(model: "claude", messages: [ChatMessage(role: .user, content: "Hi")], stream: false)
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [.reasoningDelta("chain"), .answerDelta("answer"), .completed])
    }

    func testUnauthorizedResponseKeepsServerDetail() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            let body = Data(#"{"error":{"message":"Invalid API key provided"}}"#.utf8)
            return (response, body)
        }
        let provider = AnthropicProvider(
            configuration: .init(
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKey: "bad-key",
                model: "claude",
                timeout: 5
            ),
            urlSession: makeSession()
        )

        do {
            try await provider.testConnection()
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? ChatError, .unauthorized(message: "Invalid API key provided"))
        }
    }

    func testImageAttachmentBecomesBase64ImageSource() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: {\"type\":\"message_stop\"}\n\n".utf8))
        }
        let provider = AnthropicProvider(
            configuration: .init(
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                apiKey: "key",
                model: "claude",
                timeout: 30
            ),
            urlSession: makeSession()
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let attachment = ChatAttachment(
            filename: "shot.png",
            mimeType: "image/png",
            byteCount: 4,
            payload: .image(data: imageData)
        )

        for try await _ in provider.stream(
            request: ChatRequest(
                model: "claude",
                messages: [ChatMessage(role: .user, content: "what is this?", attachments: [attachment])],
                stream: true
            )
        ) {}

        let request = try XCTUnwrap(capturedRequest)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(bodyData(of: request))) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        let imageBlock = content[0]
        XCTAssertEqual(imageBlock["type"] as? String, "image")
        let source = try XCTUnwrap(imageBlock["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())

        let textBlock = content[1]
        XCTAssertEqual(textBlock["type"] as? String, "text")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return session
    }

    private func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
