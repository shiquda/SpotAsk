import AppKit
import Testing
@testable import SpotAsk

@Suite("SpotAsk panel Space presentation")
struct SpotAskPanelPresentationTests {
    @Test("unpinned panel stays on one Space and moves when ordered front")
    func unpinnedCollectionBehavior() {
        let behavior = SpotAskPanelPresentation.collectionBehavior(keepWindowOnTop: false)
        #expect(behavior.contains(.moveToActiveSpace))
        #expect(behavior.contains(.managed))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(!behavior.contains(.canJoinAllSpaces))
        #expect(!behavior.contains(.transient))
    }

    @Test("pinned panel joins all Spaces as a floating palette")
    func pinnedCollectionBehavior() {
        let behavior = SpotAskPanelPresentation.collectionBehavior(keepWindowOnTop: true)
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.transient))
        #expect(!behavior.contains(.moveToActiveSpace))
        #expect(!behavior.contains(.managed))
    }
}
