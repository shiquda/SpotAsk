import Foundation
import XCTest
@testable import SpotAsk

final class RequestCompatibilityMappingTests: XCTestCase {
    func testProviderDefaultEmitsNoReasoningFields() {
        for profile in RequestCompatibilityProfile.allCases {
            XCTAssertEqual(
                profile.automaticReasoningParameters(for: .providerDefault),
                [:],
                "\(profile) should keep provider-default behavior unchanged"
            )
        }
    }

    func testOpenAIFamilyMapsEffort() {
        XCTAssertEqual(
            RequestCompatibilityProfile.openAI.automaticReasoningParameters(for: .high),
            ["reasoning_effort": .string("high")]
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.openAI.automaticReasoningParameters(for: .disabled),
            ["reasoning_effort": .string("none")]
        )
    }

    func testDeepSeekMapsThinkingAndEffort() {
        XCTAssertEqual(
            RequestCompatibilityProfile.deepSeek.automaticReasoningParameters(for: .disabled),
            ["thinking": .object(["type": .string("disabled")])]
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.deepSeek.automaticReasoningParameters(for: .high),
            [
                "thinking": .object(["type": .string("enabled")]),
                "reasoning_effort": .string("high")
            ]
        )
    }

    func testInferenceUsesPlatformBeforeUpstreamModelName() {
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(
                modelName: "DeepSeek R1",
                upstreamModelID: "deepseek/deepseek-r1",
                providerName: "OpenRouter",
                providerAddress: "https://openrouter.ai/api/v1"
            ),
            .openRouter
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(
                modelName: "DeepSeek V3",
                upstreamModelID: "deepseek-v3",
                providerName: "火山方舟",
                providerAddress: "https://ark.cn-beijing.volces.com/api/v3"
            ),
            .volcengineArk
        )
    }

    func testInferenceRecognizesCommonModelNames() {
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "DeepSeek V3", upstreamModelID: "deepseek-chat"),
            .deepSeek
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "Qwen3", upstreamModelID: "qwen3-235b"),
            .qwen
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "Kimi K2", upstreamModelID: "moonshot-v1"),
            .kimi
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "GLM-4", upstreamModelID: "glm-4.5"),
            .zAI
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "Codestral", upstreamModelID: "codestral-latest"),
            .mistral
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "Grok", upstreamModelID: "grok-4"),
            .xAI
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "GPT", upstreamModelID: "gpt-5"),
            .openAI
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.inferred(modelName: "Custom", upstreamModelID: "my-model"),
            .genericOpenAI
        )
    }

    func testQwenAndSiliconFlowMapBudget() {
        let expected: [String: ModelJSONValue] = [
            "enable_thinking": .bool(true),
            "thinking_budget": .number(4_096)
        ]
        XCTAssertEqual(RequestCompatibilityProfile.qwen.automaticReasoningParameters(for: .medium), expected)
        XCTAssertEqual(RequestCompatibilityProfile.siliconFlow.automaticReasoningParameters(for: .medium), expected)
        XCTAssertEqual(
            RequestCompatibilityProfile.siliconFlow.automaticReasoningParameters(for: .disabled),
            ["enable_thinking": .bool(false)]
        )
    }

    func testOpenRouterMapsUnifiedReasoningObject() {
        XCTAssertEqual(
            RequestCompatibilityProfile.openRouter.automaticReasoningParameters(for: .low),
            ["reasoning": .object(["enabled": .bool(true), "effort": .string("low")])]
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.openRouter.automaticReasoningParameters(for: .disabled),
            ["reasoning": .object(["enabled": .bool(false)])]
        )
    }

    func testArkMapsThinkingAndEffort() {
        XCTAssertEqual(
            RequestCompatibilityProfile.volcengineArk.automaticReasoningParameters(for: .medium),
            [
                "thinking": .object(["type": .string("enabled")]),
                "reasoning_effort": .string("medium")
            ]
        )
    }

    func testAnthropicMapsAdaptiveEffortAndDisabled() {
        XCTAssertEqual(
            RequestCompatibilityProfile.anthropic.automaticReasoningParameters(for: .high),
            [
                "thinking": .object(["type": .string("adaptive")]),
                "output_config": .object(["effort": .string("high")])
            ]
        )
        XCTAssertEqual(
            RequestCompatibilityProfile.anthropic.automaticReasoningParameters(for: .disabled),
            ["thinking": .object(["type": .string("disabled")])]
        )
    }

    func testJSONValuesRoundTripAndDeepMerge() throws {
        let value: ModelJSONValue = .object([
            "temperature": .number(0.7),
            "nested": .object(["enabled": .bool(true)])
        ])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ModelJSONValue.self, from: data), value)

        var merged: [String: ModelJSONValue] = [
            "nested": .object(["enabled": .bool(true), "budget": .number(1)])
        ]
        merged.mergeModelJSON([
            "nested": .object(["budget": .number(2), "extra": .string("kept")])
        ])
        XCTAssertEqual(
            merged["nested"],
            .object([
                "enabled": .bool(true),
                "budget": .number(2),
                "extra": .string("kept")
            ])
        )
    }
}
