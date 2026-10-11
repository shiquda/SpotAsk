import AppKit
import Foundation

enum QuickActionKind: Codable, Equatable, Sendable {
    case web(urlTemplate: String)
    case uriScheme(urlTemplate: String)
    case terminal(commandTemplate: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case template
    }

    private enum KindType: String, Codable {
        case web
        case uriScheme
        case terminal
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        let template = try container.decode(String.self, forKey: .template)
        switch type {
        case .web:
            self = .web(urlTemplate: template)
        case .uriScheme:
            self = .uriScheme(urlTemplate: template)
        case .terminal:
            self = .terminal(commandTemplate: template)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .web(urlTemplate):
            try container.encode(KindType.web, forKey: .type)
            try container.encode(urlTemplate, forKey: .template)
        case let .uriScheme(urlTemplate):
            try container.encode(KindType.uriScheme, forKey: .type)
            try container.encode(urlTemplate, forKey: .template)
        case let .terminal(commandTemplate):
            try container.encode(KindType.terminal, forKey: .type)
            try container.encode(commandTemplate, forKey: .template)
        }
    }

    var template: String {
        get {
            switch self {
            case let .web(t), let .uriScheme(t), let .terminal(t):
                t
            }
        }
        set {
            switch self {
            case .web:
                self = .web(urlTemplate: newValue)
            case .uriScheme:
                self = .uriScheme(urlTemplate: newValue)
            case .terminal:
                self = .terminal(commandTemplate: newValue)
            }
        }
    }
}

struct QuickAction: Identifiable, Codable, Equatable, Sendable {
    static let defaultSymbolName: String = "globe"

    let id: UUID
    var name: String
    var kind: QuickActionKind
    var symbolName: String
    let isBuiltIn: Bool
    var isEnabled: Bool
    /// What this channel is for. Empty uses the built-in description.
    var routingPurpose: String
    /// When this channel is the right choice. Empty uses the built-in description.
    var routingScenario: String
    /// Forces a confirmation even when the global mode would auto-send.
    var requiresConfirmationOnAutoRoute: Bool
    /// When true, a built-in channel keeps the saved name instead of the localized title.
    var hasCustomDisplayName: Bool

    enum BuiltInID {
        static let chatGPT: UUID = UUID(uuidString: "B9740E49-A922-41EC-A56A-C5ACC2F41A8D")!
        static let grok: UUID = UUID(uuidString: "8220B89D-763B-4AE5-933B-44BF8F7E3145")!
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case urlTemplate
        case symbolName
        case isBuiltIn
        case isEnabled
        case routingPurpose
        case routingScenario
        case requiresConfirmationOnAutoRoute
        case hasCustomDisplayName
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: QuickActionKind,
        symbolName: String = defaultSymbolName,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        routingPurpose: String = "",
        routingScenario: String = "",
        requiresConfirmationOnAutoRoute: Bool = false,
        hasCustomDisplayName: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.symbolName = Self.isValidSymbol(symbolName) ? symbolName : Self.defaultSymbolName
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.routingPurpose = routingPurpose
        self.routingScenario = routingScenario
        self.requiresConfirmationOnAutoRoute = requiresConfirmationOnAutoRoute
        self.hasCustomDisplayName = hasCustomDisplayName
    }

    /// Convenience initializer for .web actions
    init(
        id: UUID = UUID(),
        name: String,
        urlTemplate: String,
        symbolName: String = defaultSymbolName,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.init(
            id: id,
            name: name,
            kind: .web(urlTemplate: urlTemplate),
            symbolName: symbolName,
            isBuiltIn: isBuiltIn,
            isEnabled: isEnabled
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let decodedKind = try container.decodeIfPresent(QuickActionKind.self, forKey: .kind) {
            kind = decodedKind
        } else if let legacyURL = try container.decodeIfPresent(String.self, forKey: .urlTemplate) {
            kind = .web(urlTemplate: legacyURL)
        } else {
            kind = .web(urlTemplate: "")
        }
        let rawSymbol = try container.decodeIfPresent(String.self, forKey: .symbolName)
        symbolName = Self.isValidSymbol(rawSymbol) ? (rawSymbol ?? Self.defaultSymbolName) : Self.defaultSymbolName
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        routingPurpose = try container.decodeIfPresent(String.self, forKey: .routingPurpose) ?? ""
        routingScenario = try container.decodeIfPresent(String.self, forKey: .routingScenario) ?? ""
        requiresConfirmationOnAutoRoute = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmationOnAutoRoute) ?? false
        hasCustomDisplayName = try container.decodeIfPresent(Bool.self, forKey: .hasCustomDisplayName) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(routingPurpose, forKey: .routingPurpose)
        try container.encode(routingScenario, forKey: .routingScenario)
        try container.encode(requiresConfirmationOnAutoRoute, forKey: .requiresConfirmationOnAutoRoute)
        try container.encode(hasCustomDisplayName, forKey: .hasCustomDisplayName)
    }
    static var builtIn: [QuickAction] {
        [
            QuickAction(
                id: BuiltInID.chatGPT,
                name: L10n.string("externalAsk.askChatGPT"),
                kind: .web(urlTemplate: "https://chatgpt.com/?q={query}"),
                symbolName: "bubble.left.and.bubble.right",
                isBuiltIn: true,
                isEnabled: true
            ),
            QuickAction(
                id: BuiltInID.grok,
                name: L10n.string("externalAsk.askGrok"),
                kind: .web(urlTemplate: "https://grok.com/?q={query}"),
                symbolName: "sparkles",
                isBuiltIn: true,
                isEnabled: false
            )
        ]
    }

