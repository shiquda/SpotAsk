import SwiftUI
import Testing
@testable import SpotAsk

struct SpotAskURLRouterTests {
    @Test func parsesHostCommands() {
        #expect(SpotAskURLRouter.parse("spotask://open") == .open)
        #expect(SpotAskURLRouter.parse("spotask://toggle") == .toggle)
        #expect(SpotAskURLRouter.parse("spotask://settings") == .settings(nil))
        #expect(SpotAskURLRouter.parse("SPOTASK://OPEN") == .open)
        #expect(SpotAskURLRouter.parse("spotask://open/") == .open)
        #expect(SpotAskURLRouter.parse("  spotask://toggle  ") == .toggle)
    }

    @Test func parsesPathFormWhenHostIsEmpty() {
        #expect(SpotAskURLRouter.parse("spotask:///open") == .open)
        #expect(SpotAskURLRouter.parse("spotask:/settings") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask:///ask?q=hello") == .ask("hello"))
    }

    @Test func parsesSettingsDeepLinks() {
        #expect(SpotAskURLRouter.parse("spotask://settings/provider") == .settings(.provider))
        #expect(SpotAskURLRouter.parse("spotask://settings/prompts") == .settings(.prompts))
        #expect(SpotAskURLRouter.parse("spotask://settings/external-ask") == .settings(.externalAsk))
        #expect(SpotAskURLRouter.parse("spotask://settings/selection-assistant") == .settings(.selectionAssistant))
        #expect(SpotAskURLRouter.parse("spotask://settings/shortcuts") == .settings(.shortcuts))
        #expect(SpotAskURLRouter.parse("spotask://settings/general") == .settings(.general))
        #expect(SpotAskURLRouter.parse("spotask://settings/appearance") == .settings(.appearance))
        #expect(SpotAskURLRouter.parse("spotask://settings/about") == .settings(.about))

        // The path-style spelling stays readable, and ids are matched
        // case-insensitively like the command names already are.
        #expect(SpotAskURLRouter.parse("spotask:///settings/external-ask") == .settings(.externalAsk))
        #expect(SpotAskURLRouter.parse("spotask://settings/External-Ask") == .settings(.externalAsk))
        #expect(SpotAskURLRouter.parse("spotask://settings/ABOUT") == .settings(.about))
    }

    @Test func settingsDeepLinksFallBackToPlainSettings() {
        // An unknown or missing id keeps the link useful instead of rejecting
        // it, and must not select some other page.
        #expect(SpotAskURLRouter.parse("spotask://settings/unknown") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/%E5%A4%96%E9%83%A8%E6%8F%90%E9%97%AE") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/external%20ask") == .settings(nil))

        // Only `settings/<id>` is the documented form: a fragment, an extra
        // segment, or an empty segment is not a target, even when a valid id is
        // part of it.
        #expect(SpotAskURLRouter.parse("spotask://settings/provider/models") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/provider#models") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/about#anything") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings#appearance") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings//about") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/about/") == .settings(nil))

        // Percent-decoding happens before the id is matched, so an encoded
        // space, tab, newline, or Unicode look-alike must not be normalized
        // onto a real id.
        #expect(SpotAskURLRouter.parse("spotask://settings/%20about%20") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/%09general%0A") == .settings(nil))
        #expect(SpotAskURLRouter.parse("spotask://settings/external-as%E2%84%AA") == .settings(nil))

        // Query items are ignored on Settings, so an unknown parameter neither
        // picks a different page nor rejects the URL. Other commands keep
        // ignoring them entirely.
        #expect(SpotAskURLRouter.parse("spotask://settings/provider?utm_source=docs") == .settings(.provider))
        #expect(SpotAskURLRouter.parse("spotask://open?section=about") == .open)
        #expect(SpotAskURLRouter.parse("spotask://toggle?section=about") == .toggle)
    }

