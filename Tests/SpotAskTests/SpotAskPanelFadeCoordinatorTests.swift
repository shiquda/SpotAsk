import AppKit
import Testing
@testable import SpotAsk

@Suite("SpotAsk panel fade animation")
@MainActor
struct SpotAskPanelFadeCoordinatorTests {
    @Test("show fades in and hide orders out after the fade")
    func showAndHide() {
        let target = FadeTarget()
        let coordinator = SpotAskPanelFadeCoordinator()

        coordinator.show(target)
        #expect(target.orderFrontCount == 1)
        #expect(target.requestedValues == [1])
        #expect(!coordinator.isHiding)

        coordinator.hide(target)
        #expect(target.requestedValues == [1, 0])
        #expect(target.orderOutCount == 0)
        #expect(coordinator.isHiding)

        target.completeLatestAnimation()
        #expect(target.orderOutCount == 1)
        #expect(target.alphaValue == 1)
        #expect(!coordinator.isHiding)
    }

    @Test("show cancels a pending hide")
    func showCancelsHide() {
        let target = FadeTarget()
        let coordinator = SpotAskPanelFadeCoordinator()
        coordinator.show(target)
        coordinator.hide(target)
        let hideCompletion = target.completions[1]
        coordinator.show(target)

        hideCompletion()
        #expect(target.orderOutCount == 0)
        #expect(target.requestedValues == [1, 0, 1])
    }

    @Test("hide posts spotAskPanelDidHide notification when animation completes")
    func hidePostsNotificationOnComplete() {
        let target = FadeTarget()
        let coordinator = SpotAskPanelFadeCoordinator()
        let box = NotifiedBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .spotAskPanelDidHide,
            object: nil,
            queue: .main
        ) { _ in box.notified = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.show(target)
        coordinator.hide(target)
        #expect(!box.notified)

        target.completeLatestAnimation()
        #expect(box.notified)
    }

    @Test("hide posts spotAskPanelDidHide immediately when target is not visible")
    func hidePostsNotificationImmediatelyWhenNotVisible() {
        let target = FadeTarget()
        let coordinator = SpotAskPanelFadeCoordinator()
        let box = NotifiedBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .spotAskPanelDidHide,
            object: nil,
            queue: .main
        ) { _ in box.notified = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        target.isVisible = false
        coordinator.hide(target)
        #expect(box.notified)
    }
}

@MainActor
private final class FadeTarget: SpotAskPanelFadeTarget {
    var isVisible = false
    var alphaValue: CGFloat = 1
    var orderFrontCount = 0
    var orderOutCount = 0
    var requestedValues: [CGFloat] = []
    var completions: [() -> Void] = []

    func makeKeyAndOrderFront(_ sender: Any?) {
        isVisible = true
        orderFrontCount += 1
    }

    func orderOut(_ sender: Any?) {
        isVisible = false
        orderOutCount += 1
    }

    func animateAlpha(to value: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        alphaValue = value
        requestedValues.append(value)
        completions.append(completion)
    }
    func completeLatestAnimation() {
        completions.removeLast()()
    }
}

private final class NotifiedBox: @unchecked Sendable {
    var notified = false
}
