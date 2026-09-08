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

    @Test("Combined cap is 8 actions and keeps presets over External Ask")
    func combinedCapKeepsPresetsAndFoldsTrailingExternalAsks() {
        let eightPresets = (1...10).map { preset("Preset \($0)") }
        let fiveActions = (1...5).map { action("Action \($0)") }
        let overflow = SelectionActionBarLayout.make(
            presets: eightPresets,
            externalAsks: fiveActions,
            showsLabels: false
        )
        #expect(overflow.visiblePresets.count == 8)
        #expect(overflow.visibleExternalAsks.isEmpty)
        #expect(!overflow.showsDivider)

        let mixed = SelectionActionBarLayout.make(
            presets: Array(eightPresets.prefix(4)),
            externalAsks: fiveActions,
            showsLabels: false
        )
        #expect(mixed.visiblePresets.count == 4)
        #expect(mixed.visibleExternalAsks.count == 4)
        #expect(mixed.showsDivider)

        let asksOnly = SelectionActionBarLayout.make(
            presets: [],
            externalAsks: fiveActions + [action("Action 6"), action("Action 7"), action("Action 8"), action("Action 9")],
            showsLabels: false
        )
        #expect(asksOnly.visiblePresets.isEmpty)
        #expect(asksOnly.visibleExternalAsks.count == 8)
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
        expectButtonsStayInsidePanel(layout)
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
        expectButtonsStayInsidePanel(layout)
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

    @Test("Labeled long prompts stay inside the 400pt panel and remain clickable")
    func labeledLongPromptsStayInsidePanel() {
        let presets = [
            preset("A Very Long Prompt Preset Title That Consumes A Lot Of Space"),
            preset("Another Extremely Long Prompt Preset Title In The Selection Bar"),
            preset("Third Long Prompt Preset Title Taking Remaining Width In Bar")
        ]
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            externalAsks: [],
            showsLabels: true
        )
        #expect(layout.visiblePresets.count == 3)
        #expect(layout.visibleExternalAsks.isEmpty)
        expectButtonsStayInsidePanel(layout)
        let frames = layout.placedItems.map(\.frame)
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.maxX <= SelectionActionBarLayout.maxTotalWidth })
        #expect(frames.allSatisfy { $0.width > 0 })
    }

    @Test("Eight labeled prompts stay inside 400pt")
    func eightLabeledPromptsStayInsidePanel() {
        let presets = (1...8).map { preset("Labeled Prompt Title Number \($0) With Extra Words") }
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            externalAsks: [],
            showsLabels: true
        )
        #expect(layout.visiblePresets.count == 8)
        expectButtonsStayInsidePanel(layout)
    }

    @Test("Eight labeled mixed actions keep prompts and fit the panel")
    func eightLabeledMixedActionsStayInsidePanel() {
        let presets = (1...5).map { preset("Prompt \($0) With A Long Visible Title") }
        let actions = (1...5).map { action("External Ask Target \($0) With A Long Name") }
        let layout = SelectionActionBarLayout.make(
            presets: presets,
            externalAsks: actions,
            showsLabels: true
        )
        #expect(layout.visiblePresets.count == 5)
        #expect(layout.visibleExternalAsks.count <= 3)
        expectButtonsStayInsidePanel(layout)
    }

    private func preset(_ title: String) -> PromptPreset {
        PromptPreset(title: title, instruction: "Do it")
    }

    private func action(_ name: String) -> QuickAction {
        QuickAction(name: name, kind: .web(urlTemplate: "https://example.com/?q={query}"))
    }

    private func expectButtonsStayInsidePanel(_ layout: SelectionActionBarLayout) {
        #expect(layout.size.width <= SelectionActionBarLayout.maxTotalWidth)
        #expect(layout.visiblePresets.count == layout.visiblePresetWidths.count)
        #expect(layout.visibleExternalAsks.count == layout.visibleExternalAskWidths.count)
        let panel = NSRect(origin: .zero, size: layout.size)
        let inset = SelectionActionBarLayout.contentInset
        for item in layout.placedItems {
            let frame = item.frame
            #expect(frame.width > 0)
            #expect(frame.minX >= 0)
            #expect(frame.maxX <= panel.maxX + 0.001)
            #expect(frame.minY >= 0)
            #expect(frame.maxY <= panel.maxY + 0.001)
            switch item {
            case .preset, .externalAsk:
                #expect(frame.minX >= inset - 0.001)
                #expect(frame.maxX <= panel.maxX - inset + 0.001)
            case .divider:
                break
            }
        }
    }
}
