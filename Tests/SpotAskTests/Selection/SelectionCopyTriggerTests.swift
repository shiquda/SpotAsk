import ApplicationServices
import Foundation
import Testing
@testable import SpotAsk

@Suite("Selection copy triggers")
struct SelectionCopyTriggerTests {
    private let source = SelectionSourceApplication(
        processIdentifier: 42,
        bundleIdentifier: "org.zotero.zotero",
        localizedName: "Zotero"
    )

    @Test("The plain Copy menu item is pressed, not a modified one")
    func pressesPlainCommandCopyItem() throws {
        let tree = MenuTree()
        let appMenu = tree.addItem(character: "m", modifiers: 0)
        let copySpecial = tree.addItem(character: "c", modifiers: 1)
        let copy = tree.addItem(character: "c", modifiers: 0)
        let paste = tree.addItem(character: "v", modifiers: 0)
        tree.menuBar = tree.makeMenuBar(items: [tree.makeMenu(items: [appMenu])!, tree.makeMenu(items: [copySpecial, copy, paste])!])
        let performer = FakeActionPerformer()

        try AccessibilityMenuCopyTrigger(elementReader: tree, actionPerformer: performer).triggerCopy(from: source)

        #expect(performer.pressedElements == [copy])
        #expect(performer.pressedActions == [kAXPressAction as String])
    }

    @Test("A menu bar without a plain Copy item reports the fallback path")
    func reportsMissingCopyItem() {
        let tree = MenuTree()
        let paste = tree.addItem(character: "v", modifiers: 0)
        let copySpecial = tree.addItem(character: "c", modifiers: 1)
        tree.menuBar = tree.makeMenuBar(items: [tree.makeMenu(items: [paste, copySpecial])!])
        let performer = FakeActionPerformer()

        #expect(throws: SelectionCopyError.menuItemUnavailable) {
            try AccessibilityMenuCopyTrigger(elementReader: tree, actionPerformer: performer).triggerCopy(from: source)
        }
        #expect(performer.pressedElements.isEmpty)
    }

    @Test("An app that exposes no menu bar reports the fallback path")
    func reportsMissingMenuBar() {
        let tree = MenuTree()

        #expect(throws: SelectionCopyError.menuItemUnavailable) {
            try AccessibilityMenuCopyTrigger(elementReader: tree, actionPerformer: FakeActionPerformer()).triggerCopy(from: source)
        }
    }

    @Test("A localized Copy item is found by its key equivalent, not its title")
    func findsCopyItemByKeyEquivalent() throws {
        let tree = MenuTree()
        let copy = tree.addItem(character: "C", modifiers: 0)
        tree.menuBar = tree.makeMenuBar(items: [tree.makeMenu(items: [copy])!])
        let performer = FakeActionPerformer()

        try AccessibilityMenuCopyTrigger(elementReader: tree, actionPerformer: performer).triggerCopy(from: source)

        #expect(performer.pressedElements == [copy])
    }
}

/// Builds a menu bar as application -> menu bar -> menus -> items, the shape
/// Accessibility reports for a real app.
private final class MenuTree: AccessibilityElementReading, @unchecked Sendable {
    private var nextRawValue: UInt64 = 1
    private var childElements: [AccessibilityElementID: [AccessibilityElementID]] = [:]
    private var keyEquivalents: [AccessibilityElementID: (character: String, modifiers: Int)] = [:]
    private(set) var applicationElement = AccessibilityElementID(rawValue: 1)

    var menuBar: AccessibilityElementID?

    func addItem(character: String, modifiers: Int) -> AccessibilityElementID {
        let element = makeElement()
        keyEquivalents[element] = (character, modifiers)
        return element
    }

    func makeMenu(items: [AccessibilityElementID]) -> AccessibilityElementID? {
        let menu = makeElement()
        childElements[menu] = items
        return menu
    }

    func makeMenuBar(items: [AccessibilityElementID]) -> AccessibilityElementID {
        let menuBar = makeElement()
        childElements[menuBar] = items
        return menuBar
    }

    private func makeElement() -> AccessibilityElementID {
        defer { nextRawValue += 1 }
        return AccessibilityElementID(rawValue: nextRawValue + 100)
    }

    func makeApplicationElement(processIdentifier _: pid_t) throws -> AccessibilityElementID {
        applicationElement
    }

    func makeSystemWideElement() throws -> AccessibilityElementID {
        applicationElement
    }

    func setMessagingTimeout(_: TimeInterval, for _: AccessibilityElementID) throws {}

    func copyAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> AccessibilityValue {
        switch attribute {
        case kAXMenuBarAttribute as String:
            guard let menuBar else { throw AccessibilityAdapterError.ax(.noValue) }
            return .element(menuBar)
        case kAXChildrenAttribute as String:
            guard let children = childElements[element] else { throw AccessibilityAdapterError.ax(.noValue) }
            return .elements(children)
        case kAXMenuItemCmdCharAttribute as String:
            guard let equivalent = keyEquivalents[element] else { throw AccessibilityAdapterError.ax(.attributeUnsupported) }
            return .string(equivalent.character)
        case kAXMenuItemCmdModifiersAttribute as String:
            guard let equivalent = keyEquivalents[element] else { throw AccessibilityAdapterError.ax(.attributeUnsupported) }
            return .number(equivalent.modifiers)
        default:
            throw AccessibilityAdapterError.ax(.attributeUnsupported)
        }
    }

    func copyParameterizedAttribute(
        _: String,
        parameter _: AccessibilityValue,
        from _: AccessibilityElementID
    ) throws -> AccessibilityValue {
        throw AccessibilityAdapterError.ax(.parameterizedAttributeUnsupported)
    }
}

private final class FakeActionPerformer: AccessibilityElementActionPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [String] = []
    private var elements: [AccessibilityElementID] = []

    var pressedActions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return actions
    }

    var pressedElements: [AccessibilityElementID] {
        lock.lock()
        defer { lock.unlock() }
        return elements
    }

    func performAction(_ action: String, on element: AccessibilityElementID) throws {
        lock.lock()
        actions.append(action)
        elements.append(element)
        lock.unlock()
    }
}
