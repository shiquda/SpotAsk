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

    @Test("In existing conversation, external ask shortcut attaches mode badge and respects toggle")
    func existingConversationShortcutAttachesExternalAsk() {
        var pendingExternalAsk: QuickAction?
        var selectedPreset: PromptPreset? = translate

        // Pressing shortcut for ChatGPT attaches it and clears preset
        pendingExternalAsk = shortcutQuickActionSelection(current: pendingExternalAsk, requested: chatGPT)
        if pendingExternalAsk != nil {
            selectedPreset = nil
        }
        #expect(pendingExternalAsk == chatGPT)
        #expect(selectedPreset == nil)

        let badge = ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset)
        #expect(badge == .externalAsk(
            title: chatGPT.displayName,
            icon: chatGPT.symbolName,
            brandIconSlug: chatGPT.brandIconSlug
        ))

        // Pressing the same shortcut again toggles it off
        pendingExternalAsk = shortcutQuickActionSelection(current: pendingExternalAsk, requested: chatGPT)
        #expect(pendingExternalAsk == nil)
        let clearedBadge = ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset)
        #expect(clearedBadge == nil)

        // Pressing Grok shortcut sets Grok
        pendingExternalAsk = shortcutQuickActionSelection(current: pendingExternalAsk, requested: grok)
        #expect(pendingExternalAsk == grok)
        let grokBadge = ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset)
        #expect(grokBadge == .externalAsk(
            title: grok.displayName,
            icon: grok.symbolName,
            brandIconSlug: grok.brandIconSlug
        ))
    }

    @Test("Popover external ask selection and deselect state machine")
    func popoverExternalAskSelectionStateMachine() {
        var pendingExternalAsk: QuickAction?
        var selectedPreset: PromptPreset?

        func selectAction(_ action: QuickAction) {
            if shortcutQuickActionSelection(current: pendingExternalAsk, requested: action) == nil {
                pendingExternalAsk = nil
            } else {
                pendingExternalAsk = action
                selectedPreset = nil
            }
        }

        func selectPreset(_ preset: PromptPreset?) {
            pendingExternalAsk = nil
            selectedPreset = preset
        }

        // 1. Initial state: direct question
        #expect(pendingExternalAsk == nil)
        #expect(selectedPreset == nil)
        #expect(ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset) == nil)

        // 2. Select ChatGPT from popover
        selectAction(chatGPT)
        #expect(pendingExternalAsk == chatGPT)
        #expect(selectedPreset == nil)
        #expect(ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset) == .externalAsk(
            title: chatGPT.displayName,
            icon: chatGPT.symbolName,
            brandIconSlug: chatGPT.brandIconSlug
        ))

        // 3. Re-select ChatGPT from popover: deselects/toggles off
        selectAction(chatGPT)
        #expect(pendingExternalAsk == nil)
        #expect(selectedPreset == nil)
        #expect(ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset) == nil)

        // 4. Select Grok from popover
        selectAction(grok)
        #expect(pendingExternalAsk == grok)
        #expect(selectedPreset == nil)

        // 5. Select preset from popover: clears pending external ask
        selectPreset(translate)
        #expect(pendingExternalAsk == nil)
        #expect(selectedPreset == translate)
        #expect(ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset) == .preset(
            title: translate.title,
            icon: translate.symbolName
        ))

        // 6. Select direct question (nil): clears both
        selectPreset(nil)
        #expect(pendingExternalAsk == nil)
        #expect(selectedPreset == nil)
        #expect(ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset) == nil)
    }

    @Test("Submitting input launches external ask and resets pending state")
    func submittingInputLaunchesExternalAskAndResets() {
        var pendingExternalAsk: QuickAction? = chatGPT
        var input = "What is the airspeed velocity of an unladen swallow?"
        let executor = FailingThenSucceedingExecutor()
        let resolve: (UUID) -> QuickAction? = { id in id == self.chatGPT.id ? self.chatGPT : nil }

        let outcome = AtCommandSelection.confirmPending(
            chatGPT,
            query: input,
            resolve: resolve,
            executor: executor
        )
        #expect(outcome == .launched)
        #expect(executor.performedActions.count == 1)
        if case let .url(url) = executor.performedActions[0] {
            #expect(url.absoluteString.contains("chatgpt.com"))
        } else {
            Issue.record("Expected .url resolved action")
        }

        // On successful launch, pendingExternalAsk and input are cleared
        if case .launched = outcome {
            pendingExternalAsk = nil
            input = ""
        }
        #expect(pendingExternalAsk == nil)
        #expect(input.isEmpty)
    }

    @Test("PresetPopoverContent initializes with actions and selection callbacks")
    func presetPopoverContentInitialization() {
        var selectedAction: QuickAction?
        var selectedPreset: PromptPreset?

        let content = PresetPopoverContent(
            presets: [translate, polish],
            selection: nil,
            actions: [chatGPT, grok],
            selectedActionID: chatGPT.id,
            showsShortcutHints: true,
            shortcutForPreset: { _ in InAppShortcut(key: "1", modifiers: .command) },
            shortcutForAction: { _ in InAppShortcut(key: "5", modifiers: .command) },
            onChoose: { selectedPreset = $0 },
            onSelectAction: { selectedAction = $0 }
        )

        #expect(content.presets.count == 2)
        #expect(content.actions.count == 2)
        #expect(content.selectedActionID == chatGPT.id)
        #expect(content.selection == nil)

        content.onSelectAction(chatGPT)
        #expect(selectedAction == chatGPT)

        content.onChoose(translate)
        #expect(selectedPreset == translate)
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
