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

final class AccessibilitySelectedTextReader: SelectedTextReading, DeferredSelectionTextReading, @unchecked Sendable {
    private static let messagingTimeout: TimeInterval = 1
    private static let readAttempts = 2
    private static let retryDelay: TimeInterval = 0.1

    private let permissionChecker: any AccessibilityPermissionChecking
    private let applicationProvider: any ForegroundSelectionApplicationProviding
    private let elementReader: any AccessibilityElementReading
    private let pointerLocationProvider: any PointerLocationProviding
    private let clipboardAssistedPolicy: ClipboardAssistedSelectionPolicy
    private let clipboardSelectionReader: any ClipboardAssistedSelectionReading
    private let queue: DispatchQueue

    init(
        permissionChecker: any AccessibilityPermissionChecking = MacOSAccessibilityPermissionChecker(),
        applicationProvider: any ForegroundSelectionApplicationProviding = MacOSForegroundSelectionApplicationProvider(),
        elementReader: any AccessibilityElementReading = MacOSAccessibilityElementAdapter(),
        pointerLocationProvider: any PointerLocationProviding = MacOSPointerLocationProvider(),
        clipboardAssistedPolicy: ClipboardAssistedSelectionPolicy = ClipboardAssistedSelectionPolicy(),
        clipboardSelectionReader: (any ClipboardAssistedSelectionReading)? = nil
    ) {
        self.permissionChecker = permissionChecker
        self.applicationProvider = applicationProvider
        self.elementReader = elementReader
        self.pointerLocationProvider = pointerLocationProvider
        self.clipboardAssistedPolicy = clipboardAssistedPolicy
        self.clipboardSelectionReader = clipboardSelectionReader ?? ClipboardAssistedSelectionReader()
        queue = DispatchQueue(label: "com.spotask.selection.accessibility", qos: .userInitiated)
    }

    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot {
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
                let snapshot = try await readSelection(from: source)
                SafeLogger.selectionReadSucceeded(textLength: snapshot.text.count)
                return snapshot
            } catch where shouldRetry(error, attempt: attempt) {
                try? await Task.sleep(for: .seconds(Self.retryDelay))
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

    /// Runs every Accessibility step on one serial context so concurrent reads
    /// never interleave their messages to the same app.
    private func withAccessibilityContext<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func readSelection(from source: SelectionSourceApplication) async throws -> SelectedTextSnapshot {
        let candidates = try await withAccessibilityContext { try self.focusedSelectionChain() }
        let usesClipboardAssistedSelection = clipboardAssistedPolicy.allowsClipboardAssistedSelection(from: source)

        guard usesClipboardAssistedSelection else {
            return try await withAccessibilityContext { try self.readAccessibilitySelection(from: source, candidates: candidates) }
        }
        return try await readClipboardAssistedSelection(from: source, candidates: candidates)
    }

    private func focusedSelectionChain() throws -> [AccessibilityElementID] {
        let systemWideElement = try elementReader.makeSystemWideElement()
        SafeLogger.selectionReadProgress("system-wide-element-ready")
        try elementReader.setMessagingTimeout(Self.messagingTimeout, for: systemWideElement)
        SafeLogger.selectionReadProgress("messaging-timeout-set")
        let focusedElement = try SelectionElementChain.focusedElement(
            from: systemWideElement,
            reader: elementReader
        )
        SafeLogger.selectionReadProgress("focused-element-ready")
        let candidates = try SelectionElementChain.chain(
            startingAt: focusedElement,
            reader: elementReader
        )
        try SelectionElementChain.preflightSensitiveFields(in: candidates, reader: elementReader)
        return candidates
    }

    /// Detection for apps whose Accessibility text is unreliable.
    ///
    /// Only the presence of a selection is established here; the app's own
    /// Copy command runs later, when an action needs the text. Selecting text
    /// therefore behaves exactly like it does everywhere else: no pasteboard
    /// traffic, no copy command per selection gesture.
    private func readClipboardAssistedSelection(
        from source: SelectionSourceApplication,
        candidates: [AccessibilityElementID]
    ) async throws -> SelectedTextSnapshot {
        // The misreported text stays a hint: it is only used if the copy later
        // comes back empty-handed. A missing hint is not a missing selection,
        // because apps that expose no text at all can still copy it.
        let hint = try? await withAccessibilityContext {
            try self.readAccessibilitySelection(from: source, candidates: candidates)
        }
        if hint == nil {
            // Never wake the assistant on a guess: with nothing selected the
            // host would beep or copy whatever happens to be focused.
            let hasSelection = try await withAccessibilityContext {
                try SelectionElementChain.hasSelection(in: candidates, reader: self.elementReader)
            }
            guard hasSelection else {
                throw SelectionReadingError.noSelection
            }
        }
        let anchor = SelectionAnchor.pointer(pointerLocationProvider.location())
        SafeLogger.selectionAnchorResolved("snapshot=\(SelectionDiagnosticsFormatting.anchor(anchor))")
        return SelectedTextSnapshot(
            text: hint?.text ?? "",
            source: source,
            selectedRange: hint?.selectedRange,
            anchor: anchor,
            // Replacing a selection re-verifies it through the same
            // Accessibility text this path works around, so write-back stays
            // unavailable here instead of writing against a misreported range.
            canReplaceSelection: false,
            isConfirmedSelection: true,
            textOrigin: .deferredToPasteboard
        )
    }

    /// Asks the host app to copy the selection it is holding and returns the
    /// copied text, with the user's pasteboard put back exactly as it was.
    func readDeferredSelectionText(for snapshot: SelectedTextSnapshot) async -> String? {
        guard clipboardAssistedPolicy.allowsClipboardAssistedSelection(from: snapshot.source) else {
            return nil
        }
        let hasSelection = try? await withAccessibilityContext {
            try SelectionElementChain.hasSelection(in: self.focusedSelectionChain(), reader: self.elementReader)
        }
        guard hasSelection == true else {
            SafeLogger.selectionReadProgress("clipboard-assisted-selection-lost")
            return nil
        }
        guard let text = await clipboardSelectionReader.readSelectedText(from: snapshot.source),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            SafeLogger.selectionReadProgress("clipboard-assisted-copy-ignored")
            return nil
        }
        SafeLogger.selectionReadProgress("clipboard-assisted-selection")
        return text
    }

    private func readAccessibilitySelection(
        from source: SelectionSourceApplication,
        candidates: [AccessibilityElementID]
    ) throws -> SelectedTextSnapshot {
        guard let match = try SelectionElementChain.selectedTextMatch(
            in: candidates,
            reader: elementReader
        ) else {
            throw SelectionReadingError.noSelection
        }

        let selectedRange = try SelectionElementChain.selectedRange(
            for: match.element,
            reader: elementReader
        )
        let canReplaceSelection = selectedRange != nil && ((try? (elementReader as? any AccessibilityElementWriting)?
            .isAttributeSettable(kAXSelectedTextAttribute as String, for: match.element)) ?? false)
        let anchor = SelectionAnchor.pointer(pointerLocationProvider.location())
        SafeLogger.selectionAnchorResolved("snapshot=\(SelectionDiagnosticsFormatting.anchor(anchor))")
        return SelectedTextSnapshot(
            text: match.text,
            source: source,
            selectedRange: selectedRange,
            anchor: anchor,
            canReplaceSelection: canReplaceSelection,
            isConfirmedSelection: selectedRange?.isNonEmpty == true || match.evidence == .textMarkerRange
        )
    }

    private func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt + 1 < Self.readAttempts,
              case let .ax(axError) = error as? AccessibilityAdapterError else {
            return false
        }
        return axError == .cannotComplete
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
