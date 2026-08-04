import AppKit
import ServiceManagement

/// Draws a small monochrome version of the SpotAsk beacon from the app icon.
/// A template image lets macOS choose the correct status-bar color in each
/// appearance and selected-menu state.
func spotAskStatusBarImage() -> NSImage? {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setFill()

    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: 2.75, y: 2.25))
    beam.line(to: NSPoint(x: 15.25, y: 2.25))
    beam.line(to: NSPoint(x: 11.15, y: 13.4))
    beam.line(to: NSPoint(x: 6.85, y: 13.4))
    beam.close()
    beam.fill()

    let cap = NSBezierPath(
        roundedRect: NSRect(x: 6.1, y: 14.55, width: 5.8, height: 2.1),
        xRadius: 0.65,
        yRadius: 0.65
    )
    cap.fill()

    image.unlockFocus()
    image.isTemplate = true
    return image
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private let launchAtLoginItem: NSMenuItem
    private let keepWindowOnTopItem: NSMenuItem

    init(settings: AppSettings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        launchAtLoginItem = NSMenuItem(title: L10n.string("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        keepWindowOnTopItem = NSMenuItem(title: L10n.string("menu.windowOnTop"), action: #selector(toggleWindowOnTop), keyEquivalent: "")
        super.init()

        if let button = statusItem.button {
            button.image = spotAskStatusBarImage()
                ?? NSImage(systemSymbolName: "sparkle", accessibilityDescription: "SpotAsk")
            button.imagePosition = .imageOnly
            button.toolTip = "SpotAsk"
        }
        launchAtLoginItem.target = self
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenuForLanguageChange), name: .spotAskLanguageChanged, object: nil)
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.string("menu.open"), action: #selector(open), keyEquivalent: "")
        menu.addItem(withTitle: L10n.string("menu.newConversation"), action: #selector(newConversation), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string("menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)
        keepWindowOnTopItem.state = settings.keepWindowOnTop ? .on : .off
        menu.addItem(keepWindowOnTopItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    func setVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        keepWindowOnTopItem.state = settings.keepWindowOnTop ? .on : .off
    }

    @objc private func open() { SpotAskCommandCenter.shared.open() }
    @objc private func newConversation() { SpotAskCommandCenter.shared.startNewConversation() }
    @objc private func showSettings() { SpotAskCommandCenter.shared.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func rebuildMenuForLanguageChange() {
        launchAtLoginItem.title = L10n.string("menu.launchAtLogin")
        keepWindowOnTopItem.title = L10n.string("menu.windowOnTop")
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            settings.launchAtLogin.toggle()
        } catch {
            settings.launchAtLogin = false
        }
        rebuildMenu()
    }

    @objc private func toggleWindowOnTop() {
        SpotAskCommandCenter.shared.toggleWindowOnTop()
        rebuildMenu()
    }
}
