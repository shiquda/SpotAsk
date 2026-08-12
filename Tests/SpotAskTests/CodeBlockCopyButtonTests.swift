import AppKit
import SwiftUI
import XCTest
import Textual
@testable import SpotAsk

final class CodeBlockCopyButtonTests: XCTestCase {
    @MainActor
    func testCopyButtonReceivesClickPastTextSelectionOverlay() throws {
        StructuredText.CodeBlockProxy.interactiveExclusionRects.removeAll()
        let markdown = MarkdownTextView(
            content: "```swift\nlet answer = \"ready\"\nprint(answer)\n```"
        )
        let hosting = NSHostingView(rootView: AnyView(markdown.frame(width: 520, height: 240)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let button = descendants(of: hosting).first { $0 is NSButton } as? NSButton
        let overlay = descendants(of: hosting).first {
            String(describing: type(of: $0)).contains("NSTextInteractionView")
        }
        XCTAssertNotNil(button, "Expected a copy button")
        XCTAssertNotNil(overlay, "Expected Textual selection overlay")

        let buttonCenter = NSPoint(x: button!.bounds.midX, y: button!.bounds.midY)
        let hitPoint = button!.convert(buttonCenter, to: nil)
        let hit = window.contentView?.hitTest(hitPoint)
        XCTAssertTrue(
            hit === button,
            "Copy button must receive the hit instead of the text selection overlay"
        )

        NSPasteboard.general.clearContents()
        button!.performClick(nil)
        let copied = NSPasteboard.general.string(forType: .string)
        XCTAssertTrue(copied?.contains("let answer = \"ready\"") == true)
        XCTAssertTrue(copied?.contains("print(answer)") == true)
    }

    @MainActor
    func testMultipleCodeBlockCopyButtonsDoNotOverwriteExclusionRegions() throws {
        StructuredText.CodeBlockProxy.interactiveExclusionRects.removeAll()
        let markdown = MarkdownTextView(
            content: """
            ```swift
            let first = 1
            ```

            ```python
            second = 2
            ```
            """
        )
        let hosting = NSHostingView(rootView: AnyView(markdown.frame(width: 520, height: 360)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let buttons = descendants(of: hosting)
            .compactMap { $0 as? NSButton }
            .sorted { $0.convert($0.bounds, to: hosting).minY < $1.convert($1.bounds, to: hosting).minY }
        XCTAssertEqual(buttons.count, 2)

        let expectedFragments = ["let first = 1", "second = 2"]
        for (index, button) in buttons.enumerated() {
            let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
            let hit = window.contentView?.hitTest(button.convert(center, to: nil))
            XCTAssertTrue(hit === button)

            NSPasteboard.general.clearContents()
            button.performClick(nil)
            let copied = NSPasteboard.general.string(forType: .string)
            XCTAssertTrue(copied?.contains(expectedFragments[index]) == true)
        }
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        var result: [NSView] = [root]
        for child in root.subviews {
            result.append(contentsOf: descendants(of: child))
        }
        return result
    }
}
