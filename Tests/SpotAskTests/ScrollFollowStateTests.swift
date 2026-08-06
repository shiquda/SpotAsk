import XCTest
@testable import SpotAsk

final class ScrollFollowStateTests: XCTestCase {
    func testUserInteractionImmediatelyStopsFollowingWithinNearBottomTolerance() {
        var state = ScrollFollowState()
        state.positionChanged(isNearBottom: true)

        state.phaseChanged(to: .userInteracting)

        XCTAssertFalse(state.followsLatest)
    }

    func testUserDecelerationStopsFollowingWhenTheInteractionPhaseWasNotReported() {
        var state = ScrollFollowState()
        state.positionChanged(isNearBottom: true)

        state.phaseChanged(to: .userDecelerating)

        XCTAssertFalse(state.followsLatest)
    }

    func testStreamingPositionUpdatesCannotResumePausedFollowing() {
        var state = ScrollFollowState()
        state.phaseChanged(to: .userInteracting)
        state.positionChanged(isNearBottom: false)
        state.phaseChanged(to: .idle)
        XCTAssertFalse(state.followsLatest)

        state.positionChanged(isNearBottom: true)
        state.positionChanged(isNearBottom: false)

        XCTAssertFalse(state.followsLatest)
    }

    func testReturningToBottomResumesFollowingOnlyAfterUserScrollBecomesIdle() {
        var state = ScrollFollowState()
        state.phaseChanged(to: .userInteracting)
        state.positionChanged(isNearBottom: true)

        XCTAssertFalse(state.followsLatest)

        state.phaseChanged(to: .idle)

        XCTAssertTrue(state.followsLatest)
    }

    func testProgrammaticAnimationDoesNotOverridePausedFollowing() {
        var state = ScrollFollowState()
        state.phaseChanged(to: .userInteracting)
        state.positionChanged(isNearBottom: false)
        state.phaseChanged(to: .idle)

        state.positionChanged(isNearBottom: true)
        state.phaseChanged(to: .programmaticAnimating)
        state.phaseChanged(to: .idle)

        XCTAssertFalse(state.followsLatest)
    }

    func testGoToBottomExplicitlyResumesFollowing() {
        var state = ScrollFollowState()
        state.phaseChanged(to: .userInteracting)
        state.phaseChanged(to: .idle)

        state.resumeFollowing()

        XCTAssertTrue(state.followsLatest)
    }

    func testRepeatedNearBottomValueDoesNotChangeState() {
        var state = ScrollFollowState()
        state.positionChanged(isNearBottom: false)
        let before = state

        state.positionChanged(isNearBottom: false)

        XCTAssertEqual(state, before)
        XCTAssertEqual(state.isNearBottomValue, false)
    }
}
