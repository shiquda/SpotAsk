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
    private static let messagingTimeout: TimeInterval = 1
    private static let readAttempts = 2
    private static let retryDelay: TimeInterval = 0.1
    private static let clipboardCopyTimeout: TimeInterval = 0.5
    private static let clipboardPollInterval: TimeInterval = 0.01

    private let permissionChecker: any AccessibilityPermissionChecking
    private let applicationProvider: any ForegroundSelectionApplicationProviding
    private let elementReader: any AccessibilityElementReading
    private let pointerLocationProvider: any PointerLocationProviding
    private let clipboardAssistedSelectionPolicy: any ClipboardAssistedSelectionPolicy
    private let copyTrigger: any SelectionCopyTriggering
    private let pasteboard: any PasteboardAccessing
    private let queue: DispatchQueue

    init(
        permissionChecker: any AccessibilityPermissionChecking = MacOSAccessibilityPermissionChecker(),
        applicationProvider: any ForegroundSelectionApplicationProviding = MacOSForegroundSelectionApplicationProvider(),
        elementReader: any AccessibilityElementReading = MacOSAccessibilityElementAdapter(),
        pointerLocationProvider: any PointerLocationProviding = MacOSPointerLocationProvider(),
        clipboardAssistedSelectionPolicy: any ClipboardAssistedSelectionPolicy = UserDefaultsClipboardAssistedSelectionPolicy(),
        copyTrigger: any SelectionCopyTriggering = MacOSSelectionCopyTrigger(),
        pasteboard: any PasteboardAccessing = SystemPasteboard()
    ) {
        self.permissionChecker = permissionChecker
        self.applicationProvider = applicationProvider
        self.elementReader = elementReader
        self.pointerLocationProvider = pointerLocationProvider
        self.clipboardAssistedSelectionPolicy = clipboardAssistedSelectionPolicy
        self.copyTrigger = copyTrigger
        self.pasteboard = pasteboard
        queue = DispatchQueue(label: "com.spotask.selection.accessibility", qos: .userInitiated)
    }

    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
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

        if clipboardAssistedSelectionPolicy.isEnabled(for: source) {
            return try readSelectionUsingClipboard(from: source, candidates: candidates)
        }

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
        let anchor = SelectionAnchor.pointer(pointerLocationProvider.location())
        SafeLogger.selectionAnchorResolved("snapshot=\(SelectionDiagnosticsFormatting.anchor(anchor))")
        return SelectedTextSnapshot(
            text: match.text,
            source: source,
            selectedRange: selectedRange,
            anchor: anchor,
            canReplaceSelection: canReplaceSelection(in: match.element, range: selectedRange),
            isConfirmedSelection: selectedRange?.isNonEmpty == true || match.evidence == .textMarkerRange
        )
    }

    /// Reads the selection by running the source app's own Copy command and
    /// putting the user's clipboard back, for apps whose accessibility tree
    /// reports the selection text inaccurately.
    private func readSelectionUsingClipboard(
        from source: SelectionSourceApplication,
        candidates: [AccessibilityElementID]
    ) throws -> SelectedTextSnapshot {
        guard let evidence = try SelectionElementChain.selectionEvidence(in: candidates, reader: elementReader) else {
            throw SelectionReadingError.noSelection
        }

        let backup = pasteboard.snapshot()
        defer { pasteboard.restore(backup) }

        SafeLogger.selectionReadProgress("clipboard-assisted-copy")
        let applicationElement = try elementReader.makeApplicationElement(processIdentifier: source.processIdentifier)
        copyTrigger.triggerCopy(in: applicationElement)
        let text = try copiedText(since: backup.changeCount)
        SafeLogger.selectionReadProgress("clipboard-assisted-restore")

        return SelectedTextSnapshot(
            text: text,
            source: source,
            selectedRange: evidence.range,
            anchor: SelectionAnchor.pointer(pointerLocationProvider.location()),
            canReplaceSelection: canReplaceSelection(in: evidence.element, range: evidence.range),
            isConfirmedSelection: true
        )
    }

    /// Waits for the app to write its copy to the pasteboard. Reading the plain
    /// text is enough: the copy that arrives also proves the copy happened.
    private func copiedText(since changeCount: Int) throws -> String {
        let deadline = Date().addingTimeInterval(Self.clipboardCopyTimeout)
        var copyObserved = false
        while Date() < deadline {
            if pasteboard.changeCount != changeCount {
                copyObserved = true
            }
            if copyObserved,
               let text = pasteboard.string(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            Thread.sleep(forTimeInterval: Self.clipboardPollInterval)
        }
        throw copyObserved ? SelectionReadingError.noSelection : SelectionReadingError.applicationUnresponsive
    }

    private func canReplaceSelection(
        in element: AccessibilityElementID,
        range: SelectionCharacterRange?
    ) -> Bool {
        guard range != nil else { return false }
        let writer = elementReader as? any AccessibilityElementWriting
        return (try? writer?.isAttributeSettable(kAXSelectedTextAttribute as String, for: element)) ?? false
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
