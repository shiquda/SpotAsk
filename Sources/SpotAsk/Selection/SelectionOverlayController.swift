import AppKit

enum SelectionActionBarLayout {
    static let controlSize = NSSize(width: 28, height: 28)
    static let contentInset: CGFloat = 4
    static let controlSpacing: CGFloat = 2
    static let labelFontSize: CGFloat = 12
    static let maxBarWidth: CGFloat = 400
    static let dividerThickness: CGFloat = 1
    static let dividerGutter: CGFloat = 4
    static let dividerHeight: CGFloat = 18
    static let minLabeledExternalWidth: CGFloat = 48
    static let maxExternalAsks = 3
    static let compactSymbolPointSize: CGFloat = 15
    static let labeledSymbolPointSize: CGFloat = 13

    struct Plan: Equatable {
        var presetWidths: [CGFloat]
        var externalAskWidths: [CGFloat]
        var showsDivider: Bool
        var size: NSSize

        var visibleExternalAskCount: Int { externalAskWidths.count }
    }

    static func plan(
        presetTitles: [String],
        externalAskTitles: [String],
        showsLabels: Bool
    ) -> Plan {
        let presetWidths = presetTitles.map { showsLabels ? actionButtonWidth(for: $0) : controlSize.width }
        var askTitles = Array(externalAskTitles.prefix(maxExternalAsks))
        var askWidths = askTitles.map { showsLabels ? actionButtonWidth(for: $0) : controlSize.width }

        while !askWidths.isEmpty, barWidth(presetWidths: presetWidths, askWidths: askWidths) > maxBarWidth {
            if showsLabels, let fitted = fittedLabeledExternalWidths(
                presetWidths: presetWidths,
                naturalAskWidths: askWidths
            ) {
                askWidths = fitted
                break
            }
            askTitles.removeLast()
            askWidths.removeLast()
        }

        let showsDivider = !presetWidths.isEmpty && !askWidths.isEmpty
        return Plan(
            presetWidths: presetWidths,
            externalAskWidths: askWidths,
            showsDivider: showsDivider,
            size: NSSize(
                width: max(44, barWidth(presetWidths: presetWidths, askWidths: askWidths)),
                height: controlSize.height + contentInset * 2
            )
        )
    }

    static func actionButtonWidth(for title: String) -> CGFloat {
        let textWidth = (title as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: labelFontSize)]
        ).width
        // image + image-to-title gap + leading/trailing padding
        return ceil(textWidth) + 13 + 4 + 10
    }

    static func tooltip(displayName: String, shortcut: InAppShortcut?) -> String {
        guard let shortcut else { return displayName }
        return displayName + "\t" + InAppShortcutDisplay.labels(for: shortcut).joined()
    }

    static func barWidth(presetWidths: [CGFloat], askWidths: [CGFloat]) -> CGFloat {
        let divider = (!presetWidths.isEmpty && !askWidths.isEmpty)
            ? dividerGutter + dividerThickness + dividerGutter
            : 0
        return contentInset * 2 + sectionWidth(presetWidths) + divider + sectionWidth(askWidths)
    }

    private static func sectionWidth(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * controlSpacing
    }

    private static func fittedLabeledExternalWidths(
        presetWidths: [CGFloat],
        naturalAskWidths: [CGFloat]
    ) -> [CGFloat]? {
        let count = naturalAskWidths.count
        guard count > 0 else { return [] }
        let divider = presetWidths.isEmpty ? 0 : dividerGutter + dividerThickness + dividerGutter
        let available = maxBarWidth - contentInset * 2 - sectionWidth(presetWidths) - divider
        let spacing = CGFloat(count - 1) * controlSpacing
        let availableForButtons = available - spacing
        guard availableForButtons >= minLabeledExternalWidth * CGFloat(count) else { return nil }

        let evenShare = floor(availableForButtons / CGFloat(count))
        var widths = naturalAskWidths.map { min($0, max(minLabeledExternalWidth, evenShare)) }
        var used = sectionWidth(widths)
        if used <= available { return widths }

        for index in widths.indices.reversed() {
            let overflow = used - available
            guard overflow > 0 else { break }
            let reduction = min(widths[index] - minLabeledExternalWidth, overflow)
            widths[index] -= reduction
            used -= reduction
        }
        return used <= available ? widths : nil
    }
}

