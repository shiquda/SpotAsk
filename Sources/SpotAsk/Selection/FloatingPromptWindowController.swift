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
        let origin = FloatingPromptPlacement.origin(
            anchor: anchor,
            size: panel.frame.size,
            visibleFrame: FloatingPromptPlacement.visibleFrame(containing: point)
        )
        panel.setFrameOrigin(origin)
        settings.appearance.apply(to: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
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
        let size = FloatingPromptPlacement.defaultSize
        let panel = FloatingPromptPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
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
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
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
        let host = FloatingPromptHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        host.sizingOptions = []
        panel.contentView = host
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
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
            Task { @MainActor in
                self?.requestClose(.outsideClick)
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
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           !panel.frame.contains(NSEvent.mouseLocation) {
            requestClose(.outsideClick)
        }
        return event
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
}

private final class FloatingPromptPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class FloatingPromptHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        activateIfNeeded()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        activateIfNeeded()
        super.rightMouseDown(with: event)
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
    @State private var shortcutDispatcher: InAppShortcutDispatcher?
    @State private var windowReference = ChatWindowReference()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Brand.border)
            content
            Divider().overlay(Brand.border)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
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
        HStack(spacing: 8) {
            Image(systemName: session.preset.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .allowsHitTesting(false)
            Text(session.preset.title)
                .font(.headline)
                .foregroundStyle(Brand.fg)
                .lineLimit(1)
                .allowsHitTesting(false)
            Spacer(minLength: 8)
            if let model = session.modelDisplayName, !model.isEmpty {
                Text(model)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
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
        .background(HeaderMaterial())
        .background(WindowDragHandle())
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if session.answer.isEmpty {
                    status
                } else {
                    MarkdownTextView(content: session.answer)
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
            Button(L10n.string("floatingPrompt.continueInChat"), action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .disabled(!session.canContinue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Brand.surface)
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
