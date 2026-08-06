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

    func testDerivesModelsEndpointWithoutDoubleSlashes() throws {
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(from: "https://api.example.com").absoluteString,
            "https://api.example.com/models"
        )
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(from: "https://api.example.com/v1/").absoluteString,
            "https://api.example.com/v1/models"
        )
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(from: "https://api.example.com/v1/chat/completions/").absoluteString,
            "https://api.example.com/v1/models"
        )
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

    func testAnthropicBaseURLBecomesMessagesEndpoint() throws {
        XCTAssertEqual(
            try URLNormalizer.endpoint(from: "https://api.anthropic.com", useFullEndpoint: false, format: .anthropic).absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            try URLNormalizer.endpoint(from: "https://api.anthropic.com/v1", useFullEndpoint: false, format: .anthropic).absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
    }

    func testAnthropicFullEndpointIsUsedAsIs() throws {
        XCTAssertEqual(
            try URLNormalizer.endpoint(
                from: "https://api.anthropic.com/v1/messages",
                useFullEndpoint: true,
                format: .anthropic
            ).absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
    }

    func testAnthropicModelsEndpointKeepsV1Prefix() throws {
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(from: "https://api.anthropic.com", format: .anthropic).absoluteString,
            "https://api.anthropic.com/v1/models"
        )
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(from: "https://api.anthropic.com/v1/", format: .anthropic).absoluteString,
            "https://api.anthropic.com/v1/models"
        )
    }

    func testRejectsMissingSchemeAndHost() throws {
        for rawValue in ["api.example.com/v1", "https:///v1", ""] {
            XCTAssertThrowsError(try URLNormalizer.endpoint(from: rawValue, useFullEndpoint: false))
        }
    }
}
