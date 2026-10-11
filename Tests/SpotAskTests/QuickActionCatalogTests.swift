import Foundation
import Testing
@testable import SpotAsk

@MainActor
struct QuickActionCatalogTests {
    @Test("Fresh install initializes default ChatGPT enabled and Grok disabled")
    func freshInstallLoadsDefaultBuiltInCatalog() {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        #expect(settings.quickActions.count == 2)
        #expect(settings.quickActions.map(\.id) == [
            QuickAction.BuiltInID.chatGPT,
            QuickAction.BuiltInID.grok
        ])
        #expect(settings.enabledQuickActions.count == 1)
        #expect(settings.customQuickActions.isEmpty)

        let chatGPT = settings.quickActions[0]
        #expect(chatGPT.isBuiltIn == true)
        #expect(chatGPT.isEnabled == true)
        #expect(chatGPT.kind == .web(urlTemplate: "https://chatgpt.com/?q={query}"))
        #expect(chatGPT.symbolName == "bubble.left.and.bubble.right")
        #expect(chatGPT.displayName == L10n.string("externalAsk.askChatGPT"))

        let grok = settings.quickActions[1]
        #expect(grok.isBuiltIn == true)
        #expect(grok.isEnabled == false)
        #expect(grok.kind == .web(urlTemplate: "https://grok.com/?q={query}"))
        #expect(grok.symbolName == "sparkles")
        #expect(grok.displayName == L10n.string("externalAsk.askGrok"))
    }

    @Test("Catalog persists and round-trips correctly for all 3 kinds")
    func catalogRoundTrip() {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let customWeb = QuickAction(
            name: "Phind",
            kind: .web(urlTemplate: "https://www.phind.com/search?q={query}"),
            symbolName: "magnifyingglass"
        )
        let customURI = QuickAction(
            name: "App Ask",
            kind: .uriScheme(urlTemplate: "someapp://ask?q={query}"),
            symbolName: "link"
        )
        let customTerminal = QuickAction(
            name: "OMP",
            kind: .terminal(commandTemplate: "omp {query}"),
            symbolName: "terminal"
        )

        #expect(settings.saveCustomQuickAction(customWeb))
        #expect(settings.saveCustomQuickAction(customURI))
        #expect(settings.saveCustomQuickAction(customTerminal))

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.quickActions.count == 5)
        #expect(reloaded.customQuickActions == [customWeb, customURI, customTerminal])
        #expect(reloaded.customQuickActions[0].displayName == "Phind")
        #expect(reloaded.customQuickActions[1].kind == .uriScheme(urlTemplate: "someapp://ask?q={query}"))
        #expect(reloaded.customQuickActions[2].kind == .terminal(commandTemplate: "omp {query}"))
    }

    @Test("Legacy flat JSON decodes urlTemplate to .web kind")
    func legacyFlatJSONDecodesToWebKind() throws {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let customID = UUID()
        let legacyData: [[String: Any]] = [
            [
                "id": QuickAction.BuiltInID.chatGPT.uuidString,
                "name": "ChatGPT",
                "urlTemplate": "https://chatgpt.com/?q={query}",
                "symbolName": "bubble.left.and.bubble.right",
                "isBuiltIn": true,
                "isEnabled": true
            ],
            [
                "id": customID.uuidString,
                "name": "Legacy Web",
                "urlTemplate": "https://legacy.example.com/?q={query}",
                "symbolName": "globe",
                "isBuiltIn": false,
                "isEnabled": true
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: legacyData)
        defaults.set(encoded, forKey: "webQuickAskProviderCatalog")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.quickActions.count == 3) // ChatGPT + Custom + auto-appended Grok
        #expect(settings.enabledQuickActions.count == 2)

        let custom = settings.quickActions.first { $0.id == customID }
        #expect(custom?.name == "Legacy Web")
        #expect(custom?.kind == .web(urlTemplate: "https://legacy.example.com/?q={query}"))
    }

    @Test("Corrupt JSON falls back safely to built-ins")
    func corruptJSONFallsBackToBuiltIns() {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("not valid json data".data(using: .utf8), forKey: "webQuickAskProviderCatalog")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.quickActions == QuickAction.builtIn)
    }

    @Test("Duplicate UUIDs are deduplicated taking the first occurrence")
    func duplicateUUIDsAreDeduplicated() throws {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let duplicateID = UUID()
        let duplicateData: [[String: Any]] = [
            [
                "id": duplicateID.uuidString,
                "name": "First Occurrence",
                "urlTemplate": "https://first.com/?q={query}",
                "symbolName": "globe",
                "isBuiltIn": false,
                "isEnabled": true
            ],
            [
                "id": duplicateID.uuidString,
                "name": "Second Occurrence",
                "urlTemplate": "https://second.com/?q={query}",
                "symbolName": "globe",
                "isBuiltIn": false,
                "isEnabled": true
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: duplicateData)
        defaults.set(encoded, forKey: "webQuickAskProviderCatalog")

        let settings = AppSettings(defaults: defaults)
        let customItems = settings.customQuickActions
        #expect(customItems.count == 1)
        #expect(customItems.first?.name == "First Occurrence")
        #expect(customItems.first?.kind == .web(urlTemplate: "https://first.com/?q={query}"))
    }

    @Test("Saved built-in edits persist, including a changed link")
    func savedBuiltInEditsPersistAcrossReload() throws {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        var chatGPT = settings.quickActions.first { $0.id == QuickAction.BuiltInID.chatGPT }!
        chatGPT.name = "My ChatGPT"
        chatGPT.kind = .web(urlTemplate: "https://chatgpt.com/c/{query}")
        chatGPT.symbolName = "bolt"
        chatGPT.routingPurpose = "Browser drafts"
        #expect(settings.saveQuickAction(chatGPT))

        let reloaded = AppSettings(defaults: defaults)
        let saved = reloaded.quickActions.first { $0.id == QuickAction.BuiltInID.chatGPT }
        #expect(saved?.isBuiltIn == true)
        #expect(saved?.displayName == "My ChatGPT")
        #expect(saved?.kind == .web(urlTemplate: "https://chatgpt.com/c/{query}"))
        #expect(saved?.symbolName == "bolt")
        #expect(saved?.routingPurpose == "Browser drafts")
    }

    @Test("Deleted built-ins stay deleted while a missing new built-in still appears")
    func deletedBuiltInStaysGoneAndUntombstonedBuiltInReturns() throws {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.deleteQuickAction(id: QuickAction.BuiltInID.chatGPT)
        #expect(settings.quickActions.contains { $0.id == QuickAction.BuiltInID.chatGPT } == false)

        let encoded = try JSONDecoder().decode([QuickAction].self, from: defaults.data(forKey: "webQuickAskProviderCatalog")!)
        let withoutGrok = encoded.filter { $0.id != QuickAction.BuiltInID.grok }
        defaults.set(try JSONEncoder().encode(withoutGrok), forKey: "webQuickAskProviderCatalog")

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.quickActions.contains { $0.id == QuickAction.BuiltInID.chatGPT } == false)
        #expect(reloaded.quickActions.contains { $0.id == QuickAction.BuiltInID.grok })
    }

    @Test("Invalid built-in template falls back to the official link")
    func invalidBuiltInTemplateFallsBackToOfficialLink() throws {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tamperedData: [[String: Any]] = [
            [
                "id": QuickAction.BuiltInID.grok.uuidString,
                "name": "Hacked Grok",
                "urlTemplate": "not a link",
                "symbolName": "not.a.symbol",
                "isBuiltIn": true,
                "isEnabled": false
            ],
            [
                "id": QuickAction.BuiltInID.chatGPT.uuidString,
                "name": "Hacked ChatGPT",
                "urlTemplate": "https://chatgpt.com/?q={query}",
                "symbolName": "trash",
                "isBuiltIn": false,
                "isEnabled": true
            ]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: tamperedData), forKey: "webQuickAskProviderCatalog")

        let settings = AppSettings(defaults: defaults)
        let grok = settings.quickActions[0]
        #expect(grok.id == QuickAction.BuiltInID.grok)
        #expect(grok.isEnabled == false)
        #expect(grok.kind == .web(urlTemplate: "https://grok.com/?q={query}"))
        #expect(grok.symbolName == "globe")
        #expect(grok.displayName == L10n.string("externalAsk.askGrok"))

        let chatGPT = settings.quickActions[1]
        #expect(chatGPT.isBuiltIn)
        #expect(chatGPT.isEnabled)
        #expect(chatGPT.symbolName == "trash")
        #expect(chatGPT.displayName == L10n.string("externalAsk.askChatGPT"))
    }

    @Test("All available picker symbols are valid SF Symbols and have localized labels")
    func availableSymbolsAreValidAndLocalized() {
        #expect(QuickAction.availableSymbols.count == 20)
        for symbol in QuickAction.availableSymbols {
            #expect(QuickAction.isValidSymbol(symbol))
            let label = QuickAction.localizedSymbolLabel(for: symbol)
            #expect(!label.isEmpty)
        }
    }
}
