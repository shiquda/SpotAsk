import ApplicationServices
import Foundation

enum SelectionCopyError: Error, Equatable {
    case menuItemUnavailable
    case eventUnavailable
}

/// Asks the app that owns the selection to run its own Copy command, so the
/// app's own selection handling produces the pasteboard contents.
protocol SelectionCopyTriggering: Sendable {
    func triggerCopy(from source: SelectionSourceApplication) throws
}

/// Presses the Edit > Copy menu item through Accessibility, then falls back to
/// a synthesized ⌘C when the app exposes no pressable menu item. The menu path
/// is preferred because it neither synthesizes key events nor disturbs the
/// user's modifier state.
struct DefaultSelectionCopyTrigger: SelectionCopyTriggering {
    private let menuTrigger: AccessibilityMenuCopyTrigger
    private let keyTrigger: KeyCommandSelectionCopyTrigger

    init(
        menuTrigger: AccessibilityMenuCopyTrigger = AccessibilityMenuCopyTrigger(),
        keyTrigger: KeyCommandSelectionCopyTrigger = KeyCommandSelectionCopyTrigger()
    ) {
        self.menuTrigger = menuTrigger
        self.keyTrigger = keyTrigger
    }

    func triggerCopy(from source: SelectionSourceApplication) throws {
        if (try? menuTrigger.triggerCopy(from: source)) != nil { return }
        try keyTrigger.triggerCopy(from: source)
    }
}

final class AccessibilityMenuCopyTrigger: SelectionCopyTriggering, @unchecked Sendable {
    private static let messagingTimeout: TimeInterval = 1
    private static let maximumDepth = 6
    private static let nodeBudget = 600
    private static let copyKeyCharacter = "c"
    /// `kAXMenuItemCmdModifiersAttribute` reports the non-Command modifiers as
    /// a bit mask, so a plain ⌘C item carries no bits.
    private static let noExtraModifiers = 0

    private let elementReader: any AccessibilityElementReading
    private let actionPerformer: any AccessibilityElementActionPerforming

    init(
        elementReader: any AccessibilityElementReading = MacOSAccessibilityElementAdapter(),
        actionPerformer: any AccessibilityElementActionPerforming = MacOSAccessibilityElementAdapter()
    ) {
        self.elementReader = elementReader
        self.actionPerformer = actionPerformer
    }

    func triggerCopy(from source: SelectionSourceApplication) throws {
        guard let copyItem = copyMenuItem(for: source) else {
            throw SelectionCopyError.menuItemUnavailable
        }
        try actionPerformer.performAction(kAXPressAction as String, on: copyItem)
    }

    /// Walks the menu bar for the first item whose key equivalent is a plain
    /// ⌘C. Matching the key equivalent instead of the title keeps this
    /// independent of the app's interface language.
    private func copyMenuItem(for source: SelectionSourceApplication) -> AccessibilityElementID? {
        guard let application = try? elementReader.makeApplicationElement(processIdentifier: source.processIdentifier),
              (try? elementReader.setMessagingTimeout(Self.messagingTimeout, for: application)) != nil,
              let menuBar = menuBarElement(of: application) else {
            return nil
        }
        var budget = Self.nodeBudget
        return copyMenuItem(in: menuBar, depth: 0, budget: &budget)
    }

    private func menuBarElement(of application: AccessibilityElementID) -> AccessibilityElementID? {
        guard let value = try? elementReader.copyAttribute(kAXMenuBarAttribute as String, from: application),
              case let .element(menuBar) = value else {
            return nil
        }
        return menuBar
    }

    private func copyMenuItem(
        in element: AccessibilityElementID,
        depth: Int,
        budget: inout Int
    ) -> AccessibilityElementID? {
        guard depth <= Self.maximumDepth, budget > 0 else { return nil }
        budget -= 1
        if isPlainCommandCopy(element) { return element }
        for child in childElements(of: element) {
            if let match = copyMenuItem(in: child, depth: depth + 1, budget: &budget) { return match }
        }
        return nil
    }

    private func isPlainCommandCopy(_ element: AccessibilityElementID) -> Bool {
        guard let character = stringAttribute(kAXMenuItemCmdCharAttribute as String, for: element),
              character.caseInsensitiveCompare(Self.copyKeyCharacter) == .orderedSame,
              let modifiers = numberAttribute(kAXMenuItemCmdModifiersAttribute as String, for: element) else {
            return false
        }
        return modifiers == Self.noExtraModifiers
    }

    private func childElements(of element: AccessibilityElementID) -> [AccessibilityElementID] {
        guard let value = try? elementReader.copyAttribute(kAXChildrenAttribute as String, from: element),
              case let .elements(children) = value else {
            return []
        }
        return children
    }

    private func stringAttribute(_ attribute: String, for element: AccessibilityElementID) -> String? {
        guard let value = try? elementReader.copyAttribute(attribute, from: element),
              case let .string(string) = value else {
            return nil
        }
        return string
    }

    private func numberAttribute(_ attribute: String, for element: AccessibilityElementID) -> Int? {
        guard let value = try? elementReader.copyAttribute(attribute, from: element),
              case let .number(number) = value else {
            return nil
        }
        return number
    }
}

/// Synthesizes ⌘C directly. Used only when the app exposes no copy menu item,
/// and posted to the target process so the keys cannot leak into another app.
struct KeyCommandSelectionCopyTrigger: SelectionCopyTriggering {
    private static let copyKeyCode: CGKeyCode = 8

    func triggerCopy(from source: SelectionSourceApplication) throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.copyKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.copyKeyCode, keyDown: false) else {
            throw SelectionCopyError.eventUnavailable
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(source.processIdentifier)
        keyUp.postToPid(source.processIdentifier)
    }
}
