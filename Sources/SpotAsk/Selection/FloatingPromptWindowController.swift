import AppKit
import SwiftUI

@MainActor
protocol FloatingPromptWindowing: AnyObject {
    func show(near anchor: SelectionAnchor)
    func close()
}

@MainActor
final class FloatingPromptCoordinator: FloatingPromptPresenting {
    private let settings: AppSettings
    private let providerFactory: any ChatProviderFactory
    private let commandCenter: SpotAskCommandCenter
    private let modelID: () -> UUID?
    private let makeWindow: (FloatingPromptSession, AppSettings, @escaping (CompletedConversationTurn) -> Void, @escaping () -> Void) -> any FloatingPromptWindowing
    private var windows: [any FloatingPromptWindowing] = []

    var openWindowCount: Int { windows.count }

    init(
        settings: AppSettings,
        providerFactory: any ChatProviderFactory,
        commandCenter: SpotAskCommandCenter,
        modelID: @escaping () -> UUID?,
        makeWindow: ((FloatingPromptSession, AppSettings, @escaping (CompletedConversationTurn) -> Void, @escaping () -> Void) -> any FloatingPromptWindowing)? = nil
    ) {
        self.settings = settings
        self.providerFactory = providerFactory
        self.commandCenter = commandCenter
        self.modelID = modelID
        self.makeWindow = makeWindow ?? Self.liveWindow
    }

    func present(snapshot: SelectedTextSnapshot, preset: PromptPreset) {
        guard !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let session = FloatingPromptSession(
            snapshot: snapshot,
            preset: preset,
            settings: settings,
            providerFactory: providerFactory,
            modelID: modelID()
        )
        let holder = WindowHolder()
        let window = makeWindow(
            session,
            settings,
            { [weak self] turn in
                self?.commandCenter.appendCompletedTurn(turn)
            },
            { [weak self] in
                guard let self, let window = holder.window else { return }
                self.windows.removeAll { $0 === window }
            }
        )
        holder.window = window
        windows.append(window)
        session.start()
        window.show(near: snapshot.anchor)
    }

    private static func liveWindow(
        session: FloatingPromptSession,
        settings: AppSettings,
        onContinue: @escaping (CompletedConversationTurn) -> Void,
        onClosed: @escaping () -> Void
    ) -> any FloatingPromptWindowing {
        FloatingPromptWindowController(
            session: session,
            settings: settings,
            onContinue: onContinue,
            onClosed: onClosed
        )
    }

    private final class WindowHolder {
        weak var window: (any FloatingPromptWindowing)?
    }
}

@MainActor
final class FloatingPromptWindowController: NSObject, FloatingPromptWindowing, NSWindowDelegate {
    let session: FloatingPromptSession
    private let settings: AppSettings
    private let onContinue: (CompletedConversationTurn) -> Void
    private let onClosed: () -> Void
    private var panel: FloatingPromptPanel?
    private var eventMonitors: [Any] = []
    private var appearanceObserver: NSObjectProtocol?
    private var isClosing = false

    init(
        session: FloatingPromptSession,
        settings: AppSettings,
        onContinue: @escaping (CompletedConversationTurn) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.session = session
        self.settings = settings
        self.onContinue = onContinue
        self.onClosed = onClosed
        super.init()
    }

    func show(near anchor: SelectionAnchor) {
        let panel = makePanelIfNeeded()
        let point: NSPoint
        switch anchor {
        case let .pointer(value):
            point = value
        }
        let visible = FloatingPromptPlacement.visibleFrame(containing: point)
        let fitted = FloatingPromptChrome.fitted(panel.frame.size, within: visible)
        if fitted != panel.frame.size {
            panel.setContentSize(fitted)
        }
        let origin = FloatingPromptPlacement.origin(
            anchor: anchor,
            size: panel.frame.size,
            visibleFrame: visible
        )
        panel.setFrameOrigin(origin)
        settings.appearance.apply(to: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        panel.makeKey()
        installMonitorsIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SpotAskPanelFadeMetrics.duration
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        requestClose(.closeButton)
    }

    func requestClose(_ request: FloatingPromptCloseRequest) {
        guard !isClosing else { return }
        guard FloatingPromptDismissal.shouldClose(isPinned: session.isPinned, request: request) else { return }
        if request == .continueInConversation {
            guard let turn = session.completedTurn() else { return }
            onContinue(turn)
        }
        isClosing = true
        removeMonitors()
        session.cancel()
        guard let panel else {
            finishClose()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SpotAskPanelFadeMetrics.duration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finishClose()
            }
        }
    }

