import Foundation
import XCTest
@testable import SpotAsk

final class ChatProviderSkeletonTests: XCTestCase {
    override func tearDown() {
        ProviderSkeletonStubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - ChatRequestBodyBuilder Tests

    func testFormatMessageEncodesRoleAndContent() throws {
        let message = try ChatRequestBodyBuilder.formatMessage(role: "user", content: "Hello world")
        guard case let .object(dict) = message else {
            XCTFail("Expected object")
            return
        }
        XCTAssertEqual(dict["role"], .string("user"))
        XCTAssertEqual(dict["content"], .string("Hello world"))
    }

    func testMergeParametersAppliesAutomaticReasoning() throws {
        var body: [String: ModelJSONValue] = ["model": .string("test-model")]
        let profile = RequestCompatibilityProfile.openAI
        try ChatRequestBodyBuilder.mergeParameters(
            into: &body,
            compatibilityProfile: profile,
            thinkingMode: .medium,
            extraParameters: nil
        )
        XCTAssertEqual(body["reasoning_effort"], .string("medium"))
    }

    func testMergeParametersReasoningControlKeysOverridesAutomatic() throws {
        var body: [String: ModelJSONValue] = ["model": .string("test-model")]
        let profile = RequestCompatibilityProfile.openAI
        let extras: [String: ModelJSONValue] = ["reasoning_effort": .string("high")]
        try ChatRequestBodyBuilder.mergeParameters(
            into: &body,
            compatibilityProfile: profile,
            thinkingMode: .low,
            extraParameters: extras
        )
        XCTAssertEqual(body["reasoning_effort"], .string("high"))
    }

    func testMergeParametersRejectsProtectedStructuralKeys() throws {
        var body: [String: ModelJSONValue] = ["model": .string("test-model")]
        let profile = RequestCompatibilityProfile.openAI
        let extras: [String: ModelJSONValue] = ["messages": .array([])]
        XCTAssertThrowsError(
            try ChatRequestBodyBuilder.mergeParameters(
                into: &body,
                compatibilityProfile: profile,
                thinkingMode: .providerDefault,
                extraParameters: extras
            )
        ) { error in
            XCTAssertEqual(error as? ChatError, .invalidConfiguration)
        }
    }

    // MARK: - ChatStreamingDriver Tests

    func testChatStreamingDriverNonStreamingYieldsEventsAndCompletes() async throws {
        ProviderSkeletonStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"text":"Hello from non-streaming"}"#.utf8)
            return (response, body)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderSkeletonStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let transport = HTTPChatTransport(urlSession: session)

        let stream = ChatStreamingDriver.nonStreaming(
            transport: transport,
            makeRequest: { URLRequest(url: URL(string: "https://example.com/api")!) },
            decode: { data in
                let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
                return [.answerDelta(json?["text"] ?? "")]
            }
        )

        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        XCTAssertEqual(events, [.answerDelta("Hello from non-streaming"), .completed])
    }

    func testChatStreamingDriverNonStreamingMapsHttpError() async throws {
        ProviderSkeletonStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = Data(#"{"error":{"message":"Unauthorized key"}}"#.utf8)
            return (response, body)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderSkeletonStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let transport = HTTPChatTransport(urlSession: session)

        let stream = ChatStreamingDriver.nonStreaming(
            transport: transport,
            makeRequest: { URLRequest(url: URL(string: "https://example.com/api")!) },
            decode: { _ in [] }
        )

        do {
            for try await _ in stream {
                XCTFail("Should not yield any event on 401")
            }
            XCTFail("Stream should throw")
        } catch {
            XCTAssertEqual(error as? ChatError, .unauthorized(message: "Unauthorized key"))
        }
    }

    func testChatStreamingDriverTestConnectionSuccessAndFailure() async throws {
        ProviderSkeletonStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderSkeletonStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let transport = HTTPChatTransport(urlSession: session)

        // Success test
        try await ChatStreamingDriver.testConnection(transport: transport) {
            URLRequest(url: URL(string: "https://example.com/api")!)
        }

        // Failure test
        ProviderSkeletonStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":{"message":"Forbidden"}}"#.utf8))
        }

        do {
            try await ChatStreamingDriver.testConnection(transport: transport) {
                URLRequest(url: URL(string: "https://example.com/api")!)
            }
            XCTFail("Expected 403 error")
        } catch {
            XCTAssertEqual(error as? ChatError, .unauthorized(message: "Forbidden"))
        }
    }
}

private final class ProviderSkeletonStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
