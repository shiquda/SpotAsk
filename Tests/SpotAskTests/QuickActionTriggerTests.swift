import Foundation
import Testing
@testable import SpotAsk

@MainActor
struct QuickActionTriggerTests {

    final class FakeActionExecutor: QuickActionExecuting, @unchecked Sendable {
        var shouldSucceed: Bool = true
        var performedActions: [ResolvedQuickAction] = []

        func perform(_ resolved: ResolvedQuickAction) -> Bool {
            if shouldSucceed {
                performedActions.append(resolved)
                return true
            }
            return false
        }
    }

    private func makeTrigger(
        isSessionEmpty: @escaping () -> Bool = { true },
        isGenerating: @escaping () -> Bool = { false },
        input: @escaping () -> String = { "test query" },
        resolveAction: @escaping (UUID) -> QuickAction? = { id in
            QuickAction.builtIn.first(where: { $0.id == id && $0.isEnabled })
        },
        onClose: @escaping () -> Void = {},
        executor: FakeActionExecutor = FakeActionExecutor()
    ) -> (QuickActionTrigger, FakeActionExecutor) {
        let trigger = QuickActionTrigger(
            isSessionEmpty: isSessionEmpty,
            isGenerating: isGenerating,
            currentInput: input,
            resolveAction: resolveAction,
            closePanel: onClose,
            executor: executor
        )
        return (trigger, executor)
    }

    // MARK: - Input State & Guard Tests

    @Test("Empty or whitespace-only input returns false and does not open executor or close panel")
    func emptyInputDoesNothing() {
        var inputState = ""
        var closedCount = 0
        let (trigger, executor) = makeTrigger(
            input: { inputState },
            onClose: { closedCount += 1 }
        )

        let resultEmpty = trigger.trigger(actionID: QuickAction.BuiltInID.chatGPT)
        #expect(resultEmpty == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)

        inputState = "    \n\t  "
        let resultWhitespace = trigger.trigger(actionID: QuickAction.BuiltInID.chatGPT)
        #expect(resultWhitespace == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)
    }

    @Test("Disabled or nonexistent action ID returns false and does not close panel")
    func invalidOrDisabledActionIDReturnsFalse() {
        var closedCount = 0
        let invalidActionID = UUID()
        let invalidAction = QuickAction(
            id: invalidActionID,
            name: "Invalid",
            kind: .web(urlTemplate: "not a valid url {query}"),
            symbolName: "globe",
            isBuiltIn: false,
            isEnabled: false
        )

        let (trigger, executor) = makeTrigger(
            resolveAction: { id in
                if id == invalidActionID { return invalidAction }
                return nil
            },
            onClose: { closedCount += 1 }
        )

        #expect(trigger.trigger(actionID: UUID()) == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)

        #expect(trigger.trigger(actionID: invalidActionID) == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)
    }

    @Test("Non-empty session or active generation blocks quick action trigger")
    func nonEmptySessionOrGeneratingBlocksTrigger() {
        var isSessionEmpty = false
        var isGenerating = false
        var closedCount = 0

        let (trigger, executor) = makeTrigger(
            isSessionEmpty: { isSessionEmpty },
            isGenerating: { isGenerating },
            onClose: { closedCount += 1 }
        )

        let result = trigger.trigger(actionID: QuickAction.BuiltInID.chatGPT)
        #expect(result == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)

        isSessionEmpty = true
        isGenerating = true
        let resultGenerating = trigger.trigger(actionID: QuickAction.BuiltInID.chatGPT)
        #expect(resultGenerating == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)
    }

    @Test("Action re-resolved at trigger time: if disabled mid-session, returns false")
    func actionReResolvedAtTriggerTime() {
        var isEnabled = true
        var closedCount = 0

        let chatGPTID = QuickAction.BuiltInID.chatGPT
        let (trigger, executor) = makeTrigger(
            input: { "question" },
            resolveAction: { id in
                guard isEnabled else { return nil }
                return QuickAction.builtIn.first(where: { $0.id == id })
            },
            onClose: { closedCount += 1 },
            executor: FakeActionExecutor()
        )

        isEnabled = false
        let result = trigger.trigger(actionID: chatGPTID)
        #expect(result == false)
        #expect(executor.performedActions.isEmpty)
        #expect(closedCount == 0)
    }

