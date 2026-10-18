import Foundation

enum SelectionActionBarItemKind: Equatable, Sendable {
    case chat
    case promptPreset(PromptPreset)
    case externalAsk(QuickAction)
}

struct SelectionActionBarItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let kind: SelectionActionBarItemKind
    let name: String
    let symbolName: String
    let brandSlug: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SelectionActionBarItem, rhs: SelectionActionBarItem) -> Bool {
        lhs.id == rhs.id
    }
    var isChat: Bool {
        if case .chat = kind { return true }
        return false
    }

    static func chat() -> SelectionActionBarItem {
        SelectionActionBarItem(
            id: "chat",
            kind: .chat,
            name: L10n.string("selection.actionBar.chat"),
            symbolName: "quote.bubble",
            brandSlug: nil
        )
    }

    static func promptPreset(_ preset: PromptPreset) -> SelectionActionBarItem {
        SelectionActionBarItem(
            id: "preset:\(preset.id.uuidString)",
            kind: .promptPreset(preset),
            name: preset.title,
            symbolName: preset.symbolName,
            brandSlug: nil
        )
    }

    static func externalAsk(_ action: QuickAction) -> SelectionActionBarItem {
        SelectionActionBarItem(
            id: "externalAsk:\(action.id.uuidString)",
            kind: .externalAsk(action),
            name: action.displayName,
            symbolName: action.symbolName,
            brandSlug: action.brandIconSlug
        )
    }
}

/// What the selection action bar shows for the current settings.
///
/// The live overlay and the Settings preview both resolve their content here,
/// so what Settings previews cannot drift from what a real selection presents.
struct SelectionActionBarContent: Equatable {
    let showsChat: Bool
    let showsLabels: Bool
    let presets: [PromptPreset]
    let externalAsks: [QuickAction]
    let collapsesOverflow: Bool
    let primaryItems: [SelectionActionBarItem]
    let secondaryItems: [SelectionActionBarItem]

    init(
        showsChat: Bool,
        showsLabels: Bool,
        presets: [PromptPreset],
        externalAsks: [QuickAction],
        collapsesOverflow: Bool = true,
        primaryItems: [SelectionActionBarItem]? = nil,
        secondaryItems: [SelectionActionBarItem]? = nil
    ) {
        self.showsChat = showsChat
        self.showsLabels = showsLabels
        self.presets = presets
        self.externalAsks = externalAsks
        self.collapsesOverflow = collapsesOverflow

        if let primaryItems, let secondaryItems {
            self.primaryItems = primaryItems
            self.secondaryItems = secondaryItems
        } else {
            var all: [SelectionActionBarItem] = []
            if showsChat { all.append(.chat()) }
            for p in presets { all.append(.promptPreset(p)) }
            for a in externalAsks { all.append(.externalAsk(a)) }

            if collapsesOverflow && all.count > SelectionActionBarLayout.primaryActionLimit {
                self.primaryItems = Array(all.prefix(SelectionActionBarLayout.primaryActionLimit))
                self.secondaryItems = Array(all.dropFirst(SelectionActionBarLayout.primaryActionLimit))
            } else {
                self.primaryItems = all
                self.secondaryItems = []
            }
        }
    }

    /// A bar with no action to offer never appears, so callers showing it must
    /// handle this case instead of rendering an empty shell.
    var isEmpty: Bool {
        primaryItems.isEmpty && secondaryItems.isEmpty
    }

    var layout: SelectionActionBarLayout {
        SelectionActionBarLayout.make(
            showsChat: showsChat,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels,
            collapsesOverflow: collapsesOverflow,
            primaryItems: primaryItems,
            secondaryItems: secondaryItems
        )
    }

    @MainActor
    static func resolve(from settings: AppSettings) -> SelectionActionBarContent {
        let presets = settings.selectionActionBarShowsPrompts
            ? Array(settings.enabledPromptPresets.prefix(SelectionActionBarLayout.maxTotalActions))
            : []
        var externalAsks: [QuickAction] = []
        if settings.externalAskEnabled, settings.selectionActionBarShowsExternalAsk {
            let remaining = max(0, SelectionActionBarLayout.maxTotalActions - presets.count)
            externalAsks = Array(settings.enabledQuickActions.prefix(remaining))
        }

        var allItems: [SelectionActionBarItem] = []
        if settings.selectionActionBarShowsChatAction {
            allItems.append(.chat())
        }
        for preset in presets {
            allItems.append(.promptPreset(preset))
        }
        for action in externalAsks {
            allItems.append(.externalAsk(action))
        }

        let customOrder = settings.selectionActionBarItemOrder
        if !customOrder.isEmpty {
            allItems.sort { a, b in
                let indexA = customOrder.firstIndex(of: a.id) ?? Int.max
                let indexB = customOrder.firstIndex(of: b.id) ?? Int.max
                if indexA != indexB {
                    return indexA < indexB
                }
                return false
            }
        }

        let primaryItems: [SelectionActionBarItem]
        let secondaryItems: [SelectionActionBarItem]

        if !settings.selectionActionBarCollapseOverflow {
            primaryItems = allItems
            secondaryItems = []
        } else {
            let customSecondaryIDs = Set(settings.selectionActionBarSecondaryItemIDs)
            if !customSecondaryIDs.isEmpty {
                var prim: [SelectionActionBarItem] = []
                var sec: [SelectionActionBarItem] = []
                for item in allItems {
                    if customSecondaryIDs.contains(item.id) {
                        sec.append(item)
                    } else {
                        prim.append(item)
                    }
                }
                if prim.isEmpty, let first = sec.first {
                    prim.append(first)
                    sec.removeFirst()
                }
                primaryItems = prim
                secondaryItems = sec
            } else {
                if allItems.count > SelectionActionBarLayout.primaryActionLimit {
                    primaryItems = Array(allItems.prefix(SelectionActionBarLayout.primaryActionLimit))
                    secondaryItems = Array(allItems.dropFirst(SelectionActionBarLayout.primaryActionLimit))
                } else {
                    primaryItems = allItems
                    secondaryItems = []
                }
            }
        }

        return SelectionActionBarContent(
            showsChat: settings.selectionActionBarShowsChatAction,
            showsLabels: settings.selectionActionBarShowsLabels,
            presets: presets,
            externalAsks: externalAsks,
            collapsesOverflow: settings.selectionActionBarCollapseOverflow,
            primaryItems: primaryItems,
            secondaryItems: secondaryItems
        )
    }
}
