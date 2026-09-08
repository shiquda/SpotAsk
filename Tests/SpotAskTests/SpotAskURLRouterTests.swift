import SwiftUI
import Testing
@testable import SpotAsk

struct SpotAskURLRouterTests {
    @Test func parsesHostCommands() {
        #expect(SpotAskURLRouter.parse("spotask://open") == .open)
        #expect(SpotAskURLRouter.parse("spotask://toggle") == .toggle)
        #expect(SpotAskURLRouter.parse("spotask://settings") == .settings)
        #expect(SpotAskURLRouter.parse("SPOTASK://OPEN") == .open)
        #expect(SpotAskURLRouter.parse("spotask://open/") == .open)
        #expect(SpotAskURLRouter.parse("  spotask://toggle  ") == .toggle)
    }

    @Test func parsesPathFormWhenHostIsEmpty() {
        #expect(SpotAskURLRouter.parse("spotask:///open") == .open)
        #expect(SpotAskURLRouter.parse("spotask:/settings") == .settings)
        #expect(SpotAskURLRouter.parse("spotask:///ask?q=hello") == .ask("hello"))
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

    @Test func deliveryCoalescesDuplicateURLsInsideWindow() {
        var delivery = SpotAskURLDelivery()
        let url = URL(string: "spotask://ask?q=hello")!
        let start = ContinuousClock.Instant.now

        #expect(delivery.take(url, now: start) == url)
        #expect(delivery.take(url, now: start.advanced(by: .milliseconds(200))) == nil)
        #expect(delivery.take(url, now: start.advanced(by: .seconds(2))) == url)
        #expect(delivery.openedFromURL)
    }

    @Test func deliveryDoesNotCoalesceDifferentURLs() {
        var delivery = SpotAskURLDelivery()
        let open = URL(string: "spotask://open")!
        let ask = URL(string: "spotask://ask?q=hello")!
        let now = ContinuousClock.Instant.now

        #expect(delivery.take(open, now: now) == open)
        #expect(delivery.take(ask, now: now) == ask)
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
        var settingsShown = 0
        commandCenter.configure(panelController: panel)
        commandCenter.setPanelContent { EmptyView() }
        commandCenter.setActionConsumer { recorder.actions.append($0) }
        commandCenter.setSettingsPresenter { settingsShown += 1 }

        SpotAskURLRouter.perform(.compose("草稿"), using: commandCenter)
        SpotAskURLRouter.perform(.settings, using: commandCenter)

        #expect(recorder.actions == [.compose("草稿", nil)])
        #expect(settingsShown == 1)
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
