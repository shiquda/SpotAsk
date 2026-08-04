import AppIntents
import AppKit
import Carbon.HIToolbox
import SwiftUI

enum AppEntryPresentation: Equatable {
    case menuBar
    case dock

    init(showsMenuBarIcon: Bool) {
        self = showsMenuBarIcon ? .menuBar : .dock
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .menuBar: .accessory
        case .dock: .regular
        }
    }

    var showsStatusItem: Bool {
        self == .menuBar
    }
}

func handleDockReopen(hasVisibleWindows: Bool, openPanel: () -> Void) -> Bool {
    guard !hasVisibleWindows else { return true }
    openPanel()
    return true
}

@MainActor
final class AppEntryPresentationCoordinator: NSObject {
    private let settings: AppSettings
    private let notificationCenter: NotificationCenter
    private let setStatusItemVisible: (Bool) -> Void
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void

    init(
        settings: AppSettings,
        notificationCenter: NotificationCenter = .default,
        setStatusItemVisible: @escaping (Bool) -> Void,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void
    ) {
        self.settings = settings
        self.notificationCenter = notificationCenter
        self.setStatusItemVisible = setStatusItemVisible
        self.setActivationPolicy = setActivationPolicy
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(update),
            name: .spotAskMenuBarIconVisibilityChanged,
            object: settings
        )
        applyCurrentPreference()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @objc private func update() {
        applyCurrentPreference()
    }

    private func applyCurrentPreference() {
        let presentation = AppEntryPresentation(showsMenuBarIcon: settings.showsMenuBarIcon)
        setStatusItemVisible(presentation.showsStatusItem)
        setActivationPolicy(presentation.activationPolicy)
    }
}

@main
struct SpotAskApp: App {
    @NSApplicationDelegateAdaptor(SpotAskAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            // Settings are presented by SettingsWindowController. Replacing
            // the system command prevents its empty Settings scene from also
            // opening when the in-app Command-comma shortcut is used.
            .commands {
                CommandGroup(replacing: .appSettings) { }
            }
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
    private var entryPresentationCoordinator: AppEntryPresentationCoordinator?

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
        SpotAskCommandCenter.shared.configure(panelController: panelController)
        statusBarController = StatusBarController(settings: settings)
        entryPresentationCoordinator = AppEntryPresentationCoordinator(
            settings: settings,
            setStatusItemVisible: { [weak statusBarController] in
                statusBarController?.setVisible($0)
            },
            setActivationPolicy: { NSApp.setActivationPolicy($0) }
        )
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        handleDockReopen(hasVisibleWindows: flag) {
            SpotAskCommandCenter.shared.open()
        }
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
