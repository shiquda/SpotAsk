import AppKit
import SwiftUI

/// An AppKit editor gives us the marked-text signal required to avoid sending
/// while a Chinese, Japanese, or Korean input method is choosing a candidate.
struct ChatInputTextView: NSViewRepresentable {
    /// Fits one line of body text including the editor's insets.
    static let minHeight: CGFloat = 40
    /// Fits roughly six lines; the editor scrolls internally beyond that.
    static let maxHeight: CGFloat = 132

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var height: CGFloat
    let isGenerating: Bool
    let onSubmit: () -> Bool
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
        textView.onSubmit = { [weak coordinator = context.coordinator] textView in
            MainActor.assumeIsolated {
                coordinator?.submit(textView)
            }
        }
        textView.onEscape = onEscape
        textView.onRecall = onRecall
        textView.onLayoutPass = { [weak coordinator = context.coordinator] in
            guard let coordinator, let textView = $0 as? NSTextView else { return }
            coordinator.updateHeightIfNeeded(of: textView)
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

        let scrollView = ComposerScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.onWindowChange = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            DispatchQueue.main.async {
                coordinator.applyInitialFocusOnce(in: scrollView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = { [weak coordinator = context.coordinator] textView in
            MainActor.assumeIsolated {
                coordinator?.submit(textView)
            }
        }
        textView.onEscape = onEscape
        textView.onRecall = onRecall

        let editorOwnsDraft = ChatInputSynchronization.shouldPreserveFocusedDraft(
            isGenerating: isGenerating,
            isFirstResponder: scrollView.window?.firstResponder === textView
        )
        if textView.string != text && !editorOwnsDraft {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, (text as NSString).length), length: 0))
            context.coordinator.updateHeightIfNeeded(of: textView)
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
        private var needsInitialFocus = true
        private var lastMeasuredTextLength = 0
        private var lastMeasuredWidth: CGFloat = 0

        init(parent: ChatInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeightIfNeeded(of: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView,
                  scrollView.window?.firstResponder !== textView else { return }
            parent.isFocused = false
        }

        @MainActor
        func submit(_ textView: NSTextView) {
            guard parent.onSubmit() else { return }
            if !textView.string.isEmpty {
                textView.string = ""
                updateHeightIfNeeded(of: textView)
            }
        }

        @MainActor
        func applyInitialFocusOnce(in scrollView: NSScrollView) {
            guard needsInitialFocus,
                  let textView = scrollView.documentView as? ComposerTextView,
                  let window = scrollView.window else { return }
            if window.firstResponder === textView {
                needsInitialFocus = false
                return
            }
            guard window.makeFirstResponder(textView) else { return }
            needsInitialFocus = false
        }

        /// Grows the editor with its content between one and six lines; beyond
        /// that the enclosing scroll view takes over. Once the editor is at its
        /// max height, further typing does not need another full TextKit
        /// measurement unless the width or the text shrinks.
        @MainActor
        func updateHeightIfNeeded(of textView: NSTextView) {
            guard let textContainer = textView.textContainer else { return }
            let textLength = textView.string.count
            let width = textContainer.size.width
            let isAtMaxHeight = parent.height >= ChatInputTextView.maxHeight - 0.5
            let onlyGrewAtMaxHeight = isAtMaxHeight && textLength > lastMeasuredTextLength
            let widthUnchanged = abs(width - lastMeasuredWidth) < 0.5
            if onlyGrewAtMaxHeight, widthUnchanged {
                return
            }
            updateHeight(of: textView)
        }

        /// Grows the editor with its content between one and six lines; beyond
        /// that the enclosing scroll view takes over. Only writes back on a
        /// real change so layout never loops.
        @MainActor
        func updateHeight(of textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            lastMeasuredTextLength = textView.string.count
            lastMeasuredWidth = textContainer.size.width
            let height = min(max(contentHeight, ChatInputTextView.minHeight), ChatInputTextView.maxHeight)
            guard abs(height - parent.height) > 0.5 else { return }
            parent.height = height
        }
    }
}

enum ChatInputSynchronization {
    static func shouldPreserveFocusedDraft(isGenerating: Bool, isFirstResponder: Bool) -> Bool {
        isGenerating && isFirstResponder
    }
}

private final class ComposerScrollView: NSScrollView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}

private final class ComposerTextView: NSTextView {
    var onSubmit: ((NSTextView) -> Void)?
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
            onSubmit?(self)
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
