import AppKit
import SwiftUI

/// An AppKit editor gives us the marked-text signal required to avoid sending
/// while a Chinese, Japanese, or Korean input method is choosing a candidate.
struct ChatInputTextView: NSViewRepresentable {
    /// Fits roughly one line of body text including the editor's insets.
    static let minHeight: CGFloat = 52
    /// Fits roughly six lines; the editor scrolls internally beyond that.
    static let maxHeight: CGFloat = 120

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var height: CGFloat
    let onSubmit: () -> Void
    let onEscape: () -> Void
    /// Called when the up arrow is pressed in an empty input with no selection.
    /// Return true when a previous question was recalled.
    let onRecall: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.onRecall = onRecall
        textView.onLayoutPass = { [weak coordinator = context.coordinator] in
            guard let coordinator, let textView = $0 as? NSTextView else { return }
            coordinator.updateHeight(of: textView)
        }
        textView.string = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 9, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: Self.minHeight - 16)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(L10n.string("chat.inputAccessibility"))

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.onRecall = onRecall

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, (text as NSString).length), length: 0))
            context.coordinator.updateHeight(of: textView)
        }

        if isFocused, scrollView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                guard isFocused else { return }
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputTextView

        init(parent: ChatInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight(of: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        /// Grows the editor with its content between one and six lines; beyond
        /// that the enclosing scroll view takes over. Only writes back on a
        /// real change so layout never loops.
        @MainActor
        func updateHeight(of textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            let height = min(max(contentHeight, ChatInputTextView.minHeight), ChatInputTextView.maxHeight)
            guard abs(height - parent.height) > 0.5 else { return }
            parent.height = height
        }
    }
}

private final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onRecall: (() -> Bool)?
    var onLayoutPass: ((NSView) -> Void)?

    override func layout() {
        super.layout()
        onLayoutPass?(self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76

        if isReturn, !modifiers.contains(.shift), !hasMarkedText() {
            onSubmit?()
            return
        }
        if event.keyCode == 53, !hasMarkedText() {
            onEscape?()
            return
        }
        // Up arrow in an empty input with no selection recalls the previous
        // question; anything else keeps the default caret and IME behavior.
        // Ignore Caps Lock and friends so recall still works while they are on.
        if event.keyCode == 126,
           modifiers.intersection([.shift, .control, .option, .command]).isEmpty,
           !hasMarkedText(), string.isEmpty, selectedRange().length == 0 {
            if onRecall?() == true { return }
        }
        super.keyDown(with: event)
    }
}
