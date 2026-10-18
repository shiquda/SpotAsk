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
                        // Keep the trailing edge of the link flush with the card
                        // content below it (`.padding(16)`), instead of letting
                        // it run under the panel's overlay scrollbar.
                        .padding(.trailing, 16)
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

struct SettingsDangerGroup<Content: View>: View {
    let title: String
    var documentation: URL? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.red)
                }
                if let documentation {
                    Spacer(minLength: 12)
                    SettingsDocumentationLink(url: documentation, groupTitle: title)
                        .padding(.trailing, 16)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(title)
    }
}

struct SettingsDangerBanner: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.red.opacity(0.22), lineWidth: 1)
        )
    }
}

/// An adaptive row layout that arranges the label and content horizontally when
/// the available width is at least 400pt (with a fixed 134pt label and 14pt spacing),
/// or vertically when it is narrower (with 6pt vertical spacing).
///
/// Unlike `ViewThatFits`, this performs a single-pass layout without instantiating
/// duplicate subview candidate trees, avoiding repeated AppKit NSView allocations
/// and speculative size-fitting passes for embedded controls like `Picker`.
struct SettingsLabeledLayout: Layout {
    static let labelWidth: CGFloat = 134
    static let spacing: CGFloat = 14
    static let verticalSpacing: CGFloat = 6
    static let breakpoint: CGFloat = 400

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? Self.breakpoint
        let isWide = width >= Self.breakpoint

        if isWide {
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: Self.labelWidth, height: proposal.height))
            let contentWidth = max(0, width - Self.labelWidth - Self.spacing)
            let contentSize = subviews.count > 1
                ? subviews[1].sizeThatFits(ProposedViewSize(width: contentWidth, height: proposal.height))
                : .zero
            let height = max(labelSize.height, contentSize.height)
            return CGSize(width: width, height: height)
        } else {
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let contentSize = subviews.count > 1
                ? subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
                : .zero
            let height = labelSize.height + Self.verticalSpacing + contentSize.height
            return CGSize(width: width, height: height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let isWide = bounds.width >= Self.breakpoint

        if isWide {
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: Self.labelWidth, height: bounds.height))
            let contentWidth = max(0, bounds.width - Self.labelWidth - Self.spacing)
            let contentSize = subviews.count > 1
                ? subviews[1].sizeThatFits(ProposedViewSize(width: contentWidth, height: bounds.height))
                : .zero

            let rowHeight = bounds.height
            let labelY = bounds.minY + (rowHeight - labelSize.height) / 2
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: labelY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: Self.labelWidth, height: labelSize.height)
            )

            if subviews.count > 1 {
                let contentY = bounds.minY + (rowHeight - contentSize.height) / 2
                subviews[1].place(
                    at: CGPoint(x: bounds.minX + Self.labelWidth + Self.spacing, y: contentY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: contentWidth, height: contentSize.height)
                )
            }
        } else {
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: labelSize.height)
            )

            if subviews.count > 1 {
                let contentSize = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[1].place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY + labelSize.height + Self.verticalSpacing),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: contentSize.height)
                )
            }
        }
    }
}

/// A label/control row that lays out horizontally when the panel is wide enough
/// for the fixed 134pt label column, and stacks the label above the control when
/// it is not.
struct SettingsLabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        SettingsLabeledLayout {
            Text(label)
                .frame(width: SettingsLabeledLayout.labelWidth, alignment: .leading)
            content
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

