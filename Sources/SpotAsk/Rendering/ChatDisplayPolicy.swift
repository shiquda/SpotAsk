import AppKit

@MainActor
enum NewConversationConfirmation {
    static func present(
        settings: AppSettings,
        window: NSWindow?,
        onConfirm: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = L10n.string("chat.newConversationConfirmTitle")
        alert.informativeText = L10n.string("chat.newConversationConfirmMessage")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("chat.newConversation"))
        alert.addButton(withTitle: L10n.string("settings.cancel"))

        let skipFutureConfirmations = NSButton(
            checkboxWithTitle: L10n.string("chat.newConversationDontAskAgain"),
            target: nil,
            action: nil
        )
        alert.accessoryView = skipFutureConfirmations

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            if skipFutureConfirmations.state == .on {
                settings.confirmBeforeStartingNewConversation = false
            }
            onConfirm()
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
}

func shortcutPresetSelection(current: PromptPreset?, requested: PromptPreset) -> PromptPreset? {
    current?.id == requested.id ? nil : requested
}

func shortcutQuickActionSelection(current: QuickAction?, requested: QuickAction) -> QuickAction? {
    current?.id == requested.id ? nil : requested
}

enum ComposerModeBadge: Equatable {
    case preset(title: String, icon: String)
    case externalAsk(title: String, icon: String, brandIconSlug: String?)

    var title: String {
        switch self {
        case let .preset(title, _), let .externalAsk(title, _, _):
            return title
        }
    }

    var icon: String {
        switch self {
        case let .preset(_, icon), let .externalAsk(_, icon, _):
            return icon
        }
    }

    var brandIconSlug: String? {
        switch self {
        case .preset:
            return nil
        case let .externalAsk(_, _, slug):
            return slug
        }
    }

    static func resolve(pendingExternalAsk: QuickAction?, selectedPreset: PromptPreset?) -> Self? {
        if let action = pendingExternalAsk {
            return .externalAsk(
                title: action.displayName,
                icon: action.symbolName,
                brandIconSlug: action.brandIconSlug
            )
        }
        if let preset = selectedPreset {
            return .preset(title: preset.title, icon: preset.symbolName)
        }
        return nil
    }
}

func shouldClearPendingExternalAsk(from oldValue: String, to newValue: String, skipOnce: Bool) -> Bool {
    guard !skipOnce else { return false }
    let wasNonempty = !oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return wasNonempty && isEmpty
}

@MainActor
struct ComposerModeCoordinator: Equatable {
    var pendingExternalAsk: QuickAction?
    var skipEmptyPendingClear = false

    func badge(selectedPreset: PromptPreset?) -> ComposerModeBadge? {
        ComposerModeBadge.resolve(pendingExternalAsk: pendingExternalAsk, selectedPreset: selectedPreset)
    }

    /// Toggles the external ask action: if already selected, clears it; otherwise attaches it.
    /// Used by shortcut keys and popover rows.
    @discardableResult
    mutating func toggleExternalAsk(
        _ action: QuickAction,
        selectedPreset: inout PromptPreset?
    ) -> Bool {
        if shortcutQuickActionSelection(current: pendingExternalAsk, requested: action) == nil {
            pendingExternalAsk = nil
            return false
        } else {
            attachExternalAsk(action, selectedPreset: &selectedPreset)
            return true
        }
    }


    /// Unconditionally attaches an external ask action, clearing any preset.
    /// Used when confirming an `@` command target (`.becamePending`).
    mutating func attachExternalAsk(
        _ action: QuickAction,
        selectedPreset: inout PromptPreset?
    ) {
        pendingExternalAsk = action
        selectedPreset = nil
        skipEmptyPendingClear = true
    }

    mutating func applyPreset(
        _ preset: PromptPreset?,
        selectedPreset: inout PromptPreset?
    ) {
        pendingExternalAsk = nil
        selectedPreset = preset
    }

    mutating func clearSelection(selectedPreset: inout PromptPreset?) {
        pendingExternalAsk = nil
        selectedPreset = nil
    }

    enum SendOutcome: Equatable {
        case launchedExternalAsk
        case launchFailedExternalAsk(QuickAction)
        case rejectedExternalAsk
        case proceedWithStandardSend
    }

    mutating func handleSend(
        input: inout String,
        resolve: (UUID) -> QuickAction?,
        executor: any QuickActionExecuting = DefaultQuickActionExecutor()
    ) -> SendOutcome {
        guard let pending = pendingExternalAsk else {
            return .proceedWithStandardSend
        }
        let outcome = AtCommandSelection.confirmPending(
            pending,
            query: input,
            resolve: resolve,
            executor: executor
        )
        switch outcome {
        case .launched:
            pendingExternalAsk = nil
            input = ""
            return .launchedExternalAsk
        case let .launchFailed(action):
            pendingExternalAsk = action
            return .launchFailedExternalAsk(action)
        case .rejected, .appliedPreset, .becamePending:
            return .rejectedExternalAsk
        }
    }
}


