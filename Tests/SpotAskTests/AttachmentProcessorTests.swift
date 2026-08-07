import Foundation
import XCTest
@testable import SpotAsk

final class AttachmentProcessorTests: XCTestCase {
    /// 1x1 transparent PNG.
    private static let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!

    func testPNGBecomesImageAttachment() async throws {
        let url = try makeTemporaryFile(named: "shot.png", data: Self.pngData)
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try await AttachmentProcessor.shared.process(url: url)

        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(attachment.filename, "shot.png")
        if case let .image(data) = attachment.payload {
            XCTAssertFalse(data.isEmpty)
        } else {
            XCTFail("Expected image payload")
        }
    }

    func testScreenshotNormalizedToPNG() async throws {
        let attachment = try await AttachmentProcessor.shared.processScreenshot(Self.pngData)

        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(attachment.filename, "screenshot.png")
    }

    func testTextFileBecomesTextAttachment() async throws {
        let url = try makeTemporaryFile(named: "notes.txt", text: "hello world")
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try await AttachmentProcessor.shared.process(url: url)

        XCTAssertEqual(attachment.kind, .text)
        XCTAssertEqual(attachment.mimeType, "text/plain")
        if case let .text(text, originalKind) = attachment.payload {
            XCTAssertEqual(text, "hello world")
            XCTAssertEqual(originalKind, .text)
        } else {
            XCTFail("Expected text payload")
        }
    }

    func testCodeFileBecomesCodeAttachment() async throws {
        let url = try makeTemporaryFile(named: "main.swift", text: "print(\"hi\")")
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try await AttachmentProcessor.shared.process(url: url)

        if case let .text(_, originalKind) = attachment.payload {
            XCTAssertEqual(originalKind, .code)
        } else {
            XCTFail("Expected code payload")
        }
    }

    func testUnsupportedFileThrows() async throws {
        let url = try makeTemporaryFile(named: "presentation.pptx", text: "binary")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await AttachmentProcessor.shared.process(url: url)
            XCTFail("Expected unsupportedFileType error")
        } catch let error as AttachmentError {
            XCTAssertEqual(error, .unsupportedFileType("presentation.pptx"))
        }
    }

    func testDirectoryThrows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await AttachmentProcessor.shared.process(url: url)
            XCTFail("Expected directoryNotAllowed error")
        } catch let error as AttachmentError {
            XCTAssertEqual(error, .directoryNotAllowed)
        }
    }

    func testOversizedTextIsTruncatedWithMarker() async throws {
        let longText = String(repeating: "a", count: AttachmentLimits.maxExtractedTextPerAttachment + 10_000)
        let url = try makeTemporaryFile(named: "big.txt", text: longText)
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try await AttachmentProcessor.shared.process(url: url)

        XCTAssertTrue(attachment.isTruncated)
        if case let .text(text, _) = attachment.payload {
            XCTAssertEqual(text.count, AttachmentLimits.maxExtractedTextPerAttachment)
        } else {
            XCTFail("Expected text payload")
        }
    }

    func testMissingFileThrows() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).txt")
        do {
            _ = try await AttachmentProcessor.shared.process(url: url)
            XCTFail("Expected fileReadFailed error")
        } catch let error as AttachmentError {
            XCTAssertEqual(error, .fileReadFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeTemporaryFile(named name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makeTemporaryFile(named name: String, text: String) throws -> URL {
        try makeTemporaryFile(named: name, data: Data(text.utf8))
    }
}
