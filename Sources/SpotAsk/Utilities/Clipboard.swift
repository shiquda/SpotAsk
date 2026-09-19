import AppKit

enum Clipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

/// A byte-for-byte copy of every item the pasteboard held, so a temporary
/// write (the clipboard-assisted selection copy) can be undone without
/// dropping rich text, images, file URLs, or any other declared type.
struct PasteboardSnapshot: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let type: String
        let data: Data
    }

    struct Item: Equatable, Sendable {
        let entries: [Entry]
    }

    let changeCount: Int
    let items: [Item]
}

protocol PasteboardAccessing: Sendable {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func string() -> String?
    func restore(_ snapshot: PasteboardSnapshot)
}

/// The real pasteboard.
///
/// AppKit fulfills pasteboard promises synchronously and warns when that
/// happens off the main thread, which is exactly the case here: SpotAsk's own
/// copy buttons write a promise from the main thread, and the selection reader
/// then reads the pasteboard from its own queue. The data calls therefore hop
/// to the main thread. Only `changeCount` is read in place — it is a plain
/// counter with no promise behind it, and the copy wait polls it every 10ms.
struct SystemPasteboard: PasteboardAccessing, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Runs `body` on the main thread, unless it is already there.
    private func onMain<T>(_ body: () -> T) -> T {
        guard !Thread.isMainThread else { return body() }
        return DispatchQueue.main.sync(execute: body)
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func snapshot() -> PasteboardSnapshot {
        onMain {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                PasteboardSnapshot.Item(entries: item.types.compactMap { type in
                    item.data(forType: type).map { PasteboardSnapshot.Entry(type: type.rawValue, data: $0) }
                })
            }
            return PasteboardSnapshot(changeCount: pasteboard.changeCount, items: items)
        }
    }

    func string() -> String? {
        onMain { pasteboard.string(forType: .string) }
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        onMain {
            pasteboard.clearContents()
            let items = snapshot.items.map { item -> NSPasteboardItem in
                let pasteboardItem = NSPasteboardItem()
                for entry in item.entries {
                    pasteboardItem.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
                }
                return pasteboardItem
            }
            guard !items.isEmpty else { return }
            pasteboard.writeObjects(items)
        }
    }
}