enum ChatEscapeAction: Equatable {
    case preserveMarkedText
    case dismissAtPalette
    case dismissPresetPopover
    case dismissModelPicker
    case cancelGeneration
    case startNewConversation
    case dismissWindow
}

func chatEscapeAction(
    hasMarkedText: Bool,
    isAtPalettePresented: Bool = false,
    isPresetPopoverPresented: Bool,
    isModelPickerPresented: Bool = false,
    isGenerating: Bool,
    startsNewConversation: Bool,
    hasMessages: Bool
) -> ChatEscapeAction {
    if hasMarkedText {
        return .preserveMarkedText
    }
    if isAtPalettePresented {
        return .dismissAtPalette
    }
    if isPresetPopoverPresented {
        return .dismissPresetPopover
    }
    if isModelPickerPresented {
        return .dismissModelPicker
    }
    if isGenerating {
        return .cancelGeneration
    }
    if startsNewConversation, hasMessages {
        return .startNewConversation
    }
    return .dismissWindow
}

/// Shared bounded preview scan used by the user and assistant display policies.
enum LongTextDisplayPolicy {
    static func collapsedPreview(
        _ content: String,
        characterThreshold: Int,
        explicitLineThreshold: Int
    ) -> String? {
        var characterCount = 0
        var explicitLineCount = 1
        var lastContentEnd = content.startIndex

        for index in content.indices {
            if characterCount == characterThreshold {
                return String(content[..<lastContentEnd])
            }

            let nextIndex = content.index(after: index)
            characterCount += 1

            if content[index].isNewline {
                if explicitLineCount == explicitLineThreshold {
                    return String(content[..<lastContentEnd])
                }
                explicitLineCount += 1
            } else {
                lastContentEnd = nextIndex
            }
        }

        return explicitLineCount >= explicitLineThreshold
            ? String(content[..<lastContentEnd])
            : nil
    }
}

/// Decides when a sent question needs an initially compact presentation.
/// The original message content is always retained and rendered when expanded.
enum UserMessageDisplayPolicy {
    static let characterThreshold = 500
    static let explicitLineThreshold = 8
    static let collapsedLineLimit = 8

    static func shouldCollapse(_ content: String) -> Bool {
        collapsedPreview(for: content) != nil
    }

    /// Returns only the text needed for the compact view. Scanning stops as
    /// soon as either collapse threshold is reached, avoiding work proportional
    /// to an arbitrarily long saved question.
    static func collapsedPreview(for content: String) -> String? {
        LongTextDisplayPolicy.collapsedPreview(
            content,
            characterThreshold: characterThreshold,
            explicitLineThreshold: explicitLineThreshold
        )
    }
}

/// Long assistant answers use a plain compact preview instead of running the
/// full Markdown renderer until the user asks to expand them.
enum AssistantMessageDisplayPolicy {
    static let characterThreshold = 4_000
    static let explicitLineThreshold = 120
    static let collapsedLineLimit = 12

    static func shouldCollapse(_ content: String) -> Bool {
        collapsedPreview(for: content) != nil
    }

    static func collapsedPreview(for content: String) -> String? {
        LongTextDisplayPolicy.collapsedPreview(
            content,
            characterThreshold: characterThreshold,
            explicitLineThreshold: explicitLineThreshold
        )
    }
}

/// View-owned expansion state for long messages. Keeping it above lazy rows
/// preserves a user's choice while a row is temporarily recycled off-screen.
struct MessageExpansionState: Equatable {
    private(set) var expandedMessageIDs: Set<UUID> = []

    mutating func reconcile(messages: [ChatMessage], role: ChatRole) {
        let currentIDs = Set(messages.lazy.filter { $0.role == role }.map(\.id))
        expandedMessageIDs.formIntersection(currentIDs)
        // A message created in this window starts streaming before the user can
        // choose an expansion state. Keep it full-height through completion so
        // the terminal transition never collapses an answer the user just saw.
        if role == .assistant {
            expandedMessageIDs.formUnion(
                messages.lazy
                    .filter { $0.role == .assistant && $0.state == .streaming }
                    .map(\.id)
            )
        }
    }

    func isExpanded(messageID: UUID) -> Bool {
        expandedMessageIDs.contains(messageID)
    }

    mutating func toggle(messageID: UUID) {
        if expandedMessageIDs.contains(messageID) {
            expandedMessageIDs.remove(messageID)
        } else {
            expandedMessageIDs.insert(messageID)
        }
    }
}

typealias UserMessageExpansionState = MessageExpansionState