    private func finishClose() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        onClosed()
    }

    private func makePanelIfNeeded() -> FloatingPromptPanel {
        if let panel { return panel }
        let size = FloatingPromptChrome.initialSize
        let panel = FloatingPromptPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = session.preset.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = FloatingPromptPlacement.minSize
        panel.contentMinSize = FloatingPromptPlacement.minSize
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.requestClose(.escape)
        }
        let root = FloatingPromptView(
            session: session,
            settings: settings,
            onClose: { [weak self] in self?.requestClose(.closeButton) },
            onContinue: { [weak self] in self?.requestClose(.continueInConversation) }
        )
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let host = FloatingPromptHostingView(rootView: root)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        if #available(macOS 26, *) {
            container.layer?.cornerRadius = FloatingPromptChrome.cornerRadius
            container.layer?.cornerCurve = .continuous
            container.layer?.masksToBounds = true
            container.addSubview(host)
        } else {
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.autoresizingMask = [.width, .height]
            FloatingPromptChrome.applyFallback(to: effect)
            container.addSubview(effect)
            effect.addSubview(host)
        }
        let resize = FloatingPromptResizeBorder(frame: container.bounds)
        resize.autoresizingMask = [.width, .height]
        resize.onResizeEnded = { [weak panel] in
            guard let panel else { return }
            FloatingPromptChrome.remember(panel.frame.size)
            panel.invalidateShadow()
        }
        container.addSubview(resize)
        panel.contentView = container
        settings.appearance.apply(to: panel)
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .spotAskAppearanceChanged,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                self.settings.appearance.apply(to: panel)
            }
        }
        self.panel = panel
        return panel
    }

    private func installMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.handleLocalEvent(event) ?? event
        }) {
            eventMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.closeIfOutside(location)
            }
        }) {
            eventMonitors.append(global)
        }
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard let panel else { return event }
        if event.type == .keyDown, event.keyCode == 53, panel.isKeyWindow {
            requestClose(.escape)
            return nil
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            closeIfOutside(NSEvent.mouseLocation, eventWindow: event.window)
        }
        return event
    }

    private func closeIfOutside(_ location: CGPoint, eventWindow: NSWindow? = nil) {
        guard let panel else { return }
        var attached = panel.childWindows?.map(\.frame) ?? []
        if let eventWindow, eventWindow !== panel, eventWindow.parent === panel {
            attached.append(eventWindow.frame)
        }
        guard FloatingPromptOutsideClick.isOutside(
            mouse: location,
            panelFrame: panel.frame,
            attachedFrames: attached
        ) else { return }
        requestClose(.outsideClick)
    }

    private func removeMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
            self.appearanceObserver = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose(.closeButton)
        return false
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        FloatingPromptChrome.remember(panel.frame.size)
        panel.invalidateShadow()
    }
}

private final class FloatingPromptPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
private enum FloatingPromptChrome {
    static let cornerRadius: CGFloat = 16
    private static var rememberedSize: NSSize?

    static var initialSize: NSSize { rememberedSize ?? FloatingPromptPlacement.defaultSize }

    static func remember(_ size: NSSize) {
        rememberedSize = size
    }

    static func fitted(_ size: NSSize, within visible: NSRect) -> NSSize {
        NSSize(
            width: min(max(size.width, FloatingPromptPlacement.minSize.width), max(visible.width - 16, FloatingPromptPlacement.minSize.width)),
            height: min(max(size.height, FloatingPromptPlacement.minSize.height), max(visible.height - 16, FloatingPromptPlacement.minSize.height))
        )
    }

    /// macOS 15 has no `glassEffect`. Menu material is the frost that still samples
    /// the desktop inside a borderless panel; popover material stays nearly opaque there.
    static func applyFallback(to effect: NSVisualEffectView) {
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = false
        effect.maskImage = maskImage(radius: cornerRadius)
    }

