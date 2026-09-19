import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Pasteboard snapshots")
struct PasteboardSnapshotTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.spotask.tests.pasteboard.\(UUID().uuidString)"))
    }

    @Test("Restoring keeps every item, type, and byte of text, rich text, and images")
    func restoresEveryItemTypeAndByte() throws {
        let pasteboard = makePasteboard()
        let richText = Data(#"{\rtf1 rich}"#.utf8)
        let image = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let textItem = NSPasteboardItem()
        textItem.setString("plain text", forType: .string)
        textItem.setData(richText, forType: .rtf)
        let imageItem = NSPasteboardItem()
        imageItem.setData(image, forType: .png)
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([textItem, imageItem]))

        let clipboard = SystemPasteboard(pasteboard: pasteboard)
        let backup = clipboard.snapshot()
        clipboard.restore(backup)

        let restored = try #require(pasteboard.pasteboardItems)
        #expect(restored.count == 2)
        #expect(restored[0].string(forType: .string) == "plain text")
        #expect(restored[0].data(forType: .rtf) == richText)
        #expect(restored[1].data(forType: .png) == image)
    }

    @Test("Restoring puts back what a copy overwrote")
    func restoresWhatACopyOverwrote() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("mine", forType: .string)
        let clipboard = SystemPasteboard(pasteboard: pasteboard)
        let backup = clipboard.snapshot()

        pasteboard.clearContents()
        pasteboard.setString("borrowed", forType: .string)
        #expect(clipboard.string() == "borrowed")

        clipboard.restore(backup)

        #expect(clipboard.string() == "mine")
        #expect(pasteboard.changeCount != backup.changeCount)
    }

    @Test("An empty clipboard stays empty after a copy")
    func emptyClipboardStaysEmpty() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        let clipboard = SystemPasteboard(pasteboard: pasteboard)
        let backup = clipboard.snapshot()
        #expect(backup.items.isEmpty)

        clipboard.restore(backup)

        #expect(clipboard.string() == nil)
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
    }
}
