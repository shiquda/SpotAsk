import XCTest
@testable import SpotAsk

final class ChatErrorTests: XCTestCase {
    func testUnauthorizedMessageIncludesServerDetail() {
        let error = ChatError.unauthorized(message: "Invalid API key provided")

        XCTAssertEqual(error.detail, "Invalid API key provided")
        XCTAssertTrue(error.localizedDescription.contains("Invalid API key provided"))
    }

    func testRateLimitedMessageIncludesServerDetail() {
        let error = ChatError.rateLimited(message: "Quota exceeded")

        XCTAssertEqual(error.detail, "Quota exceeded")
        XCTAssertTrue(error.localizedDescription.contains("Quota exceeded"))
    }

    func testServerErrorMessageIncludesServerDetail() {
        let error = ChatError.serverError(status: 503, message: "Service unavailable")

        XCTAssertEqual(error.detail, "Service unavailable")
        XCTAssertTrue(error.localizedDescription.contains("Service unavailable"))
    }
}
