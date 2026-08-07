import XCTest
@testable import SpotAsk

final class ProviderBrandIconMatcherTests: XCTestCase {
    func testMatchesCommonModelNames() {
        XCTAssertEqual(ProviderBrandIconMatcher.match("gpt-5-mini"), "openai")
        XCTAssertEqual(ProviderBrandIconMatcher.match("claude-sonnet-4"), "claude-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("deepseek-chat"), "deepseek-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("kimi-latest"), "kimi-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("qwen-max"), "qwen-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("glm-4"), "zhipu-color")
    }

    func testMatchesProviderNamesAndAddresses() {
        XCTAssertEqual(
            ProviderBrandIconMatcher.match(
                providerName: "SiliconFlow",
                address: "https://api.siliconflow.cn/v1",
                modelName: "DeepSeek V3"
            ),
            "siliconcloud-color"
        )
        XCTAssertEqual(
            ProviderBrandIconMatcher.match(
                providerName: "Azure OpenAI",
                address: "https://example.openai.azure.com",
                modelName: "gpt-4o"
            ),
            "azure-color"
        )
        XCTAssertEqual(
            ProviderBrandIconMatcher.match(
                providerName: "Volcengine",
                address: "https://ark.cn-beijing.volces.com",
                modelName: "doubao-1-5-pro"
            ),
            "doubao-color"
        )
    }

    func testMatchesChineseProviderNames() {
        XCTAssertEqual(ProviderBrandIconMatcher.match("深度求索"), "deepseek-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("通义千问"), "qwen-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("智谱清言"), "zhipu-color")
        XCTAssertEqual(ProviderBrandIconMatcher.match("硅基流动"), "siliconcloud-color")
    }

    func testUnknownProviderFallsBackToNil() {
        XCTAssertNil(ProviderBrandIconMatcher.match("my-custom-service"))
        XCTAssertNil(ProviderBrandIconMatcher.match(""))
        XCTAssertNil(ProviderBrandIconMatcher.match("   "))
    }

    func testBundledLightAndDarkIconAssetsLoad() {
        XCTAssertNotNil(ProviderBrandIcon.image(for: "openai", dark: false))
        XCTAssertNotNil(ProviderBrandIcon.image(for: "openai", dark: true))
        XCTAssertNotNil(ProviderBrandIcon.image(for: "claude-color", dark: false))
        XCTAssertNotNil(ProviderBrandIcon.image(for: "claude-color", dark: true))
    }
}
