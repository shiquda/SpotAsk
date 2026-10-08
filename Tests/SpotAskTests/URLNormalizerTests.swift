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

    func testGeminiAddressResolvesToTheModelCollectionRoot() throws {
        XCTAssertEqual(
            try URLNormalizer.endpoint(
                from: "https://generativelanguage.googleapis.com",
                useFullEndpoint: false,
                format: .gemini
            ).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models"
        )
        XCTAssertEqual(
            try URLNormalizer.endpoint(
                from: "https://generativelanguage.googleapis.com/v1beta",
                useFullEndpoint: false,
                format: .gemini
            ).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models"
        )
        XCTAssertEqual(
            try URLNormalizer.endpoint(
                from: "https://generativelanguage.googleapis.com/v1beta/models/",
                useFullEndpoint: false,
                format: .gemini
            ).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models"
        )
    }

    func testGeminiFullEndpointResolvesToTheModelCollectionRoot() throws {
        XCTAssertEqual(
            try URLNormalizer.endpoint(
                from: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
                useFullEndpoint: true,
                format: .gemini
            ).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models"
        )
        XCTAssertThrowsError(
            try URLNormalizer.endpoint(
                from: "https://generativelanguage.googleapis.com/other",
                useFullEndpoint: true,
                format: .gemini
            )
        ) { error in
            XCTAssertEqual(error as? ChatError, .invalidURL)
        }
    }

    func testGeminiModelsEndpointDropsTheModelPath() throws {
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(
                from: "https://generativelanguage.googleapis.com",
                format: .gemini
            ).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models"
        )
        XCTAssertEqual(
            try URLNormalizer.modelsEndpoint(
                from: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash",
                format: .gemini
            ).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models"
        )
    }

    func testRejectsMissingSchemeAndHost() throws {
        for rawValue in ["api.example.com/v1", "https:///v1", ""] {
            XCTAssertThrowsError(try URLNormalizer.endpoint(from: rawValue, useFullEndpoint: false))
        }
    }
}
