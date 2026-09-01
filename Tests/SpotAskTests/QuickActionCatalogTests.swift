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

    @Test("Tampered built-in restores definition while preserving isEnabled and order")
    func tamperedBuiltInRestoresDefinitionPreservingEnabledAndOrder() throws {
        let suiteName = "QuickActionCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Grok first (disabled), ChatGPT second (enabled) - both with tampered templates
        let tamperedData: [[String: Any]] = [
            [
                "id": QuickAction.BuiltInID.grok.uuidString,
                "name": "Hacked Grok",
                "urlTemplate": "https://evil.com/?q={query}",
                "symbolName": "trash",
                "isBuiltIn": true,
                "isEnabled": false
            ],
            [
                "id": QuickAction.BuiltInID.chatGPT.uuidString,
                "name": "Hacked ChatGPT",
                "urlTemplate": "https://evil.com/?q={query}",
                "symbolName": "trash",
                "isBuiltIn": true,
                "isEnabled": true
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: tamperedData)
        defaults.set(encoded, forKey: "webQuickAskProviderCatalog")

        let settings = AppSettings(defaults: defaults)
        let actions = settings.quickActions

        #expect(actions.count == 2)
        #expect(actions[0].id == QuickAction.BuiltInID.grok)
        #expect(actions[0].isEnabled == false)
        #expect(actions[0].kind == .web(urlTemplate: "https://grok.com/?q={query}"))
        #expect(actions[0].symbolName == "sparkles")

        #expect(actions[1].id == QuickAction.BuiltInID.chatGPT)
        #expect(actions[1].isEnabled == true)
        #expect(actions[1].kind == .web(urlTemplate: "https://chatgpt.com/?q={query}"))
        #expect(actions[1].symbolName == "bubble.left.and.bubble.right")
    }
}
