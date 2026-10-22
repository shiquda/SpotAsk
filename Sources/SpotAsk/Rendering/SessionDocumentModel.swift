import AppKit
import Foundation

// MARK: - Resource Location

enum SessionDocumentResources {
    static var directoryURL: URL? {
#if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "SessionDocument", withExtension: nil) {
            return url
        }
        if let url = Bundle.module.resourceURL?.appendingPathComponent("SessionDocument", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
#endif
        if let url = Bundle.main.url(forResource: "SessionDocument", withExtension: nil) {
            return url
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SessionDocument", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    static var indexURL: URL? {
        directoryURL?.appendingPathComponent("index.html")
    }
}

// MARK: - Snapshot Model

struct SessionDocumentAttachment: Codable, Equatable, Sendable {
    let id: String
    let filename: String
    let isImage: Bool
}

struct SessionDocumentMessage: Codable, Equatable, Sendable {
    let id: String
    let role: String
    let content: String
    let state: String
    let bubble: Bool
    let title: String?
    let metadata: String?
    let iconSlug: String?
    let reasoning: String?
    let reasoningTitle: String?
    let reasoningExpanded: Bool
    let collapsed: Bool
    let preview: String?
    let errorText: String?
    let cancelledText: String?
     let canCopy: Bool
     let copied: Bool
     let canRetryUser: Bool
     let canInsert: Bool
     let canRegenerate: Bool
     let canRetry: Bool
     let canRetryWithModel: Bool
     let canToggleExpand: Bool
     let isLatest: Bool
     let attachments: [SessionDocumentAttachment]
}

struct SessionDocumentSnapshot: Codable, Equatable, Sendable {
    let generation: String
    let theme: String
    let messageStyle: String
    let fontSizePx: Double
    let renderMath: Bool
    let reduceMotion: Bool
    let followsLatest: Bool
    let labels: [String: String]
    let hints: [String: String]
    let messages: [SessionDocumentMessage]

    func toDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

struct SessionDocumentPatch: Codable, Equatable, Sendable {
    let generation: String
    let id: String
    let content: String
    let state: String
    let collapsed: Bool
    let preview: String
    let reasoningTitle: String?
    let renderMath: Bool

    func toDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// MARK: - Bridge Actions

enum SessionDocumentAction: Equatable {
    case copyMessage(id: UUID)
    case copyCode(messageID: UUID, code: String)
    case openLink(url: URL)
     case toggleReasoning(id: UUID)
     case toggleExpand(id: UUID)
     case retryUser(id: UUID)
     case showModelMenu(messageID: UUID, anchorRect: CGRect)
     case insertSelection(id: UUID)
     case regenerate(id: UUID)
     case retry(id: UUID)
     case scroll(phase: String, nearBottom: Bool)
 
