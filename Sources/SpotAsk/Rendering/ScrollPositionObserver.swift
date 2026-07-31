import AppKit
import SwiftUI

struct ScrollPositionObserver: NSViewRepresentable {
    let onNearBottomChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onNearBottomChanged = onNearBottomChanged
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onNearBottomChanged = onNearBottomChanged
        view.startObservingIfNeeded()
    }
}

final class TrackingView: NSView {
    var onNearBottomChanged: ((Bool) -> Void)?

    private weak var observedScrollView: NSScrollView?
    private var isObserving = false
    private var lastValue: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startObservingIfNeeded()
    }

    func startObservingIfNeeded() {
        guard !isObserving else { return }
        DispatchQueue.main.async { [weak self] in self?.beginObserving() }
    }

    private func beginObserving() {
        guard !isObserving, let scrollView = enclosingScrollView else { return }
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBoundsChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        isObserving = true
        reportPosition()
    }

    @objc private func handleBoundsChange(_ notification: Notification) {
        reportPosition()
    }

    private func reportPosition() {
        guard let scrollView = observedScrollView, let documentView = scrollView.documentView else { return }
        let visibleBottom = scrollView.contentView.bounds.maxY
        let isNearBottom = visibleBottom >= documentView.bounds.maxY - 12
        guard isNearBottom != lastValue else { return }
        lastValue = isNearBottom
        onNearBottomChanged?(isNearBottom)
    }
}
