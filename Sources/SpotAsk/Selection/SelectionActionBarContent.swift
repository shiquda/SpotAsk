import Foundation

/// What the selection action bar shows for the current settings.
///
/// The live overlay and the Settings preview both resolve their content here,
/// so what Settings previews cannot drift from what a real selection presents.
struct SelectionActionBarContent: Equatable {
    let showsChat: Bool
    let showsLabels: Bool
    let presets: [PromptPreset]
    let externalAsks: [QuickAction]

    /// A bar with no action to offer never appears, so callers showing it must
    /// handle this case instead of rendering an empty shell.
    var isEmpty: Bool {
        !showsChat && presets.isEmpty && externalAsks.isEmpty
    }

    var layout: SelectionActionBarLayout {
        SelectionActionBarLayout.make(
            showsChat: showsChat,
            presets: presets,
            externalAsks: externalAsks,
            showsLabels: showsLabels
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
        return SelectionActionBarContent(
            showsChat: settings.selectionActionBarShowsChatAction,
            showsLabels: settings.selectionActionBarShowsLabels,
            presets: presets,
            externalAsks: externalAsks
        )
    }
}
