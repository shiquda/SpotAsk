import XCTest
@testable import SpotAsk

final class BrandImageTests: XCTestCase {
    func testAppIconLoaderReturnsNilWhenBundleDoesNotContainTheAppIcon() {
        XCTAssertNil(spotAskAppIconImage(bundle: Bundle(for: Self.self)))
    }

    func testStatusBarBrandImageIsAnEighteenPointTemplate() throws {
        let image = try XCTUnwrap(spotAskStatusBarImage())

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
    }
}
