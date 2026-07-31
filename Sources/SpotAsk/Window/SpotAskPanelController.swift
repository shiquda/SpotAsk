import AppKit
import SwiftUI

extension Notification.Name {
    static let spotAskFocusInput = Notification.Name("com.spotask.focus-input")
    static let spotAskNewConversation = Notification.Name("com.spotask.new-conversation")
    static let spotAskAskQuestion = Notification.Name("com.spotask.ask-question")
    static let spotAskSelectPromptPreset = Notification.Name("com.spotask.select-prompt-preset")
    static let spotAskShowSettings = Notification.Name("com.spotask.show-settings")
    static let spotAskHotKeyChanged = Notification.Name("com.spotask.hot-key-changed")
    static let spotAskLanguageChanged = Notification.Name("com.spotask.language-changed")
}

extension Notification {
    static func spotAskSelectPromptPreset(_ promptPreset: PromptPreset) -> Notification {
        Notification(
            name: .spotAskSelectPromptPreset,
            object: nil,
            userInfo: ["promptPresetID": promptPreset.id.uuidString]
        )
    }

    static func spotAskAskQuestion(_ question: String, promptPreset: PromptPreset? = nil) -> Notification {
        var userInfo: [String: Any] = ["question": question]
        if let promptPreset { userInfo["promptPresetID"] = promptPreset.id.uuidString }
        return Notification(name: .spotAskAskQuestion, object: nil, userInfo: userInfo)
    }
}

@MainActor
final class SpotAskPanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private var panel: SpotAskPanel?
    private var contentBuilder: (() -> AnyView)?

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func setContent(@ViewBuilder _ content: @escaping () -> some View) {
        contentBuilder = { AnyView(content()) }
        if let panel {
            panel.contentView = NSHostingView(rootView: content())
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        constrain(panel)
        center(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .spotAskFocusInput, object: nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let panel, panel.isVisible else {
            show()
            return
        }
        hide()
    }

    func toggleWindowOnTop() {
        settings.keepWindowOnTop.toggle()
        applyWindowLevel(panel)
    }

    var isVisible: Bool { panel?.isVisible == true }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        settings.panelWidth = panel.frame.width
        settings.panelHeight = panel.frame.height
    }

    private func makePanelIfNeeded() -> SpotAskPanel {
        if let panel { return panel }

        let initialSize = NSSize(width: settings.panelWidth, height: settings.panelHeight)
        let panel = SpotAskPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "SpotAsk"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        applyWindowLevel(panel)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.minSize = NSSize(width: 520, height: 320)
        panel.delegate = self
        if let contentBuilder {
            panel.contentView = NSHostingView(rootView: contentBuilder())
        }
        self.panel = panel
        return panel
    }

    private func applyWindowLevel(_ panel: NSPanel?) {
        guard let panel else { return }
        panel.level = settings.keepWindowOnTop ? .floating : .normal
        panel.isFloatingPanel = settings.keepWindowOnTop
    }

    private func center(_ panel: NSPanel) {
        let screen = NSScreen.screenContainingMouse ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        ))
    }

    private func constrain(_ panel: NSPanel) {
        guard let screen = NSScreen.screenContainingMouse ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let size = NSSize(
            width: min(max(panel.frame.width, panel.minSize.width), visibleFrame.width),
            height: min(max(panel.frame.height, panel.minSize.height), visibleFrame.height)
        )
        panel.maxSize = visibleFrame.size
        panel.setContentSize(size)
    }
}

private final class SpotAskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first(where: { $0.frame.contains(mouseLocation) })
    }
}
