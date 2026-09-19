import AppKit
import SwiftUI

/// Transient `@` activation interval. Pure UI state; not persisted.
struct AtCommandState: Equatable {
    let atLocation: Int
    let keyword: String
    let replacementRange: NSRange
}


enum AtCommandPaletteRow: Identifiable, Equatable {
    case preset(PromptPreset)
    case action(QuickAction)

    var id: UUID {
        switch self {
        case let .preset(preset): preset.id
        case let .action(action): action.id
        }
    }
}
enum AtCommandDetector {
    /// ASCII `@`. Fullwidth `＠` never matches.
    private static let atScalar: unichar = 0x40
    private static let backslashScalar: unichar = 0x5C

    static func state(in text: String, selectedRange: NSRange) -> AtCommandState? {
        let ns = text as NSString
        let caret = selectedRange.location
        guard selectedRange.length == 0,
              caret > 0,
              caret <= ns.length else { return nil }

        var index = caret - 1
        while index >= 0 {
            let character = ns.character(at: index)
            if character == atScalar {
                if index > 0 {
                    let previous = ns.character(at: index - 1)
                    if previous == backslashScalar { return nil }
                    if !isWhitespace(ns, at: index - 1) { return nil }
                }
                let keywordLocation = index + 1
                let keywordLength = caret - keywordLocation
                let keywordRange = NSRange(location: keywordLocation, length: keywordLength)
                let keyword = ns.substring(with: keywordRange)
                if keyword.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                    return nil
                }
                return AtCommandState(
                    atLocation: index,
                    keyword: keyword,
                    replacementRange: NSRange(location: index, length: caret - index)
                )
            }
            if isWhitespace(ns, at: index) { return nil }
            index -= 1
        }
        return nil
    }

    /// Keyword uses committed text only; marked IME composition is excluded.
    @MainActor
    static func state(in textView: NSTextView) -> AtCommandState? {
        let (text, selectedRange) = committedContent(in: textView)
        return state(in: text, selectedRange: selectedRange)
    }

    @MainActor
    static func committedContent(in textView: NSTextView) -> (text: String, selectedRange: NSRange) {
        let ns = textView.string as NSString
        var text = textView.string
        var selectedRange = textView.selectedRange()
        guard textView.hasMarkedText() else { return (text, selectedRange) }
        let markedRange = textView.markedRange()
        guard markedRange.location != NSNotFound, markedRange.length > 0 else {
            return (text, selectedRange)
        }
        text = ns.replacingCharacters(in: markedRange, with: "")
        if selectedRange.location > markedRange.location {
            let clamped = min(selectedRange.location - markedRange.location, markedRange.length)
            selectedRange.location -= clamped
        }
        selectedRange.length = 0
        let maxLocation = (text as NSString).length
        selectedRange.location = min(max(selectedRange.location, 0), maxLocation)
        return (text, selectedRange)
    }

    /// Deletes `@keyword` only when `state.replacementRange` still contains that token.
    /// Returns `false` without mutating the text view when the range is stale, out of
    /// bounds, or `shouldChangeText` rejects the edit. A successful delete is undoable.
    @discardableResult
    @MainActor
    static func deleteActiveToken(_ state: AtCommandState, in textView: NSTextView) -> Bool {
        let range = state.replacementRange
        let ns = textView.string as NSString
        guard range.location != NSNotFound,
              range.location >= 0,
              NSMaxRange(range) <= ns.length else { return false }
        let expected = "@\(state.keyword)"
        guard ns.substring(with: range) == expected else { return false }
        guard textView.shouldChangeText(in: range, replacementString: "") else { return false }
        textView.replaceCharacters(in: range, with: "")
        textView.didChangeText()
        let location = min(range.location, (textView.string as NSString).length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        return true
    }


    private static func isWhitespace(_ ns: NSString, at index: Int) -> Bool {
        let unit = ns.substring(with: NSRange(location: index, length: 1))
        return unit.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }
}

/// ChatView `@` palette selection path: validate/delete the token, then apply,
/// pend, or launch. Launch failure keeps the action retryable.
@MainActor
enum AtCommandSelection {
    enum Outcome: Equatable {
        case rejected
        case appliedPreset
        case becamePending(QuickAction)
        case launched
        case launchFailed(QuickAction)
    }

