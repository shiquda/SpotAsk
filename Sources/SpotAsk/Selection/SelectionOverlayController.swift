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
            showsChat: false,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            shortcutForChat: nil,
            shortcutForPreset: nil,
            shortcutForExternalAsk: nil,
            onSelectChat: {},
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
        showActions(
            snapshot: snapshot,
            showsChat: false,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            shortcutForChat: nil,
            shortcutForPreset: shortcutForPreset,
            shortcutForExternalAsk: shortcutForExternalAsk,
            onSelectChat: {},
            onSelectPreset: onSelectPreset,
            onSelectExternalAsk: onSelectExternalAsk
        )
    }

    func showActions(
        snapshot: SelectedTextSnapshot,
        showsChat: Bool,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        collapsesOverflow: Bool = false,
        shortcutForChat: InAppShortcut?,
        shortcutForPreset: ((PromptPreset) -> InAppShortcut?)?,
        shortcutForExternalAsk: ((QuickAction) -> InAppShortcut?)?,
        onSelectChat: @escaping () -> Void,
        onSelectPreset: @escaping (PromptPreset) -> Void,
        onSelectExternalAsk: @escaping (QuickAction) -> Void
    ) {
        let layout = SelectionActionBarLayout.make(
            showsChat: showsChat,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            collapsesOverflow: collapsesOverflow
        )
        let content = SelectionActionBarContentView(
            layout: layout,
            actions: SelectionActionBarActions(
                onSelectChat: onSelectChat,
                onSelectPreset: onSelectPreset,
                onSelectExternalAsk: onSelectExternalAsk,
                shortcutForChat: shortcutForChat,
                shortcutForPreset: shortcutForPreset,
                shortcutForExternalAsk: shortcutForExternalAsk
            )
        )

        present(content: content, size: layout.size, anchor: snapshot.anchor)
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
        case let .pointer(pointValue): point = NSPoint(x: pointValue.x + 8, y: pointValue.y - size.height - 8)
        }
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return point }
        return NSPoint(x: min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8), y: min(max(point.y, visible.minY + 8), visible.maxY - size.height - 8))
    }
}

enum SelectionActionBarPlacedItem: Equatable {
    case chat(frame: NSRect)
    case preset(index: Int, frame: NSRect)
    case divider(frame: NSRect)
    case externalAsk(index: Int, frame: NSRect)
    case more(frame: NSRect)
    case item(item: SelectionActionBarItem, frame: NSRect)

    var frame: NSRect {
        switch self {
        case let .chat(frame), let .preset(_, frame), let .divider(frame), let .externalAsk(_, frame), let .more(frame), let .item(_, frame):
            return frame
        }
    }
}

struct SelectionActionBarLayout: Equatable {
    static let maxTotalActions = 8
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
    static let primaryActionLimit = 4

    var showsChat: Bool
    var showsLabels: Bool
    var chatWidth: CGFloat
    var visiblePresets: [PromptPreset]
    var visiblePresetWidths: [CGFloat]
    var visibleExternalAsks: [QuickAction]
    var visibleExternalAskWidths: [CGFloat]
    var showsDivider: Bool
    var overflowPresets: [PromptPreset] = []
    var overflowExternalAsks: [QuickAction] = []
    var size: NSSize
    var primaryItems: [SelectionActionBarItem] = []
    var secondaryItems: [SelectionActionBarItem] = []

    var showsMoreButton: Bool {
        !secondaryItems.isEmpty || !overflowPresets.isEmpty || !overflowExternalAsks.isEmpty
    }

