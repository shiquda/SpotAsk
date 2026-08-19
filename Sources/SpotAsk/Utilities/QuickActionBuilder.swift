import Foundation

/// Result of validating a Quick Action template.
enum QuickActionTemplateValidation: Equatable, Sendable {
    case valid
    case empty
    case missingQueryPlaceholder
    case invalidURL

    /// Returns `true` if the template is valid for saving/triggering.
    var isValid: Bool {
        self == .valid
    }
}

/// Pure builder and validator for Quick Action templates across web, uriScheme, and terminal kinds.
enum QuickActionBuilder {
    /// RFC 3986 ASCII unreserved characters: A-Za-z0-9-._~
    private static let queryValueAllowedCharacters = CharacterSet(
        charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
            "abcdefghijklmnopqrstuvwxyz" +
            "0123456789-._~"
    )

    /// Validates a template string according to the given QuickActionKind.
    static func validate(kind: QuickActionKind) -> QuickActionTemplateValidation {
        switch kind {
        case let .web(urlTemplate):
            return validateURLTemplate(urlTemplate)
        case let .uriScheme(urlTemplate):
            return validateURISchemeTemplate(urlTemplate)
        case let .terminal(commandTemplate):
            return validateTerminalTemplate(commandTemplate)
        }
    }

    /// Validates a web URL template: must not be empty, must contain {query}, must form a valid absolute URL with scheme.
    static func validateURLTemplate(_ rawTemplate: String) -> QuickActionTemplateValidation {
        let template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return .empty }
        guard template.contains("{query}") else { return .missingQueryPlaceholder }

        let candidate = template.replacingOccurrences(of: "{query}", with: "test")
        guard let url = URL(string: candidate),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return .invalidURL
        }
        return .valid
    }

    /// Validates a URI scheme template: must not be empty, must contain {query}, must form a valid absolute URL with scheme.
    static func validateURISchemeTemplate(_ rawTemplate: String) -> QuickActionTemplateValidation {
        let template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return .empty }
        guard template.contains("{query}") else { return .missingQueryPlaceholder }

        let candidate = template.replacingOccurrences(of: "{query}", with: "test")
        guard let url = URL(string: candidate),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return .invalidURL
        }
        return .valid
    }

    /// Validates a terminal command template: must not be empty, must contain {query}.
    static func validateTerminalTemplate(_ rawTemplate: String) -> QuickActionTemplateValidation {
        let template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return .empty }
        guard template.contains("{query}") else { return .missingQueryPlaceholder }
        return .valid
    }

    /// Checks whether the template uses an HTTPS scheme when substituted.
    /// Only applies to web kind.
    static func isHTTPScheme(_ rawTemplate: String) -> Bool {
        let template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard template.contains("{query}") else { return false }
        let candidate = template.replacingOccurrences(of: "{query}", with: "test")
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "https"
    }

    /// Builds an actionable `URL` from the given template and raw query string (for web or uriScheme).
    static func makeURL(
        template: String,
        query rawQuery: String
    ) -> URL? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        guard template.contains("{query}") else { return nil }

        guard let encoded = query.addingPercentEncoding(
            withAllowedCharacters: queryValueAllowedCharacters
        ) else {
            return nil
        }

        let urlString = template.replacingOccurrences(
            of: "{query}",
            with: encoded
        )

        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return nil
        }

        return url
    }

    /// Escapes a query string for safe shell single-quote embedding:
    /// Wraps in single quotes and replaces internal single quotes `'` with `'\''`.
    static func shellEscape(_ rawQuery: String) -> String {
        let escaped = rawQuery.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Builds a terminal command string from the template and raw query.
    static func makeTerminalCommand(
        template: String,
        query rawQuery: String
    ) -> String? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        guard template.contains("{query}") else { return nil }

        let escapedQuery = shellEscape(query)
        let command = template.replacingOccurrences(of: "{query}", with: escapedQuery)
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
