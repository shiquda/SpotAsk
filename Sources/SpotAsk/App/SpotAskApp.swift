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
    private let accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator
    private let panelController = SpotAskPanelController()
    private let globalHotKey = GlobalHotKey()
    private let selectionHotKey = GlobalHotKey(identifier: 2)
    private let selectionAssistantToggleHotKey = GlobalHotKey(identifier: 3)
    private var selectionCoordinator: SelectionAssistantCoordinator?
    private var selectionOverlay: SelectionOverlayController?
    private var selectionAutoInvokeMonitor: SelectionAutoInvokeMonitor?
    private lazy var launchUpdateNotifier = AutomaticUpdateNotifier(settings: settings)
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
        let providerFactory = OpenAICompatibleProviderFactory(settings: settings, keyStore: keyStore)
        let sessionStore = SessionStore()
        self.providerFactory = providerFactory
        self.sessionStore = sessionStore
        self.accessibilityPermissionCoordinator = AccessibilityPermissionCoordinator()
        self.chatViewModel = ChatViewModel(
            settings: settings,
            providerFactory: providerFactory,
            sessionStore: sessionStore
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
                accessibilityPermissionCoordinator: self.accessibilityPermissionCoordinator,
                onDismiss: { SpotAskCommandCenter.shared.close() }
            )
        }
        let overlay = SelectionOverlayController()
        selectionOverlay = overlay
        selectionCoordinator = SelectionAssistantCoordinator(
            settings: settings,
            permissionCoordinator: accessibilityPermissionCoordinator,
            overlay: overlay
        )
        if let selectionCoordinator {
            let monitor = SelectionAutoInvokeMonitor(coordinator: selectionCoordinator)
            monitor.start()
            selectionAutoInvokeMonitor = monitor
        }
        do {
            try registerGlobalHotKey()
        } catch {
            StatusToastCenter.shared.show(L10n.string("settings.shortcutInvalid"), isError: true)
        }
        registerSelectionHotKeyIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(reconfigureGlobalHotKey), name: .spotAskHotKeyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reconfigureSelectionHotKey), name: .spotAskSelectionAssistantChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAccessibilityPermission), name: NSApplication.didBecomeActiveNotification, object: nil)
        SpotAskShortcuts.updateAppShortcutParameters()
        DiagnosticLogStore.shared.setEnabled(settings.diagnosticsEnabled)
        DiagnosticLogStore.shared.record("app-launch")
        if !settings.silentLaunch {
            SpotAskCommandCenter.shared.open()
        }
        scheduleAutomaticUpdateCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        globalHotKey.unregister()
        selectionHotKey.unregister()
        selectionAssistantToggleHotKey.unregister()
        selectionAutoInvokeMonitor?.stop()
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
            StatusToastCenter.shared.show(L10n.string("settings.shortcutInvalid"), isError: true)
        }
    }

    @objc private func reconfigureSelectionHotKey() {
        registerSelectionHotKeyIfNeeded()
    }

    @objc private func refreshAccessibilityPermission() {
        accessibilityPermissionCoordinator.refresh()
    }

    private func scheduleAutomaticUpdateCheck() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            await self.launchUpdateNotifier.checkAtLaunchIfEnabled { update in
                StatusToastCenter.shared.show(
                    L10n.string("update.newVersionAvailable", update.version.description),
                    actionTitle: L10n.string("update.viewRelease"),
                    duration: StatusToastCenter.actionDisplayDuration
                ) {
                    NSWorkspace.shared.open(AppUpdateChecker.downloadURL)
                }
            }
        }
    }

    private func registerGlobalHotKey() throws {
        if let globalShortcut = settings.globalShortcut,
           let configuration = GlobalHotKey.configuration(for: globalShortcut) {
            try globalHotKey.register(keyCode: configuration.keyCode, modifiers: configuration.modifiers) {
                Task { @MainActor in SpotAskCommandCenter.shared.toggle() }
            }
            return
        }

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

    private func registerSelectionHotKeyIfNeeded() {
        selectionHotKey.unregister()
        selectionAssistantToggleHotKey.unregister()
        if settings.selectionAssistantEnabled {
            let modifiers: UInt32
            switch settings.selectionHotKeyPreset {
            case .optionShiftSpace: modifiers = UInt32(optionKey | shiftKey)
            }
            do {
                try selectionHotKey.register(keyCode: GlobalHotKey.defaultKeyCode, modifiers: modifiers) { [weak self] in
                    SafeLogger.selectionHotKeyTriggered()
                    Task { @MainActor in self?.selectionCoordinator?.trigger() }
                }
                SafeLogger.selectionHotKeyRegistered()
            } catch {
                SafeLogger.selectionHotKeyRegistrationFailed(error)
            }
        }
        guard let shortcut = settings.selectionAssistantToggleShortcut,
              let configuration = GlobalHotKey.configuration(for: shortcut) else { return }
        do {
            try selectionAssistantToggleHotKey.register(
                keyCode: configuration.keyCode,
                modifiers: configuration.modifiers
            ) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.settings.selectionAutoInvokeEnabled.toggle()
                    NotificationCenter.default.post(name: .spotAskSelectionAssistantChanged, object: nil)
                }
            }
        } catch {
            SafeLogger.selectionHotKeyRegistrationFailed(error)
        }
    }
}