    private static func maskImage(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 2
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { bounds in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private final class FloatingPromptResizeBorder: NSView {
    var onResizeEnded: (() -> Void)?
    private let thickness: CGFloat = 6
    private var edges: Edge = []
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    private struct Edge: OptionSet {
        let rawValue: Int
        static let minX = Edge(rawValue: 1 << 0)
        static let maxX = Edge(rawValue: 1 << 1)
        static let minY = Edge(rawValue: 1 << 2)
        static let maxY = Edge(rawValue: 1 << 3)
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return edges(at: local).isEmpty ? nil : self
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let bounds = self.bounds
        let strips = [
            NSRect(x: 0, y: 0, width: thickness, height: bounds.height),
            NSRect(x: max(bounds.width - thickness, 0), y: 0, width: thickness, height: bounds.height),
            NSRect(x: 0, y: 0, width: bounds.width, height: thickness),
            NSRect(x: 0, y: max(bounds.height - thickness, 0), width: bounds.width, height: thickness),
        ]
        for rect in strips where rect.width > 0 && rect.height > 0 {
            addTrackingArea(NSTrackingArea(
                rect: rect,
                options: [.mouseMoved, .cursorUpdate, .activeAlways],
                owner: self
            ))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        edges = edges(at: local)
        guard !edges.isEmpty, let window else { return }
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard !edges.isEmpty, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        var frame = startFrame
        let min = FloatingPromptPlacement.minSize
        if edges.contains(.minX) {
            let width = max(min.width, startFrame.width - dx)
            frame.origin.x = startFrame.maxX - width
            frame.size.width = width
        }
        if edges.contains(.maxX) {
            frame.size.width = max(min.width, startFrame.width + dx)
        }
        if edges.contains(.minY) {
            let height = max(min.height, startFrame.height - dy)
            frame.origin.y = startFrame.maxY - height
            frame.size.height = height
        }
        if edges.contains(.maxY) {
            frame.size.height = max(min.height, startFrame.height + dy)
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        edges = []
        onResizeEnded?()
    }

    private func edges(at point: NSPoint) -> Edge {
        guard bounds.contains(point) else { return [] }
        var result: Edge = []
        if point.x <= thickness { result.insert(.minX) }
        if point.x >= bounds.width - thickness { result.insert(.maxX) }
        if point.y <= thickness { result.insert(.minY) }
        if point.y >= bounds.height - thickness { result.insert(.maxY) }
        return result
    }

    private func updateCursor(at point: NSPoint) {
        let edge = edges(at: point)
        guard !edge.isEmpty else { return }
        let horizontal = edge.contains(.minX) || edge.contains(.maxX)
        let vertical = edge.contains(.minY) || edge.contains(.maxY)
        if horizontal && vertical {
            let rising = edge.contains(.minX) == edge.contains(.minY)
            (rising ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        } else if horizontal {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.resizeUpDown.set()
        }
    }
}

private final class FloatingPromptHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearBacking()
    }

    override func layout() {
        super.layout()
        clearBacking()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        activateIfNeeded()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        activateIfNeeded()
        super.rightMouseDown(with: event)
    }

    private func clearBacking() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 26, *) {
            layer?.masksToBounds = false
        } else {
            layer?.cornerRadius = FloatingPromptChrome.cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }
    }

    private func activateIfNeeded() {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKey()
    }
}

private struct FloatingPromptView: View {
    @Bindable var session: FloatingPromptSession
    let settings: AppSettings
    let onClose: () -> Void
    let onContinue: () -> Void
    @State private var didCopy = false
    @State private var showsShortcutHints = false
    @State private var showsModelPicker = false
    @State private var shortcutDispatcher: InAppShortcutDispatcher?
    @State private var windowReference = ChatWindowReference()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(FloatingPromptGlass())
        .environment(settings)
        .environment(\.dynamicTypeSize, settings.interfaceZoomLevel.dynamicTypeSize)
        .environment(\.locale, settings.language.locale)
        .preferredColorScheme(settings.appearance.colorScheme)
        .background(ChatWindowReader(reference: windowReference))
        .onAppear(perform: installShortcutDispatcher)
        .onDisappear {
            shortcutDispatcher?.stop()
            shortcutDispatcher = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow) === windowReference.window {
                showsShortcutHints = false
            }
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            didCopy = false
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                BrandMark()
                Text(session.preset.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.fg)
                    .lineLimit(1)
            }
            .allowsHitTesting(false)
            Spacer(minLength: 4)
            headerButton(
                systemName: session.isPinned ? "pin.fill" : "pin",
                label: L10n.string(session.isPinned ? "floatingPrompt.unpin" : "floatingPrompt.pin"),
                action: { session.isPinned.toggle() }
            )
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(.toggleWindowOnTop))
                    .offset(x: 4, y: 4)
            }
            .help(shortcutHelp(
                L10n.string(session.isPinned ? "floatingPrompt.unpin" : "floatingPrompt.pin"),
                operation: .toggleWindowOnTop
            ))
            headerButton(
                systemName: "xmark",
                label: L10n.string("floatingPrompt.close"),
                action: onClose
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(alignment: .center) {
            modelMenu
                .fixedSize()
        }
        .background(WindowDragHandle())
    }

    private var modelMenu: some View {
        ModelPickerHeaderButton(
            modelName: session.modelDisplayName ?? "",
            providerIconSlug: ProviderBrandIconMatcher.match(
                providerName: session.providerName,
                modelName: session.modelDisplayName
            ),
            isDisabled: false,
            isPresented: $showsModelPicker
        ) {
            ModelPickerContent(
                catalog: settings.providerRegistry.catalog,
                effectiveModelID: session.modelID ?? settings.providerRegistry.catalog?.selectedModelID,
                hasSessionOverride: session.modelID != nil,
                isDisabled: false,
                onSelect: { modelID in
                    showsModelPicker = false
                    session.answer(using: modelID)
                },
                onUseDefault: {
                    showsModelPicker = false
                    session.answer(using: nil)
                }
            )
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if session.answer.isEmpty {
                    status
                } else {
                    MarkdownTextView(content: session.answer, rendersMath: settings.renderMath)
                    if session.phase == .failed, let description = session.error?.errorDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .idle, .connecting, .streaming:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.string("chat.generating"))
                    .font(.callout)
                    .foregroundStyle(Brand.muted)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text(session.error?.errorDescription ?? L10n.string("chat.requestFailed"))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if session.canRetry {
                    Button(L10n.string("chat.retry"), action: session.retry)
                        .buttonStyle(.bordered)
                }
            }
        case .complete, .cancelled:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: copyAll) {
                Label(
                    L10n.string(didCopy ? "chat.copied" : "floatingPrompt.copyAll"),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!session.canCopy)
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(.copyAnswer))
                    .offset(x: 4, y: 4)
            }
            .help(shortcutHelp(L10n.string("floatingPrompt.copyAll"), operation: .copyAnswer))
            Spacer(minLength: 8)
            if session.canRetry, !session.answer.isEmpty {
                Button(L10n.string("chat.retry"), action: session.retry)
                    .buttonStyle(.bordered)
                    .overlay(alignment: .bottomTrailing) {
                        ShortcutKeycap(shortcut: shortcutHint(.regenerateOrRetry))
                            .offset(x: 4, y: 4)
                    }
                    .help(shortcutHelp(L10n.string("chat.retry"), operation: .regenerateOrRetry))
            }
            Button(action: onContinue) {
                Label(L10n.string("floatingPrompt.continueInChat"), systemImage: "quote.bubble")
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
            .disabled(!session.canContinue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func headerButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Brand.fg)
        .help(label)
        .accessibilityLabel(label)
    }

    private func copyAll() {
        guard session.copyAnswer(to: .general) else { return }
        didCopy = true
    }

    private func installShortcutDispatcher() {
        guard shortcutDispatcher == nil else { return }
        let dispatcher = InAppShortcutDispatcher(
            settings: settings,
            isForeground: { [windowReference] in
                guard let window = windowReference.window else { return false }
                return window === NSApp.keyWindow && window.isKeyWindow
            },
            hasMarkedText: { [windowReference] in
                responderHasMarkedText(windowReference.window?.firstResponder)
            },
            handleTarget: { performShortcut($0) },
            setHintsVisible: { showsShortcutHints = $0 }
        )
        dispatcher.start()
        shortcutDispatcher = dispatcher
    }

    private func performShortcut(_ target: InAppShortcutTarget) -> Bool {
        FloatingPromptShortcut.perform(
            target,
            session: session,
            settings: settings,
            copy: {
                let copied = session.copyAnswer(to: .general)
                if copied { didCopy = true }
                return copied
            },
            showSettings: { SpotAskCommandCenter.shared.showSettings() }
        )
    }

    private func shortcutHint(_ operation: InAppShortcutOperation) -> InAppShortcut? {
        inAppShortcutHint(settings.shortcut(for: .operation(operation)), commandHintsVisible: showsShortcutHints)
    }

    private func shortcutHelp(_ label: String, operation: InAppShortcutOperation) -> String {
        guard let shortcut = settings.shortcut(for: .operation(operation)) else { return label }
        return "\(label) (\(InAppShortcutDisplay.text(for: shortcut)))"
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct FloatingPromptGlass: ViewModifier {
    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                RoundedRectangle(cornerRadius: FloatingPromptChrome.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if #available(macOS 26, *) {
            // Liquid Glass has to sit behind the answer. Applying it to the
            // content itself drops both inline Canvas symbols and display
            // SVGs, so the formula keeps its gap and draws nothing. The
            // question window uses the same behind-content glass.
            content.background {
                Color.clear.glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: FloatingPromptChrome.cornerRadius, style: .continuous)
                )
            }
        } else {
            content.background(Color.clear)
        }
    }
}
