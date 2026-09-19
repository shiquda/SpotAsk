import Foundation

/// Published documentation entry points for Settings.
///
/// Settings pages and the documentation site ship on separate schedules: a
/// released build keeps linking to pages that were rewritten after it was cut,
/// and a reader can follow a link into a page deployed after their build. So
/// every link is addressed by the stable slug of the published route, never by
/// a localized title, and the language root follows the `AppLanguage` the
/// Settings window already uses.
enum DocumentationLinks {
    static let englishUserGuide = URL(string: "https://shiquda.github.io/SpotAsk/")!
    static let simplifiedChineseUserGuide = URL(string: "https://shiquda.github.io/SpotAsk/zh-CN/")!

    /// A published page a settings group can link to.
    ///
    /// The raw value is the route below the language root exactly as the site
    /// serves it: `guides/proxy` is `/SpotAsk/guides/proxy` in English and
    /// `/SpotAsk/zh-CN/guides/proxy` in Chinese. Slugs are additive, because an
    /// already-released build keeps requesting the old route: moving a page on
    /// the site needs a redirect rather than a rename here.
    enum Topic: String, CaseIterable {
        case serviceAddresses = "guides/service-addresses"
        case providersAndModels = "guides/providers-and-models"
        case prompts = "guides/prompts"
        case externalAsk = "guides/external-ask"
        case selectionAssistant = "guides/selection-assistant"
        case appearance = "guides/appearance"
        case proxy = "guides/proxy"
        case shortcutsReference = "reference"
        case privacy = "privacy"
    }

    /// The user guide root for a language, so a reader who switched Settings to
    /// Chinese is not sent to English pages.
    static func userGuideURL(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> URL {
        usesChineseDocumentation(language, preferredLanguages: preferredLanguages)
            ? simplifiedChineseUserGuide
            : englishUserGuide
    }

    /// The published page for one settings topic, in the reader's language.
    static func url(
        for topic: Topic,
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> URL {
        userGuideURL(for: language, preferredLanguages: preferredLanguages)
            .appendingPathComponent(topic.rawValue)
    }

    private static func usesChineseDocumentation(
        _ language: AppLanguage,
        preferredLanguages: [String]
    ) -> Bool {
        language == .simplifiedChinese
            || (language == .system && preferredLanguages.first?.lowercased().hasPrefix("zh") == true)
    }
}
