import AppKit
import SwiftUI
import XCTest
import Textual
@testable import SpotAsk

final class CodeBlockCopyButtonTests: XCTestCase {
    @MainActor
    func testCopyButtonReceivesClickPastTextSelectionOverlay() throws {
        StructuredText.CodeBlockProxy.interactiveExclusionRects.removeAll()
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let systemChangeCount = NSPasteboard.general.changeCount
        let markdown = MarkdownTextView(
            content: "```swift\nlet answer = \"ready\"\nprint(answer)\n```",
            codeBlockPasteboard: pasteboard
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
        waitForHostedCopyButtons(hosting, count: 1)

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

        button!.performClick(nil)
        let copied = pasteboard.string(forType: .string)
        XCTAssertTrue(copied?.contains("let answer = \"ready\"") == true)
        XCTAssertTrue(copied?.contains("print(answer)") == true)
        let html = pasteboard.string(forType: .html)
        XCTAssertTrue(html?.contains("<pre><code") == true)
        XCTAssertTrue(html?.contains("print(answer)") == true)
        XCTAssertEqual(
            NSPasteboard.general.changeCount,
            systemChangeCount,
            "Copying a code block must not touch the system pasteboard"
        )
    }

    @MainActor
    func testMultipleCodeBlockCopyButtonsDoNotOverwriteExclusionRegions() throws {
        StructuredText.CodeBlockProxy.interactiveExclusionRects.removeAll()
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let systemChangeCount = NSPasteboard.general.changeCount
        let markdown = MarkdownTextView(
            content: """
            ```swift
            let first = 1
            ```

            ```python
            second = 2
            ```
            """,
            codeBlockPasteboard: pasteboard
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
        waitForHostedCopyButtons(hosting, count: 2)

        let buttons = descendants(of: hosting)
            .compactMap { $0 as? NSButton }
            .sorted { $0.convert($0.bounds, to: hosting).minY < $1.convert($1.bounds, to: hosting).minY }
        XCTAssertEqual(buttons.count, 2)

        let expectedFragments = ["let first = 1", "second = 2"]
        let expectedHTMLClasses = ["language-swift", "language-python"]
        for (index, button) in buttons.enumerated() {
            let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
            let hit = window.contentView?.hitTest(button.convert(center, to: nil))
            XCTAssertTrue(hit === button)

            button.performClick(nil)
            let copied = pasteboard.string(forType: .string)
            XCTAssertTrue(copied?.contains(expectedFragments[index]) == true)
            let html = pasteboard.string(forType: .html)
            XCTAssertTrue(html?.contains(expectedHTMLClasses[index]) == true)
        }
        XCTAssertEqual(
            NSPasteboard.general.changeCount,
            systemChangeCount,
            "Copying a code block must not touch the system pasteboard"
        )
    }

    /// A private pasteboard keeps the copy flow away from the user's system clipboard.
    @MainActor
    private func makeIsolatedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("SpotAskTests.\(UUID().uuidString)"))
    }

    @MainActor
    private func waitForHostedCopyButtons(_ hosting: NSView, count: Int) {
        let deadline = Date().addingTimeInterval(0.2)
        repeat {
            hosting.window?.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            let buttons = descendants(of: hosting).compactMap { $0 as? NSButton }
            if buttons.count >= count {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        } while Date() < deadline
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
