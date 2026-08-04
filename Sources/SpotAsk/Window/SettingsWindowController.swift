import AppKit
import SwiftUI

@MainActor
func responderHasMarkedText(_ responder: NSResponder?) -> Bool {
    var currentResponder = responder
    while let current = currentResponder {
        if let textView = current as? NSTextView, textView.hasMarkedText() {
            return true
        }
        currentResponder = current.nextResponder
    }
    return false
}

private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        guard !responderHasMarkedText(firstResponder) else { return }
        performClose(sender)
    }
}

/// Presents `SettingsView` in a standard, independent macOS window instead of
/// an attached sheet. The window is titled, draggable, closable via its normal
/// close control, and reusable: repeated requests bring the same window to the
/// front rather than stacking duplicates. Closing the window reports back
/// through `onClose` so the caller's presentation flag stays in sync.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let keyStore: any APIKeyStoring
    private let providerFactory: any ChatProviderFactory
    private let onClose: () -> Void

    private var window: NSWindow?

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        onClose: @escaping () -> Void
    ) {
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
        self.onClose = onClose
        super.init()
    }

    /// Shows the settings window, creating it on first use and bringing it to
    /// the front on every subsequent request.
    func show() {
        let window = makeWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let rootView = SettingsView(
            settings: settings,
            keyStore: keyStore,
            providerFactory: providerFactory
        )
        let hostingView = NSHostingView(rootView: rootView)

        // SettingsView carries a fixed 860×590 frame; size the window to fit it.
        let contentRect = NSRect(origin: .zero, size: NSSize(width: 860, height: 590))
        let window = SettingsWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("settings.title")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        return window
    }
}
