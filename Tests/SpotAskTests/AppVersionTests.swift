import XCTest
@testable import SpotAsk

final class AppVersionTests: XCTestCase {
    func testVersionAcceptsLeadingVAndNormalizesIt() {
        XCTAssertEqual(AppVersion(string: "v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion(string: "V2.0")?.description, "2")
    }

    func testVersionComparesMissingComponentsAsZero() {
        XCTAssertEqual(AppVersion(string: "1.2"), AppVersion(string: "1.2.0"))
        XCTAssertEqual(AppVersion(string: "1.0.0"), AppVersion(string: "1.0"))
        XCTAssertLessThan(AppVersion(string: "1.2.9")!, AppVersion(string: "1.3")!)
        XCTAssertFalse(AppVersion(string: "1.0.0")! < AppVersion(string: "1.0")!)
        XCTAssertFalse(AppVersion(string: "1.0")! < AppVersion(string: "1.0.0")!)
    }

    func testVersionComparesUnequalNumericWidths() {
        XCTAssertLessThan(AppVersion(string: "1.9.9")!, AppVersion(string: "2.0")!)
        XCTAssertLessThan(AppVersion(string: "1.2")!, AppVersion(string: "1.10")!)
        XCTAssertGreaterThan(AppVersion(string: "1.10.0")!, AppVersion(string: "1.9.9")!)
    }

    func testVersionRejectsNonNumericAndEmptyValues() {
        XCTAssertNil(AppVersion(string: ""))
        XCTAssertNil(AppVersion(string: "   "))
        XCTAssertNil(AppVersion(string: "latest"))
        XCTAssertNil(AppVersion(string: "1.2.0-beta"))
        XCTAssertNil(AppVersion(string: "1..2"))
    }

    func testUpdateFeedURLsAreArchitectureSpecific() {
        XCTAssertEqual(
            UpdateFeed.officialAppcastURL(architecture: "arm64").absoluteString,
            "https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.officialAppcastURL(architecture: "x86_64").absoluteString,
            "https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-x86_64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.appcastURL(architecture: "arm64").absoluteString,
            "https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.acceleratedAppcastURL(architecture: "arm64").absoluteString,
            "https://ghproxy.net/https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.appcastURL(for: .official, architecture: "arm64").absoluteString,
            "https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.appcastURL(for: .accelerated, architecture: "arm64").absoluteString,
            "https://ghproxy.net/https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.appcastURL(for: .automatic, architecture: "arm64").absoluteString,
            "https://github.com/shiquda/SpotAsk/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(UpdateFeed.githubReleasesURL.absoluteString, "https://github.com/shiquda/SpotAsk/releases/latest")
    }

    func testAcceleratedEnclosureURLRewriting() {
        let githubURL = URL(string: "https://github.com/shiquda/SpotAsk/releases/download/v1.0.0/SpotAsk-1.0.0-arm64.dmg")!
        XCTAssertEqual(
            UpdateFeed.acceleratedEnclosureURL(for: githubURL).absoluteString,
            "https://ghproxy.net/https://github.com/shiquda/SpotAsk/releases/download/v1.0.0/SpotAsk-1.0.0-arm64.dmg"
        )

        let alreadyMirroredURL = URL(string: "https://ghproxy.net/https://github.com/shiquda/SpotAsk/releases/download/v1.0.0/SpotAsk-1.0.0-arm64.dmg")!
        XCTAssertEqual(
            UpdateFeed.acceleratedEnclosureURL(for: alreadyMirroredURL).absoluteString,
            alreadyMirroredURL.absoluteString
        )

        let customDomainURL = URL(string: "https://cdn.example.com/downloads/SpotAsk.dmg")!
        XCTAssertEqual(
            UpdateFeed.acceleratedEnclosureURL(for: customDomainURL).absoluteString,
            customDomainURL.absoluteString
        )
    }
}
