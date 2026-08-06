import AppKit
import ApplicationServices
import Darwin
import Foundation

protocol AccessibilityPermissionChecking: Sendable {
    func isTrusted(prompt: Bool) -> Bool
}

struct MacOSAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

protocol ForegroundSelectionApplicationProviding: Sendable {
    func frontmostApplication() -> SelectionSourceApplication?
    func currentProcessIdentifier() -> pid_t
}

struct MacOSForegroundSelectionApplicationProvider: ForegroundSelectionApplicationProviding {
    func frontmostApplication() -> SelectionSourceApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return SelectionSourceApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName
        )
    }

    func currentProcessIdentifier() -> pid_t {
        ProcessInfo.processInfo.processIdentifier
    }
}

protocol PointerLocationProviding: Sendable {
    func location() -> CGPoint
}

struct MacOSPointerLocationProvider: PointerLocationProviding {
    func location() -> CGPoint {
        NSEvent.mouseLocation
    }
}

final class AccessibilitySelectedTextReader: SelectedTextReading, @unchecked Sendable {
    private static let candidateLimit = 6
    private static let messagingTimeout: TimeInterval = 1
    private static let readAttempts = 2
    private static let retryDelay: TimeInterval = 0.1

    private let permissionChecker: any AccessibilityPermissionChecking
    private let applicationProvider: any ForegroundSelectionApplicationProviding
    private let elementReader: any AccessibilityElementReading
    private let pointerLocationProvider: any PointerLocationProviding

