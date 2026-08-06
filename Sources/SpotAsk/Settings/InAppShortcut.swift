import Foundation

/// A user-configurable shortcut used while SpotAsk is in the foreground.
struct InAppShortcut: Codable, Hashable, Sendable {
    let key: String
    let modifiers: InAppShortcutModifiers

    init(key: String, modifiers: InAppShortcutModifiers = .command) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    static func command(_ key: String) -> InAppShortcut {
        InAppShortcut(key: key, modifiers: .command)
    }

    static func commandShift(_ key: String) -> InAppShortcut {
        InAppShortcut(key: key, modifiers: [.command, .shift])
    }

    /// The dispatcher records one-character shortcuts with any standard
    /// keyboard modifier and leaves presentation details to the UI layer.
    var isSupported: Bool {
        let supportedModifiers: InAppShortcutModifiers = [.command, .shift, .option, .control]
        guard !modifiers.intersection(supportedModifiers).isEmpty,
              modifiers.rawValue & ~supportedModifiers.rawValue == 0,
              key.unicodeScalars.count == 1,
              let scalar = key.unicodeScalars.first else { return false }
        return scalar.isASCII && (scalar.properties.isAlphabetic || scalar.properties.numericType != nil || ",./-=".unicodeScalars.contains(scalar))
    }

    /// Global shortcuts additionally accept the Space key, matching the
    /// app's historical Option+Space trigger.
    var isSupportedGlobalShortcut: Bool {
        isSupported || (key == " " && !modifiers.isEmpty)
    }
}

struct InAppShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let command = InAppShortcutModifiers(rawValue: 1 << 0)
    static let shift = InAppShortcutModifiers(rawValue: 1 << 1)
    static let option = InAppShortcutModifiers(rawValue: 1 << 2)
    static let control = InAppShortcutModifiers(rawValue: 1 << 3)
}

/// Stable identifiers for controls that the shortcut dispatcher can invoke.
enum InAppShortcutOperation: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case focusInput
    case regenerateOrRetry
    case copyAnswer
    case toggleWindowOnTop
    case showSettings
    case newConversation
    case sendOrCancel
    case zoomIn
    case zoomOut

    var id: String { rawValue }
}

/// A shortcut target is either an application operation or one concrete prompt preset.
enum InAppShortcutTarget: Hashable, Codable, Identifiable, Sendable {
    case operation(InAppShortcutOperation)
    case promptPreset(UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case operation
        case promptPresetID
    }

    private enum Kind: String, Codable {
        case operation
        case promptPreset
    }

    var id: String {
        switch self {
        case let .operation(operation): "operation.\(operation.rawValue)"
        case let .promptPreset(id): "promptPreset.\(id.uuidString.lowercased())"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .operation:
            self = .operation(try container.decode(InAppShortcutOperation.self, forKey: .operation))
        case .promptPreset:
            self = .promptPreset(try container.decode(UUID.self, forKey: .promptPresetID))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .operation(operation):
            try container.encode(Kind.operation, forKey: .kind)
            try container.encode(operation, forKey: .operation)
        case let .promptPreset(id):
            try container.encode(Kind.promptPreset, forKey: .kind)
            try container.encode(id, forKey: .promptPresetID)
        }
    }
}

struct InAppShortcutAssignment: Codable, Hashable, Identifiable, Sendable {
    let target: InAppShortcutTarget
    let shortcut: InAppShortcut

    var id: String { target.id }
}

enum InAppShortcutAssignmentError: Error, Equatable, Sendable {
    case unsupportedShortcut
    case duplicateShortcut(InAppShortcutTarget)
    case unavailableTarget
}

