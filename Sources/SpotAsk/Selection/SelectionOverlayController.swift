import AppKit

@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayControlling {
    private static let controlSize = NSSize(width: 28, height: 28)
    private static let contentInset: CGFloat = 4
    private static let controlSpacing: CGFloat = 2

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var buttonTargets: [OverlayButtonTarget] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func showActions(snapshot: SelectedTextSnapshot, presets: [PromptPreset], onSelect: @escaping (PromptPreset) -> Void) {
        let size = actionBarSize(for: presets.count)
        let content = makeContainer(size: size)
        buttonTargets = presets.enumerated().map { index, preset in
            let target = OverlayButtonTarget { onSelect(preset) }
            let button = NSButton(frame: NSRect(
                x: Self.contentInset + CGFloat(index) * (Self.controlSize.width + Self.controlSpacing),
                y: Self.contentInset,
                width: Self.controlSize.width,
                height: Self.controlSize.height
            ))
            if let image = NSImage(systemSymbolName: preset.symbolName, accessibilityDescription: preset.title) {
                button.image = image.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            }
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .labelColor
            button.toolTip = preset.title
            button.target = target
            button.action = #selector(OverlayButtonTarget.invoke)
            button.setAccessibilityLabel(preset.title)
            content.addSubview(button)
            return target
        }
        present(content: content, size: size, anchor: snapshot.anchor)
        scheduleDismiss(after: 8)
    }

    func showMessage(_ message: SelectionFeedback) {
        let size = NSSize(width: 276, height: 44)
        let content = makeContainer(size: size)
        content.addSubview(makeLabel(
            message.title,
            frame: NSRect(x: 12, y: 10, width: size.width - 24, height: 24)
        ))
        present(content: content, size: size, anchor: .pointer(NSEvent.mouseLocation))
        scheduleDismiss(after: 2)
    }

    func showPermissionDenied(openSettings: @escaping () -> Void) {
        let size = NSSize(width: 410, height: 44)
        let content = makeContainer(size: size)
        content.addSubview(makeLabel(
            SelectionFeedback.permissionDenied.title,
            frame: NSRect(x: 12, y: 10, width: 234, height: 24)
        ))

        let target = OverlayButtonTarget { [weak self] in
            self?.hide()
            openSettings()
        }
        buttonTargets = [target]
        let button = NSButton(title: L10n.string("selection.permissionOpenSettings"), target: target, action: #selector(OverlayButtonTarget.invoke))
        button.frame = NSRect(x: 254, y: 7, width: 144, height: 30)
        button.bezelStyle = .rounded
        button.controlSize = .small
        content.addSubview(button)

        present(content: content, size: size, anchor: .pointer(NSEvent.mouseLocation))
        scheduleDismiss(after: 5)
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        buttonTargets.removeAll()
        endOutsideClickMonitoring()
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(content: NSView, size: NSSize, anchor: SelectionAnchor) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)

        let panel = makePanel(size: size)
        panel.contentView = content
        let origin = panelOrigin(for: anchor, size: size)
        SafeLogger.selectionOverlayPresented(
            "anchor=\(formatted(anchor)) origin=\(formatted(origin)) size=\(formatted(size))"
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        beginOutsideClickMonitoring()
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makeContainer(size: NSSize) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        return view
    }

    private func makeLabel(_ title: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }

    private func actionBarSize(for presetCount: Int) -> NSSize {
        let controlsWidth = CGFloat(presetCount) * Self.controlSize.width
        let spacingWidth = CGFloat(max(0, presetCount - 1)) * Self.controlSpacing
        return NSSize(
            width: max(44, controlsWidth + spacingWidth + Self.contentInset * 2),
            height: Self.controlSize.height + Self.contentInset * 2
        )
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }

    private func beginOutsideClickMonitoring() {
        endOutsideClickMonitoring()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismissForOutsideClickIfNeeded()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissForOutsideClickIfNeeded()
            return event
        }
    }

    private func endOutsideClickMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func dismissForOutsideClickIfNeeded() {
        guard let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        hide()
    }

    private func panelOrigin(for anchor: SelectionAnchor, size: NSSize) -> NSPoint {
        let point: NSPoint
        switch anchor {
        case let .selectionRect(rect), let .elementRect(rect): point = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        case let .pointer(pointValue): point = NSPoint(x: pointValue.x + 8, y: pointValue.y - size.height - 8)
        }
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return point }
        return NSPoint(x: min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8), y: min(max(point.y, visible.minY + 8), visible.maxY - size.height - 8))
    }

    private func formatted(_ anchor: SelectionAnchor) -> String {
        switch anchor {
        case let .selectionRect(rect): "selection=\(formatted(rect))"
        case let .elementRect(rect): "element=\(formatted(rect))"
        case let .pointer(point): "pointer=\(formatted(point))"
        }
    }

    private func formatted(_ rect: CGRect) -> String {
        String(format: "(%.1f,%.1f,%.1f,%.1f)", rect.minX, rect.minY, rect.width, rect.height)
    }

    private func formatted(_ point: NSPoint) -> String {
        String(format: "(%.1f,%.1f)", point.x, point.y)
    }

    private func formatted(_ size: NSSize) -> String {
        String(format: "(%.1f,%.1f)", size.width, size.height)
    }
}

private final class OverlayButtonTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

private extension SelectionFeedback {
    var title: String {
        switch self {
        case .permissionDenied: "需要允许 SpotAsk 读取你主动选中的文字。"
        case .noSelection: "请先选中文字，再试一次。"
        case .unsupported: "无法读取这个应用中的选中文字。"
        case .temporaryFailure: "暂时无法读取选中的文字，请重试。"
        case .selectionChanged: "选区已改变，请重新触发。"
        case .sensitiveField: "无法处理安全输入区域中的内容。"
        }
    }
}
