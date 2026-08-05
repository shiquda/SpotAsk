import XCTest
@testable import SpotAsk

@MainActor
final class StatusToastTests: XCTestCase {
    func testShowAppendsAndDismissRemovesItem() {
        let center = StatusToastCenter()

        center.show("Saved", isError: false)
        center.show("Failed", isError: true)

        XCTAssertEqual(center.items.map(\.message), ["Saved", "Failed"])
        XCTAssertEqual(center.items.map(\.isError), [false, true])

        center.dismiss(center.items[0].id)
        XCTAssertEqual(center.items.map(\.message), ["Failed"])
    }

    func testOverflowKeepsOnlyTheNewestThreeItems() {
        let center = StatusToastCenter()

        for index in 0 ..< 5 {
            center.show("Item \(index)")
        }

        XCTAssertEqual(center.items.map(\.message), ["Item 2", "Item 3", "Item 4"])
    }
}