     static func parse(body: Any, expectedGeneration: String, knownMessageIDs: Set<UUID>) -> SessionDocumentAction? {
         guard let dict = body as? [String: Any] else { return nil }
         guard let generation = dict["generation"] as? String, generation == expectedGeneration else {
             return nil
         }
         guard let type = dict["type"] as? String else { return nil }
 
         switch type {
         case "scroll":
             guard let phase = dict["phase"] as? String,
                   let nearBottom = dict["nearBottom"] as? Bool else { return nil }
             return .scroll(phase: phase, nearBottom: nearBottom)
 
         case "open-link":
             guard let rawURL = dict["url"] as? String,
                   let url = URL(string: rawURL),
                   let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" || scheme == "mailto" else {
                 return nil
             }
             return .openLink(url: url)
 
         case "copy-code":
             guard let rawID = dict["messageID"] as? String,
                   let id = UUID(uuidString: rawID),
                   knownMessageIDs.contains(id),
                   let code = dict["code"] as? String else { return nil }
             return .copyCode(messageID: id, code: code)
 
         case "show-model-menu":
             guard let rawID = dict["messageID"] as? String,
                   let id = UUID(uuidString: rawID),
                   knownMessageIDs.contains(id),
                   let x = dict["x"] as? Double,
                   let y = dict["y"] as? Double,
                   let width = dict["width"] as? Double,
                   let height = dict["height"] as? Double else { return nil }
             return .showModelMenu(
                 messageID: id,
                 anchorRect: CGRect(x: x, y: y, width: width, height: height)
             )
 
         default:
             guard let rawID = dict["messageID"] as? String,
                   let id = UUID(uuidString: rawID),
                   knownMessageIDs.contains(id) else { return nil }
             switch type {
             case "copy-message": return .copyMessage(id: id)
             case "toggle-reasoning": return .toggleReasoning(id: id)
             case "toggle-expand": return .toggleExpand(id: id)
             case "retry-user": return .retryUser(id: id)
             case "insert-selection": return .insertSelection(id: id)
             case "regenerate": return .regenerate(id: id)
             case "retry": return .retry(id: id)
             default: return nil
             }
         }
     }
}

// MARK: - Snapshot Builder

@MainActor
enum SessionDocumentSnapshotBuilder {
    static func make(
        messages: [ChatMessage],
        settings: AppSettings,
        effectiveAppearance: NSAppearance?,
        generation: String,
        copiedMessageID: UUID?,
        isReasoningExpanded: (UUID) -> Bool,
        isAssistantExpanded: (UUID) -> Bool,
        canInsertSelection: (UUID) -> Bool,
        pendingExternalAskID: UUID?,
        showsShortcutHints: Bool,
        shortcutHint: (InAppShortcutTarget) -> InAppShortcut?,
         followsLatest: Bool,
         generationState: GenerationState = .idle
    ) -> SessionDocumentSnapshot {
        let isDark: Bool
        if let modeScheme = settings.appearance.colorScheme {
            isDark = (modeScheme == .dark)
        } else if let effectiveAppearance {
            isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            isDark = false
        }

        let baseSize: Double
        switch settings.fontSize {
        case .small: baseSize = 13.0
        case .standard: baseSize = 14.5
        case .large: baseSize = 17.0
        }
        let fontSizePx = baseSize * Double(settings.interfaceZoomLevel.displayScale)

        let visibleMessages = messages.filter { $0.role != .system }
        let lastAssistant = visibleMessages.last(where: { $0.role == .assistant })

        var docMessages: [SessionDocumentMessage] = []
        for message in visibleMessages {
            let isLastAssistant = (message.id == lastAssistant?.id)
            let isAssistant = (message.role == .assistant)
            let isUser = (message.role == .user)

            let iconSlug: String?
            if isAssistant {
                iconSlug = ProviderBrandIconMatcher.match(
                    providerName: message.providerName,
                    modelName: message.modelDisplayName
                )
            } else {
                iconSlug = nil
            }

            let reasoning: String? = (isAssistant && message.reasoningContent?.isEmpty == false) ? message.reasoningContent : nil
            let reasoningExpanded = reasoning != nil && isReasoningExpanded(message.id)
            let reasoningTitle: String?
            if reasoning != nil {
                reasoningTitle = reasoningHeaderText(for: message)
            } else {
                reasoningTitle = nil
            }

            let shouldCollapse = isAssistant && message.state != .streaming && AssistantMessageDisplayPolicy.shouldCollapse(message.content)
            let isCollapsed = shouldCollapse && !isAssistantExpanded(message.id)
            let preview = isCollapsed ? AssistantMessageDisplayPolicy.collapsedPreview(for: message.content) : nil
            let canToggleExpand = shouldCollapse

            let attachments = message.attachments.map { att in
                let isImage: Bool
                if case .image = att.payload { isImage = true } else { isImage = false }
                return SessionDocumentAttachment(id: att.id.uuidString, filename: att.filename, isImage: isImage)
            }

             let hasUserMessage = visibleMessages.contains { $0.role == .user }
             let canRegenerate = isLastAssistant
                 && generationState == .idle
                 && message.state == .complete
                 && hasUserMessage
             let canRetryWithModel = canRegenerate
             let canCopy = !message.content.isEmpty
             let lastUser = visibleMessages.last { $0.role == .user }
             let canRetryUser = isUser
                 && generationState == .failed
                 && visibleMessages.last?.role == .assistant
                 && visibleMessages.last?.state == .failed
                 && message.id == lastUser?.id
             let canInsert = isAssistant && message.state == .complete && canInsertSelection(message.id)
             let canRetry = isLastAssistant && message.state == .failed
 
             let metadata: String?
             if isAssistant, let model = message.modelDisplayName {
                 if let duration = message.responseDuration {
                     let seconds = duration.formatted(.number.precision(.fractionLength(1)))
                     metadata = "\(model) · \(seconds)s"
                 } else {
                     metadata = model
                 }
             } else {
                 metadata = nil
             }
 
             let errorText: String?
             if message.state == .failed {
                 errorText = L10n.string("chat.requestFailed")
             } else {
                 errorText = nil
             }
 
             let cancelledText: String?
             if message.state == .cancelled {
                 cancelledText = L10n.string("chat.stopped")
             } else {
                 cancelledText = nil
             }
 
             docMessages.append(SessionDocumentMessage(
                 id: message.id.uuidString,
                 role: message.role.rawValue,
                 content: message.content,
                 state: message.state.rawValue,
                 bubble: settings.chatMessageStyle == .im,
                 title: message.modelDisplayName,
                 metadata: metadata,
                 iconSlug: iconSlug,
                 reasoning: reasoning,
                 reasoningTitle: reasoningTitle,
                 reasoningExpanded: reasoningExpanded,
                 collapsed: isCollapsed,
                 preview: preview,
                 errorText: errorText,
                 cancelledText: cancelledText,
                 canCopy: canCopy,
                 copied: copiedMessageID == message.id,
                 canRetryUser: canRetryUser,
                 canInsert: canInsert,
                 canRegenerate: canRegenerate,
                 canRetry: canRetry,
                 canRetryWithModel: canRetryWithModel,
                 canToggleExpand: canToggleExpand,
                 isLatest: isLastAssistant,
                 attachments: attachments
             ))
         }
 
         let labels: [String: String] = [
             "copy": L10n.string("chat.copy"),
             "copied": L10n.string("chat.copied"),
             "copyQuestion": L10n.string("chat.copyQuestion"),
             "copyCompleteAnswer": L10n.string("chat.copyCompleteAnswer"),
             "copyAnswer": L10n.string("chat.copyAnswer"),
             "questionCopied": L10n.string("chat.questionCopied"),
             "retry": L10n.string("chat.retry"),
             "retryFailed": L10n.string("chat.retryFailedRequest"),
             "regenerate": L10n.string("chat.regenerate"),
             "insertSelection": L10n.string("chat.insertSelection"),
             "retryWithModel": L10n.string("chat.retryWithAnotherModel"),
             "expandAnswer": L10n.string("chat.expandAnswer"),
             "collapseAnswer": L10n.string("chat.collapseAnswer"),
             "reasoning": L10n.string("chat.reasoning"),
             "reasoningExpand": L10n.string("chat.reasoningExpand"),
             "reasoningCollapse": L10n.string("chat.reasoningCollapse")
         ]
 
         var hints: [String: String] = [:]
         if showsShortcutHints {
             if let hint = shortcutHint(.operation(.regenerateOrRetry)) {
                 hints["regenerate"] = InAppShortcutDisplay.labels(for: hint, includeCommand: false).joined(separator: "|")
                 hints["regenerateFull"] = InAppShortcutDisplay.labels(for: hint).joined()
             }
             if let hint = shortcutHint(.operation(.copyAnswer)) {
                 hints["copy"] = InAppShortcutDisplay.labels(for: hint, includeCommand: false).joined(separator: "|")
                 hints["copyFull"] = InAppShortcutDisplay.labels(for: hint).joined()
             }
         }

        return SessionDocumentSnapshot(
            generation: generation,
            theme: isDark ? "dark" : "light",
            messageStyle: settings.chatMessageStyle.rawValue,
            fontSizePx: fontSizePx,
            renderMath: settings.renderMath,
            reduceMotion: false,
            followsLatest: followsLatest,
            labels: labels,
            hints: hints,
            messages: docMessages
        )
    }

    private static func reasoningHeaderText(for message: ChatMessage) -> String {
        if let duration = message.reasoningDuration {
            return L10n.string("chat.reasoningCompleted", String(format: "%.1f", duration))
        }
        if message.state == .streaming {
            let elapsed = max(0, Date.now.timeIntervalSince(message.createdAt))
            return L10n.string("chat.reasoningStreaming", String(format: "%.1f", elapsed))
        }
        if let duration = message.responseDuration {
            return L10n.string("chat.reasoningCompleted", String(format: "%.1f", duration))
        }
        return L10n.string("chat.reasoning")
    }
}
