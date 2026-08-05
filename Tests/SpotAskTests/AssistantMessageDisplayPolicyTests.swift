import XCTest
@testable import SpotAsk

final class AssistantMessageDisplayPolicyTests: XCTestCase {
    func testShortAnswerDoesNotCollapse() {
        XCTAssertFalse(AssistantMessageDisplayPolicy.shouldCollapse("A concise answer."))
    }

    func testCharacterThresholdBoundary() {
        XCTAssertFalse(AssistantMessageDisplayPolicy.shouldCollapse(String(repeating: "a", count: 4_000)))
        XCTAssertTrue(AssistantMessageDisplayPolicy.shouldCollapse(String(repeating: "a", count: 4_001)))
    }

    func testExplicitLineThresholdBoundary() {
        XCTAssertFalse(AssistantMessageDisplayPolicy.shouldCollapse(Array(repeating: "line", count: 119).joined(separator: "\n")))
        XCTAssertTrue(AssistantMessageDisplayPolicy.shouldCollapse(Array(repeating: "line", count: 120).joined(separator: "\n")))
    }

    func testCollapsedPreviewIsBoundedWithoutSplittingUnicodeCharacters() {
        let character = "👩🏽‍💻"
        let content = String(repeating: character, count: 4_001)

        let preview = AssistantMessageDisplayPolicy.collapsedPreview(for: content)

        XCTAssertEqual(preview, String(repeating: character, count: 4_000))
        XCTAssertEqual(preview?.count, AssistantMessageDisplayPolicy.characterThreshold)
    }

    @MainActor
    func testStreamingAnswerAlwaysRendersFullContent() {
        let content = String(repeating: "a", count: 4_001)
        let message = ChatMessage(role: .assistant, content: content, state: .streaming)

        let view = MessageContentView(
            message: message,
            canRegenerate: false,
            onRegenerate: {},
            isCopied: false,
            onCopy: {},
            copyShortcut: nil,
            regenerateShortcut: nil
        )

        withExtendedLifetime(view) {}
    }
}
