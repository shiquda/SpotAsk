import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Decides whether reading a selection from the given app must go through that
/// app's own Copy command. Implementations are asked on the selection reader's
/// serial queue, never on the main actor.
protocol ClipboardAssistedSelectionPolicy: Sendable {
    func isEnabled(for source: SelectionSourceApplication?) -> Bool
}

/// Reads the settings keys straight from `UserDefaults`: `AppSettings` is main
/// actor-isolated, while the selection reader resolves the foreground app and
/// reads the pasteboard on a background queue. The keys are owned by
/// `AppSettings`, so both sides always agree on the stored names.
/// `UserDefaults` is thread-safe but not annotated `Sendable`.
struct UserDefaultsClipboardAssistedSelectionPolicy: ClipboardAssistedSelectionPolicy, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(for source: SelectionSourceApplication?) -> Bool {
        guard defaults.bool(forKey: ClipboardAssistedSelectionDefaults.enabledKey) else { return false }
        guard let identifier = source?.bundleIdentifier ?? source?.localizedName, !identifier.isEmpty else {
            return false
        }
        let identifiers = defaults.stringArray(forKey: ClipboardAssistedSelectionDefaults.appIdentifiersKey) ?? []
        return identifiers.contains(identifier)
    }
}

/// Runs the source app's own Copy command. The app's native copy path is the
/// only one that produces correctly aligned text for PDF.js-style text layers,
/// where the accessibility tree reports shifted offsets and drops spaces.
protocol SelectionCopyTriggering: Sendable {
    func triggerCopy(in application: AccessibilityElementID)
}

/// Presses the app's Copy menu item through Accessibility, and falls back to a
/// synthetic ⌘C when the app exposes no pressable menu item.
struct MacOSSelectionCopyTrigger: SelectionCopyTriggering {
    private static let menuBarItemLimit = 40
    private static let menuItemLimit = 400

    private let reader: any AccessibilityElementReading
    private let actions: any AccessibilityElementActionPerforming
    private let keyEventSender: any CommandKeyEventSending

    init(
        reader: any AccessibilityElementReading = MacOSAccessibilityElementAdapter(),
        actions: any AccessibilityElementActionPerforming = MacOSAccessibilityElementAdapter(),
        keyEventSender: any CommandKeyEventSending = MacOSCommandKeyEventSender()
    ) {
        self.reader = reader
        self.actions = actions
        self.keyEventSender = keyEventSender
    }

    func triggerCopy(in application: AccessibilityElementID) {
        if pressCopyMenuItem(in: application) { return }
        keyEventSender.sendCopyShortcut()
    }

    /// Walks the app's menu bar and presses the item whose shortcut is exactly
    /// ⌘C. Menu titles are localized and therefore not matched; the command
    /// character plus an empty modifier set identifies Copy in any language.
    private func pressCopyMenuItem(in application: AccessibilityElementID) -> Bool {
        guard let menuBar = elementAttribute(kAXMenuBarAttribute as String, from: application),
              let menuBarItems = elementsAttribute(kAXChildrenAttribute as String, from: menuBar) else {
            return false
        }
        var visited = 0
        for menuBarItem in menuBarItems.prefix(Self.menuBarItemLimit) {
            guard let menus = elementsAttribute(kAXChildrenAttribute as String, from: menuBarItem) else { continue }
            for menu in menus {
                guard let menuItems = elementsAttribute(kAXChildrenAttribute as String, from: menu) else { continue }
                for menuItem in menuItems {
                    visited += 1
                    guard visited <= Self.menuItemLimit else { return false }
                    guard isCopyCommand(menuItem) else { continue }
                    do {
                        try actions.performAction(kAXPressAction as String, on: menuItem)
                        return true
                    } catch {
                        SafeLogger.selectionReadProgress("clipboard-assisted-copy-menu-unavailable")
                        return false
                    }
                }
            }
        }
        return false
    }

    private func isCopyCommand(_ element: AccessibilityElementID) -> Bool {
        guard let characterValue = try? reader.copyAttribute(kAXMenuItemCmdCharAttribute as String, from: element),
              case let .string(character) = characterValue,
              character.caseInsensitiveCompare("c") == .orderedSame else {
            return false
        }
        guard let modifiersValue = try? reader.copyAttribute(kAXMenuItemCmdModifiersAttribute as String, from: element),
              case let .number(modifiers) = modifiersValue else {
            return false
        }
        // Command is implied by a menu shortcut, so ⌘C carries no modifier bits
        // while ⇧⌘C, ⌥⌘C, and ⌃⌘C set their own.
        return modifiers == 0
    }

    private func elementAttribute(_ attribute: String, from element: AccessibilityElementID) -> AccessibilityElementID? {
        guard let value = try? reader.copyAttribute(attribute, from: element),
              case let .element(child) = value else {
            return nil
        }
        return child
    }

    private func elementsAttribute(_ attribute: String, from element: AccessibilityElementID) -> [AccessibilityElementID]? {
        guard let value = try? reader.copyAttribute(attribute, from: element),
              case let .elements(children) = value else {
            return nil
        }
        return children
    }
}

protocol CommandKeyEventSending: Sendable {
    func sendCopyShortcut()
}

/// Posts a synthetic ⌘C to the frontmost app. This is the documented fallback
/// for apps that do not expose a pressable Copy menu item.
struct MacOSCommandKeyEventSender: CommandKeyEventSending {
    func sendCopyShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        keyUp.post(tap: .cghidEventTap)
    }
}
