import AppKit
import Testing
@testable import SpotAsk

@Suite("Selection action bar layout")
struct SelectionActionBarLayoutTests {
    @Test("Presets only omit the External Ask divider")
    func presetsOnlyOmitDivider() {
        let layout = SelectionActionBarLayout.make(
            presets: [preset("Translate"), preset("Explain")],
            externalAsks: [],
            showsLabels: false
        )
        #expect(layout.visiblePresets.count == 2)
        #expect(layout.visibleExternalAsks.isEmpty)
        #expect(!layout.showsDivider)
        #expect(layout.size.width == 66.0)
        #expect(layout.size.height == 36.0)
    }

    @Test("External Asks sit behind a 9pt divider (1pt line + 4pt margins)")
    func compactExternalAskUsesDivider() {
        let layout = SelectionActionBarLayout.make(
            presets: [preset("Translate"), preset("Explain")],
            externalAsks: [action("ChatGPT"), action("Grok"), action("Terminal")],
            showsLabels: false
        )
        #expect(layout.showsDivider)
        #expect(layout.visiblePresets.count == 2)
        #expect(layout.visibleExternalAsks.count == 3)
        // insets (8) + presets (28*2 + 2 = 58) + divider (9) + external asks (28*3 + 4 = 88) = 163
        #expect(layout.size.width == 163.0)
        #expect(layout.size.width <= 400)
    }

    @Test("Combined cap is 6 actions and keeps presets over External Ask")
    func combinedCapKeepsPresetsAndFoldsTrailingExternalAsks() {
        let sixPresets = (1...8).map { preset("Preset \($0)") }
        let fiveActions = (1...5).map { action("Action \($0)") }
        let overflow = SelectionActionBarLayout.make(
            presets: sixPresets,
            externalAsks: fiveActions,
            showsLabels: false
        )
        #expect(overflow.visiblePresets.count == 6)
        #expect(overflow.visibleExternalAsks.isEmpty)
        #expect(!overflow.showsDivider)

        let mixed = SelectionActionBarLayout.make(
            presets: Array(sixPresets.prefix(4)),
            externalAsks: fiveActions,
            showsLabels: false
        )
        #expect(mixed.visiblePresets.count == 4)
        #expect(mixed.visibleExternalAsks.count == 2)
        #expect(mixed.showsDivider)

        let asksOnly = SelectionActionBarLayout.make(
            presets: [],
            externalAsks: fiveActions + [action("Action 6"), action("Action 7")],
            showsLabels: false
        )
        #expect(asksOnly.visiblePresets.isEmpty)
        #expect(asksOnly.visibleExternalAsks.count == 6)
        #expect(!asksOnly.showsDivider)
    }

    @Test("Divider is omitted when presets are empty")
    func emptyPresetsOmitsDivider() {
        let layout = SelectionActionBarLayout.make(
            presets: [],
            externalAsks: [action("ChatGPT")],
            showsLabels: false
        )
        #expect(!layout.showsDivider)
        #expect(layout.visiblePresets.isEmpty)
        #expect(layout.visibleExternalAsks.count == 1)
    }

    @Test("Labeled mode caps total width at 400pt by truncating External Ask")
    func labeledModeCapsWidthAt400ptByTruncating() {
        let presets = [
            preset("Translate"),
            preset("Explain")
        ]
        let actions = [
            action("Ask ChatGPT A Very Long Question That Exceeds Normal Length"),
            action("Ask Grok A Very Long Question That Exceeds Normal Length"),
            action("Run Terminal Command A Very Long Question That Exceeds Normal Length")
        ]
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            externalAsks: actions,
            showsLabels: true
        )
        #expect(layout.size.width <= 400)
        #expect(layout.visiblePresets.count == 2)
        // Should truncate titles to fit within 400pt
        for width in layout.visibleExternalAskWidths {
            #expect(width >= 48)
        }
    }

    @Test("Extreme labeled overflow drops trailing External Ask buttons while keeping presets")
    func labeledModeDropsTrailingExternalAsksWhenMin48Exceeds() {
        let presets = [
            preset("A Very Long Prompt Preset Title That Consumes A Lot Of Space"),
            preset("Another Extremely Long Prompt Preset Title In The Selection Bar"),
            preset("Third Long Prompt Preset Title Taking Remaining Width In Bar")
        ]
        let actions = [
            action("Action 1"),
            action("Action 2"),
            action("Action 3")
        ]
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            externalAsks: actions,
            showsLabels: true
        )
        #expect(layout.size.width <= 400)
        #expect(layout.visiblePresets.count == 3)
        // External asks should be dropped to 0 or 1 to fit under 400
        #expect(layout.visibleExternalAsks.count < 3)
    }

    @Test("Tooltips append tab-separated shortcut when assigned")
    func tooltipAppendsTabSeparatedShortcut() {
        let shortcut = InAppShortcut.commandShift("1")
        #expect(
            SelectionActionBarLayout.tooltip(
                name: "Ask ChatGPT",
                shortcut: shortcut
            ) == "Ask ChatGPT\t⌘⇧1"
        )
        #expect(
            SelectionActionBarLayout.tooltip(
                name: "Translate",
                shortcut: nil
            ) == "Translate"
        )
    }

    private func preset(_ title: String) -> PromptPreset {
        PromptPreset(title: title, instruction: "Do it")
    }

    private func action(_ name: String) -> QuickAction {
        QuickAction(name: name, kind: .web(urlTemplate: "https://example.com/?q={query}"))
    }
}
