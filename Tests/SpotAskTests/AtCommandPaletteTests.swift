import AppKit
import Foundation
import Testing
@testable import SpotAsk

@MainActor
struct AtCommandParserTests {

    @Test("Empty text returns nil")
    func emptyTextReturnsNil() {
        let query = AtCommandParser.parse(
            text: "",
            selectedRange: NSRange(location: 0, length: 0),
            hasMarkedText: false
        )
        #expect(query == nil)
    }

    @Test("Selection with length > 0 suppresses trigger")
    func selectionSuppressesTrigger() {
        let query = AtCommandParser.parse(
            text: "@hello",
            selectedRange: NSRange(location: 0, length: 3),
            hasMarkedText: false
        )
        #expect(query == nil)
    }

    @Test("Active IME marked text suppresses trigger")
    func markedTextSuppressesTrigger() {
        let query = AtCommandParser.parse(
            text: "@",
            selectedRange: NSRange(location: 1, length: 0),
            hasMarkedText: true
        )
        #expect(query == nil)
    }

    @Test("Single @ at start of input produces empty keyword query")
    func singleAtSymbolStartsTrigger() {
        let query = AtCommandParser.parse(
            text: "@",
            selectedRange: NSRange(location: 1, length: 0),
            hasMarkedText: false
        )
        #expect(query != nil)
        #expect(query?.triggerLocation == 0)
        #expect(query?.keyword == "")
        #expect(query?.range == NSRange(location: 0, length: 1))
    }

