import Foundation
import XCTest
@testable import SpotAsk

final class GeminiProviderTests: XCTestCase {
    override func tearDown() {
        GeminiURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testStreamingUsesNativeEndpointHeadersAndPayload() async throws {
        var capturedRequest: URLRequest?
        GeminiURLProtocolStub.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = Data("""
            data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]},"index":0}]}
            data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":2}}

            """.utf8)
            return (response, body)
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "gemini-key",
                model: "gemini-2.5-flash",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        var events: [ChatStreamEvent] = []
        for try await event in provider.stream(
            request: ChatRequest(
                model: "gemini-2.5-flash",
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

        XCTAssertEqual(
            events,
            [
                .answerDelta("Hello"),
                .answerDelta(" world"),
                .usage(.init(inputTokens: 7, outputTokens: 2)),
                .completed
            ]
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let json = try XCTUnwrap(bodyJSON(request))
        XCTAssertEqual(json["model"] as? String, nil)
        let systemInstruction = try XCTUnwrap(json["systemInstruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
        XCTAssertEqual(systemParts.count, 1)
        XCTAssertEqual(systemParts[0]["text"] as? String, "You are helpful.")
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 2)
        XCTAssertEqual(contents[0]["role"] as? String, "user")
        XCTAssertEqual(contents[0]["parts"] as? [[String: String]], [["text": "Hi"]])
        XCTAssertEqual(contents[1]["role"] as? String, "model")
        XCTAssertEqual(contents[1]["parts"] as? [[String: String]], [["text": "Hello"]])
    }

    func testNonStreamingUsesGenerateContentEndpoint() async throws {
        var capturedRequest: URLRequest?
        GeminiURLProtocolStub.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Data(#"{"candidates":[{"content":{"parts":[{"text":"answer"}]},"finishReason":"STOP"}]}"#.utf8)
            return (response, body)
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        var events: [ChatStreamEvent] = []
        for try await event in provider.stream(
            request: ChatRequest(model: "gemini-2.5-flash", messages: [ChatMessage(role: .user, content: "Hi")], stream: false)
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [.answerDelta("answer"), .completed])
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testThinkingPartsBecomeReasoningDeltas() async throws {
        GeminiURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = Data("""
            data: {"candidates":[{"content":{"parts":[{"text":"weighing","thought":true}]}}]}
            data: {"candidates":[{"content":{"parts":[{"text":"final"}],"role":"model"},"finishReason":"STOP"}]}

            """.utf8)
            return (response, body)
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        var events: [ChatStreamEvent] = []
        for try await event in provider.stream(
            request: ChatRequest(model: "gemini-2.5-flash", messages: [ChatMessage(role: .user, content: "Hi")], stream: true)
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [.reasoningDelta("weighing"), .answerDelta("final"), .completed])
    }

    func testStreamErrorPayloadSurfacesServerMessage() async throws {
        GeminiURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = Data(#"data: {"error":{"code":400,"message":"API key not valid","status":"INVALID_ARGUMENT"}}"#.utf8 + Data("\n\n".utf8))
            return (response, body)
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        do {
            for try await _ in provider.stream(
                request: ChatRequest(model: "gemini-2.5-flash", messages: [ChatMessage(role: .user, content: "Hi")], stream: true)
            ) {}
            XCTFail("Expected the stream to fail")
        } catch {
            XCTAssertEqual(
                error as? ChatError,
                .serverError(status: 400, message: "API key not valid")
            )
        }
    }

    func testBlockedPromptFeedbackFailsInsteadOfReturningAnEmptyAnswer() async throws {
        GeminiURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = Data(#"data: {"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8 + Data("\n\n".utf8))
            return (response, body)
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
                timeout: 30
            ),
            urlSession: makeSession()
        )

        do {
            for try await _ in provider.stream(
                request: ChatRequest(model: "gemini-2.5-flash", messages: [ChatMessage(role: .user, content: "Hi")], stream: true)
            ) {}
            XCTFail("Expected blocked prompt to fail")
        } catch {
            XCTAssertEqual(error as? ChatError, .serverError(status: 0, message: "SAFETY"))
        }
    }

    func testImageAttachmentBecomesInlineDataPart() async throws {
        var capturedRequest: URLRequest?
        GeminiURLProtocolStub.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n".utf8))
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
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
                model: "gemini-2.5-flash",
                messages: [ChatMessage(role: .user, content: "what is this?", attachments: [attachment])],
                stream: true
            )
        ) {}

        let json = try XCTUnwrap(bodyJSON(try XCTUnwrap(capturedRequest)))
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        let inlineData = try XCTUnwrap(parts[0]["inlineData"] as? [String: String])
        XCTAssertEqual(inlineData["mimeType"], "image/png")
        XCTAssertEqual(inlineData["data"], imageData.base64EncodedString())
        XCTAssertEqual(parts[1]["text"] as? String, "what is this?")
    }

    func testGeminiProfileAddsNoAutomaticReasoningAndKeepsCustomParameters() async throws {
        var capturedRequest: URLRequest?
        GeminiURLProtocolStub.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n".utf8))
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
                timeout: 30,
                compatibilityProfile: .gemini,
                thinkingMode: .high,
                extraRequestParameters: [
                    "generationConfig": .object(["thinkingConfig": .object(["thinkingBudget": .number(0)])])
                ]
            ),
            urlSession: makeSession()
        )

        for try await _ in provider.stream(
            request: ChatRequest(model: "gemini-2.5-flash", messages: [ChatMessage(role: .user, content: "Hi")], stream: true)
        ) {}

        let json = try XCTUnwrap(bodyJSON(try XCTUnwrap(capturedRequest)))
        XCTAssertNil(json["reasoning_effort"])
        XCTAssertNil(json["thinking"])
        let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingBudget"] as? Int, 0)
    }

    func testStructuralCustomParameterIsRejected() async throws {
        GeminiURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n".utf8))
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "key",
                model: "gemini-2.5-flash",
                timeout: 30,
                extraRequestParameters: ["contents": .array([])]
            ),
            urlSession: makeSession()
        )

        do {
            for try await _ in provider.stream(
                request: ChatRequest(model: "gemini-2.5-flash", messages: [ChatMessage(role: .user, content: "Hi")], stream: true)
            ) {}
            XCTFail("Expected a protected structural key to be rejected")
        } catch {
            XCTAssertEqual(error as? ChatError, .invalidConfiguration)
        }
    }

    func testTestConnectionKeepsServerErrorDetail() async throws {
        GeminiURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            let body = Data(#"{"error":{"code":401,"message":"API key not valid. Please pass a valid API key."}}"#.utf8)
            return (response, body)
        }
        let provider = GeminiProvider(
            configuration: .init(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                apiKey: "bad-key",
                model: "gemini-2.5-flash",
                timeout: 5
            ),
            urlSession: makeSession()
        )

        do {
            try await provider.testConnection()
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(
                error as? ChatError,
                .unauthorized(message: "API key not valid. Please pass a valid API key.")
            )
        }
    }

    func testModelIdentifierAcceptsPastedResourceNames() {
        XCTAssertEqual(GeminiProvider.modelIdentifier(from: "gemini-2.5-flash"), "gemini-2.5-flash")
        XCTAssertEqual(GeminiProvider.modelIdentifier(from: " models/gemini-2.5-pro "), "gemini-2.5-pro")
        XCTAssertEqual(
            GeminiProvider.modelIdentifier(from: "models/gemini-2.5-flash:generateContent"),
            "gemini-2.5-flash"
        )
        XCTAssertEqual(GeminiProvider.modelIdentifier(from: "   "), "")
    }

    func testActionURLRejectsAnEmptyModel() {
        XCTAssertThrowsError(
            try GeminiProvider.actionURL(
                root: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                model: "  ",
                stream: false
            )
        ) { error in
            XCTAssertEqual(error as? ChatError, .invalidConfiguration)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiURLProtocolStub.self]
        return URLSession(configuration: configuration)
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

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any]? {
        let data = try XCTUnwrap(bodyData(of: request))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private final class GeminiURLProtocolStub: URLProtocol {
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
