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
                .background(section.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 13) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        SettingsLabeledRow(label: label) {
            HStack(spacing: 14) {
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(label)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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