    @Test("@ with keyword at start of input captures keyword")
    func atWithKeywordAtStart() {
        let text = "@trans"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 6, length: 0),
            hasMarkedText: false
        )
        #expect(query != nil)
        #expect(query?.triggerLocation == 0)
        #expect(query?.keyword == "trans")
        #expect(query?.range == NSRange(location: 0, length: 6))
    }

    @Test("@ preceded by space triggers query")
    func atPrecededBySpace() {
        let text = "Hello @summary"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(query != nil)
        #expect(query?.triggerLocation == 6)
        #expect(query?.keyword == "summary")
        #expect(query?.range == NSRange(location: 6, length: 8))
    }

    @Test("@ preceded by newline or tab triggers query")
    func atPrecededByNewlineOrTab() {
        let textWithNewline = "Line 1\n@polish"
        let queryNewline = AtCommandParser.parse(
            text: textWithNewline,
            selectedRange: NSRange(location: (textWithNewline as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(queryNewline != nil)
        #expect(queryNewline?.triggerLocation == 7)
        #expect(queryNewline?.keyword == "polish")

        let textWithTab = "Col1\t@ask"
        let queryTab = AtCommandParser.parse(
            text: textWithTab,
            selectedRange: NSRange(location: (textWithTab as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(queryTab != nil)
        #expect(queryTab?.triggerLocation == 5)
        #expect(queryTab?.keyword == "ask")
    }

    @Test("@ inside a word or email address does not trigger")
    func atMidWordDoesNotTrigger() {
        let email = "user@example.com"
        let query1 = AtCommandParser.parse(
            text: email,
            selectedRange: NSRange(location: 5, length: 0),
            hasMarkedText: false
        )
        #expect(query1 == nil)

        let query2 = AtCommandParser.parse(
            text: email,
            selectedRange: NSRange(location: (email as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(query2 == nil)

        let chineseMidWord = "文字@提问"
        let query3 = AtCommandParser.parse(
            text: chineseMidWord,
            selectedRange: NSRange(location: (chineseMidWord as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(query3 == nil)
    }

    @Test("Escaped backslash @ does not trigger")
    func escapedAtDoesNotTrigger() {
        let text = "\\@"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 2, length: 0),
            hasMarkedText: false
        )
        #expect(query == nil)
    }

    @Test("Full-width ＠ symbol does not trigger")
    func fullWidthAtDoesNotTrigger() {
        let text = "＠"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 1, length: 0),
            hasMarkedText: false
        )
        #expect(query == nil)
    }

    @Test("Chinese and special keyword characters are supported")
    func chineseAndSpecialKeywordCharacters() {
        let text = "@翻译_v1-测试"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(query != nil)
        #expect(query?.triggerLocation == 0)
        #expect(query?.keyword == "翻译_v1-测试")
    }

    @Test("Space or punctuation in keyword terminates trigger")
    func spaceOrPunctuationTerminatesTrigger() {
        let textWithSpace = "@trans this"
        let querySpace = AtCommandParser.parse(
            text: textWithSpace,
            selectedRange: NSRange(location: (textWithSpace as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(querySpace == nil)

        let textWithDot = "@trans.action"
        let queryDot = AtCommandParser.parse(
            text: textWithDot,
            selectedRange: NSRange(location: (textWithDot as NSString).length, length: 0),
            hasMarkedText: false
        )
        #expect(queryDot == nil)
    }
}

@MainActor
struct AtCommandFilterTests {

    private func makeSamplePresets() -> [PromptPreset] {
        [
            PromptPreset(id: UUID(), title: "翻译", instruction: "将文本翻译成目标语言", customSymbolName: "globe"),
            PromptPreset(id: UUID(), title: "解释", instruction: "详细解释概念或代码", customSymbolName: "book"),
            PromptPreset(id: UUID(), title: "总结", instruction: "提炼核心要点", customSymbolName: "doc.plaintext"),
            PromptPreset(id: UUID(), title: "Translate", instruction: "Translate text into English", customSymbolName: "globe")
        ]
    }

    private func makeSampleQuickActions() -> [QuickAction] {
        [
            QuickAction(id: UUID(), name: "问 ChatGPT", kind: .web(urlTemplate: "https://chatgpt.com/?q={query}"), symbolName: "sparkles"),
            QuickAction(id: UUID(), name: "问 Grok", kind: .web(urlTemplate: "https://grok.com/?q={query}"), symbolName: "bolt"),
            QuickAction(id: UUID(), name: "终端查询", kind: .terminal(commandTemplate: "curl {query}"), symbolName: "terminal")
        ]
    }

    @Test("Empty keyword returns all items in preset-first order")
    func emptyKeywordReturnsAll() {
        let presets = AtCommandItem.makePresets(from: makeSamplePresets(), selectedPresetID: nil)
        let actions = AtCommandItem.makeQuickActions(from: makeSampleQuickActions())
        let all = presets + actions

        let filtered = AtCommandFilter.filter(items: all, keyword: "")
        #expect(filtered.count == all.count)
        #expect(filtered.first?.title == "翻译")
    }

    @Test("Prefix matching ranks before substring matching")
    func prefixMatchingRanksFirst() {
        let items = [
            AtCommandItem(id: "1", kind: .promptPreset(makeSamplePresets()[0]), title: "快速翻译", subtitle: nil, iconName: "star", brandIconSlug: nil, kindBadge: nil, isSelectedPreset: false),
            AtCommandItem(id: "2", kind: .promptPreset(makeSamplePresets()[0]), title: "翻译助手", subtitle: nil, iconName: "globe", brandIconSlug: nil, kindBadge: nil, isSelectedPreset: false)
        ]
        let filtered = AtCommandFilter.filter(items: items, keyword: "翻译")
        #expect(filtered.count == 2)
        #expect(filtered[0].title == "翻译助手") // Prefix match
        #expect(filtered[1].title == "快速翻译") // Substring match
    }

    @Test("Case-insensitive filtering matches title and subtitle")
    func caseInsensitiveMatch() {
        let presets = AtCommandItem.makePresets(from: makeSamplePresets(), selectedPresetID: nil)
        let filtered = AtCommandFilter.filter(items: presets, keyword: "trans")
        #expect(filtered.contains { $0.title == "Translate" })
    }

    @Test("Unmatched keyword returns empty results")
    func unmatchedKeywordReturnsEmpty() {
        let presets = AtCommandItem.makePresets(from: makeSamplePresets(), selectedPresetID: nil)
        let filtered = AtCommandFilter.filter(items: presets, keyword: "nonexistentkeyword123")
        #expect(filtered.isEmpty)
    }
}

@MainActor
struct AtCommandStateTests {

    @Test("Initial state is idle and unpresented")
    func initialState() {
        let state = AtCommandState()
        #expect(!state.isPresented)
        #expect(state.query == nil)
        #expect(state.currentSelectedItem == nil)
        #expect(state.filteredItems.isEmpty)
    }

    @Test("Updating with valid query presents palette and populates candidates")
    func updateWithValidQuery() {
        let state = AtCommandState()
        let presets = [
            PromptPreset(id: UUID(), title: "翻译", instruction: "翻译", customSymbolName: "globe")
        ]
        let query = AtCommandQuery(triggerLocation: 0, keyword: "")

        state.update(
            query: query,
            presets: presets,
            selectedPresetID: nil,
            quickActions: [],
            anchorPoint: CGPoint(x: 20, y: 10)
        )

        #expect(state.isPresented)
        #expect(state.query == query)
        #expect(state.filteredItems.count == 1)
        #expect(state.highlightedIndex == 0)
        #expect(state.currentSelectedItem?.title == "翻译")
    }

    @Test("selectNext and selectPrevious cycle candidates with wrap-around")
    func cycleCandidates() {
        let state = AtCommandState()
        let presets = [
            PromptPreset(id: UUID(), title: "Item 1", instruction: "", customSymbolName: "1.circle"),
            PromptPreset(id: UUID(), title: "Item 2", instruction: "", customSymbolName: "2.circle"),
            PromptPreset(id: UUID(), title: "Item 3", instruction: "", customSymbolName: "3.circle")
        ]
        state.update(
            query: AtCommandQuery(triggerLocation: 0, keyword: ""),
            presets: presets,
            selectedPresetID: nil,
            quickActions: [],
            anchorPoint: .zero
        )

        #expect(state.highlightedIndex == 0)
        state.selectNext()
        #expect(state.highlightedIndex == 1)
        state.selectNext()
        #expect(state.highlightedIndex == 2)
        state.selectNext() // Wrap around to 0
        #expect(state.highlightedIndex == 0)

        state.selectPrevious() // Wrap backward to 2
        #expect(state.highlightedIndex == 2)
        state.selectPrevious()
        #expect(state.highlightedIndex == 1)
    }

    @Test("Dismiss resets presentation and items")
    func dismissResetsState() {
        let state = AtCommandState()
        let presets = [PromptPreset(id: UUID(), title: "Item", instruction: "", customSymbolName: "star")]
        state.update(
            query: AtCommandQuery(triggerLocation: 0, keyword: ""),
            presets: presets,
            selectedPresetID: nil,
            quickActions: [],
            anchorPoint: .zero
        )
        #expect(state.isPresented)

        state.dismiss()
        #expect(!state.isPresented)
        #expect(state.query == nil)
        #expect(state.filteredItems.isEmpty)
        #expect(state.currentSelectedItem == nil)
    }
}

@MainActor
struct AtCommandActionExecutionTests {

    private final class UndoableTextView: NSTextView {
        let ownedUndoManager = UndoManager()
        override var undoManager: UndoManager? { ownedUndoManager }
    }

    private func makePresetItem(_ preset: PromptPreset) -> AtCommandItem {
        AtCommandItem.makePresets(from: [preset], selectedPresetID: nil)[0]
    }

    private func makeActionItem(_ action: QuickAction) -> AtCommandItem {
        AtCommandItem.makeQuickActions(from: [action])[0]
    }

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = UndoableTextView()
        textView.allowsUndo = true
        textView.string = text
        return textView
    }

    @Test("Preset selection plan requires matching @query and enabled preset")
    func presetPlanRequiresMatchAndEnabledPreset() {
        let preset = PromptPreset(id: UUID(), title: "翻译", instruction: "翻译", customSymbolName: "globe")
        let item = makePresetItem(preset)
        let text = "Hello @trans please"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 12, length: 0),
            hasMarkedText: false
        )!

        let accepted = AtCommandSelection.plan(
            text: text,
            query: query,
            item: item,
            allowsReplacement: true,
            isPresetEnabled: { $0.id == preset.id },
            canExecuteQuickAction: { _, _ in false }
        )
        #expect(accepted == .applyPreset(preset))

        let rejectedEdit = AtCommandSelection.plan(
            text: text,
            query: query,
            item: item,
            allowsReplacement: false,
            isPresetEnabled: { $0.id == preset.id },
            canExecuteQuickAction: { _, _ in false }
        )
        #expect(rejectedEdit == .reject)

        let staleQuery = AtCommandQuery(triggerLocation: 0, keyword: "gone")
        let rejectedStale = AtCommandSelection.plan(
            text: text,
            query: staleQuery,
            item: item,
            allowsReplacement: true,
            isPresetEnabled: { $0.id == preset.id },
            canExecuteQuickAction: { _, _ in false }
        )
        #expect(rejectedStale == .reject)

        let rejectedDisabled = AtCommandSelection.plan(
            text: text,
            query: query,
            item: item,
            allowsReplacement: true,
            isPresetEnabled: { _ in false },
            canExecuteQuickAction: { _, _ in false }
        )
        #expect(rejectedDisabled == .reject)
    }

    @Test("External ask plan uses remaining text and keeps input when not executable")
    func externalAskPlanKeepsInputWhenNotExecutable() {
        let action = QuickAction.builtIn[0]
        let item = makeActionItem(action)
        let text = "@chatgpt explain this code"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 8, length: 0),
            hasMarkedText: false
        )!
        let remaining = AtCommandQueryMatcher.remainingText(afterRemoving: query, from: text)
        #expect(remaining == " explain this code")

        var capturedRemaining: String?
        let accepted = AtCommandSelection.plan(
            text: text,
            query: query,
            item: item,
            allowsReplacement: true,
            isPresetEnabled: { _ in false },
            canExecuteQuickAction: { _, remainingQuery in
                capturedRemaining = remainingQuery
                return true
            }
        )
        #expect(accepted == .triggerQuickAction(action))
        #expect(capturedRemaining == " explain this code")

        let rejected = AtCommandSelection.plan(
            text: text,
            query: query,
            item: item,
            allowsReplacement: true,
            isPresetEnabled: { _ in false },
            canExecuteQuickAction: { _, _ in false }
        )
        #expect(rejected == .reject)
    }

    @Test("Composer edit respects shouldChangeText and restores @query on undo")
    func composerEditRespectsPermissionAndUndo() {
        let text = "Hello @trans please"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 12, length: 0),
            hasMarkedText: false
        )!
        let textView = makeTextView(text)

        #expect(AtCommandComposerEdit.removeQuery(from: textView, query: query))
        #expect(textView.string == "Hello  please")
        #expect(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()
        #expect(textView.string == text)

        final class RejectingTextView: NSTextView {
            override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
                false
            }
        }
        let rejecting = RejectingTextView()
        rejecting.allowsUndo = true
        rejecting.string = text
        #expect(!AtCommandComposerEdit.removeQuery(from: rejecting, query: query))
        #expect(rejecting.string == text)
    }

    @Test("Quick actions are omitted when session is busy or remaining query is empty")
    func executableActionsMatchTriggerGuards() {
        let action = QuickAction.builtIn[0]
        #expect(
            AtCommandQuickActionAvailability.isExecutable(
                action: action,
                sessionEmpty: true,
                isGenerating: false,
                remainingQuery: "explain this"
            )
        )
        #expect(
            !AtCommandQuickActionAvailability.isExecutable(
                action: action,
                sessionEmpty: false,
                isGenerating: false,
                remainingQuery: "explain this"
            )
        )
        #expect(
            !AtCommandQuickActionAvailability.isExecutable(
                action: action,
                sessionEmpty: true,
                isGenerating: true,
                remainingQuery: "explain this"
            )
        )
        #expect(
            !AtCommandQuickActionAvailability.isExecutable(
                action: action,
                sessionEmpty: true,
                isGenerating: false,
                remainingQuery: "   "
            )
        )

        let state = AtCommandState()
        state.update(
            query: AtCommandQuery(triggerLocation: 0, keyword: ""),
            presets: [],
            selectedPresetID: nil,
            quickActions: AtCommandQuickActionAvailability.executableActions(
                from: [action],
                sessionEmpty: false,
                isGenerating: false,
                remainingQuery: "hello"
            ),
            anchorPoint: .zero
        )
        #expect(state.filteredQuickActions.isEmpty)
        #expect(state.currentSelectedItem == nil)
    }

    @Test("Enter with an open empty palette is consumed and does not send")
    func emptyPaletteEnterIsConsumed() {
        #expect(
            AtCommandKeyPolicy.outcome(
                keyCode: 36,
                modifierFlags: [],
                isPresented: true,
                hasHighlightedItem: false
            ) == .consumeWithoutConfirm
        )
        #expect(
            AtCommandKeyPolicy.outcome(
                keyCode: 48,
                modifierFlags: [],
                isPresented: true,
                hasHighlightedItem: false
            ) == .consumeWithoutConfirm
        )
        #expect(
            AtCommandKeyPolicy.outcome(
                keyCode: 36,
                modifierFlags: [],
                isPresented: true,
                hasHighlightedItem: true
            ) == .confirm
        )
        #expect(
            AtCommandKeyPolicy.outcome(
                keyCode: 36,
                modifierFlags: [],
                isPresented: false,
                hasHighlightedItem: false
            ) == .ignore
        )
    }

    @Test("Failed trigger after a committed edit restores @query via undo")
    func failedTriggerRestoresQueryViaUndo() {
        let action = QuickAction.builtIn[0]
        let text = "@chatgpt explain this code"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 8, length: 0),
            hasMarkedText: false
        )!
        let textView = makeTextView(text)
        var input = text
        var triggerSucceeded = false

        let plan = AtCommandSelection.plan(
            text: textView.string,
            query: query,
            item: makeActionItem(action),
            allowsReplacement: true,
            isPresetEnabled: { _ in false },
            canExecuteQuickAction: { _, remaining in
                AtCommandQuickActionAvailability.isExecutable(
                    action: action,
                    sessionEmpty: true,
                    isGenerating: false,
                    remainingQuery: remaining
                )
            }
        )
        #expect(plan == .triggerQuickAction(action))
        #expect(AtCommandComposerEdit.removeQuery(from: textView, query: query))
        input = textView.string
        #expect(input == " explain this code")

        if !triggerSucceeded, textView.undoManager?.canUndo == true {
            textView.undoManager?.undo()
            input = textView.string
        }
        #expect(input == text)
        #expect(textView.string == text)
    }
}

@MainActor
struct AtCommandEscapePolicyTests {

    @Test("Escape dismisses @ command palette before other actions")
    func escapePrioritizesAtCommandPalette() {
        let action = chatEscapeAction(
            hasMarkedText: false,
            isAtCommandPalettePresented: true,
            isPresetPopoverPresented: true,
            isModelPickerPresented: true,
            isGenerating: true,
            startsNewConversation: true,
            hasMessages: true
        )
        #expect(action == .dismissAtCommandPalette)
    }

    @Test("Marked text takes precedence over @ command palette on escape")
    func markedTextPrecedesAtCommandPalette() {
        let action = chatEscapeAction(
            hasMarkedText: true,
            isAtCommandPalettePresented: true,
            isPresetPopoverPresented: false,
            isModelPickerPresented: false,
            isGenerating: false,
            startsNewConversation: false,
            hasMessages: false
        )
        #expect(action == .preserveMarkedText)
    }
}
