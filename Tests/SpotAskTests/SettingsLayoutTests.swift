import AppKit
import SwiftUI
import Testing
@testable import SpotAsk

@MainActor
struct SettingsLayoutTests {
    @Test func providerUseForChatActionUsesSelectionStyleIcon() {
        #expect(ProviderSettingsIcon.useForChat == "checkmark.circle")
    }

    @Test func providerPageScrollingRevealsBottomControls() throws {
        let fixture = makeWindow(section: .provider)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let scrollViews = descendants(of: NSScrollView.self, in: fixture.hostingView)
        let geometries = scrollViews.map { scrollView in
            (
                scrollView,
                scrollView.convert(scrollView.bounds, to: fixture.hostingView)
            )
        }
        let pageScrollView = try #require(
            geometries.first { _, frame in
                frame.width > 550 && frame.height > 400
            },
            "The Service page must keep one page-level scroll region"
        )
        #expect(
            fixture.hostingView.bounds.insetBy(dx: -1, dy: -1).contains(pageScrollView.1),
            "The Service page scroll region must stay inside the Settings window"
        )

        let documentView = try #require(pageScrollView.0.documentView)
        documentView.layoutSubtreeIfNeeded()
        let scrollableHeight = max(
            0,
            documentView.bounds.height - pageScrollView.0.contentView.bounds.height
        )
        pageScrollView.0.contentView.scroll(to: NSPoint(x: 0, y: scrollableHeight))
        pageScrollView.0.reflectScrolledClipView(pageScrollView.0.contentView)
        #expect(
            pageScrollView.0.contentView.documentVisibleRect.maxY >= documentView.bounds.maxY - 1,
            "The Service page must reveal its bottom controls"
        )
        let secureFields = descendants(of: NSSecureTextField.self, in: fixture.hostingView)
        #expect(
            secureFields.contains { field in
                let frame = field.convert(field.bounds, to: fixture.hostingView)
                return fixture.hostingView.bounds.intersects(frame)
            },
            "Access key must be reachable after scrolling the Service page to its bottom"
        )
    }

    @Test func otherSettingsPagesKeepTheirExpectedScrollBehavior() throws {
        let scrollingSections: Set<SettingsSection> = [.provider, .prompts, .shortcuts, .general]

        for section in SettingsSection.allCases {
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
            let horizontalOverflow = descendants(of: NSView.self, in: fixture.hostingView)
                .dropFirst()
                .map { $0.convert($0.bounds, to: fixture.hostingView) }
                .filter { !$0.isEmpty }
                .filter { $0.minX < windowBounds.minX || $0.maxX > windowBounds.maxX }
            #expect(
                horizontalOverflow.isEmpty,
                "The \(section) page must keep all chrome within the fixed Settings width: \(horizontalOverflow)"
            )
            if scrollingSections.contains(section) {
                let minimumPageHeight: CGFloat = section == .provider ? 400 : 500
                let pageScrollView = geometries.first { _, frame in
                    frame.width >= 550 && frame.height >= minimumPageHeight
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
                if section == .provider {
                    let documentView = try #require(page.0.documentView)
                    documentView.layoutSubtreeIfNeeded()
                    let scrollableHeight = max(
                        0,
                        documentView.bounds.height - page.0.contentView.bounds.height
                    )
                    page.0.contentView.scroll(to: NSPoint(x: 0, y: scrollableHeight))
                    page.0.reflectScrolledClipView(page.0.contentView)

                    let secureFields = descendants(of: NSSecureTextField.self, in: fixture.hostingView)
                    #expect(
                        secureFields.contains { field in
                            let frame = field.convert(field.bounds, to: fixture.hostingView)
                            return windowBounds.intersects(frame)
                        },
                        "Access key must be visible after scrolling the Service page to the bottom"
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

    @Test func promptPresetTogglesKeepOneTrailingColumnForBuiltInAndCustomRows() throws {
        let fixture = makeWindow(section: .prompts, includingCustomPrompt: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let switches = descendants(of: NSSwitch.self, in: fixture.hostingView)
        #expect(switches.count == PromptPreset.builtIn.count + 1)

        let frames = switches.map { $0.convert($0.bounds, to: fixture.hostingView) }
        let reference = try #require(frames.first)
        for frame in frames {
            #expect(
                abs(frame.minX - reference.minX) < 1 && abs(frame.maxX - reference.maxX) < 1,
                "Every prompt enable control must remain in the shared trailing column: \(frames)"
            )
        }
    }

    // MARK: - Horizontal bounds

    @Test func fixedSettingsWindowKeepsSidebarAndServiceChromeInsideBounds() throws {
        let fixture = makeWindow(section: .provider)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let hostingBounds = fixture.hostingView.bounds.insetBy(dx: -0.5, dy: 0)
        let frames = descendants(of: NSView.self, in: fixture.hostingView)
            .dropFirst()
            .map { $0.convert($0.bounds, to: fixture.hostingView) }
            .filter { !$0.isEmpty }
        let escaped = frames.filter {
            $0.minX < hostingBounds.minX || $0.maxX > hostingBounds.maxX
        }
        #expect(
            escaped.isEmpty,
            "Settings sidebar or Service chrome escaped the fixed 860pt width: \(escaped)"
        )
    }

    @Test func providerDetailControlsKeepOneContainedColumn() throws {
        let fixture = makeWindow(section: .provider)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let hostingBounds = fixture.hostingView.bounds.insetBy(dx: -0.5, dy: 0)
        let textFields = descendants(of: NSTextField.self, in: fixture.hostingView)
        let expectedInputs = expectedProviderDetailInputs(from: textFields)
        let providerNameFields = expectedInputs.providerName
        let accessKeyFields = expectedInputs.accessKey
        #expect(
            providerNameFields.count == 1,
            "Provider Service Details must expose exactly one Name text field"
        )
        #expect(
            accessKeyFields.count == 1,
            "Access Key must expose exactly one secure text field"
        )
        let providerNameField = try #require(providerNameFields.first)
        let accessKeyField = try #require(accessKeyFields.first)
        let controls = [providerNameField, accessKeyField].map {
            $0.convert($0.bounds, to: fixture.hostingView)
        }

        let reference = try #require(controls.first)
        for frame in controls {
            #expect(
                abs(frame.minX - reference.minX) < 1 && abs(frame.maxX - reference.maxX) < 1,
                "Provider detail controls must share one column; expected \(reference), found \(frame)"
            )
            #expect(
                frame.width >= 300,
                "Provider detail controls must retain an editable width: \(frame)"
            )
            #expect(
                frame.minX >= hostingBounds.minX && frame.maxX <= hostingBounds.maxX,
                "Provider detail control escaped the fixed window horizontally: \(frame)"
            )
        }
    }

    @Test func providerDetailInputLookupRejectsMissingSecureAccessKey() {
        let providerNameField = NSTextField()
        providerNameField.placeholderString = L10n.string("settings.providerNamePlaceholder")
        let serviceAddressField = NSTextField()
        serviceAddressField.placeholderString = "https://api.example.com/v1"

        let withoutAccessKey = expectedProviderDetailInputs(
            from: [providerNameField, serviceAddressField]
        )
        #expect(withoutAccessKey.providerName.count == 1)
        #expect(withoutAccessKey.accessKey.isEmpty)

        let accessKeyField = NSSecureTextField()
        accessKeyField.placeholderString = L10n.string("settings.accessKeyPlaceholder")
        let expected = expectedProviderDetailInputs(
            from: [providerNameField, serviceAddressField, accessKeyField]
        )
        #expect(expected.providerName.count == 1)
        #expect(expected.accessKey.count == 1)
    }

    private func makeWindow(
        section: SettingsSection,
        includingCustomPrompt: Bool = false
    ) -> SettingsWindowFixture {
        let suiteName = "SettingsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        if includingCustomPrompt {
            _ = settings.saveCustomPromptPreset(
                PromptPreset(title: "Custom", instruction: "Custom prompt instruction.")
            )
        }
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

    private func expectedProviderDetailInputs(
        from textFields: [NSTextField]
    ) -> (providerName: [NSTextField], accessKey: [NSTextField]) {
        (
            providerName: textFields.filter {
                !($0 is NSSecureTextField)
                    && $0.placeholderString == L10n.string("settings.providerNamePlaceholder")
            },
            accessKey: textFields.filter {
                $0 is NSSecureTextField
                    && $0.placeholderString == L10n.string("settings.accessKeyPlaceholder")
            }
        )
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
