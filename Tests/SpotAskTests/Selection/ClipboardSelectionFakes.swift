import AppKit
import Foundation
import Testing
@testable import SpotAsk

/// Fakes for the clipboard-assisted reading path. They live beside the reader
/// fixture because the reader tests drive them through `AccessibilitySelectedTextReader`.
final class FakeClipboardAssistedSelectionPolicy: ClipboardAssistedSelectionPolicy, @unchecked Sendable {
    private let lock = NSLock()
    private var enabledValue: Bool
    private var sources: [SelectionSourceApplication?] = []

    init(enabled: Bool = false) {
        enabledValue = enabled
    }

    var enabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabledValue
        }
        set {
            lock.lock()
            enabledValue = newValue
            lock.unlock()
        }
    }

    var queriedSources: [SelectionSourceApplication?] {
        lock.lock()
        defer { lock.unlock() }
        return sources
    }

    func isEnabled(for source: SelectionSourceApplication?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        sources.append(source)
        return enabledValue
    }
}

final class FakePasteboard: PasteboardAccessing, @unchecked Sendable {
    enum CopyBehaviour {
        case nothing
        case text(String)
        case nonText
    }

    private let lock = NSLock()
    private var items: [PasteboardSnapshot.Item]
    private var count = 1
    private var preferredText: String?
    private var restores: [PasteboardSnapshot] = []
    var copyBehaviour: CopyBehaviour = .nothing

    init(text: String? = nil) {
        items = text.map {
            [PasteboardSnapshot.Item(entries: [
                PasteboardSnapshot.Entry(type: NSPasteboard.PasteboardType.string.rawValue, data: Data($0.utf8))
            ])]
        } ?? []
        preferredText = text
    }

    var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var restoredSnapshots: [PasteboardSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return restores
    }

    var currentItems: [PasteboardSnapshot.Item] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func snapshot() -> PasteboardSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return PasteboardSnapshot(changeCount: count, items: items)
    }

    func string() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return preferredText
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        restores.append(snapshot)
        items = snapshot.items
        preferredText = snapshot.items
            .flatMap(\.entries)
            .first { $0.type == NSPasteboard.PasteboardType.string.rawValue }
            .map { String(decoding: $0.data, as: UTF8.self) }
        count += 1
    }

    /// Simulates the source app writing its copy to the pasteboard.
    func performCopy() {
        lock.lock()
        defer { lock.unlock() }
        switch copyBehaviour {
        case .nothing:
            return
        case let .text(text):
            items = [PasteboardSnapshot.Item(entries: [
                PasteboardSnapshot.Entry(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))
            ])]
            preferredText = text
        case .nonText:
            items = [PasteboardSnapshot.Item(entries: [
                PasteboardSnapshot.Entry(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([0x89, 0x50]))
            ])]
            preferredText = nil
        }
        count += 1
    }
}

final class FakeSelectionCopyTrigger: SelectionCopyTriggering, @unchecked Sendable {
    private let lock = NSLock()
    private let pasteboard: FakePasteboard
    private var applications: [AccessibilityElementID] = []

    init(pasteboard: FakePasteboard) {
        self.pasteboard = pasteboard
    }

    var triggeredApplications: [AccessibilityElementID] {
        lock.lock()
        defer { lock.unlock() }
        return applications
    }

    func triggerCopy(in application: AccessibilityElementID) {
        lock.lock()
        applications.append(application)
        lock.unlock()
        pasteboard.performCopy()
    }
}
