import Foundation
import OSLog

enum SafeLogger {
    private static let logger = Logger(subsystem: "com.spotask.app", category: "network")
    private static let selectionLogger = Logger(subsystem: "com.spotask.app", category: "selection")
    nonisolated(unsafe) static var selectionDiagnosticsSink: any SelectionDiagnosticsSink = UserDefaultsSelectionDiagnosticsSink()

    static func networkFailure(status: Int? = nil, url: URL? = nil) {
        var components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        components?.query = nil
        components?.fragment = nil
        let sanitizedURL = components?.url?.absoluteString ?? ""
        logger.error("Request failed. status=\(status ?? 0, privacy: .public) url=\(sanitizedURL, privacy: .public)")
    }

    static func selectionReadStarted(sourceBundleIdentifier: String?) {
        let source = sourceBundleIdentifier ?? "unknown"
        selectionLogger.notice("Selection read started. source=\(source, privacy: .public)")
        recordSelectionEvent("read-started source=\(source)")
    }

    static func selectionReadSucceeded(textLength: Int) {
        selectionLogger.notice("Selection read succeeded. length=\(textLength, privacy: .public)")
        recordSelectionEvent("read-succeeded length=\(textLength)")
    }

    static func selectionReadProgress(_ step: String) {
        selectionLogger.notice("Selection read progress. step=\(step, privacy: .public)")
        recordSelectionEvent("read-progress step=\(step)")
    }

    static func selectionReadFailed(_ error: Error) {
        selectionLogger.error("Selection read failed. error=\(String(describing: error), privacy: .public)")
        recordSelectionEvent("read-failed error=\(String(describing: error))")
    }

    static func selectionValueDecodeFailed(attribute: String, typeIdentifier: CFTypeID) {
        selectionLogger.error("Selection value decode failed. attribute=\(attribute, privacy: .public) type=\(typeIdentifier, privacy: .public)")
        recordSelectionEvent("decode-failed attribute=\(attribute) type=\(typeIdentifier)")
    }

    static func selectionHotKeyRegistered() {
        selectionLogger.notice("Selection hot key registered.")
        recordSelectionEvent("hot-key-registered")
    }

    static func selectionHotKeyRegistrationFailed(_ error: Error) {
        selectionLogger.error("Selection hot key registration failed. error=\(String(describing: error), privacy: .public)")
        recordSelectionEvent("hot-key-registration-failed error=\(String(describing: error))")
    }

    static func selectionHotKeyTriggered() {
        selectionLogger.notice("Selection hot key triggered.")
        recordSelectionEvent("hot-key-triggered")
    }

    static func selectionAnchorResolved(_ details: String) {
        selectionLogger.notice("Selection anchor resolved. \(details, privacy: .public)")
        recordSelectionEvent("anchor-resolved \(details)")
    }

    static func selectionOverlayPresented(_ details: String) {
        selectionLogger.notice("Selection overlay presented. \(details, privacy: .public)")
        recordSelectionEvent("overlay-presented \(details)")
    }

    private static func recordSelectionEvent(_ event: String) {
        selectionDiagnosticsSink.record("\(Date().timeIntervalSince1970) \(event)")
    }
}