    // MARK: - Executor Failure and Success Handlings

    @Test("Executor failure clears duplicate guard, keeps panel open, and allows retry")
    func executorFailureAllowsRetry() {
        let executor = FakeActionExecutor()
        executor.shouldSucceed = false
        var closedCount = 0

        let chatGPTID = QuickAction.BuiltInID.chatGPT
        let (trigger, _) = makeTrigger(
            input: { "question" },
            onClose: { closedCount += 1 },
            executor: executor
        )

        // First attempt fails
        let first = trigger.trigger(actionID: chatGPTID)
        #expect(first == false)
        #expect(closedCount == 0)
        #expect(trigger.isExecutingQuickAction == false)

        // Retry succeeds
        executor.shouldSucceed = true
        let second = trigger.trigger(actionID: chatGPTID)
        #expect(second == true)
        #expect(closedCount == 1)
        #expect(trigger.isExecutingQuickAction == true)
    }

    @Test("All three action kinds resolve correctly to URL or TerminalCommand")
    func allThreeKindsResolveCorrectly() {
        let webID = UUID()
        let uriID = UUID()
        let termID = UUID()

        let webAction = QuickAction(id: webID, name: "Web", kind: .web(urlTemplate: "https://web.com/?q={query}"))
        let uriAction = QuickAction(id: uriID, name: "URI", kind: .uriScheme(urlTemplate: "app://search?q={query}"))
        let termAction = QuickAction(id: termID, name: "CLI", kind: .terminal(commandTemplate: "omp {query}"))

        let actions = [webAction, uriAction, termAction]
        let (trigger, executor) = makeTrigger(
            input: { "hello world" },
            resolveAction: { id in actions.first(where: { $0.id == id }) }
        )

        #expect(trigger.trigger(actionID: webID) == true)
        #expect(executor.performedActions.count == 1)
        #expect(executor.performedActions.last == .url(URL(string: "https://web.com/?q=hello%20world")!))

        trigger.resetForNewPanelPresentation()
        #expect(trigger.trigger(actionID: uriID) == true)
        #expect(executor.performedActions.count == 2)
        #expect(executor.performedActions.last == .url(URL(string: "app://search?q=hello%20world")!))

        trigger.resetForNewPanelPresentation()
        #expect(trigger.trigger(actionID: termID) == true)
        #expect(executor.performedActions.count == 3)
        #expect(executor.performedActions.last == .terminalCommand("omp 'hello world'"))
    }

    @Test("Rapid duplicate triggers only open once during the same presentation")
    func rapidDuplicateTriggersOnlyOpenOnce() {
        let executor = FakeActionExecutor()
        var closedCount = 0

        let chatGPTID = QuickAction.BuiltInID.chatGPT
        let (trigger, _) = makeTrigger(
            input: { "rapid question" },
            onClose: { closedCount += 1 },
            executor: executor
        )

        let first = trigger.trigger(actionID: chatGPTID)
        let second = trigger.trigger(actionID: chatGPTID)
        let third = trigger.trigger(actionID: QuickAction.BuiltInID.grok)

        #expect(first == true)
        #expect(second == false)
        #expect(third == false)
        #expect(executor.performedActions.count == 1)
        #expect(closedCount == 1)
    }

    @Test("spotAskPanelDidShow resets duplicate guard")
    func notificationResetsGuard() {
        let executor = FakeActionExecutor()
        var closedCount = 0

        let chatGPTID = QuickAction.BuiltInID.chatGPT
        let (trigger, _) = makeTrigger(
            input: { "first question" },
            onClose: { closedCount += 1 },
            executor: executor
        )

        #expect(trigger.trigger(actionID: chatGPTID) == true)
        #expect(executor.performedActions.count == 1)
        #expect(trigger.isExecutingQuickAction == true)

        // Post panel did show notification
        NotificationCenter.default.post(name: .spotAskPanelDidShow, object: nil)

        #expect(trigger.isExecutingQuickAction == false)
        #expect(trigger.trigger(actionID: chatGPTID) == true)
        #expect(executor.performedActions.count == 2)
        #expect(closedCount == 2)
    }
}
