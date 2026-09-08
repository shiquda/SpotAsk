import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Selection action bar layout")
struct SelectionActionBarLayoutTests {
    @Test("Compact mixed bar includes a divider and stays under the width cap")
    func compactMixedBarIncludesDivider() {
        let plan = SelectionActionBarLayout.plan(
            presetTitles: ["Translate", "Summarize", "Explain", "Polish"],
            externalAskTitles: ["Ask ChatGPT", "Ask Grok"],
            showsLabels: false
        )

        #expect(plan.presetWidths.count == 4)
        #expect(plan.externalAskWidths == [28, 28])
        #expect(plan.showsDivider)
        #expect(plan.size.width <= SelectionActionBarLayout.maxBarWidth)
        #expect(plan.size.width == SelectionActionBarLayout.barWidth(
            presetWidths: plan.presetWidths,
            askWidths: plan.externalAskWidths
        ))
        #expect(plan.size.height == 36)
    }

    @Test("A single group does not render a divider")
    func singleGroupOmitsDivider() {
        let presetsOnly = SelectionActionBarLayout.plan(
            presetTitles: ["Translate"],
            externalAskTitles: [],
            showsLabels: false
        )
        let asksOnly = SelectionActionBarLayout.plan(
            presetTitles: [],
            externalAskTitles: ["Ask ChatGPT"],
            showsLabels: false
        )

        #expect(!presetsOnly.showsDivider)
        #expect(!asksOnly.showsDivider)
        #expect(asksOnly.visibleExternalAskCount == 1)
    }

    @Test("Labeled overflow truncates External Ask titles before dropping them")
    func labeledOverflowTruncatesThenDrops() {
        let longTitle = String(repeating: "Ask a very long external service ", count: 4)
        let plan = SelectionActionBarLayout.plan(
            presetTitles: ["Translate", "Summarize", "Explain", "Polish"],
            externalAskTitles: [longTitle, longTitle, longTitle],
            showsLabels: true
        )

        #expect(plan.size.width <= SelectionActionBarLayout.maxBarWidth)
        #expect(plan.presetWidths.count == 4)
        #expect(!plan.externalAskWidths.isEmpty)
        #expect(plan.externalAskWidths.allSatisfy { $0 >= SelectionActionBarLayout.minLabeledExternalWidth })
        #expect(plan.externalAskWidths.contains { $0 < SelectionActionBarLayout.actionButtonWidth(for: longTitle) })
    }

    @Test("Compact overflow drops trailing External Ask actions")
    func compactOverflowDropsTrailingAsks() {
        let manyAsks = Array(repeating: "Ask", count: 20)
        let plan = SelectionActionBarLayout.plan(
            presetTitles: Array(repeating: "P", count: 4),
            externalAskTitles: manyAsks,
            showsLabels: false
        )

        #expect(plan.visibleExternalAskCount <= SelectionActionBarLayout.maxExternalAsks)
        #expect(plan.size.width <= SelectionActionBarLayout.maxBarWidth)
    }

    @Test("Tooltip appends a compact shortcut description")
    func tooltipIncludesShortcut() {
        let shortcut = InAppShortcut(key: "1", modifiers: [.command, .shift])
        #expect(
            SelectionActionBarLayout.tooltip(displayName: "Ask ChatGPT", shortcut: shortcut)
            == "Ask ChatGPT\t⌘⇧1"
        )
        #expect(SelectionActionBarLayout.tooltip(displayName: "Ask ChatGPT", shortcut: nil) == "Ask ChatGPT")
    }
}
