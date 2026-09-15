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

    @Test("Placeholder is hidden while a mode badge is present")
    func placeholderHidesWhenBadgeExists() {
        #expect(composerShowsPlaceholder(inputIsEmpty: true, hasModeBadge: false))
        #expect(!composerShowsPlaceholder(inputIsEmpty: true, hasModeBadge: true))
        #expect(!composerShowsPlaceholder(inputIsEmpty: false, hasModeBadge: false))
        #expect(!composerShowsPlaceholder(inputIsEmpty: false, hasModeBadge: true))
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

    @Test("Selecting External Ask is mutually exclusive with a prompt preset")
    func selectingExternalAskClearsPreset() {
        var pending: QuickAction?
        var preset: PromptPreset? = translate

        pending = shortcutQuickActionSelection(current: pending, requested: chatGPT)
        if pending != nil {
            preset = nil
        }
        #expect(pending == chatGPT)
        #expect(preset == nil)

        let badge = ComposerModeBadge.resolve(pendingExternalAsk: pending, selectedPreset: polish)
        #expect(badge?.title == chatGPT.displayName)

        pending = shortcutQuickActionSelection(current: pending, requested: chatGPT)
        #expect(pending == nil)
    }

    @Test("Empty pending Return is rejected and a failed launch stays retryable")
    func pendingReturnProtectsDraft() {
        let action = QuickAction(name: "ChatGPT", urlTemplate: "https://example.com/?q={query}")
        let executor = FailingThenSucceedingExecutor()
        let resolve: (UUID) -> QuickAction? = { id in id == action.id ? action : nil }

        #expect(
            AtCommandSelection.confirmPending(
                action,
                query: "   ",
                resolve: resolve,
                executor: executor
            ) == .rejected
        )
        #expect(executor.performedActions.isEmpty)

        executor.shouldSucceed = false
        #expect(
            AtCommandSelection.confirmPending(
                action,
                query: "retry me",
                resolve: resolve,
                executor: executor
            ) == .launchFailed(action)
        )
        #expect(executor.performedActions.isEmpty)

        executor.shouldSucceed = true
        #expect(
            AtCommandSelection.confirmPending(
                action,
                query: "retry me",
                resolve: resolve,
                executor: executor
            ) == .launched
        )
        #expect(executor.performedActions.count == 1)
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
