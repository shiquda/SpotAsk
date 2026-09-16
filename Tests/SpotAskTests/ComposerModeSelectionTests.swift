import Foundation
import Testing
@testable import SpotAsk

@Suite("Composer mode selection")
@MainActor
struct ComposerModeSelectionTests {
    private var chatGPT: QuickAction { QuickAction.builtIn[0] }
    private var grok: QuickAction { QuickAction.builtIn[1] }
    private var translate: PromptPreset { PromptPreset.builtIn[0] }
    private var polish: PromptPreset { PromptPreset.builtIn[1] }

    @Test("Pressing the selected External Ask shortcut clears the pending target")
    func selectedQuickActionShortcutClearsSelection() {
        #expect(shortcutQuickActionSelection(current: chatGPT, requested: chatGPT) == nil)
        #expect(shortcutQuickActionSelection(current: chatGPT, requested: grok) == grok)
        #expect(shortcutQuickActionSelection(current: nil, requested: chatGPT) == chatGPT)
    }

    @Test("External Ask badge wins over a prompt preset and exposes brand icon")
    func badgePrefersExternalAskOverPreset() {
        let both = ComposerModeBadge.resolve(pendingExternalAsk: chatGPT, selectedPreset: translate)
        #expect(both == .externalAsk(
            title: chatGPT.displayName,
            icon: chatGPT.symbolName,
            brandIconSlug: chatGPT.brandIconSlug
        ))

        let presetOnly = ComposerModeBadge.resolve(pendingExternalAsk: nil, selectedPreset: translate)
        #expect(presetOnly == .preset(title: translate.title, icon: translate.symbolName))
        #expect(presetOnly?.brandIconSlug == nil)

        #expect(ComposerModeBadge.resolve(pendingExternalAsk: nil, selectedPreset: nil) == nil)
    }

    @Test("Emptying the draft after typing cancels pending External Ask unless skipped once")
    func backspaceClearingDraftCancelsPending() {
        #expect(shouldClearPendingExternalAsk(from: "hello", to: "", skipOnce: false))
        #expect(shouldClearPendingExternalAsk(from: "hello", to: "   ", skipOnce: false))
        #expect(!shouldClearPendingExternalAsk(from: "hello", to: "", skipOnce: true))
        #expect(!shouldClearPendingExternalAsk(from: "", to: "", skipOnce: false))
        #expect(!shouldClearPendingExternalAsk(from: "hello", to: "hell", skipOnce: false))
        #expect(!shouldClearPendingExternalAsk(from: "   ", to: "", skipOnce: false))
    }

    @Test("ComposerModeCoordinator manages selection, toggle, and preset mutual exclusivity")
    func composerModeCoordinatorSelectionAndMutualExclusion() {
        var coordinator = ComposerModeCoordinator()
        var preset: PromptPreset? = translate

        // 1. Initial state with a preset: badge is preset
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(coordinator.badge(selectedPreset: preset) == .preset(title: translate.title, icon: translate.symbolName))

        // 2. Select ChatGPT (via popover or shortcut): clears preset, attaches pendingExternalAsk
        let becamePending = coordinator.toggleExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(becamePending)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(preset == nil)
        #expect(coordinator.skipEmptyPendingClear)
        #expect(coordinator.badge(selectedPreset: preset) == .externalAsk(
            title: chatGPT.displayName,
            icon: chatGPT.symbolName,
            brandIconSlug: chatGPT.brandIconSlug
        ))

        // 3. Re-selecting ChatGPT toggles it off
        let toggledOff = coordinator.toggleExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(!toggledOff)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(preset == nil)
        #expect(coordinator.badge(selectedPreset: preset) == nil)

        // 4. Select Grok
        _ = coordinator.toggleExternalAsk(grok, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == grok)
        #expect(preset == nil)

        // 5. Select preset: clears pending external ask
        coordinator.applyPreset(polish, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(preset == polish)
        #expect(coordinator.badge(selectedPreset: preset) == .preset(title: polish.title, icon: polish.symbolName))

        // 6. Select direct question (nil): clears both
        coordinator.applyPreset(nil, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(preset == nil)
        #expect(coordinator.badge(selectedPreset: preset) == nil)

        // 7. Clear selection explicitly
        _ = coordinator.toggleExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        coordinator.clearSelection(selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(preset == nil)
    }
    @Test("attachExternalAsk maintains mount when same action is already pending")
    func attachExternalAskMaintainsMountWhenAlreadyPending() {
        var coordinator = ComposerModeCoordinator()
        var preset: PromptPreset? = translate

        // 1. Initial attachment clears preset and sets pending action
        coordinator.attachExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(preset == nil)
        #expect(coordinator.skipEmptyPendingClear)

        // 2. Receiving becamePending with the same action MUST keep it mounted (NOT toggle off)
        coordinator.attachExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(preset == nil)
        #expect(coordinator.skipEmptyPendingClear)

        // 3. Contrast with toggleExternalAsk which toggles it off when re-selected
        let toggledOff = coordinator.toggleExternalAsk(chatGPT, selectedPreset: &preset)
        #expect(!toggledOff)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(preset == nil)
    }


    @Test("ComposerModeCoordinator handleSend executes external ask and cleans up state on launch")
    func composerModeCoordinatorHandleSend() {
        var coordinator = ComposerModeCoordinator()
        var preset: PromptPreset?
        let executor = FailingThenSucceedingExecutor()
        let resolve: (UUID) -> QuickAction? = { id in id == self.chatGPT.id ? self.chatGPT : nil }

        // 1. Without pending external ask: proceeds with standard send
        var standardInput = "hello"
        let standardOutcome = coordinator.handleSend(input: &standardInput, resolve: resolve, executor: executor)
        #expect(standardOutcome == .proceedWithStandardSend)
        #expect(standardInput == "hello")
        #expect(executor.performedActions.isEmpty)

        // 2. With pending external ask but empty/whitespace input: rejected, preserves pending and input
        coordinator.attachExternalAsk(chatGPT, selectedPreset: &preset)
        var emptyInput = "   "
        let emptyOutcome = coordinator.handleSend(input: &emptyInput, resolve: resolve, executor: executor)
        #expect(emptyOutcome == .rejectedExternalAsk)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(emptyInput == "   ")
        #expect(executor.performedActions.isEmpty)

        // 3. Executor fails: returns launchFailed, retains pending external ask for retry
        executor.shouldSucceed = false
        var retryInput = "query to retry"
        let failedOutcome = coordinator.handleSend(input: &retryInput, resolve: resolve, executor: executor)
        #expect(failedOutcome == .launchFailedExternalAsk(chatGPT))
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(retryInput == "query to retry")
        #expect(executor.performedActions.isEmpty)

        // 4. Executor succeeds: returns launched, clears pendingExternalAsk and input automatically
        executor.shouldSucceed = true
        let launchedOutcome = coordinator.handleSend(input: &retryInput, resolve: resolve, executor: executor)
        #expect(launchedOutcome == .launchedExternalAsk)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(retryInput.isEmpty)
        #expect(executor.performedActions.count == 1)
        if case let .url(url) = executor.performedActions[0] {
            #expect(url.absoluteString.contains("chatgpt.com"))
        } else {
            Issue.record("Expected .url resolved action")
        }
    }

    @Test("External Ask immediate send policy requires canSend and non-empty trimmed text")
    func immediateExternalAskSendPolicy() {
        #expect(shouldSendExternalAskImmediately(sendIfReady: true, canSend: true, input: "如何理解量子力学"))
        #expect(shouldSendExternalAskImmediately(sendIfReady: true, canSend: true, input: "  hello world  "))
        #expect(!shouldSendExternalAskImmediately(sendIfReady: true, canSend: true, input: ""))
        #expect(!shouldSendExternalAskImmediately(sendIfReady: true, canSend: true, input: "   \n\t  "))
        #expect(!shouldSendExternalAskImmediately(sendIfReady: true, canSend: false, input: "hello"))
        #expect(!shouldSendExternalAskImmediately(sendIfReady: true, canSend: false, input: ""))
        #expect(!shouldSendExternalAskImmediately(sendIfReady: false, canSend: true, input: "hello"))
    }

    @Test("ComposerModeCoordinator external ask workflow: immediate send on input, mounting on empty, and toggle-off")
    func externalAskSelectionAndSendLifecycle() {
        var coordinator = ComposerModeCoordinator()
        var preset: PromptPreset? = translate
        let executor = FailingThenSucceedingExecutor()
        let resolve: (UUID) -> QuickAction? = { id in id == self.chatGPT.id ? self.chatGPT : nil }

        func simulateSelectExternalAsk(action: QuickAction, input: inout String, canSend: Bool) -> Bool {
            let becamePending = coordinator.toggleExternalAsk(action, selectedPreset: &preset)
            guard becamePending, shouldSendExternalAskImmediately(canSend: canSend, input: input) else {
                return false
            }
            let outcome = coordinator.handleSend(input: &input, resolve: resolve, executor: executor)
            return outcome == .launchedExternalAsk
        }

        // 1. Non-empty input: selecting external ask immediately launches and clears draft + pending state
        var inputWithText = "如何理解量子力学"
        let sentImmediately = simulateSelectExternalAsk(action: chatGPT, input: &inputWithText, canSend: true)
        #expect(sentImmediately)
        #expect(inputWithText.isEmpty)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(preset == nil)
        #expect(coordinator.badge(selectedPreset: preset) == nil)
        #expect(executor.performedActions.count == 1)
        if case let .url(url) = executor.performedActions.last {
            #expect(url.absoluteString.contains("chatgpt.com"))
        } else {
            Issue.record("Expected .url action")
        }

        // 2. Empty input: selecting external ask mounts capsule and does not launch
        var emptyInput = ""
        let sentOnEmpty = simulateSelectExternalAsk(action: chatGPT, input: &emptyInput, canSend: false)
        #expect(!sentOnEmpty)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(coordinator.badge(selectedPreset: preset) == .externalAsk(
            title: chatGPT.displayName,
            icon: chatGPT.symbolName,
            brandIconSlug: chatGPT.brandIconSlug
        ))
        #expect(executor.performedActions.count == 1)

        // 3. Repeating the same action while mounted toggles it off without sending
        var typedLater = "hello"
        let toggledOff = simulateSelectExternalAsk(action: chatGPT, input: &typedLater, canSend: true)
        #expect(!toggledOff)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(typedLater == "hello")
        #expect(coordinator.badge(selectedPreset: preset) == nil)
        #expect(executor.performedActions.count == 1)

        // 4. Mount with empty input, then failed send keeps pending state and input for retry
        _ = simulateSelectExternalAsk(action: chatGPT, input: &emptyInput, canSend: false)
        #expect(coordinator.pendingExternalAsk == chatGPT)
        executor.shouldSucceed = false
        var retryInput = "need retry"
        let failedOutcome = coordinator.handleSend(input: &retryInput, resolve: resolve, executor: executor)
        #expect(failedOutcome == .launchFailedExternalAsk(chatGPT))
        #expect(coordinator.pendingExternalAsk == chatGPT)
        #expect(retryInput == "need retry")
        #expect(coordinator.badge(selectedPreset: preset) != nil)

        // 5. Subsequent successful send cleans up pending and input
        executor.shouldSucceed = true
        let retryOutcome = coordinator.handleSend(input: &retryInput, resolve: resolve, executor: executor)
        #expect(retryOutcome == .launchedExternalAsk)
        #expect(coordinator.pendingExternalAsk == nil)
        #expect(retryInput.isEmpty)
        #expect(coordinator.badge(selectedPreset: preset) == nil)
        #expect(executor.performedActions.count == 2)
    }
}

@MainActor
private final class FailingThenSucceedingExecutor: QuickActionExecuting, @unchecked Sendable {
    var shouldSucceed = true
    var performedActions: [ResolvedQuickAction] = []

    func perform(_ resolved: ResolvedQuickAction) -> Bool {
        guard shouldSucceed else { return false }
        performedActions.append(resolved)
        return true
    }
}
