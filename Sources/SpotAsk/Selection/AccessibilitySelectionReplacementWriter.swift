import ApplicationServices
import Foundation

enum SelectionReplacementError: Error {
    case unavailable
    case selectionChanged
    case failed
}

protocol SelectionReplacementWriting: Sendable {
    func replaceSelection(in snapshot: SelectedTextSnapshot, with text: String) async throws
}

final class AccessibilitySelectionReplacementWriter: SelectionReplacementWriting, @unchecked Sendable {
    private static let messagingTimeout: TimeInterval = 1
    private let permissionChecker: any AccessibilityPermissionChecking
    private let elementReader: any AccessibilityElementReading
    private let elementWriter: any AccessibilityElementWriting

    init(
        permissionChecker: any AccessibilityPermissionChecking = MacOSAccessibilityPermissionChecker(),
        elementReader: any AccessibilityElementReading = MacOSAccessibilityElementAdapter(),
        elementWriter: any AccessibilityElementWriting = MacOSAccessibilityElementAdapter()
    ) {
        self.permissionChecker = permissionChecker
        self.elementReader = elementReader
        self.elementWriter = elementWriter
    }

    func replaceSelection(in snapshot: SelectedTextSnapshot, with text: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [self] in
                continuation.resume(with: Result {
                    try replaceSelectionSynchronously(in: snapshot, with: text)
                })
            }
        }
    }

    private func replaceSelectionSynchronously(in snapshot: SelectedTextSnapshot, with text: String) throws {
        guard snapshot.canReplaceSelection,
              let range = snapshot.selectedRange,
              permissionChecker.isTrusted(prompt: false) else {
            throw SelectionReplacementError.unavailable
        }
        let application = try elementReader.makeApplicationElement(processIdentifier: snapshot.source.processIdentifier)
        try elementReader.setMessagingTimeout(Self.messagingTimeout, for: application)
        let focused = try SelectionElementChain.focusedElement(from: application, reader: elementReader)
        let candidates = try SelectionElementChain.chain(startingAt: focused, reader: elementReader)
        try SelectionElementChain.preflightSensitiveFields(in: candidates, reader: elementReader)
        guard let match = try SelectionElementChain.selectedTextMatch(in: candidates, reader: elementReader),
              match.text == snapshot.text,
              try SelectionElementChain.selectedRange(for: match.element, reader: elementReader) == range,
              try elementWriter.isAttributeSettable(kAXSelectedTextAttribute as String, for: match.element) else {
            throw SelectionReplacementError.selectionChanged
        }
        try elementWriter.setAttribute(kAXSelectedTextAttribute as String, value: .string(text), for: match.element)
    }
}
