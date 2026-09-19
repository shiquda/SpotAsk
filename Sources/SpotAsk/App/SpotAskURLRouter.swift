import Foundation

/// The `spotask://` contract. `open`, `ask`, `toggle` and `settings` keep
/// their published behavior; settings pages add one optional, stable target:
///
///     spotask://settings                  // plain Settings
///     spotask://settings/<section-id>     // that page (see `SettingsSection.deepLinkPath`)
///
/// A settings target is exactly one path segment, matched case-insensitively.
/// Anything else — a missing or unknown id, an extra or empty segment, a
/// fragment — falls back to plain Settings instead of rejecting the URL, so a
/// link written for another app version still opens the settings window. Query
/// items are ignored on `settings`, so an unknown parameter cannot change where
/// the link lands.
enum SpotAskURLCommand: Equatable {
    case open
    case ask(String)
    case compose(String)
    case toggle
    case settings(SettingsSection?)
}

enum SpotAskURLRouter {
    static let scheme = "spotask"

    static func parse(_ url: URL) -> SpotAskURLCommand? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let command = parse(components: components) {
            return command
        }
        return parse(url.absoluteString)
    }

    static func parse(_ raw: String) -> SpotAskURLCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed),
           let command = parse(components: components) {
            return command
        }
        guard let encoded = encodeLooseURLString(trimmed),
              let components = URLComponents(string: encoded) else {
            return nil
        }
        return parse(components: components)
    }

    @MainActor
    static func perform(_ command: SpotAskURLCommand, using commandCenter: SpotAskCommandCenter = .shared) {
        switch command {
        case .open:
            commandCenter.open()
        case .ask(let query):
            commandCenter.ask(query)
        case .compose(let query):
            commandCenter.compose(query)
        case .toggle:
            commandCenter.toggle()
        case .settings(let section):
            commandCenter.showSettings(section: section)
        }
    }

    @MainActor
    @discardableResult
    static func handle(_ url: URL, using commandCenter: SpotAskCommandCenter = .shared) -> Bool {
        guard let command = parse(url) else { return false }
        perform(command, using: commandCenter)
        return true
    }

    private static func parse(components: URLComponents) -> SpotAskURLCommand? {
        guard components.scheme?.lowercased() == scheme else { return nil }
        guard let (name, arguments) = command(from: components) else { return nil }

        switch name {
        case "open":
            return .open
        case "toggle":
            return .toggle
        case "settings":
            return .settings(settingsTarget(from: components, arguments: arguments))
        case "ask":
            return parseAsk(from: components)
        default:
            return nil
        }
    }

    /// Splits a URL into its command name and the path segments that follow
    /// it. `spotask://settings/general` carries the name in the host, while the
    /// path-style `spotask:///settings/general` carries it in the first segment.
    /// Empty segments are kept, because they are what tells a malformed
    /// settings target such as `settings//about` from a valid one.
    private static func command(from components: URLComponents) -> (name: String, arguments: [String])? {
        var segments = components.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        if segments.first == "" { segments.removeFirst() }
        if let host = components.host, !host.isEmpty {
            return (host.lowercased(), segments)
        }
        guard let first = segments.first, !first.isEmpty else { return nil }
        return (first.lowercased(), Array(segments.dropFirst()))
    }

    /// Only the documented `settings` and `settings/<section-id>` forms select a
    /// page: exactly one non-empty path segment and no fragment. A missing id,
    /// an unknown id, an extra or empty segment, or a fragment opens plain
    /// Settings instead, so an undocumented link cannot land on a page the URL
    /// did not actually name.
    private static func settingsTarget(from components: URLComponents, arguments: [String]) -> SettingsSection? {
        guard components.fragment == nil, arguments.count == 1, let id = arguments.first else { return nil }
        return SettingsSection(deepLinkPath: id)
    }

    private static func parseAsk(from components: URLComponents) -> SpotAskURLCommand {
        let items = components.queryItems ?? []
        let query = queryValue(from: items)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return .open }
        return shouldSubmit(from: items) ? .ask(query) : .compose(query)
    }

    private static func queryValue(from items: [URLQueryItem]) -> String? {
        items.first { ["q", "query"].contains($0.name.lowercased()) }?.value
    }

    private static func shouldSubmit(from items: [URLQueryItem]) -> Bool {
        guard let raw = items.first(where: { ["submit", "send"].contains($0.name.lowercased()) })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return true
        }
        switch raw {
        case "0", "false", "no", "off":
            return false
        default:
            return true
        }
    }

    private static func encodeLooseURLString(_ raw: String) -> String? {
        guard let queryStart = raw.firstIndex(of: "?") else {
            return raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        }
        let head = String(raw[..<queryStart])
        let query = String(raw[raw.index(after: queryStart)...])
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return head + "?" + encodedQuery
    }
}

struct SpotAskURLDelivery {
    private(set) var openedFromURL = false

    mutating func markOpenedFromURL() {
        openedFromURL = true
    }
}

func shouldOpenPanelOnLaunch(silentLaunch: Bool, openedFromURL: Bool) -> Bool {
    !silentLaunch && !openedFromURL
}
