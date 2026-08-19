import AppKit
import SwiftUI

enum SettingsSection: CaseIterable, Hashable, Identifiable {
    case provider
    case prompts
    case externalAsk
    case selectionAssistant
    case shortcuts
    case general
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .provider: L10n.string("settings.provider")
        case .prompts: L10n.string("settings.prompts")
        case .externalAsk: L10n.string("settings.externalAsk")
        case .selectionAssistant: L10n.string("settings.selectionAssistant")
        case .shortcuts: L10n.string("settings.shortcuts")
        case .general: L10n.string("settings.general")
        case .appearance: L10n.string("settings.appearance")
        case .about: L10n.string("settings.about")
        }
    }

    var symbol: String {
        switch self {
        case .provider: "network"
        case .prompts: "text.badge.plus"
        case .externalAsk: "globe"
        case .selectionAssistant: "text.viewfinder"
        case .shortcuts: "command"
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .provider: .cyan
        case .prompts: .mint
        case .externalAsk: .blue
        case .selectionAssistant: .teal
        case .shortcuts: .orange
        case .general: .gray
        case .appearance: .indigo
        case .about: .purple
        }
    }
}

struct SettingsView: View {
    let settings: AppSettings
    let accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator
    private let accessibilitySettingsOpener: any AccessibilityPermissionSettingsOpening

    private let settingsWindowProvider: (() -> NSWindow?)?
    @State private var selectedSection: SettingsSection = .provider
    @State private var providerState: ProviderSettingsState
    @State private var generalState: GeneralSettingsState
    @State private var updateState = AppUpdateState()

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        accessibilityPermissionCoordinator: AccessibilityPermissionCoordinator = AccessibilityPermissionCoordinator(),
        accessibilitySettingsOpener: any AccessibilityPermissionSettingsOpening = MacOSAccessibilityPermissionSettingsOpener(),
        initialSection: SettingsSection = .provider,
        settingsWindowProvider: (() -> NSWindow?)? = nil
    ) {
        self.settings = settings
        self.accessibilityPermissionCoordinator = accessibilityPermissionCoordinator
        self.accessibilitySettingsOpener = accessibilitySettingsOpener
        self.settingsWindowProvider = settingsWindowProvider
        _selectedSection = State(initialValue: initialSection)
        let providerState = ProviderSettingsState(
            settings: settings,
            keyStore: keyStore,
            providerFactory: providerFactory
        )
        _providerState = State(initialValue: providerState)
        _generalState = State(initialValue: GeneralSettingsState(
            settings: settings,
            keyStore: keyStore,
            settingsWindowProvider: settingsWindowProvider,
            onConfigurationImported: { providerState.reloadCatalogSelection() }
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedSection, settings: settings)
            Divider()
            Group {
                switch selectedSection {
                case .provider:
                    ProviderSettingsPage(settings: settings, state: providerState)
                case .prompts:
                    ScrollView {
                        PromptPresetsSettingsPage(settings: settings)
                    }
                case .externalAsk:
                    ScrollView {
                        ExternalAskSettingsPage(settings: settings)
                    }
                case .selectionAssistant:
                    SelectionAssistantSettingsPage(
                        settings: settings,
                        permissionCoordinator: accessibilityPermissionCoordinator,
                        settingsOpener: accessibilitySettingsOpener,
                        onOpenShortcuts: { selectedSection = .shortcuts }
                    )
                case .shortcuts:
                    ScrollView {
                        ShortcutSettingsPage(settings: settings)
                    }
                case .general:
                    ScrollView {
                        GeneralSettingsPage(settings: settings, generalState: generalState)
                    }
                case .appearance:
                    AppearanceSettingsPage(settings: settings)
                case .about:
                    AboutSettingsPage(updateState: updateState, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 860, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.appearance.colorScheme)
        .environment(\.dynamicTypeSize, settings.interfaceZoomLevel.dynamicTypeSize)
        .overlay(alignment: .topTrailing) {
            StatusToastOverlay()
                .padding(.top, 36)
        }
    }
}

