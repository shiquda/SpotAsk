import SwiftUI

// MARK: - Appearance Settings Page

struct AppearanceSettingsPage: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(section: .appearance, settings: settings)
            SettingsCallout(L10n.string("settings.readingDescription"))

            SettingsGroup(
                title: L10n.string("settings.appearance"),
                documentation: DocumentationLinks.url(for: .appearance, language: settings.language)
            ) {
                AppearanceThemePicker(selection: Bindable(settings).appearance)
            }

            SettingsGroup(title: L10n.string("settings.reading")) {
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
                if settings.renderMath {
                    SettingsToggleRow(
                        label: L10n.string("settings.copyMathWithDelimiters"),
                        isOn: Bindable(settings).copyMathWithDelimiters
                    )
                }
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

// MARK: - LookAway Style 3-Card Appearance Theme Picker

struct AppearanceThemePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 16) {
            ForEach(AppearanceMode.allCases) { mode in
                AppearanceThemeCard(
                    mode: mode,
                    isSelected: selection == mode,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = mode
                        }
                    }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("settings.appearance"))
    }
}

struct AppearanceThemeCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                AppearanceWindowPreview(mode: mode)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.25) : Color.primary.opacity(0.12)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.04),
                        radius: isSelected ? 4 : 2,
                        x: 0,
                        y: 1
                    )

                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .frame(width: 124)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String {
        switch mode {
        case .system: L10n.string("appearance.system")
        case .light: L10n.string("appearance.light")
        case .dark: L10n.string("appearance.dark")
        }
    }
}

struct AppearanceWindowPreview: View {
    let mode: AppearanceMode

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                switch mode {
                case .light:
                    LightModeWindowSilhouette()
                case .dark:
                    DarkModeWindowSilhouette()
                case .system:
                    HStack(spacing: 0) {
                        LightModeWindowSilhouette()
                            .frame(width: width / 2, height: height, alignment: .leading)
                            .clipped()
                        DarkModeWindowSilhouette()
                            .frame(width: width / 2, height: height, alignment: .trailing)
                            .clipped()
                    }
                    .overlay(
                        Rectangle()
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 0.5)
                    )
                }
            }
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LightModeWindowSilhouette: View {
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 2.5) {
                Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.32)).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.25)).frame(width: 3.5, height: 3.5)
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 12)
            .background(Color(red: 0.92, green: 0.93, blue: 0.95))

            // Content body
            VStack(alignment: .leading, spacing: 4) {
                // Search prompt pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.blue.opacity(0.75))
                        .frame(width: 3.5, height: 3.5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.78, green: 0.80, blue: 0.85))
                        .frame(width: 24, height: 3)
                    Spacer()
                }
                .padding(.horizontal, 5)
                .frame(height: 9)
                .background(Color(red: 0.89, green: 0.90, blue: 0.93), in: RoundedRectangle(cornerRadius: 3, style: .continuous))

                // Chat user bubble (right aligned)
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 36, height: 6.5)
                }

                // Chat assistant response placeholder (left aligned)
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.80, green: 0.82, blue: 0.86))
                        .frame(width: 44, height: 4)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.86, green: 0.88, blue: 0.90))
                        .frame(width: 28, height: 4)
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        }
    }
}

struct DarkModeWindowSilhouette: View {
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 2.5) {
                Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.32)).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.25)).frame(width: 3.5, height: 3.5)
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 12)
            .background(Color(red: 0.18, green: 0.18, blue: 0.20))

            // Content body
            VStack(alignment: .leading, spacing: 4) {
                // Search prompt pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.blue.opacity(0.85))
                        .frame(width: 3.5, height: 3.5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.45, green: 0.45, blue: 0.48))
                        .frame(width: 24, height: 3)
                    Spacer()
                }
                .padding(.horizontal, 5)
                .frame(height: 9)
                .background(Color(red: 0.22, green: 0.22, blue: 0.25), in: RoundedRectangle(cornerRadius: 3, style: .continuous))

                // Chat user bubble (right aligned)
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 36, height: 6.5)
                }

                // Chat assistant response placeholder (left aligned)
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.34, green: 0.34, blue: 0.38))
                        .frame(width: 44, height: 4)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.26, green: 0.26, blue: 0.29))
                        .frame(width: 28, height: 4)
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        }
    }
}
