import AppKit
import Foundation
import SwiftUI

// MARK: - Core Query Model & Parser

/// Represents an active `@` query in the composer.
struct AtCommandQuery: Equatable, Sendable {
    /// The 0-based character index of the `@` symbol in the editor.
    let triggerLocation: Int
    /// The keyword typed after `@` up to the caret.
    let keyword: String

    /// The text range covered by `@keyword`.
    var range: NSRange {
        NSRange(location: triggerLocation, length: 1 + (keyword as NSString).length)
    }
}

enum AtCommandParser {
    /// Determines whether the character is permitted in an `@` command keyword.
    /// Spec §2.3: `a-z A-Z 0-9 _ -` plus CJK ideographs, hiragana, katakana.
    static func isAllowedKeywordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "-"
    }

    /// Parses text and caret location to detect an active `@` trigger.
    static func parse(
        text: String,
        selectedRange: NSRange,
        hasMarkedText: Bool
    ) -> AtCommandQuery? {
        // IME composition suppresses trigger
        guard !hasMarkedText else { return nil }
        // Caret must be a single point, not a text selection range
        guard selectedRange.length == 0 else { return nil }
        let caret = selectedRange.location
        let nsText = text as NSString
        guard caret >= 0, caret <= nsText.length else { return nil }

        // Scan backwards from caret to find '@'
        var idx = caret - 1
        var keywordChars: [Character] = []
        while idx >= 0 {
            let chCode = nsText.character(at: idx)
            if chCode == 0x40 { // '@'
                // Escaped by backslash
                if idx > 0 && nsText.character(at: idx - 1) == 0x5C {
                    return nil
                }
                // Boundary check: start of text or preceded by whitespace/newline
                if idx > 0 {
                    let prevCode = nsText.character(at: idx - 1)
                    guard let scalar = UnicodeScalar(prevCode),
                          CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                        return nil
                    }
                }
                let keyword = String(keywordChars.reversed())
                return AtCommandQuery(triggerLocation: idx, keyword: keyword)
            }

            guard let scalar = UnicodeScalar(chCode) else { return nil }
            let ch = Character(scalar)
            // Stop scanning if whitespace, full-width ＠, or invalid character is encountered
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || chCode == 0xFF20 || !isAllowedKeywordCharacter(ch) {
                return nil
            }
            keywordChars.append(ch)
            idx -= 1
        }
        return nil
    }
}

// MARK: - Candidate Item Model & Filtering

enum AtCommandItemKind: Equatable, Sendable {
    case promptPreset(PromptPreset)
    case quickAction(QuickAction)
}

struct AtCommandItem: Identifiable, Equatable, Sendable {
    let id: String
    let kind: AtCommandItemKind
    let title: String
    let subtitle: String?
    let iconName: String
    let brandIconSlug: String?
    let kindBadge: String?
    let isSelectedPreset: Bool

    static func makePresets(
        from presets: [PromptPreset],
        selectedPresetID: UUID?
    ) -> [AtCommandItem] {
        presets.map { preset in
            AtCommandItem(
                id: "preset-\(preset.id.uuidString)",
                kind: .promptPreset(preset),
                title: preset.title,
                subtitle: preset.instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                iconName: preset.symbolName,
                brandIconSlug: nil,
                kindBadge: nil,
                isSelectedPreset: selectedPresetID == preset.id
            )
        }
    }

    static func makeQuickActions(
        from actions: [QuickAction]
    ) -> [AtCommandItem] {
        actions.map { action in
            let kindBadge: String
            switch action.kind {
            case .web:
                kindBadge = L10n.string("externalAsk.kind.web")
            case .uriScheme:
                kindBadge = L10n.string("externalAsk.kind.uriScheme")
            case .terminal:
                kindBadge = L10n.string("externalAsk.kind.terminal")
            }
            return AtCommandItem(
                id: "action-\(action.id.uuidString)",
                kind: .quickAction(action),
                title: action.displayName,
                subtitle: nil,
                iconName: action.symbolName,
                brandIconSlug: action.brandIconSlug,
                kindBadge: kindBadge,
                isSelectedPreset: false
            )
        }
    }
}

enum AtCommandFilter {
    static func filter(
        items: [AtCommandItem],
        keyword: String
    ) -> [AtCommandItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        var prefixMatches: [AtCommandItem] = []
        var substringMatches: [AtCommandItem] = []

        for item in items {
            if item.title.range(of: trimmed, options: [.caseInsensitive, .anchored]) != nil {
                prefixMatches.append(item)
            } else if item.title.localizedCaseInsensitiveContains(trimmed) ||
                      item.subtitle?.localizedCaseInsensitiveContains(trimmed) == true {
                substringMatches.append(item)
            }
        }
        return prefixMatches + substringMatches
    }
}

// MARK: - State Machine

@MainActor
@Observable
final class AtCommandState {
    var isPresented: Bool = false
    var query: AtCommandQuery?
    var highlightedIndex: Int = 0
    var anchorPoint: CGPoint = .zero

    private(set) var filteredItems: [AtCommandItem] = []
    private(set) var filteredPresets: [AtCommandItem] = []
    private(set) var filteredQuickActions: [AtCommandItem] = []

    var currentSelectedItem: AtCommandItem? {
        guard isPresented, !filteredItems.isEmpty,
              highlightedIndex >= 0, highlightedIndex < filteredItems.count else {
            return nil
        }
        return filteredItems[highlightedIndex]
    }