    var placedItems: [SelectionActionBarPlacedItem] {
        if !primaryItems.isEmpty {
            var x = Self.contentInset
            var items: [SelectionActionBarPlacedItem] = []
            let buttonY = Self.contentInset
            let buttonHeight = Self.controlSize.height

            for (index, item) in primaryItems.enumerated() {
                if index > 0 { x += Self.controlSpacing }
                let itemWidth: CGFloat
                if !showsLabels || item.isChat {
                    itemWidth = Self.controlSize.width
                } else {
                    itemWidth = Self.buttonWidth(for: item.name)
                }
                items.append(.item(item: item, frame: NSRect(x: x, y: buttonY, width: itemWidth, height: buttonHeight)))
                x += itemWidth
            }

            if showsMoreButton {
                if !primaryItems.isEmpty { x += Self.controlSpacing }
                items.append(.more(frame: NSRect(x: x, y: buttonY, width: Self.controlSize.width, height: buttonHeight)))
                x += Self.controlSize.width
            }
            return items
        }

        var x = Self.contentInset
        var items: [SelectionActionBarPlacedItem] = []
        let buttonY = Self.contentInset
        let buttonHeight = Self.controlSize.height

        if showsChat {
            items.append(.chat(frame: NSRect(x: x, y: buttonY, width: chatWidth, height: buttonHeight)))
            x += chatWidth
        }

        for (index, width) in visiblePresetWidths.enumerated() {
            if showsChat || index > 0 { x += Self.controlSpacing }
            items.append(.preset(index: index, frame: NSRect(x: x, y: buttonY, width: width, height: buttonHeight)))
            x += width
        }
        if showsDivider {
            x += Self.dividerMargin
            items.append(.divider(frame: NSRect(
                x: x,
                y: (size.height - Self.dividerHeight) / 2,
                width: Self.dividerWidth,
                height: Self.dividerHeight
            )))
            x += Self.dividerWidth + Self.dividerMargin
        }
        for (index, width) in visibleExternalAskWidths.enumerated() {
            if index > 0 { x += Self.controlSpacing }
            items.append(.externalAsk(index: index, frame: NSRect(x: x, y: buttonY, width: width, height: buttonHeight)))
            x += width
        }
        if showsMoreButton {
            if showsChat || !visiblePresetWidths.isEmpty || !visibleExternalAskWidths.isEmpty {
                x += Self.controlSpacing
            }
            items.append(.more(frame: NSRect(x: x, y: buttonY, width: Self.controlSize.width, height: buttonHeight)))
            x += Self.controlSize.width
        }
        return items
    }

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
        showsChat: Bool = false,
        chatTitle: String = L10n.string("selection.actionBar.chat"),
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        showsLabels: Bool,
        collapsesOverflow: Bool = false,
        primaryItems: [SelectionActionBarItem] = [],
        secondaryItems: [SelectionActionBarItem] = []
    ) -> SelectionActionBarLayout {
        let totalActionCount = (showsChat ? 1 : 0) + presets.count + externalAsks.count
        let shouldCollapse = collapsesOverflow && totalActionCount > primaryActionLimit

        let cappedPresets: [PromptPreset]
        let overflowPresets: [PromptPreset]
        let cappedExternalAsks: [QuickAction]
        let overflowExternalAsks: [QuickAction]

        if shouldCollapse {
            let primaryRemaining = showsChat ? max(0, primaryActionLimit - 1) : primaryActionLimit
            let presetTake = min(primaryRemaining, presets.count)
            cappedPresets = Array(presets.prefix(presetTake))
            overflowPresets = Array(presets.dropFirst(presetTake))

            let externalRemaining = max(0, primaryRemaining - cappedPresets.count)
            let eaTake = min(externalRemaining, externalAsks.count)
            cappedExternalAsks = Array(externalAsks.prefix(eaTake))
            overflowExternalAsks = Array(externalAsks.dropFirst(eaTake))
        } else {
            let availableForPresets = showsChat ? max(0, maxTotalActions - 1) : maxTotalActions
            cappedPresets = Array(presets.prefix(availableForPresets))
            let remainingSlots = max(0, maxTotalActions - (showsChat ? 1 : 0) - cappedPresets.count)
            cappedExternalAsks = Array(externalAsks.prefix(remainingSlots))
            overflowPresets = []
            overflowExternalAsks = []
        }

        if !primaryItems.isEmpty || !secondaryItems.isEmpty {
            let showsMore = !secondaryItems.isEmpty
            let totalWidth: CGFloat
            if !showsLabels {
                let count = primaryItems.count
                let itemsW = CGFloat(count) * controlSize.width + CGFloat(max(0, count - 1)) * controlSpacing
                let moreW = showsMore ? (controlSpacing + controlSize.width) : 0
                totalWidth = contentInset * 2 + itemsW + moreW
            } else {
                let widths = primaryItems.map { $0.isChat ? controlSize.width : buttonWidth(for: $0.name) }
                let itemsW = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * controlSpacing
                let moreW = showsMore ? (controlSpacing + controlSize.width) : 0
                totalWidth = contentInset * 2 + itemsW + moreW
            }

            return SelectionActionBarLayout(
                showsChat: showsChat,
                showsLabels: showsLabels,
                chatWidth: showsChat ? controlSize.width : 0,
                visiblePresets: cappedPresets,
                visiblePresetWidths: cappedPresets.map { showsLabels ? buttonWidth(for: $0.title) : controlSize.width },
                visibleExternalAsks: cappedExternalAsks,
                visibleExternalAskWidths: cappedExternalAsks.map { showsLabels ? buttonWidth(for: $0.displayName) : controlSize.width },
                showsDivider: false,
                overflowPresets: overflowPresets,
                overflowExternalAsks: overflowExternalAsks,
                size: NSSize(width: max(minimumSize.width, totalWidth), height: minimumSize.height),
                primaryItems: primaryItems,
                secondaryItems: secondaryItems
            )
        }

        let showsMore = !overflowPresets.isEmpty || !overflowExternalAsks.isEmpty

        if !showsLabels {
            var chosenExternalAsks = cappedExternalAsks
            func compactWidth(hasChat: Bool, pCount: Int, eCount: Int, hasMore: Bool) -> CGFloat {
                let cWidth = hasChat ? controlSize.width : 0
                let pWidth = pCount > 0 ? CGFloat(pCount) * controlSize.width + CGFloat(pCount - 1) * controlSpacing : 0
                let spacingAfterChat = (hasChat && pCount > 0) ? controlSpacing : 0
                let div = ((hasChat || pCount > 0) && eCount > 0) ? dividerOccupiedWidth : 0
                let eWidth = eCount > 0 ? CGFloat(eCount) * controlSize.width + CGFloat(eCount - 1) * controlSpacing : 0
                let spacingBeforeMore = (hasMore && (hasChat || pCount > 0 || eCount > 0)) ? controlSpacing : 0
                let moreWidth = hasMore ? controlSize.width : 0
                return contentInset * 2 + cWidth + spacingAfterChat + pWidth + div + eWidth + spacingBeforeMore + moreWidth
            }

            var showsDivider = (showsChat || !cappedPresets.isEmpty) && !chosenExternalAsks.isEmpty
            while !chosenExternalAsks.isEmpty && compactWidth(hasChat: showsChat, pCount: cappedPresets.count, eCount: chosenExternalAsks.count, hasMore: showsMore) > maxTotalWidth {
                chosenExternalAsks.removeLast()
                showsDivider = (showsChat || !cappedPresets.isEmpty) && !chosenExternalAsks.isEmpty
            }

            let totalWidth = compactWidth(hasChat: showsChat, pCount: cappedPresets.count, eCount: chosenExternalAsks.count, hasMore: showsMore)
            return SelectionActionBarLayout(
                showsChat: showsChat,
                showsLabels: false,
                chatWidth: showsChat ? controlSize.width : 0,
                visiblePresets: cappedPresets,
                visiblePresetWidths: Array(repeating: controlSize.width, count: cappedPresets.count),
                visibleExternalAsks: chosenExternalAsks,
                visibleExternalAskWidths: Array(repeating: controlSize.width, count: chosenExternalAsks.count),
                showsDivider: showsDivider,
                overflowPresets: overflowPresets,
                overflowExternalAsks: overflowExternalAsks,
                size: NSSize(width: max(minimumSize.width, totalWidth), height: minimumSize.height)
            )
        }

        let chatWidth: CGFloat = showsChat ? controlSize.width : 0
        let presetNaturalWidths = cappedPresets.map { buttonWidth(for: $0.title) }
        var chosenExternalAsks = cappedExternalAsks
        let moreOccupiedWidth: CGFloat = showsMore ? (controlSpacing + controlSize.width) : 0

        func groupWidth(_ widths: [CGFloat]) -> CGFloat {
            guard !widths.isEmpty else { return 0 }
            return widths.reduce(0, +) + CGFloat(widths.count - 1) * controlSpacing
        }

        func spotAskGroupWidth(presetWidths: [CGFloat]) -> CGFloat {
            let pWidth = groupWidth(presetWidths)
            if showsChat && !presetWidths.isEmpty {
                return chatWidth + controlSpacing + pWidth
            } else if showsChat {
                return chatWidth
            } else {
                return pWidth
            }
        }

        func labeledWidth(presetWidths: [CGFloat], eaWidths: [CGFloat]) -> CGFloat {
            let saWidth = spotAskGroupWidth(presetWidths: presetWidths)
            let div = (saWidth > 0 && !eaWidths.isEmpty) ? dividerOccupiedWidth : 0
            let moreSpacing = (showsMore && (saWidth > 0 || !eaWidths.isEmpty)) ? controlSpacing : 0
            let moreW = showsMore ? controlSize.width : 0
            return contentInset * 2 + saWidth + div + groupWidth(eaWidths) + moreSpacing + moreW
        }

        while !chosenExternalAsks.isEmpty {
            let minEAWidths = Array(repeating: minExternalAskWidth, count: chosenExternalAsks.count)
            if labeledWidth(presetWidths: presetNaturalWidths, eaWidths: minEAWidths) <= maxTotalWidth {
                break
            }
            chosenExternalAsks.removeLast()
        }

        let showsDivider = (showsChat || !cappedPresets.isEmpty) && !chosenExternalAsks.isEmpty
        let eaSpacing = chosenExternalAsks.count > 1 ? CGFloat(chosenExternalAsks.count - 1) * controlSpacing : 0
        let presetWidths: [CGFloat]
        let eaWidths: [CGFloat]

        if chosenExternalAsks.isEmpty {
            let presetSpacing = cappedPresets.count > 1 ? CGFloat(cappedPresets.count - 1) * controlSpacing : 0
            let spacingAfterChat = (showsChat && !cappedPresets.isEmpty) ? controlSpacing : 0
            let availableForPresets = max(0, maxTotalWidth - contentInset * 2 - chatWidth - spacingAfterChat - presetSpacing - moreOccupiedWidth)
            presetWidths = compressedWidths(presetNaturalWidths, into: availableForPresets)
            eaWidths = []
        } else {
            presetWidths = presetNaturalWidths
            let saWidth = spotAskGroupWidth(presetWidths: presetNaturalWidths)
            let availableEA = max(
                0,
                maxTotalWidth - contentInset * 2 - saWidth - dividerOccupiedWidth - eaSpacing - moreOccupiedWidth
            )
            eaWidths = compressedWidths(
                chosenExternalAsks.map { buttonWidth(for: $0.displayName) },
                into: availableEA
            )
        }

        let totalWidth = labeledWidth(presetWidths: presetWidths, eaWidths: eaWidths)

        return SelectionActionBarLayout(
            showsChat: showsChat,
            showsLabels: true,
            chatWidth: chatWidth,
            visiblePresets: cappedPresets,
            visiblePresetWidths: presetWidths,
            visibleExternalAsks: chosenExternalAsks,
            visibleExternalAskWidths: eaWidths,
            showsDivider: showsDivider,
            overflowPresets: overflowPresets,
            overflowExternalAsks: overflowExternalAsks,
            size: NSSize(
                width: max(minimumSize.width, totalWidth),
                height: max(minimumSize.height, controlSize.height + contentInset * 2)
            )
        )
    }

    /// Caps the longest titles first so every remaining button fits `available`.
    /// Never drops items. Short titles keep their natural width.
    static func compressedWidths(
        _ natural: [CGFloat],
        into available: CGFloat
    ) -> [CGFloat] {
        guard !natural.isEmpty else { return [] }
        if natural.reduce(0, +) <= available {
            return natural
        }

        let equalShare = max(1, floor(available / CGFloat(natural.count)))
        var low = equalShare
        var high = max(equalShare, natural.max() ?? equalShare)
        var bestCap = equalShare
        for _ in 0..<20 {
            let mid = (low + high) / 2
            let sum = natural.map { min($0, mid) }.reduce(0, +)
            if sum <= available {
                bestCap = mid
                low = mid
            } else {
                high = mid
            }
        }

        var widths = natural.map { floor(min($0, max(1, bestCap))) }
        var leftover = floor(available) - widths.reduce(0, +)
        if leftover > 0 {
            for index in widths.indices {
                let extra = min(natural[index] - widths[index], leftover)
                widths[index] += extra
                leftover -= extra
                if leftover <= 0 { break }
            }
        } else if leftover < 0 {
            for index in widths.indices.reversed() {
                let reducible = max(0, widths[index] - 1)
                let take = min(reducible, -leftover)
                widths[index] -= take
                leftover += take
                if leftover >= 0 { break }
            }
        }
        return widths
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