@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayControlling {
    var shortcutForQuickAction: (UUID) -> InAppShortcut? = { _ in nil }

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var buttonTargets: [OverlayButtonTarget] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        let cappedAsks = Array(externalAsks.prefix(SelectionActionBarLayout.maxExternalAsks))
        let plan = SelectionActionBarLayout.plan(
            presetTitles: presets.map(\.title),
            externalAskTitles: cappedAsks.map(\.displayName),
            showsLabels: showsLabels
        )
        let visibleAsks = Array(cappedAsks.prefix(plan.visibleExternalAskCount))
        let content = makeContainer(size: plan.size)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let symbolSize = showsLabels
            ? SelectionActionBarLayout.labeledSymbolPointSize
            : SelectionActionBarLayout.compactSymbolPointSize
        var cursorX = SelectionActionBarLayout.contentInset
        var targets: [OverlayButtonTarget] = []

        for (index, preset) in presets.enumerated() {
            let width = plan.presetWidths[index]
            let target = OverlayButtonTarget { onSelectPreset(preset) }
            content.addSubview(
                makeActionButton(
                    frame: buttonFrame(x: cursorX, width: width),
                    title: preset.title,
                    tooltip: preset.title,
                    image: symbolImage(named: preset.symbolName, title: preset.title, pointSize: symbolSize),
                    showsLabels: showsLabels,
                    target: target
                )
            )
            cursorX += width
            if index < presets.count - 1 {
                cursorX += SelectionActionBarLayout.controlSpacing
            }
            targets.append(target)
        }

        if plan.showsDivider {
            cursorX += SelectionActionBarLayout.dividerGutter
            content.addSubview(makeDivider(x: cursorX))
            cursorX += SelectionActionBarLayout.dividerThickness + SelectionActionBarLayout.dividerGutter
        }

        for (index, action) in visibleAsks.enumerated() {
            let width = plan.externalAskWidths[index]
            let target = OverlayButtonTarget { onSelectExternalAsk(action) }
            content.addSubview(
                makeActionButton(
                    frame: buttonFrame(x: cursorX, width: width),
                    title: action.displayName,
                    tooltip: SelectionActionBarLayout.tooltip(
                        displayName: action.displayName,
                        shortcut: shortcutForQuickAction(action.id)
                    ),
                    image: externalAskImage(for: action, pointSize: symbolSize, dark: isDark),
                    showsLabels: showsLabels,
                    target: target
                )
            )
            cursorX += width
            if index < visibleAsks.count - 1 {
                cursorX += SelectionActionBarLayout.controlSpacing
            }
            targets.append(target)
        }

        buttonTargets = targets
        present(content: content, size: plan.size, anchor: snapshot.anchor)
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
            "anchor=\(SelectionDiagnosticsFormatting.anchor(anchor)) origin=\(SelectionDiagnosticsFormatting.point(origin)) size=\(SelectionDiagnosticsFormatting.size(CGSize(width: size.width, height: size.height)))"
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

    private func buttonFrame(x: CGFloat, width: CGFloat) -> NSRect {
        NSRect(
            x: x,
            y: SelectionActionBarLayout.contentInset,
            width: width,
            height: SelectionActionBarLayout.controlSize.height
        )
    }

    private func makeDivider(x: CGFloat) -> NSView {
        let y = SelectionActionBarLayout.contentInset
            + (SelectionActionBarLayout.controlSize.height - SelectionActionBarLayout.dividerHeight) / 2
        let divider = OverlaySeparatorView(frame: NSRect(
            x: x,
            y: y,
            width: SelectionActionBarLayout.dividerThickness,
            height: SelectionActionBarLayout.dividerHeight
        ))
        divider.wantsLayer = true
        return divider
    }

    private func makeActionButton(
        frame: NSRect,
        title: String,
        tooltip: String,
        image: NSImage?,
        showsLabels: Bool,
        target: OverlayButtonTarget
    ) -> NSButton {
        let button = NSButton(frame: frame)
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        if showsLabels {
            button.title = title
            button.font = .systemFont(ofSize: SelectionActionBarLayout.labelFontSize)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .left
            if let cell = button.cell as? NSButtonCell {
                cell.lineBreakMode = .byTruncatingTail
            }
        } else {
            button.imagePosition = .imageOnly
        }
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.toolTip = tooltip
        button.target = target
        button.action = #selector(OverlayButtonTarget.invoke)
        button.setAccessibilityLabel(title)
        return button
    }

    private func symbolImage(named symbolName: String, title: String, pointSize: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
    }

    private func externalAskImage(for action: QuickAction, pointSize: CGFloat, dark: Bool) -> NSImage? {
        if let slug = action.brandIconSlug,
           let loaded = ProviderBrandIcon.image(for: slug, dark: dark) {
            let image = (loaded.copy() as? NSImage) ?? loaded
            image.size = NSSize(width: pointSize, height: pointSize)
            return image
        }
        return symbolImage(named: action.symbolName, title: action.displayName, pointSize: pointSize)
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
}

private final class OverlaySeparatorView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
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
        case .permissionDenied: L10n.string("selection.feedback.permissionDenied")
        case .noSelection: L10n.string("selection.feedback.noSelection")
        case .unsupported: L10n.string("selection.feedback.unsupported")
        case .temporaryFailure: L10n.string("selection.feedback.temporaryFailure")
        case .selectionChanged: L10n.string("selection.feedback.selectionChanged")
        case .sensitiveField: L10n.string("selection.feedback.sensitiveField")
        }
    }
}
