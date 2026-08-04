import AppKit
import SwiftUI

/// Routes configured shortcuts only while the SpotAsk chat window is key.
/// It deliberately sits before AppKit's responder chain so a focused composer
/// receives the same remapped behavior as every other chat control.
@MainActor
final class InAppShortcutDispatcher {
    typealias TargetHandler = (InAppShortcutTarget) -> Bool

    private let settings: AppSettings
    private let isForeground: () -> Bool
    private let hasMarkedText: () -> Bool
    private let handleTarget: TargetHandler
    private let setHintsVisible: (Bool) -> Void
    private var monitor: Any?

    init(
        settings: AppSettings,
        isForeground: @escaping () -> Bool,
        hasMarkedText: @escaping () -> Bool,
        handleTarget: @escaping TargetHandler,
        setHintsVisible: @escaping (Bool) -> Void
    ) {
        self.settings = settings
        self.isForeground = isForeground
        self.hasMarkedText = hasMarkedText
        self.handleTarget = handleTarget
        self.setHintsVisible = setHintsVisible
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.process(event) ?? event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        setHintsVisible(false)
    }

    func process(_ event: NSEvent) -> NSEvent? {
        guard isForeground() else {
            setHintsVisible(false)
            return event
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .flagsChanged {
            setHintsVisible(modifiers.contains(.command))
            return event
        }

        guard event.type == .keyDown,
              !hasMarkedText(),
              let shortcut = shortcut(for: event),
              let target = settings.shortcutTarget(for: shortcut),
              handleTarget(target) else {
            return event
        }
        return nil
    }

    private func shortcut(for event: NSEvent) -> InAppShortcut? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var shortcutModifiers: InAppShortcutModifiers = []
        if modifiers.contains(.command) { shortcutModifiers.insert(.command) }
        if modifiers.contains(.shift) { shortcutModifiers.insert(.shift) }
        if modifiers.contains(.option) { shortcutModifiers.insert(.option) }
        if modifiers.contains(.control) { shortcutModifiers.insert(.control) }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let shortcut = InAppShortcut(key: key, modifiers: shortcutModifiers)
        return shortcut.isSupported ? shortcut : nil
    }
}

@MainActor
final class ChatWindowReference {
    weak var window: NSWindow?
}

struct ChatWindowReader: NSViewRepresentable {
    let reference: ChatWindowReference

    func makeNSView(context: Context) -> NSView {
        WindowReaderView(reference: reference)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowReaderView)?.reference = reference
    }
}

@MainActor
private final class WindowReaderView: NSView {
    var reference: ChatWindowReference

    init(reference: ChatWindowReference) {
        self.reference = reference
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reference.window = window
    }
}

enum InAppShortcutDisplay {
    static func text(for shortcut: InAppShortcut?) -> String {
        guard let shortcut else { return L10n.string("settings.shortcutUnassigned") }
        return labels(for: shortcut).joined(separator: " + ")
    }

    static func labels(for shortcut: InAppShortcut, includeCommand: Bool = true) -> [String] {
        var labels: [String] = []
        if includeCommand, shortcut.modifiers.contains(.command) { labels.append("⌘") }
        if shortcut.modifiers.contains(.shift) { labels.append("⇧") }
        if shortcut.modifiers.contains(.option) { labels.append("⌥") }
        if shortcut.modifiers.contains(.control) { labels.append("⌃") }
        labels.append(shortcut.key.uppercased())
        return labels
    }
}

func inAppShortcutHint(_ shortcut: InAppShortcut?, commandHintsVisible: Bool) -> InAppShortcut? {
    commandHintsVisible ? shortcut : nil
}
