import AppKit
import Darwin
import Foundation

struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let source: SelectionSourceApplication
    let selectedRange: SelectionCharacterRange?
    let anchor: SelectionAnchor
}

struct SelectionCharacterRange: Equatable, Sendable {
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
