import AppKit
import Foundation
import SwiftUI
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

    @Test("Resolve passes collapseOverflow setting and reflects in layout")
    func resolveReflectsCollapseOverflowSetting() {
        let settings = makeSettings()
        disableEveryPreset(settings)
        addEnabledPresets(count: 6, to: settings)

        settings.selectionActionBarCollapseOverflow = true
        var content = SelectionActionBarContent.resolve(from: settings)
        #expect(content.collapsesOverflow == true)
        #expect(content.layout.showsMoreButton == true)
        #expect(content.layout.showsChat == true)
        // 1 chat + 3 presets = 4 primary actions
        #expect(content.layout.visiblePresets.count == 3)
        #expect(content.layout.overflowPresets.count == 3)

        settings.selectionActionBarCollapseOverflow = false
        content = SelectionActionBarContent.resolve(from: settings)
        #expect(content.collapsesOverflow == false)
        #expect(content.layout.showsMoreButton == false)
        #expect(content.layout.visiblePresets.count == 6)
        #expect(content.layout.overflowPresets.isEmpty)
    }

    @Test("Preview bar with overflow renders more button inertly")
    func previewBarWithOverflowRendersMoreButtonInertly() {
        let presets = (1...6).map { PromptPreset(title: "P\($0)", instruction: "I\($0)") }
        let layout = SelectionActionBarLayout.make(
            showsChat: false,
            presets: presets,
            externalAsks: [],
            showsLabels: false,
            collapsesOverflow: true
        )
        #expect(layout.showsMoreButton)

        let preview = SelectionActionBarContentView(layout: layout, actions: nil)
        let previewButtons = preview.subviews.compactMap { $0 as? NSButton }
        // 4 visible presets + 1 more button = 5 buttons
        #expect(previewButtons.count == 5)
        #expect(previewButtons.allSatisfy { $0.target == nil })
    }

    @Test("Render SelectionAssistantSettingsPage to image for visual verification")
    func renderSettingsPageToImage() throws {
        let settings = makeSettings()
        settings.selectionAssistantEnabled = true
        settings.selectionAssistantMode = .actionBar
        settings.selectionActionBarCollapseOverflow = true
        UserDefaults.standard.set("zh-Hans", forKey: AppLanguage.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey) }
        for isDark in [false, true] {
            let view = SelectionAssistantSettingsPage(
                settings: settings,
                permissionCoordinator: AccessibilityPermissionCoordinator(),
                settingsOpener: MacOSAccessibilityPermissionSettingsOpener(),
                onOpenShortcuts: {}
            )
            .environment(\.colorScheme, isDark ? .dark : .light)
            .frame(width: 580)
            .padding(20)
            .background(isDark ? Color(nsColor: .windowBackgroundColor) : Color.white)

            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 780)
            hosting.layoutSubtreeIfNeeded()

            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let path = isDark ? "/tmp/selection_assistant_page_dark.png" : "/tmp/selection_assistant_page_light.png"
            try data.write(to: URL(fileURLWithPath: path))
        }
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
