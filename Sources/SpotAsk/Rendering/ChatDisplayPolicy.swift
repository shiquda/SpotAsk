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

enum ChatEscapeAction: Equatable {
    case preserveMarkedText
    case dismissPresetPopover
    case dismissModelPicker
    case cancelGeneration
    case startNewConversation
    case dismissWindow
}

func chatEscapeAction(
    hasMarkedText: Bool,
    isPresetPopoverPresented: Bool,
    isModelPickerPresented: Bool = false,
    isGenerating: Bool,
    startsNewConversation: Bool,
    hasMessages: Bool
) -> ChatEscapeAction {
    if hasMarkedText {
        return .preserveMarkedText
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