    @Test func parsesAskQueryAndSubmitFlag() {
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello") == .ask("hello"))
        #expect(SpotAskURLRouter.parse("spotask://ask?query=hello") == .ask("hello"))
        #expect(SpotAskURLRouter.parse("spotask://ask?Q=Hello") == .ask("Hello"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello%20world") == .ask("hello world"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=%E4%BD%A0%E5%A5%BD") == .ask("你好"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello&submit=false") == .compose("hello"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello&send=0") == .compose("hello"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello&submit=true") == .ask("hello"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=%20hello%20") == .ask("hello"))
    }

    @Test func emptyOrMissingAskQueryOpensPanel() {
        #expect(SpotAskURLRouter.parse("spotask://ask") == .open)
        #expect(SpotAskURLRouter.parse("spotask://ask?q=") == .open)
        #expect(SpotAskURLRouter.parse("spotask://ask?q=%20%20") == .open)
        #expect(SpotAskURLRouter.parse("spotask://ask?submit=false") == .open)
    }

    @Test func repairsUnencodedSpecialCharacters() {
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello world") == .ask("hello world"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=你好") == .ask("你好"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=hello world&submit=false") == .compose("hello world"))
        #expect(SpotAskURLRouter.parse("spotask://ask?q=line1\nline2") == .ask("line1\nline2"))
    }

    @Test func rejectsMalformedAndUnknownURLs() {
        #expect(SpotAskURLRouter.parse("") == nil)
        #expect(SpotAskURLRouter.parse("   ") == nil)
        #expect(SpotAskURLRouter.parse("not-a-url") == nil)
        #expect(SpotAskURLRouter.parse("http://example.com/open") == nil)
        #expect(SpotAskURLRouter.parse("file:///tmp") == nil)
        #expect(SpotAskURLRouter.parse("spotask://") == nil)
        #expect(SpotAskURLRouter.parse("spotask://unknown") == nil)
        #expect(SpotAskURLRouter.parse("spotask") == nil)
        #expect(SpotAskURLRouter.parse("mailto:hi@example.com") == nil)
    }

    @Test func ignoresFragmentAndUsesFirstQueryValue() {
        #expect(SpotAskURLRouter.parse("spotask://ask?q=first&q=second#ignored") == .ask("first"))
        #expect(SpotAskURLRouter.parse("spotask://open#fragment") == .open)
    }

    @Test func launchPresentationSkipsDefaultOpenAfterURL() {
        #expect(shouldOpenPanelOnLaunch(silentLaunch: false, openedFromURL: false))
        #expect(!shouldOpenPanelOnLaunch(silentLaunch: true, openedFromURL: false))
        #expect(!shouldOpenPanelOnLaunch(silentLaunch: false, openedFromURL: true))
        #expect(!shouldOpenPanelOnLaunch(silentLaunch: true, openedFromURL: true))
    }

    @Test func deliveryMarksOpenedFromURL() {
        var delivery = SpotAskURLDelivery()
        #expect(!delivery.openedFromURL)
        delivery.markOpenedFromURL()
        #expect(delivery.openedFromURL)
    }

