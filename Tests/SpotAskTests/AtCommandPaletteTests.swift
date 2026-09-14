import Foundation
import Testing
@testable import SpotAsk

struct AtCommandPaletteTests {
    private func caret(_ text: String) -> NSRange {
        NSRange(location: (text as NSString).length, length: 0)
    }

    @Test("Bare @ after start, newline, or whitespace activates")
    func triggerActivatesOnBareAt() {
        for text in ["@", "hello @", "hello\n@"] {
            let state = AtCommandDetector.state(in: text, selectedRange: caret(text))
            #expect(state?.keyword == "")
            #expect(state?.atLocation == (text as NSString).length - 1)
        }
    }

    @Test("Keyword after @ is captured until the caret")
    func triggerCapturesKeyword() {
        let text = "ask @Chat"
        let state = AtCommandDetector.state(in: text, selectedRange: caret(text))
        #expect(state?.keyword == "Chat")
        #expect(state?.replacementRange == NSRange(location: 4, length: 5))
    }

    @Test("In-word, URL, escaped, and fullwidth @ do not activate")
    func triggerIgnoresNonCommandAts() {
        #expect(AtCommandDetector.state(in: "email@x", selectedRange: caret("email@x")) == nil)
        #expect(AtCommandDetector.state(in: "https://x.com/@me", selectedRange: caret("https://x.com/@me")) == nil)
        #expect(AtCommandDetector.state(in: "\\@", selectedRange: caret("\\@")) == nil)
        #expect(AtCommandDetector.state(in: "＠", selectedRange: caret("＠")) == nil)
        #expect(AtCommandDetector.state(in: "＠foo", selectedRange: caret("＠foo")) == nil)
    }

    @Test("Whitespace in the keyword or a non-collapsed caret dismisses")
    func triggerRequiresCollapsedCaretAndNoSpaces() {
        let spaced = "hello @foo bar"
        #expect(AtCommandDetector.state(in: spaced, selectedRange: caret(spaced)) == nil)

        let text = "hello @foo"
        #expect(AtCommandDetector.state(in: text, selectedRange: NSRange(location: 8, length: 2)) == nil)
        #expect(AtCommandDetector.state(in: text, selectedRange: NSRange(location: 4, length: 0)) == nil)
        #expect(AtCommandDetector.state(in: text, selectedRange: NSRange(location: 9, length: 0))?.keyword == "fo")
    }

    @Test("Empty keyword keeps catalog order; prefix ranks above substring")
    func matcherRanksPrefixThenSubstring() {
        let translate = PromptPreset(title: "Translate", instruction: "t")
        let summarize = PromptPreset(title: "Summarize", instruction: "s")
        let notes = PromptPreset(title: "Remote notes", instruction: "n")
        let presets = [translate, summarize, notes]

        #expect(
            AtCommandMatcher.ranked(presets, keyword: "") { AtCommandMatcher.searchFields(for: $0) }.map(\.title)
                == ["Translate", "Summarize", "Remote notes"]
        )
        #expect(
            AtCommandMatcher.ranked(presets, keyword: "tra") { AtCommandMatcher.searchFields(for: $0) }.map(\.title)
                == ["Translate"]
        )
        #expect(
            AtCommandMatcher.ranked(presets, keyword: "note") { AtCommandMatcher.searchFields(for: $0) }.map(\.title)
                == ["Remote notes"]
        )
        #expect(
            AtCommandMatcher.ranked(presets, keyword: "ote") { AtCommandMatcher.searchFields(for: $0) }.map(\.title)
                == ["Remote notes"]
        )

        let noteTaker = PromptPreset(title: "Note taker", instruction: "nt")
        #expect(
            AtCommandMatcher.ranked([notes, noteTaker], keyword: "note") { AtCommandMatcher.searchFields(for: $0) }.map(\.title)
                == ["Note taker", "Remote notes"]
        )
    }

    @Test("Builtin preset titles match English and Simplified Chinese aliases")
    func matcherUsesBilingualBuiltinTitles() {
        let translate = PromptPreset.builtIn.first { $0.id.uuidString.uppercased() == "EF8CF35C-386A-4389-A137-C207E4DB11FD" }!
        let ranked = AtCommandMatcher.ranked([translate], keyword: "翻译") { AtCommandMatcher.searchFields(for: $0) }
        #expect(ranked.count == 1)
        #expect(ranked.first?.id == translate.id)
    }

    @Test("External Ask kind aliases match web/app/terminal keywords")
    func matcherUsesKindAliases() {
        let web = QuickAction(name: "ChatGPT", kind: .web(urlTemplate: "https://example.com?q={query}"))
        let app = QuickAction(name: "Notes", kind: .uriScheme(urlTemplate: "notes://{query}"))
        let terminal = QuickAction(name: "omp", kind: .terminal(commandTemplate: "omp {query}"))

        #expect(AtCommandMatcher.ranked([web, app, terminal], keyword: "web") { AtCommandMatcher.searchFields(for: $0) }.map(\.name) == ["ChatGPT"])
        #expect(AtCommandMatcher.ranked([web, app, terminal], keyword: "应用") { AtCommandMatcher.searchFields(for: $0) }.map(\.name) == ["Notes"])
        #expect(AtCommandMatcher.ranked([web, app, terminal], keyword: "terminal") { AtCommandMatcher.searchFields(for: $0) }.map(\.name) == ["omp"])
    }
}

@MainActor
struct AtCommandLaunchTests {
    final class FakeActionExecutor: QuickActionExecuting, @unchecked Sendable {
        var shouldSucceed = true
        var performedActions: [ResolvedQuickAction] = []

        func perform(_ resolved: ResolvedQuickAction) -> Bool {
            guard shouldSucceed else { return false }
            performedActions.append(resolved)
            return true
        }
    }

    @Test("Shared launch resolves a nonempty query and calls the same executor")
    func launchPerformsResolvedAction() {
        let executor = FakeActionExecutor()
        let action = QuickAction(name: "ChatGPT", urlTemplate: "https://example.com/?q={query}")
        #expect(QuickActionLaunch.perform(action, query: "hello world", executor: executor))
        #expect(executor.performedActions.count == 1)
        guard case let .url(url) = executor.performedActions[0] else {
            Issue.record("expected URL launch")
            return
        }
        #expect(url.absoluteString.contains("hello"))
    }

    @Test("Empty query does not launch")
    func launchRejectsEmptyQuery() {
        let executor = FakeActionExecutor()
        let action = QuickAction(name: "ChatGPT", urlTemplate: "https://example.com/?q={query}")
        #expect(!QuickActionLaunch.perform(action, query: "   ", executor: executor))
        #expect(executor.performedActions.isEmpty)
    }

    @Test("Executor failure is returned without recording success")
    func launchReportsExecutorFailure() {
        let executor = FakeActionExecutor()
        executor.shouldSucceed = false
        let action = QuickAction(name: "ChatGPT", urlTemplate: "https://example.com/?q={query}")
        #expect(!QuickActionLaunch.perform(action, query: "hello", executor: executor))
        #expect(executor.performedActions.isEmpty)
    }
}
