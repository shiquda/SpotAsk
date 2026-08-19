import SwiftUI

// MARK: - Appearance Settings Page

struct AppearanceSettingsPage: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .appearance, settings: settings)
            SettingsCallout(L10n.string("settings.readingDescription"))
            SettingsGroup(title: L10n.string("settings.reading")) {
                SettingsFieldRow(label: L10n.string("settings.appearance")) {
                    HStack(spacing: 0) {
                        Picker(L10n.string("settings.appearance"), selection: Bindable(settings).appearance) {
                            Text(L10n.string("appearance.system")).tag(AppearanceMode.system)
                            Text(L10n.string("appearance.light")).tag(AppearanceMode.light)
                            Text(L10n.string("appearance.dark")).tag(AppearanceMode.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
                }
                SettingsFieldRow(label: L10n.string("settings.chatMessageStyle")) {
                    HStack(spacing: 0) {
                        Picker(L10n.string("settings.chatMessageStyle"), selection: Bindable(settings).chatMessageStyle) {
                            Text(L10n.string("chatMessageStyle.standard")).tag(ChatMessageStyle.standard)
                            Text(L10n.string("chatMessageStyle.im")).tag(ChatMessageStyle.im)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
                }
                SettingsToggleRow(
                    label: L10n.string("settings.renderMath"),
                    isOn: Bindable(settings).renderMath
                )
                SettingsFieldRow(label: L10n.string("settings.fontSize")) {
                    HStack(spacing: 0) {
                        Picker(L10n.string("settings.fontSize"), selection: Bindable(settings).fontSize) {
                            Text(L10n.string("font.small")).tag(FontSize.small)
                            Text(L10n.string("font.standard")).tag(FontSize.standard)
                            Text(L10n.string("font.large")).tag(FontSize.large)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
