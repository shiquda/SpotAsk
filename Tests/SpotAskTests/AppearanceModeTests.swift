import AppKit
import SwiftUI
import Testing
@testable import SpotAsk

@MainActor
struct AppearanceModeTests {
    @Test func mapsToMatchingSwiftUIAndAppKitOverrides() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.system.nsAppearance == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.light.nsAppearance?.name == .aqua)
        #expect(AppearanceMode.dark.colorScheme == .dark)
        #expect(AppearanceMode.dark.nsAppearance?.name == .darkAqua)
    }

    @Test func appliesForcedAndSystemWindowAppearances() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        AppearanceMode.dark.apply(to: window)
        #expect(window.appearance?.name == .darkAqua)

        AppearanceMode.light.apply(to: window)
        #expect(window.appearance?.name == .aqua)

        AppearanceMode.system.apply(to: window)
        #expect(window.appearance == nil)
    }

    @Test func settingsRootLayoutInheritsTheForcedWindowAppearance() {
        let suiteName = "AppearanceModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        let hostingView = NSHostingView(rootView: AnyView(
            SettingsView(
                settings: settings,
                keyStore: AppearanceModeEmptyKeyStore(),
                providerFactory: AppearanceModeNoopProviderFactory()
            )
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 590),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        settings.appearance.apply(to: window)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.frame.size == NSSize(width: 860, height: 590))
        #expect(
            hostingView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            "The Settings root must lay out under the app's forced appearance."
        )
    }
}

private struct AppearanceModeEmptyKeyStore: APIKeyStoring {
    func readAPIKey(for providerID: UUID) throws -> String? { nil }
    func saveAPIKey(_ key: String, for providerID: UUID) throws {}
    func deleteAPIKey(for providerID: UUID) throws {}
    func deleteAllAPIKeys() throws {}
}

private struct AppearanceModeNoopProviderFactory: ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider { AppearanceModeNoopProvider() }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        AppearanceModeNoopProvider()
    }
}

private struct AppearanceModeNoopProvider: ChatProvider {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func testConnection() async throws {}
}
