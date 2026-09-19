import Foundation
import Testing
@testable import SpotAsk

@MainActor
struct SettingsDeepLinkTests {
    /// Documentation links are published outside the app, so these ids are a
    /// frozen protocol: renaming one silently breaks every existing link until
    /// the next docs deploy, and the fallback then hides the mistake by opening
    /// plain Settings.
    @Test func settingsSectionsExposeFrozenDeepLinkIdentifiers() {
        #expect(
            SettingsSection.allCases.map(\.deepLinkPath) == [
                "provider",
                "prompts",
                "external-ask",
                "selection-assistant",
                "shortcuts",
                "general",
                "appearance",
                "about",
            ]
        )
        for section in SettingsSection.allCases {
            #expect(SettingsSection(deepLinkPath: section.deepLinkPath) == section)
        }
    }

    @Test func deepLinkIdentifiersMatchRegardlessOfCase() {
        #expect(SettingsSection(deepLinkPath: "External-Ask") == .externalAsk)
        #expect(SettingsSection(deepLinkPath: "ABOUT") == .about)
        #expect(SettingsSection(deepLinkPath: " about ") == .about)
    }

    @Test func deepLinkIdentifiersRejectUnknownAndLocalizedValues() {
        #expect(SettingsSection(deepLinkPath: "") == nil)
        #expect(SettingsSection(deepLinkPath: "   ") == nil)
        #expect(SettingsSection(deepLinkPath: "nowhere") == nil)
        #expect(SettingsSection(deepLinkPath: "externalask") == nil)
        #expect(SettingsSection(deepLinkPath: "external ask") == nil)

        // Localized titles are presentation text; sending one over the scheme
        // must not select a page.
        for language in [AppLanguage.english, .simplifiedChinese] {
            let title = L10n.string("settings.externalAsk", language: language)
            #expect(SettingsSection(deepLinkPath: title) == nil, "\(title) is a title, not a protocol id")
            let assistantTitle = L10n.string("settings.selectionAssistant", language: language)
            #expect(SettingsSection(deepLinkPath: assistantTitle) == nil, "\(assistantTitle) is a title, not a protocol id")
        }
    }

    @Test func revealSelectsThePageForBothColdAndRepeatedRequests() {
        let model = SettingsWindowModel()
        #expect(model.selectedSection == .provider)

        // Cold start: the selection is in place before the view is built.
        model.reveal(.general)
        #expect(model.selectedSection == .general)

        // The view clears its sidebar filter on every reveal, so a request for
        // the page already recorded in the model has to stay observable.
        let generation = model.revealGeneration
        model.reveal(.general)
        #expect(model.selectedSection == .general)
        #expect(model.revealGeneration == generation + 1)
    }
}
