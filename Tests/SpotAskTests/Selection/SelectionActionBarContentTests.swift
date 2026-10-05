import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Selection action bar content")
@MainActor
struct SelectionActionBarContentTests {

    @Test("Prompts and External Ask each need their own switch and their master switch")
    func sourcesFollowTheirOwnSwitches() {
        let settings = makeSettings()
        settings.selectionActionBarShowsPrompts = false
        settings.selectionActionBarShowsExternalAsk = false

        var content = SelectionActionBarContent.resolve(from: settings)
        #expect(content.presets.isEmpty)
        #expect(content.externalAsks.isEmpty)

        settings.selectionActionBarShowsPrompts = true
        content = SelectionActionBarContent.resolve(from: settings)
        #expect(!content.presets.isEmpty)

        settings.selectionActionBarShowsExternalAsk = true
        settings.externalAskEnabled = false
        content = SelectionActionBarContent.resolve(from: settings)
        #expect(content.externalAsks.isEmpty, "the External Ask master switch alone gates the preview")

        settings.externalAskEnabled = true
        content = SelectionActionBarContent.resolve(from: settings)
        #expect(!content.externalAsks.isEmpty)
    }

    @Test("Prompts fill the action slots first, so External Ask only gets what is left")
    func promptsCapBeforeExternalAsks() {
        let settings = makeSettings()
        disableEveryPreset(settings)
        addEnabledPresets(count: SelectionActionBarLayout.maxTotalActions + 2, to: settings)
        addEnabledQuickActions(count: 4, to: settings)

        var content = SelectionActionBarContent.resolve(from: settings)
        #expect(content.presets.count == SelectionActionBarLayout.maxTotalActions)
        #expect(content.externalAsks.isEmpty)

        disableEveryPreset(settings)
        addEnabledPresets(count: 6, to: settings)
        content = SelectionActionBarContent.resolve(from: settings)
        #expect(content.presets.count == 6)
        #expect(content.externalAsks.count == SelectionActionBarLayout.maxTotalActions - 6)
    }

    @Test("The content is empty only when chat, prompts, and External Ask are all off")
    func emptyOnlyWhenEverySourceIsOff() {
        let settings = makeSettings()
        settings.selectionActionBarShowsChatAction = false
        settings.selectionActionBarShowsPrompts = false
        settings.selectionActionBarShowsExternalAsk = false
        #expect(SelectionActionBarContent.resolve(from: settings).isEmpty)

        settings.selectionActionBarShowsChatAction = true
        #expect(!SelectionActionBarContent.resolve(from: settings).isEmpty)
    }

    @Test("A preview bar renders the same items but stays inert, while the live bar runs the click")
    func previewRendersItemsWithoutWiringClicks() {
        let preset = PromptPreset(title: "Translate", instruction: "Translate this")
        let layout = SelectionActionBarLayout.make(
            showsChat: true,
            presets: [preset],
            externalAsks: [],
            showsLabels: true
        )

        var chatClicks = 0
        let live = SelectionActionBarContentView(
            layout: layout,
            actions: SelectionActionBarActions(
                onSelectChat: { chatClicks += 1 },
                onSelectPreset: { _ in },
                onSelectExternalAsk: { _ in },
                shortcutForChat: nil,
                shortcutForPreset: nil,
                shortcutForExternalAsk: nil
            )
        )
        let liveButtons = live.subviews.compactMap { $0 as? NSButton }
        #expect(liveButtons.count == 2)
        liveButtons.first?.performClick(nil)
        #expect(chatClicks == 1)

        let preview = SelectionActionBarContentView(layout: layout, actions: nil)
        let previewButtons = preview.subviews.compactMap { $0 as? NSButton }
        #expect(previewButtons.count == 2)
        #expect(previewButtons.allSatisfy { $0.target == nil })
        #expect(previewButtons.allSatisfy { ($0.toolTip ?? "").isEmpty == false })
        previewButtons.forEach { $0.performClick(nil) }
        #expect(chatClicks == 1, "preview buttons must not run a live action")
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "SelectionActionBarContentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private func disableEveryPreset(_ settings: AppSettings) {
        for preset in settings.promptPresets {
            settings.setPromptPresetEnabled(id: preset.id, isEnabled: false)
        }
    }

    private func addEnabledPresets(count: Int, to settings: AppSettings) {
        for index in 0 ..< count {
            let preset = PromptPreset(title: "Preset \(index)", instruction: "Instruction \(index)")
            #expect(settings.saveCustomPromptPreset(preset))
        }
    }

    private func addEnabledQuickActions(count: Int, to settings: AppSettings) {
        for index in 0 ..< count {
            let action = QuickAction(name: "Ask \(index)", urlTemplate: "https://example\(index).com/?q={query}")
            #expect(settings.saveCustomQuickAction(action))
        }
    }
}