    static func selectPreset(state: AtCommandState?, textView: NSTextView?) -> Outcome {
        guard let state, let textView,
              AtCommandDetector.deleteActiveToken(state, in: textView) else {
            return .rejected
        }
        return .appliedPreset
    }

    static func selectAction(
        _ action: QuickAction,
        state: AtCommandState?,
        textView: NSTextView?,
        resolve: (UUID) -> QuickAction?,
        executor: any QuickActionExecuting = DefaultQuickActionExecutor()
    ) -> Outcome {
        guard let state, let textView,
              AtCommandDetector.deleteActiveToken(state, in: textView) else {
            return .rejected
        }
        let query = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return .becamePending(action)
        }
        return launch(action, query: query, resolve: resolve, executor: executor)
    }

    static func confirmPending(
        _ action: QuickAction,
        query: String,
        resolve: (UUID) -> QuickAction?,
        executor: any QuickActionExecuting = DefaultQuickActionExecutor()
    ) -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected }
        return launch(action, query: trimmed, resolve: resolve, executor: executor)
    }

    private static func launch(
        _ action: QuickAction,
        query: String,
        resolve: (UUID) -> QuickAction?,
        executor: any QuickActionExecuting
    ) -> Outcome {
        guard let current = resolve(action.id) else {
            return .launchFailed(action)
        }
        if QuickActionLaunch.perform(current, query: query, executor: executor) {
            return .launched
        }
        return .launchFailed(current)
    }
}

enum AtCommandMatcher {
    static func ranked<T>(_ items: [T], keyword: String, fields: (T) -> [String]) -> [T] {
        if keyword.isEmpty { return items }
        var prefixes: [T] = []
        var substrings: [T] = []
        for item in items {
            let texts = fields(item)
            if texts.contains(where: { matches($0, keyword: keyword, prefix: true) }) {
                prefixes.append(item)
            } else if texts.contains(where: { matches($0, keyword: keyword, prefix: false) }) {
                substrings.append(item)
            }
        }
        return prefixes + substrings
    }

    static func searchFields(for preset: PromptPreset) -> [String] {
        var fields = [preset.title]
        if let key = builtinTitleKey(for: preset.id) {
            fields.append(L10n.string(key, language: .english))
            fields.append(L10n.string(key, language: .simplifiedChinese))
        }
        return fields
    }

    static func searchFields(for action: QuickAction) -> [String] {
        var fields = [action.displayName, action.name]
        fields.append(contentsOf: kindAliases(for: action.kind))
        return fields
    }

    static func matches(_ field: String, keyword: String, prefix: Bool) -> Bool {
        guard !field.isEmpty, !keyword.isEmpty else { return false }
        var options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if prefix { options.insert(.anchored) }
        return field.range(of: keyword, options: options, locale: .current) != nil
    }

    private static func builtinTitleKey(for id: UUID) -> String? {
        switch id.uuidString.uppercased() {
        case "EF8CF35C-386A-4389-A137-C207E4DB11FD": "preset.translate.title"
        case "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248": "preset.explain.title"
        case "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2": "preset.summarize.title"
        case "1C85A324-65B3-4EBD-B2C4-0C6B072E284A": "preset.polish.title"
        default: nil
        }
    }

    private static func kindAliases(for kind: QuickActionKind) -> [String] {
        switch kind {
        case .web:
            [
                "web", "网页",
                L10n.string("selection.actionBar.kind.web"),
                L10n.string("externalAsk.kind.web"),
            ]
        case .uriScheme:
            [
                "app", "应用",
                L10n.string("selection.actionBar.kind.uriScheme"),
                L10n.string("externalAsk.kind.uriScheme"),
            ]
        case .terminal:
            [
                "terminal", "终端",
                L10n.string("selection.actionBar.kind.terminal"),
                L10n.string("externalAsk.kind.terminal"),
            ]
        }
    }
}

enum AtCommandPaletteMetrics {
    static let rowHeight: CGFloat = 32
    static let headerHeight: CGFloat = 22
    static let maxVisibleRows = 8
    static let emptyHeight: CGFloat = 56
    static let contentPadding: CGFloat = 6
    static let cornerRadius: CGFloat = 10
    static let inputGap: CGFloat = 6
}