    @Test @MainActor func warmAskDispatchesToReadyCommandCenter() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(SpotAskURLRouter.handle(URL(string: "spotask://ask?q=暖路径")!, using: commandCenter))
        #expect(panel.didShow)
        #expect(recorder.actions == [.ask("暖路径", nil)])
    }

    @Test @MainActor func coldStartAskIsBufferedUntilPanelIsReady() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()

        #expect(SpotAskURLRouter.handle(URL(string: "spotask://ask?q=冷启动")!, using: commandCenter))
        #expect(panel.didShow == false)

        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(panel.didShow)
        #expect(recorder.actions == [.ask("冷启动", nil)])
    }

    @Test @MainActor func composeAndSettingsDispatch() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        var requestedSections: [SettingsSection?] = []
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }
        commandCenter.setSettingsPresenter { requestedSections.append($0) }

        SpotAskURLRouter.perform(.compose("草稿"), using: commandCenter)
        SpotAskURLRouter.perform(.settings(nil), using: commandCenter)

        #expect(recorder.actions == [.compose("草稿", nil)])
        #expect(requestedSections == [nil])
    }

    @Test @MainActor func warmSettingsDeepLinkPresentsRequestedSection() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        var requestedSections: [SettingsSection?] = []
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { _ in }
        commandCenter.setSettingsPresenter { requestedSections.append($0) }

        #expect(SpotAskURLRouter.handle(URL(string: "spotask://settings/general")!, using: commandCenter))
        #expect(requestedSections == [.general])

        // A second link moves the same window to another page.
        #expect(SpotAskURLRouter.handle(URL(string: "spotask://settings/about")!, using: commandCenter))
        #expect(requestedSections == [.general, .about])

        // Unknown targets still open Settings.
        #expect(SpotAskURLRouter.handle(URL(string: "spotask://settings/nowhere")!, using: commandCenter))
        #expect(requestedSections == [.general, .about, nil])

        // Opening Settings must never open the question panel.
        #expect(panel.didShow == false)
    }

    @Test @MainActor func coldStartSettingsDeepLinkWaitsOnlyForThePresenter() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        var requestedSections: [SettingsSection?] = []

        // The link arrives before anything is wired up, as on a cold start.
        #expect(SpotAskURLRouter.handle(URL(string: "spotask://settings/shortcuts")!, using: commandCenter))
        #expect(requestedSections.isEmpty)

        // The chat panel becoming ready must not be what delivers a Settings
        // request, and must not even be shown for one.
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }
        #expect(requestedSections.isEmpty)
        #expect(recorder.actions.isEmpty)
        #expect(panel.didShow == false)

        // Installing the Settings presenter delivers the buffered request.
        commandCenter.setSettingsPresenter { requestedSections.append($0) }
        #expect(requestedSections == [.shortcuts])
        #expect(panel.didShow == false)
    }

    @Test @MainActor func settingsRequestsStayOutOfTheChatPanelQueue() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        var requestedSections: [SettingsSection?] = []

        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(SpotAskURLRouter.handle(URL(string: "spotask://settings/general")!, using: commandCenter))
        #expect(recorder.actions.isEmpty, "Settings must not ride the panel action queue")
        #expect(panel.didShow == false)

        commandCenter.setSettingsPresenter { requestedSections.append($0) }
        #expect(requestedSections == [.general])
        #expect(recorder.actions.isEmpty)
        #expect(panel.didShow == false)
    }

    @Test @MainActor func unknownURLDoesNotTouchCommandCenter() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(!SpotAskURLRouter.handle(URL(string: "https://example.com")!, using: commandCenter))
        #expect(recorder.actions.isEmpty)
        #expect(panel.didShow == false)
    }

    @Test @MainActor func toggleOnColdStartOpensWhenPanelIsNotConfigured() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()

        SpotAskURLRouter.perform(.toggle, using: commandCenter)
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        #expect(recorder.actions == [.focusInput])
        #expect(panel.didShow)
    }

    @Test @MainActor func rapidIndependentTogglesRestoreVisibility() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { _ in }

        SpotAskURLRouter.perform(.open, using: commandCenter)
        #expect(panel.isVisible)

        let toggle = URL(string: "spotask://toggle")!
        #expect(SpotAskURLRouter.handle(toggle, using: commandCenter))
        #expect(!panel.isVisible)
        #expect(SpotAskURLRouter.handle(toggle, using: commandCenter))
        #expect(panel.isVisible)
    }

    @Test @MainActor func rapidIndependentAsksBothDispatch() {
        let commandCenter = SpotAskCommandCenter()
        let panel = PanelControllerSpy()
        let recorder = ActionRecorder()
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }

        let ask = URL(string: "spotask://ask?q=hello")!
        #expect(SpotAskURLRouter.handle(ask, using: commandCenter))
        #expect(SpotAskURLRouter.handle(ask, using: commandCenter))
        #expect(recorder.actions == [.ask("hello", nil), .ask("hello", nil)])
    }
}

@MainActor
private final class ActionRecorder {
    var actions: [SpotAskCommandAction] = []
}

@MainActor
private final class PanelControllerSpy: SpotAskPanelControlling {
    var didShow = false
    var isVisible = false

    func setContent(_ content: @escaping () -> AnyView) {}

    func show() {
        didShow = true
        isVisible = true
    }

    func hide() {
        isVisible = false
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func toggleWindowOnTop() {}
}
