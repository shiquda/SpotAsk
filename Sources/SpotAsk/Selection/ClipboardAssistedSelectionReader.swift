import AppKit
import Foundation

struct ClipboardRepresentation: Equatable, Sendable {
    let type: String
    let data: Data
}

struct ClipboardItemSnapshot: Equatable, Sendable {
    let representations: [ClipboardRepresentation]
}

/// A full copy of what the pasteboard held, together with the change count it
/// was taken at, so a copy can be detected and the old contents put back.
struct ClipboardSnapshot: Equatable, Sendable {
    let items: [ClipboardItemSnapshot]
    let changeCount: Int
}

protocol ClipboardPasteboardAccessing: Sendable {
    func changeCount() -> Int
    func snapshot() -> ClipboardSnapshot
    func plainText() -> String?
    func restore(_ snapshot: ClipboardSnapshot)
}

struct SystemClipboardPasteboard: ClipboardPasteboardAccessing {
    func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    func snapshot() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            ClipboardItemSnapshot(
                representations: item.types.compactMap { type in
                    item.data(forType: type).map { ClipboardRepresentation(type: type.rawValue, data: $0) }
                }
            )
        }
        return ClipboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    func plainText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.items.compactMap { item -> NSPasteboardItem? in
            let pasteboardItem = NSPasteboardItem()
            var wroteAnyRepresentation = false
            for representation in item.representations {
                let type = NSPasteboard.PasteboardType(representation.type)
                if pasteboardItem.setData(representation.data, forType: type) {
                    wroteAnyRepresentation = true
                }
            }
            return wroteAnyRepresentation ? pasteboardItem : nil
        }
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}

protocol ClipboardAssistedSelectionReading: Sendable {
    func readSelectedText(from source: SelectionSourceApplication) async -> String?
}

/// Reads a selection the way the app's own Copy command does, borrowing the
/// app's selection handling for hosts whose Accessibility text is unreliable.
///
/// The user's pasteboard is captured first and put back as soon as the copied
/// text is read, so the copy stays inside a window of milliseconds and the
/// previous contents (text, rich text, images, file URLs) are not lost.
///
/// Pasteboard access is AppKit-owned state and runs on the main actor, while
/// the copy command and the wait for it stay off the main thread so a slow app
/// cannot stall the interface.
final class ClipboardAssistedSelectionReader: ClipboardAssistedSelectionReading, @unchecked Sendable {
    static let defaultTimeout: TimeInterval = 0.5
    static let defaultMenuFallbackTimeout: TimeInterval = 0.15
    static let defaultPollInterval: TimeInterval = 0.01

    private let pasteboard: any ClipboardPasteboardAccessing
    private let copyTrigger: any SelectionCopyTriggering
    private let fallbackCopyTrigger: (any SelectionCopyTriggering)?
    private let timeout: TimeInterval
    private let menuFallbackTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let queue: DispatchQueue

    init(
        pasteboard: any ClipboardPasteboardAccessing = SystemClipboardPasteboard(),
        copyTrigger: (any SelectionCopyTriggering)? = nil,
        fallbackCopyTrigger: (any SelectionCopyTriggering)? = nil,
        timeout: TimeInterval = ClipboardAssistedSelectionReader.defaultTimeout,
        menuFallbackTimeout: TimeInterval = ClipboardAssistedSelectionReader.defaultMenuFallbackTimeout,
        pollInterval: TimeInterval = ClipboardAssistedSelectionReader.defaultPollInterval
    ) {
        self.pasteboard = pasteboard
        if let copyTrigger {
            self.copyTrigger = copyTrigger
            self.fallbackCopyTrigger = fallbackCopyTrigger
        } else {
            self.copyTrigger = AccessibilityMenuCopyTrigger()
            self.fallbackCopyTrigger = fallbackCopyTrigger ?? KeyCommandSelectionCopyTrigger()
        }
        self.timeout = timeout
        self.menuFallbackTimeout = menuFallbackTimeout
        self.pollInterval = pollInterval
        queue = DispatchQueue(label: "com.spotask.selection.clipboard", qos: .userInitiated)
    }

    func readSelectedText(from source: SelectionSourceApplication) async -> String? {
        let backup = await onMain { self.pasteboard.snapshot() }
        guard await copyIntoPasteboard(from: source, after: backup.changeCount) else {
            return nil
        }
        let text = await onMain { self.pasteboard.plainText() }
        await onMain { self.pasteboard.restore(backup) }
        SafeLogger.selectionReadProgress("clipboard-restored")
        return text
    }

    private func copyIntoPasteboard(from source: SelectionSourceApplication, after changeCount: Int) async -> Bool {
        do {
            try await triggerCopyOffMain(using: copyTrigger, from: source)
        } catch {
            SafeLogger.selectionReadProgress("clipboard-copy-trigger-failed")
            return await attemptFallbackCopy(from: source, after: changeCount, waitBudget: timeout)
        }

        if let fallbackCopyTrigger {
            let primaryBudget = min(menuFallbackTimeout, timeout)
            if await waitForCopy(after: changeCount, waitBudget: primaryBudget) {
                return true
            }
            SafeLogger.selectionReadProgress("clipboard-copy-primary-no-change")
            let remainingBudget = max(timeout - primaryBudget, 0)
            return await attemptFallbackCopy(from: source, after: changeCount, waitBudget: remainingBudget, fallback: fallbackCopyTrigger)
        }

        // An unchanged pasteboard means the app ignored the copy command, so
        // there is nothing to restore and nothing to read.
        guard await waitForCopy(after: changeCount, waitBudget: timeout) else {
            SafeLogger.selectionReadProgress("clipboard-copy-not-observed")
            return false
        }
        return true
    }

    private func attemptFallbackCopy(
        from source: SelectionSourceApplication,
        after changeCount: Int,
        waitBudget: TimeInterval,
        fallback: (any SelectionCopyTriggering)? = nil
    ) async -> Bool {
        guard let trigger = fallback ?? fallbackCopyTrigger else { return false }
        do {
            try await triggerCopyOffMain(using: trigger, from: source)
        } catch {
            SafeLogger.selectionReadProgress("clipboard-copy-fallback-failed")
            return false
        }
        guard await waitForCopy(after: changeCount, waitBudget: waitBudget) else {
            SafeLogger.selectionReadProgress("clipboard-copy-not-observed")
            return false
        }
        return true
    }

    private func triggerCopyOffMain(using trigger: any SelectionCopyTriggering, from source: SelectionSourceApplication) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try trigger.triggerCopy(from: source) })
            }
        }
    }

    private func waitForCopy(after changeCount: Int, waitBudget: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(waitBudget)
        while true {
            if await onMain({ self.pasteboard.changeCount() }) != changeCount { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
    }

    private func onMain<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await MainActor.run { work() }
    }
}
