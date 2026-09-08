import Foundation

enum SpotAskURLCommand: Equatable {
    case open
    case ask(String)
    case compose(String)
    case toggle
    case settings
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
        case .settings:
            commandCenter.showSettings()
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
        guard let name = commandName(from: components) else { return nil }

        switch name {
        case "open":
            return .open
        case "toggle":
            return .toggle
        case "settings":
            return .settings
        case "ask":
            return parseAsk(from: components)
        default:
            return nil
        }
    }

    private static func commandName(from components: URLComponents) -> String? {
        if let host = components.host, !host.isEmpty {
            return host.lowercased()
        }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        return first.lowercased()
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
    private var lastURL: URL?
    private var lastInstant: ContinuousClock.Instant?

    mutating func markOpenedFromURL() {
        openedFromURL = true
    }

    mutating func take(
        _ url: URL,
        now: ContinuousClock.Instant = .now,
        coalesceFor: Duration = .seconds(1)
    ) -> URL? {
        openedFromURL = true
        if let lastURL, lastURL == url, let lastInstant, now - lastInstant < coalesceFor {
            return nil
        }
        self.lastURL = url
        self.lastInstant = now
        return url
    }
}

func shouldOpenPanelOnLaunch(silentLaunch: Bool, openedFromURL: Bool) -> Bool {
    !silentLaunch && !openedFromURL
}
