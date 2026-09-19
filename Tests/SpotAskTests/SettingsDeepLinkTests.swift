import AppKit
import Foundation
import SwiftUI
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

    /// The whole chain as the app runs it: URL → router → command center →
    /// settings window. A deep link selects a page and nothing else, so no
    /// configuration value and no stored credential may change on the way.
    @Test @MainActor func settingsDeepLinkDispatchSelectsThePageWithoutWritingConfiguration() throws {
        let suiteName = "SettingsDeepLinkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.language = .simplifiedChinese
        settings.silentLaunch = true
        let keyStore = DeepLinkKeyStoreSpy()
        let controller = SettingsWindowController(
            settings: settings,
            keyStore: keyStore,
            providerFactory: DeepLinkNoopProviderFactory(),
            accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator(),
            onClose: {}
        )
        let commandCenter = SpotAskCommandCenter()
        commandCenter.setSettingsPresenter { controller.show(section: $0) }
        let configurationBefore = defaults.persistentDomain(forName: suiteName)

        #expect(SpotAskURLRouter.handle(URL(string: "spotask://settings/about")!, using: commandCenter))

        let window = try #require(
            NSApplication.shared.windows.first { $0.title == L10n.string("settings.title") },
            "A settings deep link must present the settings window"
        )
        defer { window.close() }
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        #expect(isShowingAboutPage(contentView), "The window must show the page the URL named")
        #expect(!hasProviderNameField(contentView))

        // The window reads the current provider's key to fill its field, as it
        // does for any Settings open; the deep link itself must never write.
        #expect(keyStore.saveCount == 0, "A settings deep link must not write stored credentials")
        #expect(keyStore.deleteCount == 0)
        #expect(keyStore.deleteAllCount == 0)
        #expect(
            (defaults.persistentDomain(forName: suiteName) as NSDictionary?) == (configurationBefore as NSDictionary?),
            "A settings deep link must not change configuration"
        )
    }

    /// Only the About page lists the update download sources.
    private func isShowingAboutPage(_ root: NSView) -> Bool {
        descendants(of: NSPopUpButton.self, in: root)
            .contains { $0.itemTitles.contains(UpdateDownloadSource.automatic.title) }
    }

    private func hasProviderNameField(_ root: NSView) -> Bool {
        descendants(of: NSTextField.self, in: root).contains {
            !($0 is NSSecureTextField) && $0.placeholderString == L10n.string("settings.providerNamePlaceholder")
        }
    }

    private func descendants<ViewType: NSView>(of type: ViewType.Type, in root: NSView) -> [ViewType] {
        var result: [ViewType] = []
        if let matchingView = root as? ViewType { result.append(matchingView) }
        for subview in root.subviews {
            result.append(contentsOf: descendants(of: type, in: subview))
        }
        return result
    }
}

private final class DeepLinkKeyStoreSpy: APIKeyStoring, @unchecked Sendable {
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private(set) var deleteAllCount = 0

    func readAPIKey(for providerID: UUID) throws -> String? { nil }

    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        saveCount += 1
    }

    func deleteAPIKey(for providerID: UUID) throws {
        deleteCount += 1
    }

    func deleteAllAPIKeys() throws {
        deleteAllCount += 1
    }
}

private struct DeepLinkNoopProviderFactory: ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider { DeepLinkNoopProvider() }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot { ProviderTargetSnapshot.testValue() }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider { DeepLinkNoopProvider() }
}

private struct DeepLinkNoopProvider: ChatProvider {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func testConnection() async throws {}
}
