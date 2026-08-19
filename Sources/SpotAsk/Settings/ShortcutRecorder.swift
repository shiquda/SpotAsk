import AppKit
import Foundation
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: InAppShortcut?
    let onRecord: (InAppShortcut) -> Void
    let onInvalid: () -> Void
    var allowsSpace: Bool = false

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.setAccessibilityRole(.textField)
        field.onRecord = onRecord
        field.onInvalid = onInvalid
        field.allowsSpace = allowsSpace
        return field
    }

    func updateNSView(_ field: ShortcutRecorderField, context: Context) {
        field.update(shortcut: shortcut)
        field.onRecord = onRecord
        field.onInvalid = onInvalid
        field.allowsSpace = allowsSpace
    }
}

final class ShortcutRecorderField: NSTextField {
    var onRecord: ((InAppShortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var allowsSpace = false
    private var monitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var displayedShortcut: InAppShortcut?
    private var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        alignment = .center
        font = .systemFont(ofSize: 12, weight: .medium)
        focusRingType = .default
        lineBreakMode = .byTruncatingMiddle
        wantsLayer = true
        layer?.cornerRadius = 5
        updateRecordingAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            removeMonitor()
            removeWindowObservers()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startCapturing()
    }

    func update(shortcut: InAppShortcut?) {
        displayedShortcut = shortcut
        if !isCapturing {
            stringValue = InAppShortcutDisplay.text(for: shortcut)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        removeWindowObservers()
        guard let window else { return }
        windowObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.installMonitorIfNeeded()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopCapturing()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeMonitor()
                }
            }
        ]
        installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil, isCapturing, window?.isKeyWindow == true else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isCapturing, self.window?.isKeyWindow == true else { return event }
            return self.handleCaptureEvent(event)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        stopCapturing()
        return result
    }

    private func startCapturing() {
        isCapturing = true
        stringValue = L10n.string("settings.shortcutRecording")
        updateRecordingAppearance()
        window?.makeFirstResponder(self)
        installMonitorIfNeeded()
    }

    private func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false
        removeMonitor()
        stringValue = InAppShortcutDisplay.text(for: displayedShortcut)
        updateRecordingAppearance()
    }

    private func updateRecordingAppearance() {
        guard let layer else { return }
        layer.cornerRadius = 5
        layer.borderWidth = isCapturing ? 1.5 : 1
        layer.borderColor = isCapturing
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        _ = handleCaptureEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else {
            return super.performKeyEquivalent(with: event)
        }
        _ = handleCaptureEvent(event)
        return true
    }

    private func handleCaptureEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            return nil
        }
        if ShortcutRecorderEventParser.isCancelKey(event) {
            stopCapturing()
            return nil
        }
        guard let shortcut = ShortcutRecorderEventParser.shortcut(from: event, allowsSpace: allowsSpace) else {
            onInvalid?()
            NSSound.beep()
            return nil
        }
        stopCapturing()
        onRecord?(shortcut)
        return nil
    }
}

enum ShortcutRecorderEventParser {
    static func shortcut(from event: NSEvent, allowsSpace: Bool = false) -> InAppShortcut? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var shortcutModifiers: InAppShortcutModifiers = []
        if modifiers.contains(.command) { shortcutModifiers.insert(.command) }
        if modifiers.contains(.shift) { shortcutModifiers.insert(.shift) }
        if modifiers.contains(.option) { shortcutModifiers.insert(.option) }
        if modifiers.contains(.control) { shortcutModifiers.insert(.control) }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        let shortcut = InAppShortcut(key: key, modifiers: shortcutModifiers)
        return (shortcut.isSupported || (allowsSpace && shortcut.isSupportedGlobalShortcut)) ? shortcut : nil
    }

    static func isCancelKey(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == 53
    }
}
