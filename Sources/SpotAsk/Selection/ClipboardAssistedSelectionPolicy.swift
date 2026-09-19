import Foundation

/// Thread-safe mirror of the clipboard-assisted selection preferences.
///
/// `AppSettings` is main-actor bound while `AccessibilitySelectedTextReader`
/// performs reads on its own queue, so the app pushes every settings change
/// into this box instead of reading settings off the main actor mid-read.
final class ClipboardAssistedSelectionPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var isEnabled = false
    private var identifiers: Set<String> = []

    func update(enabled: Bool, identifiers: [String]) {
        lock.lock()
        isEnabled = enabled
        self.identifiers = Set(identifiers)
        lock.unlock()
    }

    func allowsClipboardAssistedSelection(from source: SelectionSourceApplication) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isEnabled, let identifier = source.selectionIdentifier else { return false }
        return identifiers.contains(identifier)
    }
}
