import AppIntents
import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct SpotAskApp: App {
    @NSApplicationDelegateAdaptor(SpotAskAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class SpotAskAppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let keyStore: any APIKeyStoring
    private let providerFactory: any ChatProviderFactory
    private let sessionStore: SessionStore
    private let chatViewModel: ChatViewModel
    private let panelController = SpotAskPanelController()
    private let globalHotKey = GlobalHotKey()
    private var statusBarController: StatusBarController?

    override init() {
        let settings = AppSettings.shared
        let keyStore = LocalAPIKeyStore()
        do {
            try settings.migratePendingLegacyAPIKey(using: keyStore)
        } catch {
            assertionFailure("Unable to migrate local API key: \(error)")
        }
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = OpenAICompatibleProviderFactory(settings: settings, keyStore: keyStore)
        self.sessionStore = SessionStore()
        self.chatViewModel = ChatViewModel(
            settings: settings,
            providerFactory: OpenAICompatibleProviderFactory(settings: settings, keyStore: keyStore),
            sessionStore: SessionStore()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SpotAskCommandCenter.shared.configure(panelController: panelController)
        statusBarController = StatusBarController(settings: settings)
        SpotAskCommandCenter.shared.setPanelContent {
            ChatView(
                viewModel: self.chatViewModel,
                settings: self.settings,
                keyStore: self.keyStore,
                providerFactory: self.providerFactory,
                onDismiss: { SpotAskCommandCenter.shared.close() }
            )
        }
        do {
            try registerGlobalHotKey()
        } catch {
            assertionFailure("Unable to register default global hot key: \(error)")
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reconfigureGlobalHotKey), name: .spotAskHotKeyChanged, object: nil)
        SpotAskShortcuts.updateAppShortcutParameters()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        globalHotKey.unregister()
    }

    @objc private func reconfigureGlobalHotKey() {
        do {
            try registerGlobalHotKey()
        } catch {
            assertionFailure("Unable to register global hot key: \(error)")
        }
    }

    private func registerGlobalHotKey() throws {
        let configuration: (keyCode: UInt32, modifiers: UInt32)
        switch settings.hotKeyPreset {
        case .optionSpace:
            configuration = (GlobalHotKey.defaultKeyCode, GlobalHotKey.defaultModifiers)
        case .controlSpace:
            configuration = (GlobalHotKey.defaultKeyCode, UInt32(controlKey))
        case .commandShiftSpace:
            configuration = (GlobalHotKey.defaultKeyCode, UInt32(cmdKey | shiftKey))
        }
        try globalHotKey.register(keyCode: configuration.keyCode, modifiers: configuration.modifiers) {
            Task { @MainActor in SpotAskCommandCenter.shared.toggle() }
        }
    }
}
