import Foundation

/// Frozen wire contract for documentation → App settings deep links.
///
/// A documentation link opens one settings page with the `spotask://` scheme:
///
///     spotask://settings                 // plain Settings
///     spotask://settings/<section-id>    // one page, addressed by a stable id
///
/// The rules below are what published documentation links may rely on:
/// - **Path form only.** The page is a path segment following the `settings`
///   command. Query items are not part of the contract and are ignored, so an
///   unknown parameter can never change what happens. `open`, `ask`, `toggle`
///   and plain `settings` keep their existing behavior.
/// - **Stable ids, never localized titles.** An id is ASCII, lowercase and
///   hyphen-separated; `SettingsSection.title` is presentation text and must
///   never be sent over the scheme.
/// - **Exact target only.** The target is exactly one path segment after the
///   `settings` command. A missing or unknown id, an extra or empty segment, or
///   a fragment is not a target and opens plain Settings rather than failing,
///   so a link written for a newer app version still lands on the settings
///   window.
/// - **Case-insensitive ids.** `settings/External-Ask` resolves like
///   `settings/external-ask`.
/// - **Additive versioning.** New pages add new ids. Existing ids are never
///   renamed or reused, because already-published documentation links cannot
///   be updated atomically with a release.
extension SettingsSection {
    /// The id used in `spotask://settings/<deepLinkPath>`.
    ///
    /// Frozen: renaming one breaks every published documentation link, so it
    /// is a breaking protocol change rather than a refactor.
    var deepLinkPath: String {
        switch self {
        case .provider: "provider"
        case .prompts: "prompts"
        case .externalAsk: "external-ask"
        case .selectionAssistant: "selection-assistant"
        case .shortcuts: "shortcuts"
        case .general: "general"
        case .appearance: "appearance"
        case .about: "about"
        }
    }

    /// Resolves the `<section-id>` of `spotask://settings/<section-id>`.
    /// Returns `nil` for an unknown id so the caller falls back to plain Settings.
    init?(deepLinkPath: String) {
        let id = deepLinkPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let section = Self.allCases.first(where: { $0.deepLinkPath == id }) else { return nil }
        self = section
    }
}
