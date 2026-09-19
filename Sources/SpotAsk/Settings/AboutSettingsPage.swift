import Foundation
import SwiftUI

// MARK: - About Settings Page

struct AboutSettingsPage: View {
    @Bindable var coordinator: UpdateCoordinator
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .about, settings: settings)
            SettingsCallout(L10n.string("settings.aboutDescription"))

            SettingsGroup(title: "SpotAsk") {
                SettingsFieldRow(label: L10n.string("settings.version")) {
                    Text(AppVersion.current.description)
                        .textSelection(.enabled)
                }
                Divider()
                SettingsFieldRow(label: L10n.string("settings.source")) {
                    Link(UpdateFeed.sourceURL.absoluteString, destination: UpdateFeed.sourceURL)
                        .textSelection(.enabled)
                }
                Divider()
                SettingsFieldRow(label: L10n.string("settings.userGuide")) {
                    Link(destination: DocumentationLinks.userGuideURL(for: settings.language)) {
                        Label(L10n.string("settings.openDocumentation"), systemImage: "book")
                    }
                }
            }

            SettingsGroup(title: L10n.string("settings.updates")) {
                SettingsToggleRow(
                    label: L10n.string("settings.autoCheckForUpdates"),
                    description: L10n.string("settings.autoCheckForUpdatesDescription"),
                    isOn: Bindable(settings).automaticUpdateCheckEnabled
                )
                .onChange(of: settings.automaticUpdateCheckEnabled) { _, enabled in
                    coordinator.setAutomaticChecksEnabled(enabled)
                }

                Divider()

                SettingsFieldRow(label: L10n.string("settings.updateSource")) {
                    Picker(L10n.string("settings.updateSource"), selection: Bindable(settings).updateDownloadSource) {
                        ForEach(UpdateDownloadSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                }

                if let skippedVersion = coordinator.skippedVersion {
                    Divider()
                    SettingsFieldRow(label: L10n.string("update.ignoredVersionRow", skippedVersion)) {
                        Button(L10n.string("update.restoreReminder")) {
                            coordinator.restoreReminders()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }

                Divider()
                HStack(spacing: 10) {
                    Button {
                        coordinator.checkForUpdates()
                    } label: {
                        Label(L10n.string("settings.checkForUpdates"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.isChecking)

                    Button {
                        coordinator.openGitHubReleaseFallback()
                    } label: {
                        Label(L10n.string("settings.openGitHubRelease"), systemImage: "safari")
                    }
                    .buttonStyle(.bordered)

                    if coordinator.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if coordinator.status == .unavailable {
                    Text(L10n.string("settings.updateCheckUnavailable"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            coordinator.refreshSkippedVersion()
        }
    }
}
