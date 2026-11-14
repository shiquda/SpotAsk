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

    @Test func settingsAppearancePageIsWrappedInScrollViewAndCanScroll() throws {
        let suiteName = "AppearanceModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.language = .simplifiedChinese
        let model = SettingsWindowModel(selectedSection: .appearance)
        let hostingView = NSHostingView(rootView: AnyView(
            SettingsView(
                settings: settings,
                keyStore: AppearanceModeEmptyKeyStore(),
                providerFactory: AppearanceModeNoopProviderFactory(),
                model: model
            )
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 590),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        func findScrollViews(in view: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            if let sv = view as? NSScrollView {
                result.append(sv)
            }
            for sub in view.subviews {
                result.append(contentsOf: findScrollViews(in: sub))
            }
            return result
        }

        let scrollViews = findScrollViews(in: hostingView)
        #expect(!scrollViews.isEmpty, "SettingsView must contain a scroll view for appearance content")
        guard let detailScrollView = scrollViews.first(where: { sv in
            let frame = sv.convert(sv.bounds, to: hostingView)
            return frame.origin.x > 150
        }) else {
            Issue.record("Could not find detail NSScrollView in right pane")
            return
        }

        let documentHeight = detailScrollView.documentView?.bounds.height ?? 0
        let viewportHeight = detailScrollView.contentView.bounds.height
        #expect(documentHeight > viewportHeight, "Document height (\(documentHeight)) must exceed viewport height (\(viewportHeight)) so appearance page is scrollable")

        let maxScrollY = documentHeight - viewportHeight
        detailScrollView.contentView.scroll(to: NSPoint(x: 0, y: maxScrollY))
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
        hostingView.layoutSubtreeIfNeeded()
        #expect(detailScrollView.contentView.bounds.origin.y > 0, "Detail scroll view should reflect scroll offset")
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
