import Foundation
import SwiftUI

// MARK: - About Settings Page

enum DocumentationLinks {
    static let englishUserGuide = URL(string: "https://shiquda.github.io/SpotAsk/")!
    static let simplifiedChineseUserGuide = URL(string: "https://shiquda.github.io/SpotAsk/zh-CN/")!

    static func userGuideURL(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> URL {
        let usesChineseDocumentation = language == .simplifiedChinese
            || (language == .system && preferredLanguages.first?.lowercased().hasPrefix("zh") == true)
        return usesChineseDocumentation ? simplifiedChineseUserGuide : englishUserGuide
    }
}

struct AboutSettingsPage: View {
    let updateState: AppUpdateState
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
                    Link(AppUpdateChecker.sourceURL.absoluteString, destination: AppUpdateChecker.sourceURL)
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
                Divider()
                HStack(spacing: 10) {
                    Button {
                        updateState.checkForUpdate()
                    } label: {
                        Label(L10n.string("settings.checkForUpdates"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(updateState.isChecking)

                    if case .updateAvailable = updateState.status {
                        Link(destination: AppUpdateChecker.downloadURL) {
                            Label(L10n.string("settings.downloadUpdate"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if updateState.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
        }
    }

    private var statusText: String? {
        switch updateState.status {
        case .idle:
            nil
        case .checking:
            L10n.string("settings.checkingForUpdates")
        case .upToDate:
            L10n.string("settings.upToDate")
        case let .updateAvailable(update):
            L10n.string("settings.updateAvailable", update.version.description)
        case .unavailable:
            L10n.string("settings.updateCheckUnavailable")
        }
    }

    private var statusColor: Color {
        switch updateState.status {
        case .unavailable:
            .red
        default:
            .secondary
        }
    }
}

