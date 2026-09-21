import Foundation
import Testing
@testable import SpotAsk

@Suite("Clipboard-assisted selection reader")
struct ClipboardAssistedSelectionReaderTests {
    private let source = SelectionSourceApplication(
        processIdentifier: 42,
        bundleIdentifier: "org.zotero.zotero",
        localizedName: "Zotero"
    )

    @Test("A copied selection is returned and the previous pasteboard is restored")
    func returnsCopiedTextAndRestoresPasteboard() async {
        let pasteboard = FakeClipboardPasteboard()
        let richText = ClipboardItemSnapshot(representations: [
            ClipboardRepresentation(type: "public.rtf", data: Data([0x01, 0x02])),
            ClipboardRepresentation(type: "public.utf8-plain-text", data: Data("before".utf8))
        ])
        let image = ClipboardItemSnapshot(representations: [
            ClipboardRepresentation(type: "public.png", data: Data([0x03, 0x04]))
        ])
        pasteboard.items = [richText, image]
        let trigger = FakeSelectionCopyTrigger {
            pasteboard.write(text: "elided observations are stored externally", items: [])
        }

        let text = await reader(pasteboard: pasteboard, trigger: trigger).readSelectedText(from: source)

        #expect(text == "elided observations are stored externally")
        #expect(pasteboard.restoredItems == [[richText, image]])
    }

    @Test("A copy the app ignores leaves the pasteboard untouched")
    func ignoredCopyLeavesPasteboardUntouched() async {
        let pasteboard = FakeClipboardPasteboard()
        pasteboard.items = [ClipboardItemSnapshot(representations: [
            ClipboardRepresentation(type: "public.utf8-plain-text", data: Data("before".utf8))
        ])]

        let text = await reader(pasteboard: pasteboard, trigger: FakeSelectionCopyTrigger {}).readSelectedText(from: source)

        #expect(text == nil)
        #expect(pasteboard.restoredItems.isEmpty)
    }

    @Test("A copy trigger that fails leaves the pasteboard untouched")
    func failingTriggerLeavesPasteboardUntouched() async {
        let pasteboard = FakeClipboardPasteboard()
        let trigger = FakeSelectionCopyTrigger(error: .menuItemUnavailable)

        let text = await reader(pasteboard: pasteboard, trigger: trigger).readSelectedText(from: source)

        #expect(text == nil)
        #expect(pasteboard.restoredItems.isEmpty)
    }

    @Test("A copy without plain text is discarded but still restored")
    func copyWithoutPlainTextIsRestored() async {
        let pasteboard = FakeClipboardPasteboard()
        let original = ClipboardItemSnapshot(representations: [
            ClipboardRepresentation(type: "public.utf8-plain-text", data: Data("before".utf8))
        ])
        pasteboard.items = [original]
        let trigger = FakeSelectionCopyTrigger {
            pasteboard.write(text: nil, items: [ClipboardItemSnapshot(representations: [
                ClipboardRepresentation(type: "public.png", data: Data([0x05]))
            ])])
        }

        let text = await reader(pasteboard: pasteboard, trigger: trigger).readSelectedText(from: source)

        #expect(text == nil)
        #expect(pasteboard.restoredItems == [[original]])
    }

    private func reader(
        pasteboard: FakeClipboardPasteboard,
        trigger: FakeSelectionCopyTrigger
    ) -> ClipboardAssistedSelectionReader {
        ClipboardAssistedSelectionReader(
            pasteboard: pasteboard,
            copyTrigger: trigger,
            timeout: 0.05,
            pollInterval: 0.005
        )
    }
}

private final class FakeClipboardPasteboard: ClipboardPasteboardAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedItems: [ClipboardItemSnapshot] = []
    private var storedText: String?
    private var storedChangeCount = 0
    private var restores: [[ClipboardItemSnapshot]] = []

    var items: [ClipboardItemSnapshot] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedItems
        }
        set {
            lock.lock()
            storedItems = newValue
            lock.unlock()
        }
    }

    var restoredItems: [[ClipboardItemSnapshot]] {
        lock.lock()
        defer { lock.unlock() }
        return restores
    }

    /// Stands in for the host app answering the copy command.
    func write(text: String?, items: [ClipboardItemSnapshot]) {
        lock.lock()
        storedChangeCount += 1
        storedText = text
        storedItems = items
        lock.unlock()
    }

    func changeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storedChangeCount
    }

    func snapshot() -> ClipboardSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ClipboardSnapshot(items: storedItems, changeCount: storedChangeCount)
    }

    func plainText() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedText
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        lock.lock()
        restores.append(snapshot.items)
        storedItems = snapshot.items
        lock.unlock()
    }
}

private struct FakeSelectionCopyTrigger: SelectionCopyTriggering {
    let error: SelectionCopyError?
    let onCopy: @Sendable () -> Void

    init(error: SelectionCopyError? = nil, onCopy: @escaping @Sendable () -> Void = {}) {
        self.error = error
        self.onCopy = onCopy
    }

    func triggerCopy(from _: SelectionSourceApplication) throws {
        if let error { throw error }
        onCopy()
    }
}
