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

/// Renders a `SelectionActionBarLayout` as the bar's translucent container and
/// its buttons. The live overlay panel and the Settings preview share this one
/// implementation, so the bar's look cannot diverge between them.
@MainActor
final class SelectionActionBarContentView: NSVisualEffectView {
    private var buttonTargets: [OverlayButtonTarget] = []

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
