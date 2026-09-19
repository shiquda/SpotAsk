import SwiftUI

// MARK: - Reusable Settings Components

struct SettingsPageHeader: View {
    let section: SettingsSection
    let settings: AppSettings

    var body: some View {
        let _ = settings.language  // observe so header re-renders on language change

        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: section.tintGradient, startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            Text(section.title)
                .font(.system(size: 27, weight: .bold))
        }
    }
}

struct SettingsCallout: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The documentation link for one settings group.
///
/// The visible label is the shared open-documentation action, while the group
/// title it sits beside names the feature, so the same control repeated across
/// pages still reads distinctly to VoiceOver. `Link` hands the URL to the
/// system browser, which keeps Settings editable when the page cannot be
/// opened.
struct SettingsDocumentationLink: View {
    let url: URL
    /// Localized title of the group this link explains, used for the tooltip
    /// and the accessibility label.
    let groupTitle: String

    var body: some View {
        Link(destination: url) {
            Label(L10n.string("settings.openDocumentation"), systemImage: "book")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.link)
        .help(actionTitle)
        .accessibilityLabel(actionTitle)
    }

    private var actionTitle: String {
        L10n.string("settings.openDocumentationFor", groupTitle)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    /// Published documentation for the feature this group configures, when the
    /// group carries behavior worth a guide. Plain toggles keep no link.
    var documentation: URL? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if let documentation {
                    Spacer(minLength: 12)
                    SettingsDocumentationLink(url: documentation, groupTitle: title)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(title)
    }
}

/// A label/control row that lays out horizontally when the panel is wide enough
/// for the fixed 134pt label column, and stacks the label above the control when
/// it is not. The horizontal candidate demands at least 400pt so every row in a
/// given column makes the same choice, keeping the Service editor visually uniform.
struct SettingsLabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    private var wideForm: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .frame(width: 134, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stackedForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideForm
                .frame(minWidth: 400)
            stackedForm
        }
    }
}

struct SettingsToggleRow: View {
    let label: String
    var description: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fixedSize(horizontal: false, vertical: true)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(label)
        }
    }
}

struct SettingsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        SettingsLabeledRow(label: label) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