    static func localizedTitle(for id: UUID) -> String? {
        switch id {
        case BuiltInID.chatGPT:
            L10n.string("externalAsk.askChatGPT")
        case BuiltInID.grok:
            L10n.string("externalAsk.askGrok")
        default:
            nil
        }
    }

    var displayName: String {
        if isBuiltIn, !hasCustomDisplayName, let localized = Self.localizedTitle(for: id) {
            return localized
        }
        return name
    }

    /// Bundled LobeHub brand icon slug, matching the model/provider picker
    /// visuals. Built-ins pin their brand; custom actions derive one from
    /// the link/command/name text and fall back to the SF Symbol when nothing matches.
    var brandIconSlug: String? {
        switch id {
        case BuiltInID.chatGPT:
            "openai"
        case BuiltInID.grok:
            "grok"
        default:
            ProviderBrandIconMatcher.match(
                providerName: name,
                address: kind.template
            )
        }
    }

    static func isValidSymbol(_ symbolName: String?) -> Bool {
        guard let symbolName = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines), !symbolName.isEmpty else {
            return false
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    }

    static let availableSymbols: [String] = [
        "globe",
        "safari",
        "magnifyingglass",
        "sparkles",
        "bubble.left.and.bubble.right",
        "character.bubble",
        "terminal",
        "chevron.left.forwardslash.chevron.right",
        "cpu",
        "hammer",
        "wrench.and.screwdriver",
        "doc.text.magnifyingglass",
        "doc.text",
        "list.bullet.rectangle",
        "pencil.and.scribble",
        "book",
        "folder",
        "link",
        "paperplane",
        "bolt"
    ]

    static func localizedSymbolLabel(for symbolName: String) -> String {
        switch symbolName {
        case "globe":
            L10n.string("externalAsk.symbol.globe")
        case "safari":
            L10n.string("externalAsk.symbol.safari")
        case "magnifyingglass":
            L10n.string("externalAsk.symbol.magnifyingglass")
        case "sparkles":
            L10n.string("externalAsk.symbol.sparkles")
        case "bubble.left.and.bubble.right":
            L10n.string("externalAsk.symbol.chat")
        case "character.bubble":
            L10n.string("externalAsk.symbol.characterBubble")
        case "terminal":
            L10n.string("externalAsk.symbol.terminal")
        case "chevron.left.forwardslash.chevron.right":
            L10n.string("externalAsk.symbol.code")
        case "cpu":
            L10n.string("externalAsk.symbol.cpu")
        case "hammer":
            L10n.string("externalAsk.symbol.hammer")
        case "wrench.and.screwdriver":
            L10n.string("externalAsk.symbol.wrench")
        case "doc.text.magnifyingglass":
            L10n.string("externalAsk.symbol.docSearch")
        case "doc.text":
            L10n.string("externalAsk.symbol.docText")
        case "list.bullet.rectangle":
            L10n.string("externalAsk.symbol.list")
        case "pencil.and.scribble":
            L10n.string("externalAsk.symbol.pencil")
        case "book":
            L10n.string("externalAsk.symbol.book")
        case "folder":
            L10n.string("externalAsk.symbol.folder")
        case "link":
            L10n.string("externalAsk.symbol.link")
        case "paperplane":
            L10n.string("externalAsk.symbol.paperplane")
        case "bolt":
            L10n.string("externalAsk.symbol.bolt")
        default:
            symbolName
        }
    }
}

extension QuickActionKind {
    /// Verb-first label for the target, matching the Settings kind picker's
    /// wording. Used by the model picker's External Ask rows.
    var localizedLabel: String {
        switch self {
        case .web: L10n.string("externalAsk.kind.web")
        case .uriScheme: L10n.string("externalAsk.kind.uriScheme")
        case .terminal: L10n.string("externalAsk.kind.terminal")
        }
    }

    /// SF Symbol used when no bundled brand icon matches the action.
    var fallbackSymbolName: String {
        switch self {
        case .web: "globe"
        case .uriScheme: "app.badge"
        case .terminal: "terminal"
        }
    }
}