    func update(
        query: AtCommandQuery?,
        presets: [PromptPreset],
        selectedPresetID: UUID?,
        quickActions: [QuickAction],
        anchorPoint: CGPoint
    ) {
        guard let query else {
            dismiss()
            return
        }
        self.query = query
        self.anchorPoint = anchorPoint

        let allPresets = AtCommandItem.makePresets(from: presets, selectedPresetID: selectedPresetID)
        let allActions = AtCommandItem.makeQuickActions(from: quickActions)

        let matchingPresets = AtCommandFilter.filter(items: allPresets, keyword: query.keyword)
        let matchingActions = AtCommandFilter.filter(items: allActions, keyword: query.keyword)

        self.filteredPresets = matchingPresets
        self.filteredQuickActions = matchingActions
        self.filteredItems = matchingPresets + matchingActions

        if !isPresented {
            isPresented = true
            highlightedIndex = 0
        } else {
            if filteredItems.isEmpty {
                highlightedIndex = 0
            } else if highlightedIndex >= filteredItems.count {
                highlightedIndex = max(0, filteredItems.count - 1)
            }
        }
    }

    func dismiss() {
        isPresented = false
        query = nil
        highlightedIndex = 0
        filteredItems = []
        filteredPresets = []
        filteredQuickActions = []
    }

    func selectNext() {
        guard !filteredItems.isEmpty else { return }
        highlightedIndex = (highlightedIndex + 1) % filteredItems.count
    }

    func selectPrevious() {
        guard !filteredItems.isEmpty else { return }
        highlightedIndex = (highlightedIndex - 1 + filteredItems.count) % filteredItems.count
    }

    func highlight(item: AtCommandItem) {
        if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
            highlightedIndex = index
        }
    }
}

// MARK: - UI Views

struct AtCommandPaletteView: View {
    @Bindable var state: AtCommandState
    let showsShortcutHints: Bool
    let shortcutForPreset: (PromptPreset) -> InAppShortcut?
    let shortcutForAction: (QuickAction) -> InAppShortcut?
    let onSelect: (AtCommandItem) -> Void

    private func shortcut(for item: AtCommandItem) -> InAppShortcut? {
        switch item.kind {
        case let .promptPreset(preset):
            shortcutForPreset(preset)
        case let .quickAction(action):
            shortcutForAction(action)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status / search indicator
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                if let query = state.query, !query.keyword.isEmpty {
                    Text(L10n.string("chat.atCommand.filtering", query.keyword))
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.muted)
                } else {
                    Text(L10n.string("chat.atCommand.searchPlaceholder"))
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if state.filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.muted)
                    Text(L10n.string("chat.atCommand.noMatching", state.query?.keyword ?? ""))
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.muted)
                    Text(L10n.string("chat.atCommand.pressEscToCancel"))
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.vertical, 12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !state.filteredPresets.isEmpty {
                                Text(L10n.string("settings.prompts").uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Brand.muted)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)

                                ForEach(state.filteredPresets) { item in
                                    AtCommandRow(
                                        item: item,
                                        isHighlighted: state.currentSelectedItem?.id == item.id,
                                        shortcut: showsShortcutHints ? shortcut(for: item) : nil,
                                        action: { onSelect(item) },
                                        onHover: { if $0 { state.highlight(item: item) } }
                                    )
                                    .id(item.id)
                                }
                            }

                            if !state.filteredQuickActions.isEmpty {
                                if !state.filteredPresets.isEmpty {
                                    Divider()
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                }

                                Text(L10n.string("settings.externalAsk").uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Brand.muted)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)

                                ForEach(state.filteredQuickActions) { item in
                                    AtCommandRow(
                                        item: item,
                                        isHighlighted: state.currentSelectedItem?.id == item.id,
                                        shortcut: showsShortcutHints ? shortcut(for: item) : nil,
                                        action: { onSelect(item) },
                                        onHover: { if $0 { state.highlight(item: item) } }
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                        .padding(5)
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: state.highlightedIndex) { _, _ in
                        if let selected = state.currentSelectedItem {
                            proxy.scrollTo(selected.id, anchor: nil)
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(L10n.string("chat.atCommand.accessibilityLabel"))
    }
}

private struct AtCommandRow: View {
    let item: AtCommandItem
    let isHighlighted: Bool
    let shortcut: InAppShortcut?
    let action: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let brandSlug = item.brandIconSlug {
                    ProviderBrandIconView(
                        slug: brandSlug,
                        size: 13,
                        fallbackSymbol: item.iconName
                    )
                    .frame(width: 14)
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 13))
                        .foregroundStyle(isHighlighted || isHovering ? Brand.fg : Brand.muted)
                        .frame(width: 14)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.fg)
                        .lineLimit(1)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let kindBadge = item.kindBadge {
                    Text(kindBadge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Brand.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4).fill(Brand.muted.opacity(0.12))
                        )
                }

                if let shortcut {
                    ShortcutKeycap(shortcut: shortcut)
                }

                if item.isSelectedPreset {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHighlighted ? Brand.accent.opacity(0.12) : (isHovering ? Brand.surface : Color.clear))
            )
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Brand.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.isSelectedPreset ? .isSelected : [])
    }
}