struct AtCommandPaletteView: View {
    let keyword: String
    let presets: [PromptPreset]
    let actions: [QuickAction]
    let highlightedID: UUID?
    let onHover: (UUID?) -> Void
    let onSelectPreset: (PromptPreset) -> Void
    let onSelectAction: (QuickAction) -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool {
        presets.isEmpty && actions.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                emptyState
                    .frame(height: AtCommandPaletteMetrics.emptyHeight)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !presets.isEmpty {
                                sectionHeader(L10n.string("atCommand.prompts"))
                                ForEach(presets) { preset in
                                    presetRow(preset)
                                        .id(preset.id)
                                }
                            }
                            if !presets.isEmpty, !actions.isEmpty {
                                Divider()
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 2)
                            }
                            if !actions.isEmpty {
                                sectionHeader(L10n.string("atCommand.externalAsk"))
                                ForEach(actions) { action in
                                    actionRow(action)
                                        .id(action.id)
                                }
                            }
                        }
                        .padding(.vertical, AtCommandPaletteMetrics.contentPadding)
                    }
                    .frame(height: paletteHeight)
                    .onChange(of: highlightedID) { _, id in
                        guard let id else { return }
                        if reduceMotion {
                            proxy.scrollTo(id, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    .onAppear {
                        if let highlightedID {
                            proxy.scrollTo(highlightedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AtCommandPaletteMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AtCommandPaletteMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("atCommand.accessibilityLabel"))
    }

    private var paletteHeight: CGFloat {
        if isEmpty { return AtCommandPaletteMetrics.emptyHeight }
        let headers = (presets.isEmpty ? 0 : 1) + (actions.isEmpty ? 0 : 1)
        let divider: CGFloat = (!presets.isEmpty && !actions.isEmpty) ? 4 : 0
        let visibleCount = min(presets.count + actions.count, AtCommandPaletteMetrics.maxVisibleRows)
        let rows = CGFloat(visibleCount) * AtCommandPaletteMetrics.rowHeight
        return AtCommandPaletteMetrics.contentPadding * 2
            + CGFloat(headers) * AtCommandPaletteMetrics.headerHeight
            + divider
            + rows
    }

    private var emptyState: some View {
        HStack {
            Text(L10n.string("atCommand.empty", keyword))
                .font(.system(size: 12))
                .foregroundStyle(Brand.muted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(L10n.string("atCommand.emptyEsc"))
                .font(.system(size: 11))
                .foregroundStyle(Brand.muted)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Brand.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AtCommandPaletteMetrics.headerHeight)
            .padding(.horizontal, 12)
            .accessibilityAddTraits(.isHeader)
    }

    private func presetRow(_ preset: PromptPreset) -> some View {
        let isHighlighted = highlightedID == preset.id
        return Button {
            onSelectPreset(preset)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 16, height: 16)
                Text(preset.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.fg)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PresetPlaceholder.text(for: preset.id, title: preset.title))
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: AtCommandPaletteMetrics.rowHeight)
            .background(rowBackground(isHighlighted))
            .overlay {
                if isHighlighted, colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.accent, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            onHover(hovering ? preset.id : nil)
        }
        .accessibilityLabel("\(preset.title), \(PresetPlaceholder.text(for: preset.id, title: preset.title))")
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private func actionRow(_ action: QuickAction) -> some View {
        let isHighlighted = highlightedID == action.id
        let kindLabel = localizedKind(action.kind)
        return Button {
            onSelectAction(action)
        } label: {
            HStack(spacing: 8) {
                ProviderBrandIconView(
                    slug: action.brandIconSlug,
                    size: 16,
                    fallbackSymbol: action.kind.fallbackSymbolName,
                    fallbackColor: Brand.muted
                )
                Text(action.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.fg)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(kindLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Brand.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .padding(.horizontal, 8)
            .frame(height: AtCommandPaletteMetrics.rowHeight)
            .background(rowBackground(isHighlighted))
            .overlay {
                if isHighlighted, colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.accent, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            onHover(hovering ? action.id : nil)
        }
        .accessibilityLabel("\(action.displayName), \(kindLabel)")
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func rowBackground(_ isHighlighted: Bool) -> some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Brand.surface)
        }
    }

    private func localizedKind(_ kind: QuickActionKind) -> String {
        switch kind {
        case .web: L10n.string("selection.actionBar.kind.web")
        case .uriScheme: L10n.string("selection.actionBar.kind.uriScheme")
        case .terminal: L10n.string("selection.actionBar.kind.terminal")
        }
    }
}
