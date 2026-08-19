import AppKit
import SwiftUI

/// A reasoning transcript owns its own follow preference, so reading earlier
/// reasoning never changes the user's position in the conversation.
struct ReasoningContentView: View {
    let reasoning: String

    var body: some View {
        ReasoningTextView(content: reasoning)
            .frame(height: 240)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ReasoningTextView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .caption1)
        textView.textColor = .secondaryLabelColor
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = content
        textView.setAccessibilityLabel(L10n.string("chat.reasoning"))

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        DispatchQueue.main.async {
            textView.scrollToEndOfDocument(nil)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = textView.textStorage else { return }

        let followsLatest = Self.isNearBottom(scrollView) || textStorage.length == 0
        switch ReasoningTextUpdate.change(from: textView.string, to: content) {
        case .unchanged:
            return
        case let .append(suffix):
            textStorage.append(NSAttributedString(string: suffix, attributes: Self.attributes))
        case let .replace(replacement):
            let selectedRange = textView.selectedRange()
            textStorage.setAttributedString(NSAttributedString(string: replacement, attributes: Self.attributes))
            let length = (replacement as NSString).length
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, length), length: 0))
        }

        guard followsLatest else { return }
        textView.scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
    }

    private static var attributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    private static func isNearBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        return scrollView.contentView.bounds.maxY >= documentView.bounds.height - 12
    }
}
