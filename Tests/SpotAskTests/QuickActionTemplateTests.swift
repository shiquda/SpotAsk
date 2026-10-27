import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpotAsk
@MainActor
struct QuickActionTemplateTests {
    @Test("All preset templates are valid and contain query placeholder")
    func allTemplatesAreValid() {
        let templates = QuickActionTemplate.allTemplates
        #expect(templates.count >= 8)

        for template in templates {
            #expect(!template.id.isEmpty)
            #expect(!template.name.isEmpty)
            #expect(!template.category.isEmpty)
            #expect(!template.description.isEmpty)
            #expect(!template.defaultRoutingPurpose.isEmpty)
            #expect(!template.defaultRoutingScenario.isEmpty)
            #expect(QuickAction.isValidSymbol(template.symbolName))

            // Validate that the template string contains {query}
            #expect(template.kind.template.contains("{query}"))

            // Validate with QuickActionBuilder
            let validation = QuickActionBuilder.validate(kind: template.kind)
            #expect(validation == .valid)
        }
    }

    @Test("makeQuickAction creates ready-to-use custom action with routing metadata")
    func makeQuickActionProducesConfiguredAction() {
        guard let claudeTemplate = QuickActionTemplate.allTemplates.first(where: { $0.id == "claude" }) else {
            Issue.record("Claude template missing")
            return
        }

        let action = claudeTemplate.makeQuickAction()
        #expect(action.name == "Claude")
        #expect(action.isBuiltIn == false)
        #expect(action.isEnabled == true)
        #expect(action.symbolName == "sparkles")
        #expect(action.kind == .web(urlTemplate: "https://claude.ai/new?q={query}"))
        #expect(action.routingPurpose == claudeTemplate.defaultRoutingPurpose)
        #expect(action.routingScenario == claudeTemplate.defaultRoutingScenario)
        #expect(action.requiresConfirmationOnAutoRoute == false)
    }

    @Test("isConfigured detects existing matching channels")
    func isConfiguredMatchesByTemplateOrName() {
        guard let perplexity = QuickActionTemplate.allTemplates.first(where: { $0.id == "perplexity" }),
              let deepseek = QuickActionTemplate.allTemplates.first(where: { $0.id == "deepseek" }) else {
            Issue.record("Templates missing")
            return
        }

        let actions = [
            QuickAction(
                name: "Perplexity AI",
                kind: .web(urlTemplate: "https://www.perplexity.ai/search?q={query}"),
                symbolName: "globe"
            )
        ]

        #expect(perplexity.isConfigured(in: actions) == true)
        #expect(deepseek.isConfigured(in: actions) == false)
    }

    @Test("AppSettings addQuickAction saves and persists template successfully")
    func appSettingsAddQuickActionPersists() {
        let suiteName = "QuickActionTemplateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let initialCount = settings.quickActions.count

        guard let deepseek = QuickActionTemplate.allTemplates.first(where: { $0.id == "deepseek" }) else {
            Issue.record("DeepSeek template missing")
            return
        }

        let added = settings.addQuickAction(from: deepseek)
        #expect(added != nil)
        #expect(settings.quickActions.count == initialCount + 1)
        #expect(deepseek.isConfigured(in: settings.quickActions) == true)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.quickActions.count == initialCount + 1)
        let savedDeepseek = reloaded.quickActions.first { $0.name == "DeepSeek" }
        #expect(savedDeepseek != nil)
        #expect(savedDeepseek?.routingPurpose == deepseek.defaultRoutingPurpose)
        #expect(savedDeepseek?.routingScenario == deepseek.defaultRoutingScenario)
    }

    @Test("Add channel localization strings exist across supported languages")
    func addChannelLocalizationStringsExist() {
        for lang in AppLanguage.allCases {
            let addChannel = L10n.string("externalAsk.addChannel", language: lang)
            let customChannel = L10n.string("externalAsk.customChannel", language: lang)
            #expect(!addChannel.isEmpty)
            #expect(!addChannel.hasPrefix("externalAsk."))
            #expect(!customChannel.isEmpty)
            #expect(!customChannel.hasPrefix("externalAsk."))
        }
    }

    @Test("Capture ExternalAskSettingsPage screenshot for visual verification")
    func captureExternalAskSettingsScreenshot() throws {
        let suiteName = "QuickActionTemplateTests.Screenshots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let previousLang = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.defaultsKey)
        defer {
            if let previousLang {
                UserDefaults.standard.set(previousLang, forKey: AppLanguage.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
            }
        }
        settings.language = .simplifiedChinese
        let externalAskView = ExternalAskSettingsPage(
            settings: settings,
            keyStore: MockTestKeyStore()
        )
        .frame(width: 580)
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: externalAskView)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 700)
        hosting.layoutSubtreeIfNeeded()

        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                let outURL = URL(fileURLWithPath: "../attachments/external_ask_settings_preview.png")
                try? pngData.write(to: outURL)
            }
        }
    }
}

private final class MockTestKeyStore: APIKeyStoring, @unchecked Sendable {
    func readAPIKey(for providerID: UUID) throws -> String? { nil }
    func saveAPIKey(_ key: String, for providerID: UUID) throws {}
    func deleteAPIKey(for providerID: UUID) throws {}
    func deleteAllAPIKeys() throws {}
}
