import AppKit
import SwiftUI

enum SpotAskPanelFadeMetrics {
    static let duration: TimeInterval = 0.15
}

@MainActor
protocol SpotAskPanelFadeTarget: AnyObject, Sendable {
    var isVisible: Bool { get }
    var alphaValue: CGFloat { get set }
    func makeKeyAndOrderFront(_ sender: Any?)
    func orderOut(_ sender: Any?)
    func animateAlpha(to value: CGFloat, duration: TimeInterval, completion: @escaping () -> Void)
}

@MainActor
final class SpotAskPanelFadeCoordinator {
    private enum Direction {
        case showing
        case hiding
    }

    private var currentAnimationToken = 0
    private var direction: Direction?
    private var animatedTarget: (any SpotAskPanelFadeTarget)?

    var isHiding: Bool { direction == .hiding }

    func show(_ target: any SpotAskPanelFadeTarget) {
        if !target.isVisible {
            target.alphaValue = 0
        }
        target.makeKeyAndOrderFront(nil)
        beginAnimation(target, to: 1, direction: .showing)
    }

    func hide(_ target: any SpotAskPanelFadeTarget) {
        guard target.isVisible else {
            cancelCurrentAnimation()
            target.alphaValue = 1
            target.orderOut(nil)
            return
        }
        beginAnimation(target, to: 0, direction: .hiding)
    }

    private func beginAnimation(
        _ target: any SpotAskPanelFadeTarget,
        to value: CGFloat,
        direction: Direction
    ) {
        cancelCurrentAnimation()
        let token = currentAnimationToken
        self.direction = direction

        if value == 0, target.alphaValue <= 0.001 {
            finishHide(target)
            return
        }

        if value == 1, target.alphaValue >= 0.999 {
            self.direction = nil
            return
        }

        animatedTarget = target
        target.animateAlpha(to: value, duration: SpotAskPanelFadeMetrics.duration) { [weak self, weak target] in
            guard let self, let target else { return }
            guard self.currentAnimationToken == token else { return }
            self.direction = nil
            self.animatedTarget = nil
            if value == 0 {
                self.finishHide(target)
            }
        }
    }

    private func cancelCurrentAnimation() {
        currentAnimationToken += 1
        direction = nil
        animatedTarget = nil
    }

    private func finishHide(_ target: any SpotAskPanelFadeTarget) {
        direction = nil
        animatedTarget = nil
        target.orderOut(nil)
        target.alphaValue = 1
    }
}

extension Notification.Name {
    static let spotAskHotKeyChanged = Notification.Name("com.spotask.hot-key-changed")
    static let spotAskLanguageChanged = Notification.Name("com.spotask.language-changed")
}

@MainActor
protocol SpotAskPanelControlling: AnyObject {
    func setContent(_ content: @escaping () -> AnyView)
    func show()
    func hide()
    func toggle()
    func toggleWindowOnTop()
    var isVisible: Bool { get }
}

@MainActor
final class SpotAskPanelController: NSObject, NSWindowDelegate, SpotAskPanelControlling {
    private let settings: AppSettings
    private var panel: SpotAskPanel?
    private var contentBuilder: (() -> AnyView)?
    private var shouldCenterNormalizedInitialSize = false
    private let fadeCoordinator = SpotAskPanelFadeCoordinator()

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyCurrentAppearance),
            name: .spotAskAppearanceChanged,
            object: settings
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setContent(_ content: @escaping () -> AnyView) {
        contentBuilder = content
        if let panel {
            panel.contentView = NSHostingView(rootView: content())
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        applyCurrentAppearance()
        constrain(panel)
        if shouldCenterNormalizedInitialSize {
            center(panel)
            shouldCenterNormalizedInitialSize = false
        } else {
            restorePositionOrCenter(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        fadeCoordinator.show(SpotAskPanelFadeTargetAdapter(panel: panel))
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        }
    }

    func hide() {
        guard let panel else { return }
        fadeCoordinator.hide(SpotAskPanelFadeTargetAdapter(panel: panel))
    }

    func toggle() {
        if fadeCoordinator.isHiding {
            show()
            return
        }
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
        settings.panelOrigin = panel.frame.origin
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        settings.panelOrigin = panel.frame.origin
    }

    private func makePanelIfNeeded() -> SpotAskPanel {
        if let panel { return panel }

        let initialSize = normalizedInitialSize()
        shouldCenterNormalizedInitialSize = initialSize.width > settings.panelWidth
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
        panel.isMovableByWindowBackground = true
        settings.appearance.apply(to: panel)
        applyWindowLevel(panel)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.minSize = NSSize(width: 364, height: 320)
        panel.delegate = self
        if let contentBuilder {
            panel.contentView = NSHostingView(rootView: contentBuilder())
        }
        applyContentCornerRadius(panel)
        self.panel = panel
        return panel
    }

    /// Avoid restoring an overly narrow, portrait-like panel while retaining
    /// the user's chosen height. A corrected frame is centered once on launch.
    private func normalizedInitialSize() -> NSSize {
        let height = settings.panelHeight
        return NSSize(
            width: max(settings.panelWidth, height * 1.5),
            height: height
        )
    }

    private func applyWindowLevel(_ panel: NSPanel?) {
        guard let panel else { return }
        panel.level = settings.keepWindowOnTop ? .floating : .normal
        panel.isFloatingPanel = settings.keepWindowOnTop
    }

    @objc private func applyCurrentAppearance() {
        guard let panel else { return }
        settings.appearance.apply(to: panel)
    }

    /// Match the header's continuous geometry without relying on a private
    /// NSWindow API. Apply this after the SwiftUI hosting view is installed.
    private func applyContentCornerRadius(_ panel: SpotAskPanel) {
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
    }

    /// Restores the saved frame when it is still reachable on a connected
    /// display; otherwise (first launch, or the display was unplugged) centers
    /// on the screen that has the mouse.
    private func restorePositionOrCenter(_ panel: NSPanel) {
        if let origin = settings.panelOrigin {
            let restored = NSRect(origin: origin, size: panel.frame.size)
            let isReachable = NSScreen.screens.contains { screen in
                let overlap = screen.visibleFrame.intersection(restored)
                return !overlap.isNull && overlap.width >= 120 && overlap.height >= 120
            }
            if isReachable {
                panel.setFrameOrigin(restored.origin)
                return
            }
        }
        center(panel)
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

@MainActor
private final class SpotAskPanelFadeTargetAdapter: SpotAskPanelFadeTarget {
    private let panel: SpotAskPanel

    init(panel: SpotAskPanel) {
        self.panel = panel
    }

    var isVisible: Bool { panel.isVisible }

    var alphaValue: CGFloat {
        get { panel.alphaValue }
        set { panel.alphaValue = newValue }
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        panel.makeKeyAndOrderFront(sender)
    }

    func orderOut(_ sender: Any?) {
        panel.orderOut(sender)
    }

    func animateAlpha(to value: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = duration
                panel.animator().alphaValue = value
            },
            completionHandler: { completion() }
        )
    }
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first(where: { $0.frame.contains(mouseLocation) })
    }
}
