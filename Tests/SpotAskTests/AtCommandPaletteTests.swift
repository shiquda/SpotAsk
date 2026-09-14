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

    @Test("Selecting a prompt preset removes @query from input and activates the preset")
    func promptPresetSelectionUpdatesState() {
        let defaults = UserDefaults(suiteName: "AtCommandActionTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let settings = AppSettings(defaults: defaults)
        let preset = PromptPreset.builtIn[0] // Translate

        // Simulate text replacement as done in handleAtCommandSelection
        var text = "Hello @trans please"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 12, length: 0),
            hasMarkedText: false
        )!
        #expect(query.keyword == "trans")

        let nsText = text as NSString
        let range = query.range
        text = nsText.replacingCharacters(in: range, with: "")
        #expect(text == "Hello  please")

        // Verify preset lookup
        let enabled = settings.promptPresetAllowedForUse(preset)
        #expect(enabled?.id == preset.id)
    }

    @Test("Selecting an external ask removes @query and passes remaining input to trigger")
    func externalAskSelectionPassesRemainingInput() {
        let action = QuickAction.builtIn[0] // ChatGPT
        var text = "@chatgpt explain this code"
        let query = AtCommandParser.parse(
            text: text,
            selectedRange: NSRange(location: 8, length: 0),
            hasMarkedText: false
        )!
        #expect(query.keyword == "chatgpt")

        let nsText = text as NSString
        let range = query.range
        text = nsText.replacingCharacters(in: range, with: "")
        #expect(text == " explain this code")

        // Resolving template with remaining input
        let resolved = ResolvedQuickAction.resolve(action, query: text)
        #expect(resolved != nil)
        if case let .url(url) = resolved {
            #expect(url.absoluteString.contains("chatgpt.com"))
            #expect(url.absoluteString.contains("explain%20this%20code"))
        } else {
            Issue.record("Expected web URL execution")
        }
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
