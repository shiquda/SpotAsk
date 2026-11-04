import AppKit
import SwiftUI
import Testing
@testable import SpotAsk

@MainActor
@Suite(.serialized)
struct SpotAskPanelControllerTests {
    @Test func togglingChatWindowBackgroundKeepsPanelInPlace() throws {
        let fixture = try Fixture()
        let panel = try fixture.panel()
        panel.setFrameOrigin(NSPoint(x: 100, y: 150))
        fixture.settings.panelOrigin = panel.frame.origin
        fixture.controller.hide()

        fixture.settings.chatWindowBackground = .frosted
        fixture.settings.chatWindowBackground = .opaque
        fixture.controller.show()

        #expect(panel.frame.origin == NSPoint(x: 100, y: 150))
        #expect(panel.frame.size == NSSize(width: 780, height: 520))
    }

    @Test func togglingChatWindowBackgroundKeepsTheSameContentHost() throws {
        let fixture = try Fixture()
        let panel = try fixture.panel()
        let host = try #require(panel.contentView)

        fixture.settings.chatWindowBackground = .frosted
        #expect(panel.contentView === host, "Frosted must not replace the chat hosting view")
        #expect(panel.isOpaque == false)

        fixture.settings.chatWindowBackground = .opaque
        #expect(panel.contentView === host, "Solid must not replace the chat hosting view")
        #expect(panel.isOpaque == true)
    }

    /// The solid fill used to be painted onto a helper view as
    /// `NSColor.windowBackgroundColor.cgColor`, which froze the color of
    /// whichever appearance was current when that view was built. Pinning the
    /// app to dark then left a light window, and later light/dark switches
    /// repainted nothing. The fill must stay a dynamic color on the window.
    @Test func solidFillFollowsThePinnedAppearance() throws {
        let fixture = try Fixture()
        let panel = try fixture.panel()
        let fill = try #require(panel.backgroundColor)

        let light = Self.brightness(of: fill, appearance: .aqua)
        let dark = Self.brightness(of: fill, appearance: .darkAqua)

        #expect(light > dark, "The window fill must be dynamic (light \(light), dark \(dark))")
        #expect(
            (panel.contentView?.layer?.backgroundColor?.alpha ?? 0) < 0.01,
            "The content view must not carry a frozen solid fill"
        )
    }

    private static func brightness(of color: NSColor, appearance: NSAppearance.Name) -> CGFloat {
        var resolved = color.cgColor
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return NSColor(cgColor: resolved)?.usingColorSpace(.sRGB)?.brightnessComponent ?? -1
    }

    @MainActor
    private struct Fixture {
        let settings: AppSettings
        let controller: SpotAskPanelController

        init() throws {
            let suiteName = "SpotAskPanelControllerTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            self.settings = AppSettings(defaults: defaults)
            self.controller = SpotAskPanelController(settings: settings)
            controller.setContent { AnyView(Text("Test Content")) }
            controller.show()
        }

        func panel() throws -> NSWindow {
            // Earlier tests leave their panels behind; the fixture's own panel
            // is the most recently created window with this title.
            try #require(NSApp.windows.last { $0.title == "SpotAsk" })
        }
    }
}
