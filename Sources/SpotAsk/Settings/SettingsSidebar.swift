import SwiftUI

enum SettingsSidebarNavigationDirection: Hashable {
    case up
    case down
}

extension SettingsSection {
    func moving(_ direction: SettingsSidebarNavigationDirection) -> SettingsSection? {
        guard let index = SettingsSection.allCases.firstIndex(of: self) else { return nil }
        switch direction {
        case .up where index > SettingsSection.allCases.startIndex:
            return SettingsSection.allCases[SettingsSection.allCases.index(before: index)]
        case .down where index < SettingsSection.allCases.index(before: SettingsSection.allCases.endIndex):
            return SettingsSection.allCases[SettingsSection.allCases.index(after: index)]
        default:
            return nil
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    let settings: AppSettings
    @FocusState private var focusedSection: SettingsSection?

    var body: some View {
        let _ = settings.language  // observe so sidebar re-renders on language change

        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("settings.title"))
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                    focusedSection = section
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(section.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(section.title)
                            .font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .background(selection == section ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedSection, equals: section)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) {
                    moveSelection(from: section, direction: .up)
                }
                .onKeyPress(.downArrow) {
                    moveSelection(from: section, direction: .down)
                }
            }

            Spacer()

            Label("SpotAsk", systemImage: "sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .padding(.top, 24)
        .frame(width: 190)
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(12)
    }

    private func moveSelection(from current: SettingsSection, direction: SettingsSidebarNavigationDirection) -> KeyPress.Result {
        guard let next = current.moving(direction) else { return .ignored }
        selection = next
        focusedSection = next
        return .handled
    }
}

