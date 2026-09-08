import AppKit
import Testing
@testable import SpotAsk

@Suite("Selection action bar layout")
struct SelectionActionBarLayoutTests {
    @Test("Presets only omit the External Ask separator")
    func presetsOnlyOmitSeparator() {
        let layout = SelectionActionBarLayout.make(
            presets: [preset("Translate"), preset("Explain")],
            quickActions: [],
            showsLabels: false
        )
        #expect(layout.visiblePresets.count == 2)
        #expect(layout.visibleQuickActions.isEmpty)
        #expect(!layout.showsSeparator)
        #expect(!layout.showsMore)
        #expect(layout.size.width == 8 + 28 + 2 + 28)
        #expect(layout.size.height == 36)
    }

    @Test("External Ask actions sit behind a 13pt separator")
    func compactExternalAskUsesSeparator() {
        let layout = SelectionActionBarLayout.make(
            presets: [preset("Translate"), preset("Explain")],
            quickActions: [action("ChatGPT"), action("Grok"), action("Terminal")],
            showsLabels: false
        )
        #expect(layout.showsSeparator)
        #expect(!layout.showsMore)
        #expect(layout.visibleQuickActions.count == 3)
        #expect(layout.size.width == 8 + 58 + 13 + 88)
    }

    @Test("A fifth External Ask action folds into More")
    func fifthQuickActionFoldsIntoMore() {
        let actions = (1...5).map { action("Action \($0)") }
        let layout = SelectionActionBarLayout.make(
            presets: [preset("Translate")],
            quickActions: actions,
            showsLabels: false
        )
        #expect(layout.visibleQuickActions.map(\.name) == ["Action 1", "Action 2", "Action 3", "Action 4"])
        #expect(layout.overflowQuickActions.map(\.name) == ["Action 5"])
        #expect(layout.showsMore)
        #expect(layout.showsSeparator)
    }

    @Test("Labeled mode stays at or under 480pt by folding External Ask first")
    func labeledModeFoldsExternalAskToFit() {
        let presets = [
            preset("Translate Selected Text Now"),
            preset("Explain Selected Text Now"),
            preset("Summarize Selected Text Now"),
            preset("Polish Selected Text Now")
        ]
        let actions = [
            action("Ask ChatGPT About This Selection"),
            action("Ask Grok About This Selection"),
            action("Open Custom App With Selection"),
            action("Run Terminal Command With Selection")
        ]
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            quickActions: actions,
            showsLabels: true
        )
        #expect(layout.size.width <= 480)
        #expect(layout.visiblePresets.count == 4)
        #expect(layout.visibleQuickActions.count < 4 || layout.overflowQuickActions.isEmpty)
        #expect(layout.overflowPresets.isEmpty)
        #expect(layout.showsMore)
    }

    @Test("Extreme labeled overflow folds presets only after External Ask is gone")
    func labeledModeFoldsPresetsAfterExternalAsk() {
        let presets = (1...4).map { preset(String(repeating: "PresetTitle", count: $0 + 3)) }
        let actions = (1...4).map { action(String(repeating: "ExternalAskTitle", count: $0 + 3)) }
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            quickActions: actions,
            showsLabels: true
        )
        #expect(layout.size.width <= 480)
        if !layout.visibleQuickActions.isEmpty {
            #expect(layout.overflowPresets.isEmpty)
        }
    }

    @Test("Tooltips include type and shortcut for External Ask")
    func tooltipIncludesKindAndShortcut() {
        let shortcut = InAppShortcut.commandShift("1")
        #expect(
            SelectionActionBarLayout.tooltip(
                name: "Ask ChatGPT",
                kind: "网页提问",
                shortcut: shortcut
            ) == "Ask ChatGPT — 网页提问（⌘⇧1）"
        )
        #expect(
            SelectionActionBarLayout.tooltip(
                name: "Translate",
                kind: nil,
                shortcut: shortcut
            ) == "Translate（⌘⇧1）"
        )
    }

    private func preset(_ title: String) -> PromptPreset {
        PromptPreset(title: title, instruction: "Do it")
    }

    private func action(_ name: String) -> QuickAction {
        QuickAction(name: name, kind: .web(urlTemplate: "https://example.com/?q={query}"))
    }
}
