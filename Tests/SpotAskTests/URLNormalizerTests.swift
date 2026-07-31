import Foundation
import XCTest
@testable import SpotAsk

final class URLNormalizerTests: XCTestCase {
    func testAppendsChatCompletionsToBaseURL() throws {
        let endpoint = try URLNormalizer.endpoint(
            from: "  https://api.example.com/v1/  ",
            useFullEndpoint: false
        )

        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testPreservesAnAlreadyCompleteEndpoint() throws {
        let endpoint = try URLNormalizer.endpoint(
            from: "https://api.example.com/v1/chat/completions/",
            useFullEndpoint: false
        )

        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testFullEndpointModeRequiresChatCompletionsPath() throws {
        XCTAssertThrowsError(
            try URLNormalizer.endpoint(from: "https://api.example.com/v1", useFullEndpoint: true)
        ) { error in
            XCTAssertEqual(error as? ChatError, .invalidURL)
        }
    }

    func testRejectsInsecureRemoteEndpoint() throws {
        XCTAssertThrowsError(
            try URLNormalizer.endpoint(from: "http://api.example.com/v1", useFullEndpoint: false)
        ) { error in
            XCTAssertEqual(error as? ChatError, .invalidURL)
        }
    }

    func testAllowsLocalHTTPForDevelopment() throws {
        let endpoint = try URLNormalizer.endpoint(
            from: "http://localhost:8080/v1",
            useFullEndpoint: false
        )

        XCTAssertEqual(endpoint.absoluteString, "http://localhost:8080/v1/chat/completions")
    }

    func testRejectsMissingSchemeAndHost() throws {
        for rawValue in ["api.example.com/v1", "https:///v1", ""] {
            XCTAssertThrowsError(try URLNormalizer.endpoint(from: rawValue, useFullEndpoint: false))
        }
    }
}
