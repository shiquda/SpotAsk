import AppKit
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

@MainActor
struct AtCommandSelectionTests {
    final class FakeActionExecutor: QuickActionExecuting, @unchecked Sendable {
        var shouldSucceed = true
        var performedActions: [ResolvedQuickAction] = []

        func perform(_ resolved: ResolvedQuickAction) -> Bool {
            guard shouldSucceed else { return false }
            performedActions.append(resolved)
            return true
        }
    }

    private final class RejectingTextView: NSTextView {
        override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
            false
        }
    }

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        textView.string = text
        textView.allowsUndo = true
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func hostedTextView(_ text: String) -> (NSWindow, NSTextView) {
        let textView = makeTextView(text)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        return (window, textView)
    }

    private func makeAction(_ name: String = "ChatGPT") -> QuickAction {
        QuickAction(name: name, urlTemplate: "https://example.com/?q={query}")
    }

    private func resolve(_ action: QuickAction) -> (UUID) -> QuickAction? {
        { id in id == action.id ? action : nil }
    }

    @Test("Successful token delete is undone with Cmd+Z")
    func deleteActiveTokenIsUndoable() {
        let (window, textView) = hostedTextView("ask @gpt")
        _ = window
        let state = AtCommandDetector.state(
            in: textView.string,
            selectedRange: textView.selectedRange()
        )
        #expect(state?.keyword == "gpt")
        #expect(AtCommandDetector.deleteActiveToken(state!, in: textView))
        #expect(textView.string == "ask ")
        #expect(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()
        #expect(textView.string == "ask @gpt")
    }

    @Test("Rejected shouldChangeText leaves the token and skips dispatch")
    func rejectedEditDoesNotDispatch() {
        let textView = RejectingTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        textView.string = "ask @gpt extra"
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        let state = AtCommandDetector.state(
            in: textView.string,
            selectedRange: textView.selectedRange()
        )
        let action = makeAction()
        let executor = FakeActionExecutor()
        let outcome = AtCommandSelection.selectAction(
            action,
            state: state,
            textView: textView,
            resolve: resolve(action),
            executor: executor
        )
        #expect(outcome == .rejected)
        #expect(textView.string == "ask @gpt extra")
        #expect(executor.performedActions.isEmpty)
        #expect(AtCommandSelection.selectPreset(state: state, textView: textView) == .rejected)
    }

    @Test("Stale token range that is no longer @keyword does not delete or launch")
    func staleTokenDoesNotDispatch() {
        let textView = makeTextView("hello world")
        let stale = AtCommandState(
            atLocation: 6,
            keyword: "gpt",
            replacementRange: NSRange(location: 6, length: 5)
        )
        let action = makeAction()
        let executor = FakeActionExecutor()
        #expect(!AtCommandDetector.deleteActiveToken(stale, in: textView))
        #expect(textView.string == "hello world")
        let outcome = AtCommandSelection.selectAction(
            action,
            state: stale,
            textView: textView,
            resolve: resolve(action),
            executor: executor
        )
        #expect(outcome == .rejected)
        #expect(textView.string == "hello world")
        #expect(executor.performedActions.isEmpty)
        #expect(AtCommandSelection.selectPreset(state: stale, textView: textView) == .rejected)
        #expect(AtCommandSelection.selectPreset(state: stale, textView: nil) == .rejected)
    }

    @Test("Nonempty External Ask launch failure keeps the draft and retries on Return")
    func launchFailureKeepsDraftAndRetries() {
        let textView = makeTextView("ask @gpt")
        let state = AtCommandDetector.state(
            in: textView.string,
            selectedRange: textView.selectedRange()
        )
        let action = makeAction()
        let executor = FakeActionExecutor()
        executor.shouldSucceed = false
        let failed = AtCommandSelection.selectAction(
            action,
            state: state,
            textView: textView,
            resolve: resolve(action),
            executor: executor
        )
        #expect(failed == .launchFailed(action))
        #expect(textView.string == "ask ")
        #expect(executor.performedActions.isEmpty)

        executor.shouldSucceed = true
        let retried = AtCommandSelection.confirmPending(
            action,
            query: textView.string,
            resolve: resolve(action),
            executor: executor
        )
        #expect(retried == .launched)
        #expect(executor.performedActions.count == 1)
    }

    @Test("Empty External Ask pending survives a failed Return and retries")
    func pendingReturnFailureStaysRetryable() {
        let textView = makeTextView("@gpt")
        let state = AtCommandDetector.state(
            in: textView.string,
            selectedRange: textView.selectedRange()
        )
        let action = makeAction()
        let executor = FakeActionExecutor()
        let pending = AtCommandSelection.selectAction(
            action,
            state: state,
            textView: textView,
            resolve: resolve(action),
            executor: executor
        )
        #expect(pending == .becamePending(action))
        #expect(textView.string.isEmpty)
        #expect(executor.performedActions.isEmpty)

        executor.shouldSucceed = false
        let failed = AtCommandSelection.confirmPending(
            action,
            query: "retry me",
            resolve: resolve(action),
            executor: executor
        )
        #expect(failed == .launchFailed(action))
        #expect(executor.performedActions.isEmpty)

        let ignoredEmpty = AtCommandSelection.confirmPending(
            action,
            query: "   ",
            resolve: resolve(action),
            executor: executor
        )
        #expect(ignoredEmpty == .rejected)

        executor.shouldSucceed = true
        let retried = AtCommandSelection.confirmPending(
            action,
            query: "retry me",
            resolve: resolve(action),
            executor: executor
        )
        #expect(retried == .launched)
        #expect(executor.performedActions.count == 1)
    }

    @Test("Return submit keeps editor and model draft when pending launch fails")
    func submitPathKeepsDraftOnLaunchFailure() {
        let textView = makeTextView("retry me")
        var modelDraft = "retry me"
        let action = makeAction()
        let executor = FakeActionExecutor()
        executor.shouldSucceed = false

        let onSubmit = { () -> Bool in
            let outcome = AtCommandSelection.confirmPending(
                action,
                query: modelDraft,
                resolve: resolve(action),
                executor: executor
            )
            guard outcome == .launched else { return false }
            modelDraft = ""
            return true
        }

        #expect(!ChatInputSubmission.submit(textView, onSubmit: onSubmit))
        #expect(textView.string == "retry me")
        #expect(modelDraft == "retry me")
        #expect(executor.performedActions.isEmpty)

        executor.shouldSucceed = true
        #expect(ChatInputSubmission.submit(textView, onSubmit: onSubmit))
        #expect(textView.string.isEmpty)
        #expect(modelDraft.isEmpty)
        #expect(executor.performedActions.count == 1)
    }

    @Test("Return submit keeps editor when pending query is empty")
    func submitPathKeepsDraftOnEmptyPendingQuery() {
        let textView = makeTextView("   ")
        var modelDraft = "   "
        let action = makeAction()
        let executor = FakeActionExecutor()

        let onSubmit = { () -> Bool in
            let outcome = AtCommandSelection.confirmPending(
                action,
                query: modelDraft,
                resolve: resolve(action),
                executor: executor
            )
            guard outcome == .launched else { return false }
            modelDraft = ""
            return true
        }

        #expect(!ChatInputSubmission.submit(textView, onSubmit: onSubmit))
        #expect(textView.string == "   ")
        #expect(modelDraft == "   ")
        #expect(executor.performedActions.isEmpty)
    }
}
