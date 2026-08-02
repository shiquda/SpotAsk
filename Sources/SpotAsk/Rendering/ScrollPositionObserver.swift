import Foundation

/// Keeps the user's follow preference separate from the scroll view's current
/// geometry. A programmatic scroll can change the latter, but must never turn
/// a user's paused preference back into automatic following.
struct ScrollFollowState: Equatable {
    enum Phase: Equatable {
        case idle
        case userInteracting
        case userDecelerating
        case programmaticAnimating
    }

    private(set) var followsLatest = true
    private var isNearBottom = true
    private var isHandlingUserScroll = false

    mutating func positionChanged(isNearBottom: Bool) {
        self.isNearBottom = isNearBottom
    }

    mutating func phaseChanged(to phase: Phase) {
        switch phase {
        case .userInteracting:
            // Stop on the first input phase, before the view moves beyond the
            // near-bottom tolerance used to decide whether to resume later.
            followsLatest = false
            isHandlingUserScroll = true
        case .userDecelerating:
            followsLatest = false
            isHandlingUserScroll = true
        case .idle:
            guard isHandlingUserScroll else { return }
            isHandlingUserScroll = false
            followsLatest = isNearBottom
        case .programmaticAnimating:
            break
        }
    }

    mutating func resumeFollowing() {
        followsLatest = true
        isHandlingUserScroll = false
    }
}
