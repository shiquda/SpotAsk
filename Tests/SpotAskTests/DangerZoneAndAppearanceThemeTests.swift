import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpotAsk

@MainActor
struct DangerZoneAndAppearanceThemeTests {

    // MARK: - Appearance Theme Picker Tests

    @Test func appearanceModeAllCasesRepresentedInThemePicker() {
        #expect(AppearanceMode.allCases.count == 3)
        #expect(AppearanceMode.allCases == [.system, .light, .dark])

        for mode in AppearanceMode.allCases {
            let titleEn = L10n.string("appearance.\(mode.rawValue)", language: .english)
            let titleZh = L10n.string("appearance.\(mode.rawValue)", language: .simplifiedChinese)

            #expect(!titleEn.isEmpty)
            #expect(!titleZh.isEmpty)
            #expect(titleEn != "appearance.\(mode.rawValue)")
            #expect(titleZh != "appearance.\(mode.rawValue)")
        }

        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)

        #expect(AppearanceMode.system.nsAppearance == nil)
        #expect(AppearanceMode.light.nsAppearance?.name == .aqua)
        #expect(AppearanceMode.dark.nsAppearance?.name == .darkAqua)
    }

    @Test func appearanceSettingsPageUpdatesWindowAppearanceInstantly() {
        let suiteName = "DangerZoneAndAppearanceThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        settings.appearance = .light
        settings.appearance.apply(to: window)
        #expect(window.appearance?.name == .aqua)

        settings.appearance = .dark
        settings.appearance.apply(to: window)
        #expect(window.appearance?.name == .darkAqua)

        settings.appearance = .system
        settings.appearance.apply(to: window)
        #expect(window.appearance == nil)
    }

    // MARK: - Search Index Integration

    @Test func searchIndexFindsAppearanceThemeAndDangerZone() {
        // Appearance search queries
        for query in ["theme", "主题", "appearance", "外观"] {
            let results = SettingsSearchIndex.results(for: query)
            #expect(
                results.contains { $0.target.section == .appearance },
                "Expected search results for '\(query)' to include .appearance section"
            )
        }

        // Danger Zone search queries
        for query in ["danger zone", "危险区域", "local data", "本地数据"] {
            let results = SettingsSearchIndex.results(for: query)
            #expect(
                results.contains { $0.target.section == .general },
                "Expected search results for '\(query)' to include .general section"
            )
        }

        // Specifically test Danger Zone target title
        let dangerResults = SettingsSearchIndex.results(for: "danger zone")
        let dangerZoneTitle = L10n.string("settings.dangerZone")
        #expect(
            dangerResults.contains { $0.target.section == .general && $0.title == dangerZoneTitle },
            "Expected search for 'danger zone' to target the Danger Zone group"
        )
    }

    // MARK: - Danger Zone Localizations

    @Test func dangerZoneStringsAreLocalizedAcrossAllSupportedLanguages() {
        let concreteLanguages: [AppLanguage] = [
            .english,
            .simplifiedChinese,
            .german,
            .spanish,
            .french,
            .japanese,
            .portuguese,
            .russian
        ]

        let requiredKeys = [
            "settings.dangerZone",
            "settings.dangerZoneWarning",
            "settings.clearAllLocalDataConfirmTitle",
            "settings.clearAllLocalDataConfirmMessage",
            "settings.dangerZoneContinue",
            "settings.dangerZoneSecondConfirmTitle",
            "settings.dangerZoneSecondConfirmMessage",
            "settings.dangerZoneFinalClear"
        ]

        for lang in concreteLanguages {
            for key in requiredKeys {
                let localized = L10n.string(key, language: lang)
                #expect(
                    !localized.isEmpty,
                    "Key '\(key)' must not be empty in \(lang.rawValue)"
                )
                #expect(
                    localized != key,
                    "Key '\(key)' was not localized in \(lang.rawValue) (returned raw key)"
                )
            }
        }
    }

    // MARK: - Data Clear Execution & Safety

    @Test func dangerZoneClearAllLocalDataPurgesEverything() throws {
        let testBundleID = "com.spotask.test.\(UUID().uuidString)"
        let sessionStore = SessionStore(bundleIdentifier: testBundleID)
        let suiteName = "SpotAskDangerZoneClearingTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskDangerZoneClearingTest-\(UUID().uuidString).json")
        let diagnostics = DiagnosticLogStore(fileURL: diagnosticsURL)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? sessionStore.clear()
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }

        let settings = AppSettings(defaults: defaults, persistentDomainName: suiteName)
        let keyStore = DangerZoneInMemoryKeyStore()

        // 1. Setup session data
        let dummyMessage = ChatMessage(role: .user, content: "Test message", attachments: [])
        try sessionStore.save([dummyMessage])
        #expect(try sessionStore.load().count == 1)

        // 2. Setup key store
        let testProviderID = UUID()
        try keyStore.saveAPIKey("secret-api-key", for: testProviderID)
        try keyStore.saveAPIKey("proxy-pass", for: ProxyCredentialSlot.providerID)
        #expect(try keyStore.readAPIKey(for: testProviderID) == "secret-api-key")

        // 3. Setup diagnostics in an isolated file, never the shared production log.
        diagnostics.setEnabled(true)
        diagnostics.record("Test diagnostic log")
        #expect(diagnostics.exportedText().contains("Test diagnostic log"))

        // 4. Setup settings
        settings.systemPrompt = "Custom prompt"
        settings.contextLimit = 50
        settings.proxyEnabled = true
        settings.proxyHost = "127.0.0.1"

        var clearCallbackInvoked = false
        let generalState = GeneralSettingsState(
            settings: settings,
            keyStore: keyStore,
            sessionStore: sessionStore,
            diagnosticLogStore: diagnostics,
            onConfigurationImported: {},
            onClearAllData: {
                clearCallbackInvoked = true
            }
        )
        #expect(generalState.proxyPasswordDraft == "proxy-pass")

        // 5. Execute clearAllLocalData (as triggered by Danger Zone Stage 2 confirm)
        generalState.clearAllLocalData()

        // Verify session cleared
        #expect(try sessionStore.load().count == 0)

        // Verify keys cleared
        #expect(try keyStore.readAPIKey(for: testProviderID) == nil)
        #expect(try keyStore.readAPIKey(for: ProxyCredentialSlot.providerID) == nil)

        // Verify callback invoked
        #expect(clearCallbackInvoked)

        // Verify settings reset
        #expect(settings.systemPrompt == "")
        #expect(settings.contextLimit == 20)
        #expect(!settings.proxyEnabled)
        #expect(generalState.proxyPasswordDraft == "")
        #expect(!generalState.statusIsError)
        #expect(!diagnostics.exportedText().contains("Test diagnostic log"))
    }

    // MARK: - Screenshot Capture for Visual Verification

    @Test func captureSettingsScreenshotsForVerification() throws {
        let suiteName = "DangerZoneAndAppearanceThemeTests.Screenshots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let generalState = GeneralSettingsState(
            settings: settings,
            keyStore: DangerZoneInMemoryKeyStore(),
            onConfigurationImported: {}
        )

        // Render AppearanceSettingsPage
        let appearanceView = AppearanceSettingsPage(settings: settings)
            .frame(width: 580)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))

        let hostingAppearance = NSHostingView(rootView: appearanceView)
        hostingAppearance.frame = NSRect(x: 0, y: 0, width: 620, height: 420)
        hostingAppearance.layoutSubtreeIfNeeded()

        if let bitmap = hostingAppearance.bitmapImageRepForCachingDisplay(in: hostingAppearance.bounds) {
            hostingAppearance.cacheDisplay(in: hostingAppearance.bounds, to: bitmap)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                let outURL = URL(fileURLWithPath: "../attachments/appearance_3card_preview.png")
                try? pngData.write(to: outURL)
            }
        }

        // Render GeneralSettingsPage
        let generalView = GeneralSettingsPage(settings: settings, generalState: generalState)
            .frame(width: 580)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))

        let hostingGeneral = NSHostingView(rootView: generalView)
        hostingGeneral.frame = NSRect(x: 0, y: 0, width: 620, height: 1400)
        hostingGeneral.layoutSubtreeIfNeeded()

        if let bitmap = hostingGeneral.bitmapImageRepForCachingDisplay(in: hostingGeneral.bounds) {
            hostingGeneral.cacheDisplay(in: hostingGeneral.bounds, to: bitmap)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                let outURL = URL(fileURLWithPath: "../attachments/general_danger_zone_preview.png")
                try? pngData.write(to: outURL)
            }
        }

        // Render focused Danger Zone card preview
        let dangerZoneView = SettingsDangerGroup(
            title: L10n.string("settings.dangerZone"),
            documentation: DocumentationLinks.url(for: .privacy, language: settings.language)
        ) {
            SettingsDangerBanner(L10n.string("settings.dangerZoneWarning"))

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("settings.clearAllLocalData"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.string("settings.localDataDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Button(role: .destructive) {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text(L10n.string("settings.clearAllLocalData"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .frame(width: 580)
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))

        let hostingDanger = NSHostingView(rootView: dangerZoneView)
        hostingDanger.frame = NSRect(x: 0, y: 0, width: 620, height: 230)
        hostingDanger.layoutSubtreeIfNeeded()

        if let bitmap = hostingDanger.bitmapImageRepForCachingDisplay(in: hostingDanger.bounds) {
            hostingDanger.cacheDisplay(in: hostingDanger.bounds, to: bitmap)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                let outURL = URL(fileURLWithPath: "../attachments/danger_zone_card_preview.png")
                try? pngData.write(to: outURL)
            }
        }
    }
}

private final class DangerZoneInMemoryKeyStore: APIKeyStoring, @unchecked Sendable {
    private var keys: [UUID: String] = [:]

    func readAPIKey(for providerID: UUID) throws -> String? {
        keys[providerID]
    }

    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        keys[providerID] = key
    }

    func deleteAPIKey(for providerID: UUID) throws {
        keys.removeValue(forKey: providerID)
    }

    func deleteAllAPIKeys() throws {
        keys.removeAll()
    }
}
