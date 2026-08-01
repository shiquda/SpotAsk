import AppKit
import SwiftUI
import Testing
@testable import SpotAsk

@MainActor
struct SettingsLayoutTests {
    @Test func providerTreeAndDetailOwnScrollingAtCompactWindowSize() throws {
        let fixture = makeWindow(section: .provider)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let scrollViews = descendants(of: NSScrollView.self, in: fixture.hostingView)
        let geometries = scrollViews.map { scrollView in
            (
                scrollView,
                scrollView.convert(scrollView.bounds, to: fixture.hostingView)
            )
        }

        let pageScrollView = geometries.first { _, frame in
            frame.width > 700 && frame.height > 500
        }
        #expect(
            pageScrollView == nil,
            "The Service page must stay fixed while its tree and detail regions scroll independently"
        )

        let treeScrollView = geometries.first { _, frame in
            abs(frame.width - 200) < 1 && frame.minX >= 200
        }
        let detailScrollView = geometries.first { _, frame in
            frame.minX > 400 && frame.width > 400 && frame.width < 500
        }

        let tree = try #require(treeScrollView)
        let detail = try #require(detailScrollView)
        let minimumWorkspaceHeight = fixture.hostingView.bounds.height * 0.5
        #expect(tree.1.height >= minimumWorkspaceHeight, "The provider tree must retain at least half the Settings window height")
        #expect(detail.1.height >= minimumWorkspaceHeight, "The provider detail must retain at least half the Settings window height")

        let documentView = try #require(detail.0.documentView)
        documentView.layoutSubtreeIfNeeded()
        let scrollableHeight = documentView.bounds.height - detail.0.contentView.bounds.height
        detail.0.contentView.scroll(to: NSPoint(x: 0, y: scrollableHeight))
        detail.0.reflectScrolledClipView(detail.0.contentView)
        #expect(
            detail.0.contentView.documentVisibleRect.maxY >= documentView.bounds.maxY - 1,
            "The detail scroll region must be able to reveal its bottom controls"
        )
    }

    @Test func otherSettingsPagesKeepTheirExpectedScrollBehavior() throws {
        let scrollingSections: Set<SettingsSection> = [.prompts, .general]

        for section in SettingsSection.allCases where section != .provider {
            let fixture = makeWindow(section: section)
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

            let scrollViews = descendants(of: NSScrollView.self, in: fixture.hostingView)
            let geometries = scrollViews.map { scrollView in
                (
                    scrollView,
                    scrollView.convert(scrollView.bounds, to: fixture.hostingView)
                )
            }
            #expect(fixture.hostingView.frame.size == NSSize(width: 860, height: 590))

            let windowBounds = fixture.hostingView.bounds.insetBy(dx: -1, dy: -1)
            if scrollingSections.contains(section) {
                let pageScrollView = geometries.first { _, frame in
                    frame.width >= 550 && frame.height >= 500
                }
                let page = try #require(
                    pageScrollView,
                    "The \(section) page must retain its page-level scrolling"
                )
                #expect(
                    windowBounds.contains(page.1),
                    "The \(section) page scroll region must stay inside the Settings window"
                )
                if section == .prompts {
                    let documentView = try #require(page.0.documentView)
                    documentView.layoutSubtreeIfNeeded()
                    let scrollableHeight = max(
                        0,
                        documentView.bounds.height - page.0.contentView.bounds.height
                    )
                    page.0.contentView.scroll(to: NSPoint(x: 0, y: scrollableHeight))
                    page.0.reflectScrolledClipView(page.0.contentView)

                    let textViews = descendants(of: NSTextView.self, in: fixture.hostingView)
                    #expect(
                        textViews.contains { textView in
                            let frame = textView.convert(textView.bounds, to: fixture.hostingView)
                            return windowBounds.intersects(frame)
                        },
                        "The Custom Instructions editor must be visible after scrolling Prompts to the bottom"
                    )
                }
            } else {
                #expect(
                    scrollViews.isEmpty,
                    "The \(section) page should not gain an unnecessary scroll layer"
                )
            }
        }
    }

    private func makeWindow(section: SettingsSection) -> SettingsWindowFixture {
        let suiteName = "SettingsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        let hostingView = NSHostingView(rootView: AnyView(
            SettingsView(
                settings: settings,
                keyStore: EmptyKeyStore(),
                providerFactory: NoopProviderFactory(),
                initialSection: section
            )
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 590),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        return SettingsWindowFixture(
            window: window,
            hostingView: hostingView,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func descendants<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> [ViewType] {
        var result: [ViewType] = []
        if let matchingView = root as? ViewType {
            result.append(matchingView)
        }
        for subview in root.subviews {
            result.append(contentsOf: descendants(of: type, in: subview))
        }
        return result
    }
}

@MainActor
private struct SettingsWindowFixture {
    let window: NSWindow
    let hostingView: NSHostingView<AnyView>
    let defaults: UserDefaults
    let suiteName: String
}

private struct EmptyKeyStore: APIKeyStoring {
    func readAPIKey(for providerID: UUID) throws -> String? { nil }
    func saveAPIKey(_ key: String, for providerID: UUID) throws {}
    func deleteAPIKey(for providerID: UUID) throws {}
    func deleteAllAPIKeys() throws {}
}

private struct NoopProviderFactory: ChatProviderFactory {
    func makeProvider() throws -> any ChatProvider {
        NoopChatProvider()
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        NoopChatProvider()
    }
}

private struct NoopChatProvider: ChatProvider {
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func testConnection() async throws {}
}