    init(
        permissionChecker: any AccessibilityPermissionChecking = MacOSAccessibilityPermissionChecker(),
        applicationProvider: any ForegroundSelectionApplicationProviding = MacOSForegroundSelectionApplicationProvider(),
        elementReader: any AccessibilityElementReading = MacOSAccessibilityElementAdapter(),
        pointerLocationProvider: any PointerLocationProviding = MacOSPointerLocationProvider()
    ) {
        self.permissionChecker = permissionChecker
        self.applicationProvider = applicationProvider
        self.elementReader = elementReader
        self.pointerLocationProvider = pointerLocationProvider
    }

    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [self] in
                continuation.resume(with: Result { try readSelectionSynchronously(promptForPermission: promptForPermission) })
            }
        }
    }

    private func readSelectionSynchronously(promptForPermission: Bool) throws -> SelectedTextSnapshot {
        guard permissionChecker.isTrusted(prompt: promptForPermission) else {
            throw SelectionReadingError.permissionDenied
        }
        guard let source = applicationProvider.frontmostApplication(),
              source.processIdentifier != applicationProvider.currentProcessIdentifier() else {
            throw SelectionReadingError.noExternalSelection
        }
        SafeLogger.selectionReadStarted(sourceBundleIdentifier: source.bundleIdentifier)

        for attempt in 0 ..< Self.readAttempts {
            do {
                let snapshot = try readSelection(from: source)
                SafeLogger.selectionReadSucceeded(textLength: snapshot.text.count)
                return snapshot
            } catch where shouldRetry(error, attempt: attempt) {
                Thread.sleep(forTimeInterval: Self.retryDelay)
            } catch let error as SelectionReadingError {
                SafeLogger.selectionReadFailed(error)
                throw error
            } catch {
                let mappedError = mapAccessibilityError(error)
                SafeLogger.selectionReadFailed(error)
                throw mappedError
            }
        }

        throw SelectionReadingError.applicationUnresponsive
    }

    private func readSelection(from source: SelectionSourceApplication) throws -> SelectedTextSnapshot {
        let applicationElement = try elementReader.makeApplicationElement(processIdentifier: source.processIdentifier)
        SafeLogger.selectionReadProgress("application-element-ready")
        try elementReader.setMessagingTimeout(Self.messagingTimeout, for: applicationElement)
        SafeLogger.selectionReadProgress("messaging-timeout-set")
        let focusedElement = try focusedElement(from: applicationElement)
        SafeLogger.selectionReadProgress("focused-element-ready")
        let candidates = try candidateChain(startingAt: focusedElement)
        try preflightSensitiveFields(in: candidates)
        guard let match = try selectedTextMatch(in: candidates) else {
            throw SelectionReadingError.noSelection
        }

        let selectedRange = try selectedRange(for: match.element)
        let canReplaceSelection = selectedRange != nil && ((try? (elementReader as? any AccessibilityElementWriting)?
            .isAttributeSettable(kAXSelectedTextAttribute as String, for: match.element)) ?? false)
        let anchor = SelectionAnchor.pointer(pointerLocationProvider.location())
        SafeLogger.selectionAnchorResolved("snapshot=\(formatted(anchor))")
        return SelectedTextSnapshot(
            text: match.text,
            source: source,
            selectedRange: selectedRange,
            anchor: anchor,
            canReplaceSelection: canReplaceSelection
        )
    }

    private func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt + 1 < Self.readAttempts,
              case let .ax(axError) = error as? AccessibilityAdapterError else {
            return false
        }
        return axError == .cannotComplete
    }

    private func focusedElement(from systemWideElement: AccessibilityElementID) throws -> AccessibilityElementID {
        let value = try elementReader.copyAttribute(kAXFocusedUIElementAttribute as String, from: systemWideElement)
        guard case let .element(element) = value else {
            throw SelectionReadingError.noSelection
        }
        return element
    }

    private func candidateChain(startingAt focusedElement: AccessibilityElementID) throws -> [AccessibilityElementID] {
        var candidates: [AccessibilityElementID] = []
        var currentElement: AccessibilityElementID? = focusedElement
        var visited: Set<AccessibilityElementID> = []

        while let element = currentElement,
              candidates.count < Self.candidateLimit,
              visited.insert(element).inserted {
            candidates.append(element)
            currentElement = try parent(of: element)
        }
        return candidates
    }

    private func parent(of element: AccessibilityElementID) throws -> AccessibilityElementID? {
        do {
            let value = try elementReader.copyAttribute(kAXParentAttribute as String, from: element)
            guard case let .element(parent) = value else { return nil }
            return parent
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }

    private func preflightSensitiveFields(in candidates: [AccessibilityElementID]) throws {
        for element in candidates {
            _ = try optionalStringAttribute(kAXRoleAttribute as String, from: element)
            let subrole = try optionalStringAttribute(kAXSubroleAttribute as String, from: element)
            if subrole == kAXSecureTextFieldSubrole as String {
                throw SelectionReadingError.sensitiveField
            }
        }
    }

    private func optionalStringAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> String? {
        do {
            let value = try elementReader.copyAttribute(attribute, from: element)
            guard case let .string(string) = value else { return nil }
            return string
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }

    private func selectedTextMatch(in candidates: [AccessibilityElementID]) throws -> (element: AccessibilityElementID, text: String)? {
        for element in candidates {
            do {
                let value = try elementReader.copyAttribute(kAXSelectedTextAttribute as String, from: element)
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

    private func selectedRange(for element: AccessibilityElementID) throws -> SelectionCharacterRange? {
        do {
            let value = try elementReader.copyAttribute(kAXSelectedTextRangeAttribute as String, from: element)
            guard case let .range(range) = value else { return nil }
            return range.isNonEmpty ? range : nil
        } catch {
            if isAbsentAttribute(error) { return nil }
            throw error
        }
    }

    private func formatted(_ point: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", point.x, point.y)
    }

    private func formatted(_ rect: CGRect) -> String {
        String(format: "(%.1f,%.1f,%.1f,%.1f)", rect.minX, rect.minY, rect.width, rect.height)
    }

    private func formatted(_ anchor: SelectionAnchor) -> String {
        switch anchor {
        case let .selectionRect(rect): "selection=\(formatted(rect))"
        case let .elementRect(rect): "element=\(formatted(rect))"
        case let .pointer(point): "pointer=\(formatted(point))"
        }
    }

    private func isAbsentAttribute(_ error: Error) -> Bool {
        guard case let .ax(axError) = error as? AccessibilityAdapterError else { return false }
        return [
            AccessibilityAXError.attributeUnsupported,
            AccessibilityAXError.noValue,
            AccessibilityAXError.parameterizedAttributeUnsupported
        ].contains(axError)
    }

    private func mapAccessibilityError(_ error: Error) -> SelectionReadingError {
        guard let adapterError = error as? AccessibilityAdapterError else {
            return .invalidAccessibilityValue
        }
        switch adapterError {
        case .invalidValue:
            return .invalidAccessibilityValue
        case let .ax(axError):
            switch axError {
            case .apiDisabled:
                return .accessibilityDisabled
            case .cannotComplete:
                return .applicationUnresponsive
            case .notImplemented:
                return .unsupportedApplication
            case .invalidUIElement, .invalidUIElementObserver:
                return .applicationUnavailable
            default:
                return .unsupportedApplication
            }
        }
    }
}
