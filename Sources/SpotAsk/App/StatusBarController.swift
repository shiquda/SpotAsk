import AppKit
import ServiceManagement

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private let launchAtLoginItem: NSMenuItem
    private let keepWindowOnTopItem: NSMenuItem

    init(settings: AppSettings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        launchAtLoginItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        keepWindowOnTopItem = NSMenuItem(title: "窗口置顶", action: #selector(toggleWindowOnTop), keyEquivalent: "")
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "SpotAsk")
            button.imagePosition = .imageOnly
            button.toolTip = "SpotAsk"
        }
        launchAtLoginItem.target = self
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 SpotAsk", action: #selector(open), keyEquivalent: "")
        menu.addItem(withTitle: "新对话", action: #selector(newConversation), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)
        keepWindowOnTopItem.state = settings.keepWindowOnTop ? .on : .off
        menu.addItem(keepWindowOnTopItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        keepWindowOnTopItem.state = settings.keepWindowOnTop ? .on : .off
    }

    @objc private func open() { SpotAskCommandCenter.shared.open() }
    @objc private func newConversation() { SpotAskCommandCenter.shared.startNewConversation() }
    @objc private func showSettings() { SpotAskCommandCenter.shared.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

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
