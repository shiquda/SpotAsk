import Carbon.HIToolbox
import Testing
@testable import SpotAsk

@Suite("Global hot key routing")
struct GlobalHotKeyTests {
    @Test("Routes only the matching registered hot key")
    func routesOnlyMatchingHotKey() {
        #expect(GlobalHotKey.matchesEvent(
            signature: GlobalHotKey.signature,
            identifier: 1,
            expectedIdentifier: 1
        ))
        #expect(!GlobalHotKey.matchesEvent(
            signature: GlobalHotKey.signature,
            identifier: 2,
            expectedIdentifier: 1
        ))
        #expect(!GlobalHotKey.matchesEvent(
            signature: 0x4F_5448_52,
            identifier: 1,
            expectedIdentifier: 1
        ))
    }

    @Test("Maps a recorded shortcut to a Carbon hot key")
    func mapsRecordedShortcut() {
        let configuration = GlobalHotKey.configuration(for: InAppShortcut(key: "k", modifiers: [.command, .shift]))

        #expect(configuration?.keyCode == UInt32(kVK_ANSI_K))
        #expect(configuration?.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test("Maps the space key to the historical Option+Space trigger")
    func mapsSpaceShortcut() {
        let configuration = GlobalHotKey.configuration(for: InAppShortcut(key: " ", modifiers: .option))

        #expect(configuration?.keyCode == UInt32(kVK_Space))
        #expect(configuration?.modifiers == UInt32(optionKey))
    }
}
