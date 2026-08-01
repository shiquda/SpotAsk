import XCTest
@testable import SpotAsk

final class AppUpdateCheckerTests: XCTestCase {
    func testVersionAcceptsLeadingVAndNormalizesIt() {
        XCTAssertEqual(AppVersion(string: "v1.2.3")?.description, "1.2.3")
    }

    func testVersionComparesMissingComponentsAsZero() {
        XCTAssertEqual(AppVersion(string: "1.2"), AppVersion(string: "1.2.0"))
        XCTAssertLessThan(AppVersion(string: "1.2.9")!, AppVersion(string: "1.3")!)
    }

    func testUpdateIsAvailableOnlyWhenReleaseIsNewer() {
        let currentVersion = AppVersion(string: "0.1.1")!

        XCTAssertNil(AppUpdateChecker.update(forReleaseTag: "v0.1.1", currentVersion: currentVersion))
        XCTAssertEqual(
            AppUpdateChecker.update(forReleaseTag: "v0.2.0", currentVersion: currentVersion)?.version,
            AppVersion(string: "0.2.0")
        )
    }

    func testInvalidReleaseTagDoesNotReportAnUpdate() {
        XCTAssertNil(
            AppUpdateChecker.update(
                forReleaseTag: "latest",
                currentVersion: AppVersion(string: "0.1.1")!
            )
        )
    }
}
