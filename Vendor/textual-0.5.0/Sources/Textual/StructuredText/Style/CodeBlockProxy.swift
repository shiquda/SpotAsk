import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension StructuredText {
  /// A proxy for a rendered code block that custom code block styles can use.
  public struct CodeBlockProxy {
    @MainActor public static var interactiveExclusionRects: [UUID: CGRect] = [:]

    private let content: AttributedSubstring

    internal init(_ content: AttributedSubstring) {
      self.content = content
    }

    @MainActor public func registerInteractiveExclusionRect(id: UUID, rect: CGRect) {
      Self.interactiveExclusionRects[id] = rect
    }

    @MainActor public func unregisterInteractiveExclusionRect(id: UUID) {
      Self.interactiveExclusionRects[id] = nil
    }

    /// Copies the code block contents to the system pasteboard.
    ///
    /// Textual writes both a plain-text and an HTML representation when possible.
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public func copyToPasteboard() {
      #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let formatter = Formatter(AttributedString(content))
        pasteboard.setString(formatter.plainText(), forType: .string)
        pasteboard.setString(formatter.html(), forType: .html)
      #elseif TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
        let formatter = Formatter(AttributedString(content))
        UIPasteboard.general.setItems(
          [
            [
              UTType.plainText.identifier: formatter.plainText(),
              UTType.html.identifier: formatter.html(),
            ]
          ]
        )
      #endif
    }
  }
}
