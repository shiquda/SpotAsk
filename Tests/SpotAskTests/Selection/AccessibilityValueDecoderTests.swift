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
}
