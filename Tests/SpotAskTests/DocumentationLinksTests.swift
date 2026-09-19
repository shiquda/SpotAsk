import Foundation
import Testing
@testable import SpotAsk

/// The settings window links to a site that is deployed independently of the
/// app: an already-released build keeps requesting the routes it shipped with,
/// so what sits below the language root is a published contract rather than an
/// implementation detail.
struct DocumentationLinksTests {
    @Test func topicsExposeFrozenDocumentationRoutes() {
        #expect(
            DocumentationLinks.Topic.allCases.map(\.rawValue) == [
                "guides/service-addresses",
                "guides/providers-and-models",
                "guides/prompts",
                "guides/external-ask",
                "guides/selection-assistant",
                "guides/appearance",
                "guides/proxy",
                "reference",
                "privacy",
            ]
        )
    }

    @Test func topicsResolveUnderTheLanguageRoot() {
        for topic in DocumentationLinks.Topic.allCases {
            #expect(
                DocumentationLinks.url(for: topic, language: .english).absoluteString
                    == "https://shiquda.github.io/SpotAsk/\(topic.rawValue)"
            )
            #expect(
                DocumentationLinks.url(for: topic, language: .simplifiedChinese).absoluteString
                    == "https://shiquda.github.io/SpotAsk/zh-CN/\(topic.rawValue)"
            )
        }
    }

    @Test func topicsFollowTheInterfaceLanguage() {
        #expect(
            DocumentationLinks.url(for: .proxy, language: .system, preferredLanguages: ["zh-Hans-CN"]).absoluteString
                == "https://shiquda.github.io/SpotAsk/zh-CN/guides/proxy"
        )
        #expect(
            DocumentationLinks.url(for: .proxy, language: .system, preferredLanguages: ["en-US"]).absoluteString
                == "https://shiquda.github.io/SpotAsk/guides/proxy"
        )
        // The site publishes English and Simplified Chinese only, so any other
        // interface language reads the English pages rather than a translated
        // page that does not exist.
        #expect(
            DocumentationLinks.url(for: .proxy, language: .japanese).absoluteString
                == "https://shiquda.github.io/SpotAsk/guides/proxy"
        )
    }

    @Test func topicsTargetPublishedPages() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SpotAskTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root

        for topic in DocumentationLinks.Topic.allCases {
            for languageRoot in ["docs/site", "docs/site/zh-CN"] {
                let page = repositoryRoot
                    .appendingPathComponent(languageRoot)
                    .appendingPathComponent("\(topic.rawValue).md")
                #expect(
                    FileManager.default.fileExists(atPath: page.path),
                    "\(languageRoot)/\(topic.rawValue).md is linked from Settings but missing"
                )
            }
        }
    }
}
