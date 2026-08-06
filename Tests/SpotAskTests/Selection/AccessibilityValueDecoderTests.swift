import ApplicationServices
import Foundation
import Testing
@testable import SpotAsk

@Suite("Accessibility value decoding")
struct AccessibilityValueDecoderTests {
    @Test("An attributed selection is decoded as plain text")
    func attributedSelectionDecodesAsPlainText() throws {
        let attributed = NSAttributedString(string: "Selected text")

        let value = try AccessibilityValueDecoder.decode(attributed as CFTypeRef) { _ in
            throw AccessibilityAdapterError.invalidValue
        }

        #expect(value == .string("Selected text"))
    }

    @Test("An AXTextMarkerRange is decoded as a text marker range")
    func textMarkerRangeDecodesAsTextMarkerRange() throws {
        let start = Data([0x01, 0x02])
        let end = Data([0x03, 0x04])
        let range = AXTextMarkerRangeCreateWithBytes(
            kCFAllocatorDefault,
            [UInt8](start),
            start.count,
            [UInt8](end),
            end.count
        )

        let value = try AccessibilityValueDecoder.decode(range) { _ in
            throw AccessibilityAdapterError.invalidValue
        }

        #expect(value == .textMarkerRange(AccessibilityTextMarkerRange(startMarker: start, endMarker: end)))
    }
}
