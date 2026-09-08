import AppKit

@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayControlling {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var buttonTargets: [OverlayButtonTarget] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isPresentingMenu = false
    private var overflowPresets: [PromptPreset] = []
    private var overflowQuickActions: [QuickAction] = []
    private var presetShortcut: ((PromptPreset) -> InAppShortcut?)?
    private var actionShortcut: ((QuickAction) -> InAppShortcut?)?
    private var selectPreset: ((PromptPreset) -> Void)?
    private var selectQuickAction: ((QuickAction) -> Void)?

    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        quickActions: [QuickAction],
        showsLabels: Bool,
        shortcutForPreset: @escaping (PromptPreset) -> InAppShortcut?,
        shortcutForAction: @escaping (QuickAction) -> InAppShortcut?,
        onSelect: @escaping (PromptPreset) -> Void,
        onSelectQuickAction: @escaping (QuickAction) -> Void
    ) {
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            quickActions: quickActions,
            showsLabels: showsLabels
        )
        overflowPresets = layout.overflowPresets
        overflowQuickActions = layout.overflowQuickActions
        presetShortcut = shortcutForPreset
        actionShortcut = shortcutForAction
        selectPreset = onSelect
        selectQuickAction = onSelectQuickAction

        let size = layout.size
        let content = makeContainer(size: size)
        var cursorX = SelectionActionBarLayout.contentInset
        buttonTargets = []

        func placeButton(width: CGFloat, configure: (NSRect) -> NSButton) {
            let frame = NSRect(
                x: cursorX,
                y: SelectionActionBarLayout.contentInset,
                width: width,
                height: SelectionActionBarLayout.controlSize.height
            )
            content.addSubview(configure(frame))
            cursorX += width
        }

        func placeGroupSpacing() {
            cursorX += SelectionActionBarLayout.controlSpacing
        }

        for (index, preset) in layout.visiblePresets.enumerated() {
            if index > 0 { placeGroupSpacing() }
            let width = SelectionActionBarLayout.buttonWidth(for: preset.title, showsLabels: showsLabels)
            let target = OverlayButtonTarget { onSelect(preset) }
            buttonTargets.append(target)
            placeButton(width: width) { frame in
                makeActionButton(
                    frame: frame,
                    title: preset.title,
                    symbolName: preset.symbolName,
                    brandSlug: nil,
                    showsLabels: showsLabels,
                    toolTip: SelectionActionBarLayout.tooltip(
                        name: preset.title,
                        kind: nil,
                        shortcut: shortcutForPreset(preset)
                    ),
                    accessibilityLabel: preset.title,
                    target: target
                )
            }
        }

        if layout.showsSeparator {
            cursorX += SelectionActionBarLayout.separatorMargin
            let separator = NSView(frame: NSRect(
                x: cursorX,
                y: (size.height - SelectionActionBarLayout.separatorHeight) / 2,
                width: SelectionActionBarLayout.separatorWidth,
                height: SelectionActionBarLayout.separatorHeight
            ))
            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
            separator.setAccessibilityElement(false)
            content.addSubview(separator)
            cursorX += SelectionActionBarLayout.separatorWidth + SelectionActionBarLayout.separatorMargin
        } else if layout.showsMore, !layout.visiblePresets.isEmpty {
            placeGroupSpacing()
        }

        for (index, action) in layout.visibleQuickActions.enumerated() {
            if index > 0 { placeGroupSpacing() }
            let width = SelectionActionBarLayout.buttonWidth(for: action.displayName, showsLabels: showsLabels)
            let target = OverlayButtonTarget { onSelectQuickAction(action) }
            buttonTargets.append(target)
            placeButton(width: width) { frame in
                makeActionButton(
                    frame: frame,
                    title: action.displayName,
                    symbolName: action.symbolName,
                    brandSlug: action.brandIconSlug,
                    showsLabels: showsLabels,
                    toolTip: SelectionActionBarLayout.tooltip(
                        name: action.displayName,
                        kind: SelectionActionBarLayout.kindLabel(for: action.kind),
                        shortcut: shortcutForAction(action)
                    ),
                    accessibilityLabel: L10n.string("selection.actionBar.externalAskAccessibility", action.displayName),
                    target: target
                )
            }
        }

        if layout.showsMore {
            if layout.showsSeparator || !layout.visibleQuickActions.isEmpty {
                if !layout.visibleQuickActions.isEmpty { placeGroupSpacing() }
            }
            let moreTitle = L10n.string("selection.actionBar.more")
            let width = SelectionActionBarLayout.buttonWidth(for: moreTitle, showsLabels: showsLabels)
            let target = OverlayButtonTarget { [weak self] in
                self?.presentOverflowMenu()
            }
            buttonTargets.append(target)
            placeButton(width: width) { frame in
                let button = makeActionButton(
                    frame: frame,
                    title: moreTitle,
                    symbolName: "ellipsis",
                    brandSlug: nil,
                    showsLabels: showsLabels,
                    toolTip: moreTitle,
                    accessibilityLabel: L10n.string("selection.actionBar.moreAccessibility"),
                    target: target
                )
                button.identifier = NSUserInterfaceItemIdentifier("selection.actionBar.more")
                return button
            }
        }

        present(content: content, size: size, anchor: snapshot.anchor)
        scheduleDismiss(after: SelectionActionBarLayout.actionBarDismissDelay)
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
        overflowPresets = []
        overflowQuickActions = []
        presetShortcut = nil
        actionShortcut = nil
        selectPreset = nil
        selectQuickAction = nil
        isPresentingMenu = false
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

    private func makeActionButton(
        frame: NSRect,
        title: String,
        symbolName: String,
        brandSlug: String?,
        showsLabels: Bool,
        toolTip: String,
        accessibilityLabel: String,
        target: OverlayButtonTarget
    ) -> OverlayHoverButton {
        let iconPointSize = showsLabels
            ? SelectionActionBarLayout.labeledIconSize
            : SelectionActionBarLayout.compactIconSize
        let button = OverlayHoverButton(frame: frame)
        button.iconPointSize = iconPointSize
        button.symbolName = symbolName
        button.brandImage = brandImage(for: brandSlug)
        button.applyRestingIcon()
        if showsLabels {
            button.title = title
            button.font = .systemFont(ofSize: SelectionActionBarLayout.labelFontSize)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .left
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.toolTip = toolTip
        button.target = target
        button.action = #selector(OverlayButtonTarget.invoke)
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    private func brandImage(for slug: String?) -> NSImage? {
        guard let slug else { return nil }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let image = ProviderBrandIcon.image(for: slug, dark: dark) else { return nil }
        image.isTemplate = false
        return image
    }

    private func presentOverflowMenu() {
        guard let moreButton = moreButton() else { return }
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        isPresentingMenu = true

        let menu = NSMenu()
        menu.autoenablesItems = false
        for preset in overflowPresets {
            menu.addItem(menuItem(
                title: preset.title,
                symbolName: preset.symbolName,
                brandSlug: nil,
                shortcut: presetShortcut?(preset)
            ) { [weak self] in
                self?.selectPreset?(preset)
            })
        }
        for action in overflowQuickActions {
            menu.addItem(menuItem(
                title: action.displayName,
                symbolName: action.symbolName,
                brandSlug: action.brandIconSlug,
                shortcut: actionShortcut?(action)
            ) { [weak self] in
                self?.selectQuickAction?(action)
            })
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: moreButton)
        isPresentingMenu = false
        if panel != nil {
            scheduleDismiss(after: SelectionActionBarLayout.actionBarDismissDelay)
        }
    }

    private func menuItem(
        title: String,
        symbolName: String,
        brandSlug: String?,
        shortcut: InAppShortcut?,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let target = OverlayButtonTarget(handler: handler)
        buttonTargets.append(target)
        let item = NSMenuItem(title: title, action: #selector(OverlayButtonTarget.invoke), keyEquivalent: "")
        item.target = target
        item.isEnabled = true
        if let brand = brandImage(for: brandSlug) {
            let icon = brand.copy() as? NSImage ?? brand
            icon.size = NSSize(width: 16, height: 16)
            icon.isTemplate = false
            item.image = icon
        } else {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        }
        if let shortcut {
            item.keyEquivalent = shortcut.key == " " ? " " : shortcut.key.lowercased()
            item.keyEquivalentModifierMask = shortcut.modifierFlags
        }
        return item
    }

    private func moreButton() -> NSView? {
        panel?.contentView?.subviews.first { $0.identifier?.rawValue == "selection.actionBar.more" }
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
        guard !isPresentingMenu, let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
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

private final class OverlayButtonTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

private final class OverlayHoverButton: NSButton {
    var iconPointSize: CGFloat = SelectionActionBarLayout.compactIconSize
    var symbolName: String?
    var brandImage: NSImage?
    private var hoverTrackingArea: NSTrackingArea?
    private let hoverFill = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        hoverFill.cornerRadius = SelectionActionBarLayout.hoverCornerRadius
        hoverFill.backgroundColor = NSColor.labelColor.withAlphaComponent(SelectionActionBarLayout.hoverFillOpacity).cgColor
        hoverFill.opacity = 0
        layer?.insertSublayer(hoverFill, at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hoverFill.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    func applyRestingIcon() {
        applyIcon(pointSize: iconPointSize)
    }

    private func setHovering(_ hovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SelectionActionBarLayout.hoverDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hoverFill.opacity = hovering ? 1 : 0
        }
        applyIcon(pointSize: hovering ? iconPointSize * SelectionActionBarLayout.hoverScale : iconPointSize)
    }

    private func applyIcon(pointSize: CGFloat) {
        if let brandImage {
            let icon = brandImage.copy() as? NSImage ?? brandImage
            icon.size = NSSize(width: pointSize, height: pointSize)
            icon.isTemplate = false
            image = icon
            return
        }
        guard let symbolName,
              let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: title.isEmpty ? nil : title)
        else { return }
        image = symbol.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
    }
}

struct SelectionActionBarLayout: Equatable {
    static let maxVisiblePerGroup = 4
    static let maxLabeledWidth: CGFloat = 480
    static let controlSize = NSSize(width: 28, height: 28)
    static let contentInset: CGFloat = 4
    static let controlSpacing: CGFloat = 2
    static let separatorWidth: CGFloat = 1
    static let separatorHeight: CGFloat = 20
    static let separatorMargin: CGFloat = 6
    static let separatorOccupiedWidth: CGFloat = separatorWidth + separatorMargin * 2
    static let labelFontSize: CGFloat = 12
    static let compactIconSize: CGFloat = 15
    static let labeledIconSize: CGFloat = 13
    static let hoverScale: CGFloat = 1.1
    static let hoverDuration: TimeInterval = 0.12
    static let hoverCornerRadius: CGFloat = 6
    static let hoverFillOpacity: CGFloat = 0.08
    static let actionBarDismissDelay: TimeInterval = 8
    static let minimumSize = NSSize(width: 44, height: 36)

    var visiblePresets: [PromptPreset]
    var visibleQuickActions: [QuickAction]
    var overflowPresets: [PromptPreset]
    var overflowQuickActions: [QuickAction]
    var showsSeparator: Bool
    var showsMore: Bool
    var size: NSSize

    static func make(
        presets: [PromptPreset],
        quickActions: [QuickAction],
        showsLabels: Bool,
        moreTitle: String = L10n.string("selection.actionBar.more")
    ) -> SelectionActionBarLayout {
        var visiblePresets = Array(presets.prefix(maxVisiblePerGroup))
        var overflowPresets = Array(presets.dropFirst(maxVisiblePerGroup))
        var visibleQuickActions = Array(quickActions.prefix(maxVisiblePerGroup))
        var overflowQuickActions = Array(quickActions.dropFirst(maxVisiblePerGroup))

        func current() -> SelectionActionBarLayout {
            let showsMore = !overflowPresets.isEmpty || !overflowQuickActions.isEmpty
            let moreOnTrailingGroup = !quickActions.isEmpty
            let leadingHasContent = !visiblePresets.isEmpty || (showsMore && !moreOnTrailingGroup)
            let trailingHasContent = !visibleQuickActions.isEmpty || (showsMore && moreOnTrailingGroup)
            let showsSeparator = leadingHasContent && trailingHasContent
            let size = barSize(
                visiblePresets: visiblePresets,
                visibleQuickActions: visibleQuickActions,
                showsSeparator: showsSeparator,
                showsMore: showsMore,
                moreOnTrailingGroup: moreOnTrailingGroup,
                showsLabels: showsLabels,
                moreTitle: moreTitle
            )
            return SelectionActionBarLayout(
                visiblePresets: visiblePresets,
                visibleQuickActions: visibleQuickActions,
                overflowPresets: overflowPresets,
                overflowQuickActions: overflowQuickActions,
                showsSeparator: showsSeparator,
                showsMore: showsMore,
                size: size
            )
        }

        var layout = current()
        if showsLabels {
            while layout.size.width > maxLabeledWidth {
                if !visibleQuickActions.isEmpty {
                    overflowQuickActions.insert(visibleQuickActions.removeLast(), at: 0)
                } else if !visiblePresets.isEmpty {
                    overflowPresets.insert(visiblePresets.removeLast(), at: 0)
                } else {
                    break
                }
                layout = current()
            }
        }
        return layout
    }

    static func buttonWidth(for title: String, showsLabels: Bool) -> CGFloat {
        showsLabels ? actionButtonWidth(for: title) : controlSize.width
    }

    static func actionButtonWidth(for title: String) -> CGFloat {
        let textWidth = (title as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: labelFontSize)]
        ).width
        return ceil(textWidth) + 13 + 4 + 10
    }

    static func kindLabel(for kind: QuickActionKind) -> String {
        switch kind {
        case .web: L10n.string("selection.actionBar.kind.web")
        case .uriScheme: L10n.string("selection.actionBar.kind.uriScheme")
        case .terminal: L10n.string("selection.actionBar.kind.terminal")
        }
    }

    static func tooltip(name: String, kind: String?, shortcut: InAppShortcut?) -> String {
        var text = name
        if let kind {
            text += " — \(kind)"
        }
        if let shortcut {
            text += "（\(InAppShortcutDisplay.labels(for: shortcut).joined())）"
        }
        return text
    }

    private static func barSize(
        visiblePresets: [PromptPreset],
        visibleQuickActions: [QuickAction],
        showsSeparator: Bool,
        showsMore: Bool,
        moreOnTrailingGroup: Bool,
        showsLabels: Bool,
        moreTitle: String
    ) -> NSSize {
        let moreWidth = showsMore ? buttonWidth(for: moreTitle, showsLabels: showsLabels) : nil
        var leading = visiblePresets.map { buttonWidth(for: $0.title, showsLabels: showsLabels) }
        var trailing = visibleQuickActions.map { buttonWidth(for: $0.displayName, showsLabels: showsLabels) }
        if let moreWidth {
            if moreOnTrailingGroup {
                trailing.append(moreWidth)
            } else {
                leading.append(moreWidth)
            }
        }

        var width = contentInset * 2 + groupWidth(leading)
        if showsSeparator {
            width += separatorOccupiedWidth + groupWidth(trailing)
        } else {
            width += groupWidth(trailing)
        }
        return NSSize(
            width: max(minimumSize.width, width),
            height: max(minimumSize.height, controlSize.height + contentInset * 2)
        )
    }

    private static func groupWidth(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * controlSpacing
    }
}

private extension InAppShortcut {
    var modifierFlags: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.control) { mask.insert(.control) }
        return mask
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
