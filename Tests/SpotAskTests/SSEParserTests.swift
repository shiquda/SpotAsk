import Foundation
import XCTest
@testable import SpotAsk

final class SSEParserTests: XCTestCase {
    func testParsesFragmentedTextEventOnlyAfterNewline() throws {
        var parser = SSEParser()

        XCTAssertEqual(try parser.feed(Data("data: {\"choices\":[{\"delta\":{\"content\":\"Hel".utf8)), [])
        XCTAssertEqual(
            try parser.feed(Data("lo\"}}]}\n".utf8)),
            [.answerDelta("Hello")]
        )
    }

    func testPreservesUnicodeSplitAcrossNetworkChunks() throws {
        var parser = SSEParser()
        let event = Data("data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\n".utf8)
        let unicodeStart = event.firstIndex(of: 0xE4)!

        XCTAssertEqual(try parser.feed(Data(event.prefix(upTo: event.index(after: unicodeStart)))), [])
        XCTAssertEqual(try parser.feed(Data(event.suffix(from: event.index(after: unicodeStart)))), [.answerDelta("你")])
    }

    func testIgnoresEmptyDataEvent() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed(Data("data:    \n".utf8)), [])
    }

    func testParsesCommentsUsageAndCompletion() throws {
        var parser = SSEParser()
        let stream = """
        : keepalive
        data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}
        data: {\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":4}}
        data: [DONE]

        """

        XCTAssertEqual(
            try parser.feed(Data(stream.utf8)),
            [.answerDelta("Hello"), .usage(.init(inputTokens: 12, outputTokens: 4)), .completed]
        )
    }

    func testFinishParsesUnterminatedFinalEvent() throws {
        var parser = SSEParser()
        XCTAssertEqual(
            try parser.feed(Data("data: {\"choices\":[{\"delta\":{\"content\":\"final\"}}]}".utf8)),
            []
        )

        XCTAssertEqual(try parser.finish(), [.answerDelta("final")])
    }

    func testParsesReasoningAndAnswerDeltas() throws {
        var parser = SSEParser()

        XCTAssertEqual(
            try parser.feed(Data("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"Plan\",\"content\":\"Answer\"}}]}\n".utf8)),
            [.reasoningDelta("Plan"), .answerDelta("Answer")]
        )
    }

    func testDecodesNonStreamingReasoningAndAnswer() throws {
        let response = try JSONDecoder().decode(
            NonStreamingResponse.self,
            from: Data("{\"choices\":[{\"message\":{\"reasoning_content\":\"Plan\",\"content\":\"Answer\"}}]}".utf8)
        )

        XCTAssertEqual(response.events, [.reasoningDelta("Plan"), .answerDelta("Answer")])
    }

    func testServerErrorPayloadBecomesChatError() throws {
        var parser = SSEParser()

        XCTAssertThrowsError(
            try parser.feed(Data("data: {\"error\":{\"message\":\"quota exceeded\"}}\n".utf8))
        ) { error in
            XCTAssertEqual(error as? ChatError, .serverError(status: 0, message: "quota exceeded"))
        }
    }

    func testMalformedPayloadFailsDecoding() throws {
        var parser = SSEParser()

        XCTAssertThrowsError(try parser.feed(Data("data: not-json\n".utf8))) { error in
            XCTAssertEqual(error as? ChatError, .decodingFailed)
        }
    }
}
