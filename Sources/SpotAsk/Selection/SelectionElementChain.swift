import ApplicationServices
import Foundation

/// Shared bounded accessibility traversal used by both the selection reader and
/// the write-back engine: resolve the focused element, walk a limited parent
/// chain, reject secure input fields, and look up a non-empty selected text
/// with its range. Keeping this logic in one place guarantees the reader and
/// the write-back re-verification follow the same element resolution rules.
enum SelectionElementChain {
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
    ) throws -> (element: AccessibilityElementID, text: String)? {
        for element in candidates {
            do {
                let value = try reader.copyAttribute(kAXSelectedTextAttribute as String, from: element)
                guard case let .string(text) = value else { continue }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (element, text)
                }
            } catch {
                if isAbsentAttribute(error) { continue }
                throw error
            }
        }
        return nil
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
