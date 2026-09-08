import AppKit

@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayControlling {
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
        showActions(
            snapshot: snapshot,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            shortcutForPreset: nil,
            shortcutForExternalAsk: nil,
            onSelectPreset: onSelectPreset,
            onSelectExternalAsk: onSelectExternalAsk
        )
    }

    func showActions(
        snapshot: SelectedTextSnapshot,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        shortcutForPreset: ((PromptPreset) -> InAppShortcut?)?,
        shortcutForExternalAsk: ((QuickAction) -> InAppShortcut?)?,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels
        )

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
            let width = layout.visiblePresetWidths[index]
            let target = OverlayButtonTarget { onSelectPreset(preset) }
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
                        shortcut: shortcutForPreset?(preset)
                    ),
                    accessibilityLabel: preset.title,
                    target: target
                )
            }
        }

        if layout.showsDivider {
            cursorX += SelectionActionBarLayout.dividerMargin
            let divider = NSView(frame: NSRect(
                x: cursorX,
                y: (size.height - SelectionActionBarLayout.dividerHeight) / 2,
                width: SelectionActionBarLayout.dividerWidth,
                height: SelectionActionBarLayout.dividerHeight
            ))
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
            divider.setAccessibilityElement(false)
            content.addSubview(divider)
            cursorX += SelectionActionBarLayout.dividerWidth + SelectionActionBarLayout.dividerMargin
        }

        for (index, action) in layout.visibleExternalAsks.enumerated() {
            if index > 0 { placeGroupSpacing() }
            let width = layout.visibleExternalAskWidths[index]
            let target = OverlayButtonTarget { onSelectExternalAsk(action) }
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
                        shortcut: shortcutForExternalAsk?(action)
                    ),
                    accessibilityLabel: L10n.string("selection.actionBar.externalAskAccessibility", action.displayName),
                    target: target
                )
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
    ) -> NSButton {
        let button = NSButton(frame: frame)
        let iconPointSize = showsLabels
            ? SelectionActionBarLayout.labeledIconSize
            : SelectionActionBarLayout.compactIconSize

        if let brandImage = brandImage(for: brandSlug, pointSize: showsLabels ? 13 : SelectionActionBarLayout.compactBrandIconSize) {
            button.image = brandImage
        } else if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel) {
            button.image = symbol.withSymbolConfiguration(.init(pointSize: iconPointSize, weight: .regular))
        }

        if showsLabels {
            button.title = title
            button.font = .systemFont(ofSize: SelectionActionBarLayout.labelFontSize)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
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

    private func brandImage(for slug: String?, pointSize: CGFloat) -> NSImage? {
        guard let slug else { return nil }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let image = ProviderBrandIcon.image(for: slug, dark: isDark) else { return nil }
        let resized = image.copy() as? NSImage ?? image
        resized.size = NSSize(width: pointSize, height: pointSize)
        resized.isTemplate = false
        return resized
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

private final class OverlayButtonTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

struct SelectionActionBarLayout: Equatable {
    static let maxTotalActions = 6
    static let maxTotalWidth: CGFloat = 400
    static let minExternalAskWidth: CGFloat = 48
    static let controlSize = NSSize(width: 28, height: 28)
    static let contentInset: CGFloat = 4
    static let controlSpacing: CGFloat = 2
    static let dividerWidth: CGFloat = 1
    static let dividerHeight: CGFloat = 18
    static let dividerMargin: CGFloat = 4
    static let dividerOccupiedWidth: CGFloat = dividerWidth + dividerMargin * 2 // 9 pt
    static let labelFontSize: CGFloat = 12
    static let compactIconSize: CGFloat = 15
    static let compactBrandIconSize: CGFloat = 16
    static let labeledIconSize: CGFloat = 13
    static let actionBarDismissDelay: TimeInterval = 8
    static let minimumSize = NSSize(width: 44, height: 36)

    var visiblePresets: [PromptPreset]
    var visiblePresetWidths: [CGFloat]
    var visibleExternalAsks: [QuickAction]
    var visibleExternalAskWidths: [CGFloat]
    var showsDivider: Bool
    var size: NSSize

    static func buttonWidth(for title: String) -> CGFloat {
        let textWidth = (title as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: labelFontSize)]
        ).width
        return ceil(textWidth) + 27
    }

    static func tooltip(name: String, shortcut: InAppShortcut?) -> String {
        guard let shortcut else { return name }
        let labels = InAppShortcutDisplay.labels(for: shortcut).joined()
        return "\(name)\t\(labels)"
    }

    static func make(
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool
    ) -> SelectionActionBarLayout {
        let cappedPresets = Array(presets.prefix(maxTotalActions))
        let remainingSlots = max(0, maxTotalActions - cappedPresets.count)
        let cappedExternalAsks = Array(externalAsks.prefix(remainingSlots))

        if !showsLabels {
            var chosenExternalAsks = cappedExternalAsks
            func compactWidth(pCount: Int, eCount: Int) -> CGFloat {
                let pWidth = pCount > 0 ? CGFloat(pCount) * controlSize.width + CGFloat(pCount - 1) * controlSpacing : 0
                let eWidth = eCount > 0 ? CGFloat(eCount) * controlSize.width + CGFloat(eCount - 1) * controlSpacing : 0
                let div = (pCount > 0 && eCount > 0) ? dividerOccupiedWidth : 0
                return contentInset * 2 + pWidth + div + eWidth
            }

            while !chosenExternalAsks.isEmpty && compactWidth(pCount: cappedPresets.count, eCount: chosenExternalAsks.count) > maxTotalWidth {
                chosenExternalAsks.removeLast()
            }

            let showsDivider = !cappedPresets.isEmpty && !chosenExternalAsks.isEmpty
            let totalWidth = compactWidth(pCount: cappedPresets.count, eCount: chosenExternalAsks.count)
            return SelectionActionBarLayout(
                visiblePresets: cappedPresets,
                visiblePresetWidths: Array(repeating: controlSize.width, count: cappedPresets.count),
                visibleExternalAsks: chosenExternalAsks,
                visibleExternalAskWidths: Array(repeating: controlSize.width, count: chosenExternalAsks.count),
                showsDivider: showsDivider,
                size: NSSize(width: max(minimumSize.width, totalWidth), height: minimumSize.height)
            )
        }

        let presetWidths = cappedPresets.map { buttonWidth(for: $0.title) }
        let pGroupWidth: CGFloat
        if presetWidths.isEmpty {
            pGroupWidth = 0
        } else {
            pGroupWidth = presetWidths.reduce(0, +) + CGFloat(presetWidths.count - 1) * controlSpacing
        }

        let hasPresets = !cappedPresets.isEmpty
        var finalExternalAsks: [QuickAction] = []
        var finalExternalAskWidths: [CGFloat] = []

        if !cappedExternalAsks.isEmpty {
            let availableForEA = maxTotalWidth - (contentInset * 2) - pGroupWidth - (hasPresets ? dividerOccupiedWidth : 0)
            if availableForEA >= minExternalAskWidth {
                for k in stride(from: cappedExternalAsks.count, through: 1, by: -1) {
                    let candidates = Array(cappedExternalAsks.prefix(k))
                    let naturalWidths = candidates.map { buttonWidth(for: $0.displayName) }
                    let spacingTotal = CGFloat(k - 1) * controlSpacing
                    let minRequired = CGFloat(k) * minExternalAskWidth + spacingTotal

                    if availableForEA >= minRequired {
                        let naturalTotal = naturalWidths.reduce(0, +) + spacingTotal
                        if naturalTotal <= availableForEA {
                            finalExternalAsks = candidates
                            finalExternalAskWidths = naturalWidths
                            break
                        } else {
                            let availableForButtons = availableForEA - spacingTotal
                            var low: CGFloat = minExternalAskWidth
                            var high: CGFloat = naturalWidths.max() ?? minExternalAskWidth
                            var bestCap: CGFloat = minExternalAskWidth
                            for _ in 0..<15 {
                                let mid = (low + high) / 2
                                let sum = naturalWidths.map { min($0, mid) }.reduce(0, +)
                                if sum <= availableForButtons {
                                    bestCap = mid
                                    low = mid
                                } else {
                                    high = mid
                                }
                            }
                            finalExternalAsks = candidates
                            finalExternalAskWidths = naturalWidths.map { floor(min($0, bestCap)) }
                            break
                        }
                    }
                }
            }
        }

        let showsDivider = !cappedPresets.isEmpty && !finalExternalAsks.isEmpty
        let eaGroupWidth: CGFloat
        if finalExternalAskWidths.isEmpty {
            eaGroupWidth = 0
        } else {
            eaGroupWidth = finalExternalAskWidths.reduce(0, +) + CGFloat(finalExternalAskWidths.count - 1) * controlSpacing
        }

        var totalWidth = contentInset * 2 + pGroupWidth
        if showsDivider {
            totalWidth += dividerOccupiedWidth + eaGroupWidth
        } else {
            totalWidth += eaGroupWidth
        }

        return SelectionActionBarLayout(
            visiblePresets: cappedPresets,
            visiblePresetWidths: presetWidths,
            visibleExternalAsks: finalExternalAsks,
            visibleExternalAskWidths: finalExternalAskWidths,
            showsDivider: showsDivider,
            size: NSSize(
                width: max(minimumSize.width, min(maxTotalWidth, totalWidth)),
                height: max(minimumSize.height, controlSize.height + contentInset * 2)
            )
        )
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