/// User changes are stored as overrides and explicit removals. Defaults remain
/// derived from the available presets so a newly-created custom preset can get
/// its numbered shortcut without writing a new app-wide settings schema.
struct InAppShortcutConfiguration: Codable, Equatable, Sendable {
    private(set) var overrides: [InAppShortcutAssignment] = []
    private(set) var disabledTargets: Set<InAppShortcutTarget> = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case overrides
        case disabledTargets
    }

    private static let currentSchemaVersion = 1

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        overrides = try container.decodeIfPresent([InAppShortcutAssignment].self, forKey: .overrides) ?? []
        disabledTargets = try container.decodeIfPresent(Set<InAppShortcutTarget>.self, forKey: .disabledTargets) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(overrides, forKey: .overrides)
        try container.encode(disabledTargets, forKey: .disabledTargets)
    }

    func shortcut(for target: InAppShortcutTarget, presets: [PromptPreset]) -> InAppShortcut? {
        resolvedAssignments(for: presets).first(where: { $0.target == target })?.shortcut
    }

    func target(for shortcut: InAppShortcut, presets: [PromptPreset]) -> InAppShortcutTarget? {
        let assignments = resolvedAssignments(for: presets)
        if let exact = assignments.first(where: { $0.shortcut == shortcut }) {
            return exact.target
        }
        // The plus key is physically Command+Shift+= on macOS. Treat it as an
        // alias for the default Command+= zoom shortcut unless a user has
        // explicitly assigned Command+Shift+= to another action.
        if shortcut == .commandShift("="),
           assignments.contains(where: {
               $0.target == .operation(.zoomIn) && $0.shortcut == .command("=")
           }) {
            return .operation(.zoomIn)
        }
        return nil
    }

    func resolvedAssignments(for presets: [PromptPreset]) -> [InAppShortcutAssignment] {
        let defaults = Self.defaultAssignments(for: presets)
        let available = Self.availableTargets(for: presets)
        var assignments = defaults.filter { !disabledTargets.contains($0.target) }
        for override in overrides where available.contains(override.target) {
            assignments.removeAll { $0.target == override.target }
            assignments.append(override)
        }
        return assignments
    }

    mutating func assign(
        _ shortcut: InAppShortcut,
        to target: InAppShortcutTarget,
        presets: [PromptPreset]
    ) -> InAppShortcutAssignmentError? {
        guard shortcut.isSupported else { return .unsupportedShortcut }
        guard Self.availableTargets(for: presets).contains(target) else { return .unavailableTarget }

        var candidate = self
        candidate.overrides.removeAll { $0.target == target }
        candidate.disabledTargets.remove(target)
        if let conflict = candidate.resolvedAssignments(for: presets).first(where: {
            $0.target != target && $0.shortcut == shortcut
        }) {
            return .duplicateShortcut(conflict.target)
        }

        overrides.removeAll { $0.target == target }
        disabledTargets.remove(target)
        overrides.append(InAppShortcutAssignment(target: target, shortcut: shortcut))
        return nil
    }

    mutating func removeShortcut(for target: InAppShortcutTarget, presets: [PromptPreset]) -> InAppShortcutAssignmentError? {
        guard Self.availableTargets(for: presets).contains(target) else { return .unavailableTarget }
        overrides.removeAll { $0.target == target }
        disabledTargets.insert(target)
        return nil
    }

    mutating func resetShortcut(for target: InAppShortcutTarget, presets: [PromptPreset]) -> InAppShortcutAssignmentError? {
        guard Self.availableTargets(for: presets).contains(target) else { return .unavailableTarget }
        overrides.removeAll { $0.target == target }
        disabledTargets.remove(target)
        return nil
    }

    mutating func resetAll() {
        overrides = []
        disabledTargets = []
    }

    /// Removes assignments that refer to deleted custom prompts or invalid data.
    @discardableResult
    mutating func cleanUp(for presets: [PromptPreset]) -> Bool {
        let available = Self.availableTargets(for: presets)
        let previous = self
        disabledTargets.formIntersection(available)
        var accepted: [InAppShortcutAssignment] = []
        for assignment in overrides where available.contains(assignment.target) && assignment.shortcut.isSupported {
            var candidate = InAppShortcutConfiguration(overrides: accepted, disabledTargets: disabledTargets)
            if candidate.assign(assignment.shortcut, to: assignment.target, presets: presets) == nil {
                accepted = candidate.overrides
            }
        }
        overrides = accepted
        return self != previous
    }

    private init(overrides: [InAppShortcutAssignment], disabledTargets: Set<InAppShortcutTarget>) {
        self.overrides = overrides
        self.disabledTargets = disabledTargets
    }

    private static func availableTargets(for presets: [PromptPreset]) -> Set<InAppShortcutTarget> {
        Set(InAppShortcutOperation.allCases.map(InAppShortcutTarget.operation))
            .union(presets.map { .promptPreset($0.id) })
    }

    private static func defaultAssignments(for presets: [PromptPreset]) -> [InAppShortcutAssignment] {
        let operations: [(InAppShortcutOperation, InAppShortcut)] = [
            (.focusInput, .command("l")),
            (.regenerateOrRetry, .command("r")),
            (.copyAnswer, .commandShift("c")),
            (.showSettings, .command(",")),
            (.newConversation, .command("n")),
            (.zoomIn, .command("=")),
            (.zoomOut, .command("-"))
        ]
        let operationAssignments = operations.map {
            InAppShortcutAssignment(target: .operation($0.0), shortcut: $0.1)
        }
        // The catalog order is the shortcut order. A freshly migrated catalog
        // starts with the historical four built-ins followed by custom prompts,
        // preserving existing Command-1 through Command-9 assignments.
        let promptAssignments = presets.prefix(9).enumerated().map {
            InAppShortcutAssignment(target: .promptPreset($0.element.id), shortcut: .command("\($0.offset + 1)"))
        }
        return operationAssignments + promptAssignments
    }
}
