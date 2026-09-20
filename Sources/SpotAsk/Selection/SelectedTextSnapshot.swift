import AppKit
import Darwin
import Foundation

/// Where the text of a snapshot came from.
enum SelectionTextOrigin: Equatable, Sendable {
    /// `text` is the selection the app reported.
    case accessibility
    /// The app misreports its Accessibility text, so only the presence of a
    /// selection is known here. `text` is a best-effort hint at most, and the
    /// authoritative text is read when an action needs it.
    case deferredToPasteboard
}

struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let source: SelectionSourceApplication
    let selectedRange: SelectionCharacterRange?
    let anchor: SelectionAnchor
    let canReplaceSelection: Bool
    let isConfirmedSelection: Bool
    let textOrigin: SelectionTextOrigin

    init(
        text: String,
        source: SelectionSourceApplication,
        selectedRange: SelectionCharacterRange?,
        anchor: SelectionAnchor,
        canReplaceSelection: Bool = false,
        isConfirmedSelection: Bool? = nil,
        textOrigin: SelectionTextOrigin = .accessibility
    ) {
        self.text = text
        self.source = source
        self.selectedRange = selectedRange
        self.anchor = anchor
        self.canReplaceSelection = canReplaceSelection
        self.isConfirmedSelection = isConfirmedSelection ?? selectedRange?.isNonEmpty == true
        self.textOrigin = textOrigin
    }

    /// Whether this selection is substantial enough to wake the assistant. A
    /// deferred selection is confirmed by its presence alone; its text arrives
    /// later, when an action runs.
    var hasUsableSelection: Bool {
        textOrigin == .deferredToPasteboard || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The same selection with its text filled in, so whoever receives a
    /// resolved snapshot never reads the pasteboard for it again.
    func resolvingText(_ text: String) -> SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: text,
            source: source,
            selectedRange: selectedRange,
            anchor: anchor,
            canReplaceSelection: canReplaceSelection,
            isConfirmedSelection: isConfirmedSelection,
            textOrigin: .accessibility
        )
    }
}

struct SelectionCharacterRange: Equatable, Hashable, Sendable {
    let location: Int
    let length: Int

    var isNonEmpty: Bool {
        length > 0
    }
}

struct SelectionSourceApplication: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?

    /// The stable identifier per-app selection settings store: the bundle
    /// identifier, falling back to the app name for apps that publish none.
    var selectionIdentifier: String? {
        guard let identifier = bundleIdentifier ?? localizedName, !identifier.isEmpty else {
            return nil
        }
        return identifier
    }
}

enum SelectionAnchor: Equatable, Sendable {
    case selectionRect(CGRect)
    case elementRect(CGRect)
    case pointer(CGPoint)
}

enum SelectionReadingError: Error, Equatable, Sendable {
    case permissionDenied
    case noExternalSelection
    case noSelection
    case unsupportedApplication
    case applicationUnresponsive
    case accessibilityDisabled
    case sensitiveField
    case applicationUnavailable
    case invalidAccessibilityValue
}

protocol SelectedTextReading: Sendable {
    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot
}

/// Reads the text of a selection that detection could only locate, by asking
/// the host application to copy it.
///
/// Detection runs on every selection gesture and must stay free of side
/// effects, so the copy belongs to the moment an action actually needs the
/// text rather than to the moment a selection is seen.
protocol DeferredSelectionTextReading: Sendable {
    func readDeferredSelectionText(for snapshot: SelectedTextSnapshot) async -> String?
}
