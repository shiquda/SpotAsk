import ApplicationServices
import Foundation

/// Shared bounded accessibility traversal used by both the selection reader and
/// the write-back engine: resolve the focused element, walk a limited parent
/// chain, reject secure input fields, and look up a non-empty selected text
/// with its range. Keeping this logic in one place guarantees the reader and
/// the write-back re-verification follow the same element resolution rules.
enum SelectionElementChain {
    struct SelectedTextMatch: Equatable {
        enum Evidence: Equatable {
            case selectedText
            case textMarkerRange
        }

        let element: AccessibilityElementID
        let text: String
        let evidence: Evidence
    }

    static let defaultLimit = 6

    static func focusedElement(
        from applicationElement: AccessibilityElementID,
        reader: any AccessibilityElementReading
    ) throws -> AccessibilityElementID {
        let value = try reader.copyAttribute(kAXFocusedUIElementAttribute as String, from: applicationElement)
        guard case let .element(element) = value else {
            throw SelectionReadingError.noSelection
        }
        return element
    }

    static func chain(
        startingAt focusedElement: AccessibilityElementID,
        reader: any AccessibilityElementReading,
        limit: Int = defaultLimit
    ) throws -> [AccessibilityElementID] {
        var candidates: [AccessibilityElementID] = []
        var currentElement: AccessibilityElementID? = focusedElement
        var visited: Set<AccessibilityElementID> = []

        while let element = currentElement,
              candidates.count < limit,
              visited.insert(element).inserted {
            candidates.append(element)
            currentElement = try parent(of: element, reader: reader)
        }
        return candidates
    }

    /// Throws `SelectionReadingError.sensitiveField` before any selected text is
    /// read when any layer of the chain is a secure text field.
    static func preflightSensitiveFields(
        in candidates: [AccessibilityElementID],
        reader: any AccessibilityElementReading
    ) throws {
        for element in candidates {
            _ = try optionalStringAttribute(kAXRoleAttribute as String, from: element, reader: reader)
            let subrole = try optionalStringAttribute(kAXSubroleAttribute as String, from: element, reader: reader)
            if subrole == kAXSecureTextFieldSubrole as String {
                throw SelectionReadingError.sensitiveField
            }
        }
    }

    static func selectedTextMatch(
        in candidates: [AccessibilityElementID],
        reader: any AccessibilityElementReading
    ) throws -> SelectedTextMatch? {
        for element in candidates {
            if let match = try selectedText(from: element, reader: reader),
               !match.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return match
            }
        }
        return nil
    }

    private static func selectedText(
        from element: AccessibilityElementID,
        reader: any AccessibilityElementReading
    ) throws -> SelectedTextMatch? {
        do {
            let value = try reader.copyAttribute(kAXSelectedTextAttribute as String, from: element)
            if case let .string(text) = value, !text.isEmpty {
                return SelectedTextMatch(element: element, text: text, evidence: .selectedText)
            }
        } catch {
            if !isAbsentAttribute(error) { throw error }
        }

        // Firefox-derived browsers expose web selections through text markers
        // instead of the older AXSelectedText attribute.
        do {
            let markerValue = try reader.copyAttribute(
                kAXSelectedTextMarkerRangeAttribute as String,
                from: element
            )
            guard case let .textMarkerRange(markerRange) = markerValue,
                  markerRange.isNonEmpty else { return nil }
            let stringValue = try reader.copyParameterizedAttribute(
                kAXStringForTextMarkerRangeParameterizedAttribute as String,
                parameter: .textMarkerRange(markerRange),
                from: element
            )
            guard case let .string(text) = stringValue else { return nil }
            return SelectedTextMatch(element: element, text: text, evidence: .textMarkerRange)
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }

    static func selectedRange(
        for element: AccessibilityElementID,
        reader: any AccessibilityElementReading
    ) throws -> SelectionCharacterRange? {
        do {
            let value = try reader.copyAttribute(kAXSelectedTextRangeAttribute as String, from: element)
            guard case let .range(range) = value else { return nil }
            return range.isNonEmpty ? range : nil
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }

    static func isAbsentAttribute(_ error: Error) -> Bool {
        guard case let .ax(axError) = error as? AccessibilityAdapterError else { return false }
        return [
            AccessibilityAXError.attributeUnsupported,
            AccessibilityAXError.noValue,
            AccessibilityAXError.parameterizedAttributeUnsupported
        ].contains(axError)
    }

    /// Presence probe used before any clipboard-assisted copy. It only reports
    /// whether the focus chain owns a non-empty selection; it never asks the
    /// app to hand over the text, which is the part Gecko misreports.
    static func hasSelection(
        in candidates: [AccessibilityElementID],
        reader: any AccessibilityElementReading
    ) throws -> Bool {
        for element in candidates where try hasSelection(in: element, reader: reader) {
            return true
        }
        return false
    }

    private static func hasSelection(
        in element: AccessibilityElementID,
        reader: any AccessibilityElementReading
    ) throws -> Bool {
        if let text = try optionalStringAttribute(kAXSelectedTextAttribute as String, from: element, reader: reader),
           !text.isEmpty {
            return true
        }
        if let range = try selectedRange(for: element, reader: reader), range.isNonEmpty {
            return true
        }
        do {
            let value = try reader.copyAttribute(kAXSelectedTextMarkerRangeAttribute as String, from: element)
            guard case let .textMarkerRange(markerRange) = value else { return false }
            return markerRange.isNonEmpty
        } catch {
            if isAbsentAttribute(error) { return false }
            throw error
        }
    }

    private static func parent(of element: AccessibilityElementID, reader: any AccessibilityElementReading) throws -> AccessibilityElementID? {
        do {
            let value = try reader.copyAttribute(kAXParentAttribute as String, from: element)
            guard case let .element(parent) = value else { return nil }
            return parent
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }

    private static func optionalStringAttribute(
        _ attribute: String,
        from element: AccessibilityElementID,
        reader: any AccessibilityElementReading
    ) throws -> String? {
        do {
            let value = try reader.copyAttribute(attribute, from: element)
            guard case let .string(string) = value else { return nil }
            return string
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }
}
