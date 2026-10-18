import AppKit

/// What a click on a rendered action bar item does. Passing `nil` instead keeps
/// the bar's exact appearance with no click handling, which is how Settings
/// previews the bar.
struct SelectionActionBarActions {
    var onSelectChat: () -> Void
    var onSelectPreset: (PromptPreset) -> Void
    var onSelectExternalAsk: (QuickAction) -> Void
    var shortcutForChat: InAppShortcut?
    var shortcutForPreset: ((PromptPreset) -> InAppShortcut?)?
    var shortcutForExternalAsk: ((QuickAction) -> InAppShortcut?)?
}

final class OverlayButtonTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

final class MenuItemTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

/// Renders a `SelectionActionBarLayout` as the bar's translucent container and
/// its buttons. The live overlay panel and the Settings preview share this one
/// implementation, so the bar's look cannot diverge between them.
@MainActor
final class SelectionActionBarContentView: NSVisualEffectView {
    private var buttonTargets: [OverlayButtonTarget] = []
    private var menuTargets: [MenuItemTarget] = []
    private weak var moreButton: NSButton?

    init(layout: SelectionActionBarLayout, actions: SelectionActionBarActions?) {
        super.init(frame: NSRect(origin: .zero, size: layout.size))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        render(layout: layout, actions: actions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: SelectionActionBarLayout, actions: SelectionActionBarActions?) {
        frame.size = layout.size
        render(layout: layout, actions: actions)
    }

    private func render(layout: SelectionActionBarLayout, actions: SelectionActionBarActions?) {
        subviews.forEach { $0.removeFromSuperview() }
        buttonTargets.removeAll()

        for item in layout.placedItems {
            switch item {
            case let .item(actionItem, frame):
                switch actionItem.kind {
                case .chat:
                    let target = actions.map { wired in OverlayButtonTarget { wired.onSelectChat() } }
                    if let target { buttonTargets.append(target) }
                    addSubview(makeActionButton(
                        frame: frame,
                        title: "",
                        symbolName: "quote.bubble",
                        brandSlug: nil,
                        showsLabels: false,
                        toolTip: SelectionActionBarLayout.tooltip(
                            name: actionItem.name,
                            shortcut: actions?.shortcutForChat
                        ),
                        accessibilityLabel: actionItem.name,
                        target: target
                    ))
                case let .promptPreset(preset):
                    let target = actions.map { wired in OverlayButtonTarget { wired.onSelectPreset(preset) } }
                    if let target { buttonTargets.append(target) }
                    addSubview(makeActionButton(
                        frame: frame,
                        title: preset.title,
                        symbolName: preset.symbolName,
                        brandSlug: nil,
                        showsLabels: layout.showsLabels,
                        toolTip: SelectionActionBarLayout.tooltip(
                            name: preset.title,
                            shortcut: actions?.shortcutForPreset?(preset)
                        ),
                        accessibilityLabel: preset.title,
                        target: target
                    ))
                case let .externalAsk(action):
                    let target = actions.map { wired in OverlayButtonTarget { wired.onSelectExternalAsk(action) } }
                    if let target { buttonTargets.append(target) }
                    addSubview(makeActionButton(
                        frame: frame,
                        title: action.displayName,
                        symbolName: action.symbolName,
                        brandSlug: action.brandIconSlug,
                        showsLabels: layout.showsLabels,
                        toolTip: SelectionActionBarLayout.tooltip(
                            name: action.displayName,
                            shortcut: actions?.shortcutForExternalAsk?(action)
                        ),
                        accessibilityLabel: L10n.string("selection.actionBar.externalAskAccessibility", action.displayName),
                        target: target
                    ))
                }
            case let .chat(frame):
                let target = actions.map { wired in OverlayButtonTarget { wired.onSelectChat() } }
                if let target { buttonTargets.append(target) }
                addSubview(makeActionButton(
                    frame: frame,
                    title: "",
                    symbolName: "quote.bubble",
                    brandSlug: nil,
                    showsLabels: false,
                    toolTip: SelectionActionBarLayout.tooltip(
                        name: L10n.string("selection.actionBar.chatTooltip"),
                        shortcut: actions?.shortcutForChat
                    ),
                    accessibilityLabel: L10n.string("selection.actionBar.chatTooltip"),
                    target: target
                ))
            case let .preset(index, frame):
                let preset = layout.visiblePresets[index]
                let target = actions.map { wired in OverlayButtonTarget { wired.onSelectPreset(preset) } }
                if let target { buttonTargets.append(target) }
                addSubview(makeActionButton(
                    frame: frame,
                    title: preset.title,
                    symbolName: preset.symbolName,
                    brandSlug: nil,
                    showsLabels: layout.showsLabels,
                    toolTip: SelectionActionBarLayout.tooltip(
                        name: preset.title,
                        shortcut: actions?.shortcutForPreset?(preset)
                    ),
                    accessibilityLabel: preset.title,
                    target: target
                ))
            case let .divider(frame):
                let divider = NSView(frame: frame)
                divider.wantsLayer = true
                divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
                divider.setAccessibilityElement(false)
                addSubview(divider)
            case let .externalAsk(index, frame):
                let action = layout.visibleExternalAsks[index]
                let target = actions.map { wired in OverlayButtonTarget { wired.onSelectExternalAsk(action) } }
                if let target { buttonTargets.append(target) }
                addSubview(makeActionButton(
                    frame: frame,
                    title: action.displayName,
                    symbolName: action.symbolName,
                    brandSlug: action.brandIconSlug,
                    showsLabels: layout.showsLabels,
                    toolTip: SelectionActionBarLayout.tooltip(
                        name: action.displayName,
                        shortcut: actions?.shortcutForExternalAsk?(action)
                    ),
                    accessibilityLabel: L10n.string("selection.actionBar.externalAskAccessibility", action.displayName),
                    target: target
                ))
            case let .more(frame):
                let target = actions.map { wired in
                    OverlayButtonTarget { [weak self] in
                        self?.showOverflowMenu(layout: layout, actions: wired)
                    }
                }
                if let target { buttonTargets.append(target) }
                let btn = makeActionButton(
                    frame: frame,
                    title: "",
                    symbolName: "ellipsis",
                    brandSlug: nil,
                    showsLabels: false,
                    toolTip: L10n.string("selection.actionBar.more"),
                    accessibilityLabel: L10n.string("selection.actionBar.moreAccessibility"),
                    target: target
                )
                moreButton = btn
                addSubview(btn)
            }
        }
    }

    private func makeActionButton(
        frame: NSRect,
        title: String,
        symbolName: String,
        brandSlug: String?,
        showsLabels: Bool,
        toolTip: String,
        accessibilityLabel: String,
        target: OverlayButtonTarget?
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
        if let target {
            button.target = target
            button.action = #selector(OverlayButtonTarget.invoke)
        }
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    private func showOverflowMenu(layout: SelectionActionBarLayout, actions: SelectionActionBarActions) {
        guard let button = moreButton else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuTargets.removeAll()

        if !layout.secondaryItems.isEmpty {
            for item in layout.secondaryItems {
                let menuItem = NSMenuItem(
                    title: item.name,
                    action: #selector(MenuItemTarget.invoke),
                    keyEquivalent: ""
                )
                if let brand = brandImage(for: item.brandSlug, pointSize: 14) {
                    menuItem.image = brand
                } else if let symbol = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.name) {
                    menuItem.image = symbol.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
                }
                let target = MenuItemTarget {
                    switch item.kind {
                    case .chat:
                        actions.onSelectChat()
                    case let .promptPreset(preset):
                        actions.onSelectPreset(preset)
                    case let .externalAsk(action):
                        actions.onSelectExternalAsk(action)
                    }
                }
                menuTargets.append(target)
                menuItem.target = target
                menu.addItem(menuItem)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            return
        }

        for preset in layout.overflowPresets {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(MenuItemTarget.invoke),
                keyEquivalent: ""
            )
            if let symbol = NSImage(systemSymbolName: preset.symbolName, accessibilityDescription: preset.title) {
                item.image = symbol.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            }
            if let shortcut = actions.shortcutForPreset?(preset) {
                let labels = InAppShortcutDisplay.labels(for: shortcut).joined()
                item.toolTip = "\(preset.title)\t\(labels)"
            }
            let target = MenuItemTarget {
                actions.onSelectPreset(preset)
            }
            menuTargets.append(target)
            item.target = target
            menu.addItem(item)
        }

        if !layout.overflowPresets.isEmpty && !layout.overflowExternalAsks.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        for action in layout.overflowExternalAsks {
            let item = NSMenuItem(
                title: action.displayName,
                action: #selector(MenuItemTarget.invoke),
                keyEquivalent: ""
            )
            if let brand = brandImage(for: action.brandIconSlug, pointSize: 14) {
                item.image = brand
            } else if let symbol = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.displayName) {
                item.image = symbol.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            }
            if let shortcut = actions.shortcutForExternalAsk?(action) {
                let labels = InAppShortcutDisplay.labels(for: shortcut).joined()
                item.toolTip = "\(action.displayName)\t\(labels)"
            }
            let target = MenuItemTarget {
                actions.onSelectExternalAsk(action)
            }
            menuTargets.append(target)
            item.target = target
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }
}

private extension SelectionActionBarContentView {
    func brandImage(for slug: String?, pointSize: CGFloat) -> NSImage? {
        guard let slug else { return nil }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let image = ProviderBrandIcon.image(for: slug, dark: isDark) else { return nil }
        let resized = image.copy() as? NSImage ?? image
        resized.size = NSSize(width: pointSize, height: pointSize)
        resized.isTemplate = false
        return resized
    }
}
