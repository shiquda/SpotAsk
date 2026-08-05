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
