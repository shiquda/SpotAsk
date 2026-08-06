import Foundation
import XCTest
@testable import SpotAsk

final class DiagnosticLogStoreTests: XCTestCase {
    func testOnlyRecordsWhileEnabled() throws {
        let store = makeStore()

        store.record("before-enable")
        store.setEnabled(true)
        store.record("after-enable")
        store.setEnabled(false)
        store.record("after-disable")

        let text = store.exportedText()
        XCTAssertTrue(text.contains("after-enable"))
        XCTAssertFalse(text.contains("before-enable"))
        XCTAssertFalse(text.contains("after-disable"))
    }

    func testRollingLogKeepsMostRecentEntries() throws {
        let store = makeStore()
        store.setEnabled(true)

        for index in 0 ..< (DiagnosticLogStore.maximumEntryCount + 20) {
            store.record("entry-\(index)")
        }

        let text = store.exportedText()
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, DiagnosticLogStore.maximumEntryCount)
        XCTAssertTrue(text.contains("entry-\(DiagnosticLogStore.maximumEntryCount - 1)"))
        XCTAssertTrue(text.contains("entry-\(DiagnosticLogStore.maximumEntryCount + 19)"))
        XCTAssertFalse(text.contains("entry-0"))
    }

    func testClearRemovesAllEntries() throws {
        let store = makeStore()
        store.setEnabled(true)
        store.record("one")

        store.clear()

        XCTAssertEqual(store.exportedText(), "")
    }

    func testExportedTextContainsTimestampAndMessage() throws {
        let store = makeStore()
        store.setEnabled(true)
        store.record("hello-diagnostics")

        let text = store.exportedText()

        XCTAssertTrue(text.contains("hello-diagnostics"))
        XCTAssertTrue(text.hasPrefix("["))
        XCTAssertTrue(text.contains("] "))
    }

    func testTruncationLimitsLongContent() {
        let long = String(repeating: "a", count: DiagnosticLogStore.maximumContentLength + 100)
        let truncated = DiagnosticLogStore.truncated(long)

        XCTAssertEqual(truncated.count, DiagnosticLogStore.maximumContentLength + 1)
        XCTAssertTrue(truncated.hasSuffix("…"))
    }

    private func makeStore() -> DiagnosticLogStore {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("diagnostics.json")
        let store = DiagnosticLogStore(fileURL: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return store
    }
}
