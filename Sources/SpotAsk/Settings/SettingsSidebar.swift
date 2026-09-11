import SwiftUI

enum SettingsSidebarNavigationDirection: Hashable {
    case up
    case down
}

extension SettingsSection {
    func moving(_ direction: SettingsSidebarNavigationDirection) -> SettingsSection? {
        moving(direction, within: Array(SettingsSection.allCases))
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @Binding var searchText: String
    let settings: AppSettings
    let visibleSections: [SettingsSection]
    /// Results are computed by the parent so they reflect which groups can
    /// actually render (e.g. available models only when refresh is supported).
    let searchResults: [SettingsSearchResult]
    let onSelectResult: (SettingsSearchResult) -> Void
    @FocusState private var focusedSection: SettingsSection?

    private var sectionsByGroup: [(SettingsSectionGroup, [SettingsSection])] {
        SettingsSectionGroup.allCases.compactMap { group in
            let sections = visibleSections.filter { $0.group == group }
            return sections.isEmpty ? nil : (group, sections)
        }
    }

    var body: some View {
        let _ = settings.language
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("settings.title"))
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            TextField(L10n.string("settings.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .overlay(alignment: .trailing) {
                    if searchText.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 6)
                    } else {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                        .accessibilityLabel(L10n.string("settings.clearSearch"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                .accessibilityLabel(L10n.string("settings.searchPlaceholder"))
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sectionsByGroup, id: \.0) { group, sections in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 2)
                            ForEach(sections) { section in sectionButton(section) }
                        }
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(searchResults) { result in
                            Button { onSelectResult(result) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: result.target.section.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(
                                            LinearGradient(colors: result.target.section.tintGradient, startPoint: .top, endPoint: .bottom),
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                        Text(result.sectionTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 5).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if searchResults.isEmpty {
                            Text(L10n.string("settings.noSearchResults"))
                                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 390)
            }
            Spacer()
            Label("SpotAsk", systemImage: "sparkle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .padding(.top, 16)
        .frame(width: 210)
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(12)
    }

    private func sectionButton(_ section: SettingsSection) -> some View {
        Button {
            selection = section
            focusedSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        LinearGradient(colors: section.tintGradient, startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                Text(section.title).font(.system(size: 13, weight: selection == section ? .semibold : .regular)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
            .background(selection == section ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain).focusable().focused($focusedSection, equals: section).focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(from: section, direction: .up) }
        .onKeyPress(.downArrow) { moveSelection(from: section, direction: .down) }
    }

    private func moveSelection(from current: SettingsSection, direction: SettingsSidebarNavigationDirection) -> KeyPress.Result {
        guard let next = current.moving(direction, within: visibleSections) else { return .ignored }
        selection = next
        focusedSection = next
        return .handled
    }
}

