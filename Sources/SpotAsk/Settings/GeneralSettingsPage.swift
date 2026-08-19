import Foundation
import ServiceManagement
import SwiftUI

// MARK: - General Settings Page

struct GeneralSettingsPage: View {
    let settings: AppSettings
    @Bindable var generalState: GeneralSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .general, settings: settings)
            SettingsCallout(L10n.string("settings.generalDescription"))

            SettingsGroup(title: L10n.string("settings.language")) {
                SettingsFieldRow(label: L10n.string("settings.language")) {
                    Picker(L10n.string("settings.language"), selection: Bindable(settings).language) {
                        Text(L10n.string("language.system")).tag(AppLanguage.system)
                        ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                            Text(language.nativeName ?? language.rawValue).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroup(title: L10n.string("settings.behavior")) {
                SettingsFieldRow(label: L10n.string("settings.globalShortcut")) {
                    HStack(spacing: 8) {
                        ShortcutRecorder(
                            shortcut: settings.globalShortcut ?? .init(key: " ", modifiers: .option),
                            onRecord: { shortcut in
                                settings.globalShortcut = shortcut
                                StatusToastCenter.shared.show(L10n.string("settings.shortcutSaved"))
                            },
                            onInvalid: {
                                StatusToastCenter.shared.show(L10n.string("settings.shortcutInvalid"), isError: true)
                            },
                            allowsSpace: true
                        )
                        .frame(width: 176, height: 28)

                        Button {
                            settings.globalShortcut = nil
                            StatusToastCenter.shared.show(L10n.string("settings.shortcutRestored"))
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.string("settings.resetShortcut"))
                        .accessibilityLabel(L10n.string("settings.resetShortcut"))
                    }
                }
                SettingsToggleRow(label: L10n.string("settings.launchAtLogin"), isOn: Bindable(settings).launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                SettingsToggleRow(
                    label: L10n.string("settings.silentLaunch"),
                    description: L10n.string("settings.silentLaunchDescription"),
                    isOn: Bindable(settings).silentLaunch
                )
                SettingsToggleRow(label: L10n.string("settings.showMenuBarIcon"), isOn: Bindable(settings).showsMenuBarIcon)
                SettingsToggleRow(label: L10n.string("settings.restoreSession"), isOn: Bindable(settings).retainSession)
                SettingsToggleRow(label: L10n.string("settings.clearInputOnClose"), isOn: Bindable(settings).clearInputOnClose)
                SettingsToggleRow(label: L10n.string("settings.confirmBeforeStartingNewConversation"), isOn: Bindable(settings).confirmBeforeStartingNewConversation)
                SettingsToggleRow(label: L10n.string("settings.escapeStartsNewConversation"), isOn: Bindable(settings).escapeStartsNewConversation)
                SettingsToggleRow(label: L10n.string("settings.defaultExpandReasoning"), isOn: Bindable(settings).defaultExpandReasoning)
                SettingsToggleRow(
                    label: L10n.string("settings.windowOnTop"),
                    isOn: Binding(
                        get: { settings.keepWindowOnTop },
                        set: { _ in SpotAskCommandCenter.shared.toggleWindowOnTop() }
                    )
                )
                SettingsFieldRow(label: L10n.string("settings.contextLimit")) {
                    Picker(L10n.string("settings.contextLimit"), selection: Bindable(settings).contextLimit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("40").tag(40)
                        Text(L10n.string("settings.unlimited")).tag(0)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroup(title: L10n.string("settings.proxy")) {
                SettingsToggleRow(label: L10n.string("settings.proxyEnabled"), isOn: Bindable(settings).proxyEnabled)
                if settings.proxyEnabled {
                    SettingsFieldRow(label: L10n.string("settings.proxyType")) {
                        HStack(spacing: 0) {
                            Picker(L10n.string("settings.proxyType"), selection: Bindable(settings).proxyType) {
                                ForEach(ProxyType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Spacer(minLength: 0)
                        }
                    }
                    SettingsFieldRow(label: L10n.string("settings.proxyHost")) {
                        TextField(L10n.string("settings.proxyHostPlaceholder"), text: Bindable(settings).proxyHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    SettingsFieldRow(label: L10n.string("settings.proxyPort")) {
                        TextField(
                            "",
                            value: Bindable(settings).proxyPort,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120, alignment: .leading)
                    }
                    SettingsFieldRow(label: L10n.string("settings.proxyUsername")) {
                        TextField(L10n.string("settings.proxyUsernamePlaceholder"), text: Bindable(settings).proxyUsername)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.username)
                    }
                    SettingsFieldRow(label: L10n.string("settings.proxyPassword")) {
                        SecureField(L10n.string("settings.proxyPasswordPlaceholder"), text: $generalState.proxyPasswordDraft)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .onChange(of: generalState.proxyPasswordDraft) { _, _ in
                                generalState.persistProxyPasswordDraft()
                            }
                    }
                    HStack(spacing: 10) {
                        Button(L10n.string("settings.testProxy")) {
                            generalState.testProxy()
                        }
                        .buttonStyle(.bordered)
                        .disabled(generalState.isTestingProxy)

                        if generalState.isTestingProxy {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }

            SettingsGroup(title: L10n.string("settings.diagnostics")) {
                SettingsToggleRow(
                    label: L10n.string("settings.diagnosticsEnabled"),
                    description: L10n.string("settings.diagnosticsDescription"),
                    isOn: Bindable(settings).diagnosticsEnabled
                )
                if settings.diagnosticsEnabled {
                    HStack(spacing: 10) {
                        Button(L10n.string("settings.diagnosticsExport")) {
                            generalState.exportDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        Button(L10n.string("settings.diagnosticsClear"), role: .destructive) {
                            generalState.clearDiagnostics()
                        }
                    }
                }
            }

            SettingsGroup(title: L10n.string("settings.localData")) {
                Text(L10n.string("settings.localDataDescription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.string("settings.clearAllLocalData"), role: .destructive) {
                    generalState.clearAllLocalData()
                }
            }

            SettingsGroup(title: L10n.string("settings.configuration")) {
                Text(L10n.string("settings.configurationDescription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(L10n.string("settings.exportConfiguration")) {
                        generalState.exportConfiguration()
                    }
                    .buttonStyle(.bordered)
                    Button(L10n.string("settings.importConfiguration")) {
                        generalState.importConfiguration()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            settings.launchAtLogin = false
        }
    }
}

