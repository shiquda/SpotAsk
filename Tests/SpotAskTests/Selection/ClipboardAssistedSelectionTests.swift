import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import SpotAsk

@Suite("Clipboard-assisted selection settings policy")
struct UserDefaultsClipboardAssistedSelectionPolicyTests {
    @Test("The policy stays off until the setting and the app are both set")
    func requiresBothTheSettingAndAListedApp() {
        let suite = "ClipboardAssistedSelectionPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = UserDefaultsClipboardAssistedSelectionPolicy(defaults: defaults)
        let zotero = SelectionSourceApplication(
            processIdentifier: 42,
            bundleIdentifier: "org.zotero.zotero",
            localizedName: "Zotero"
        )

        #expect(!policy.isEnabled(for: zotero))

        defaults.set(true, forKey: ClipboardAssistedSelectionDefaults.enabledKey)
        #expect(!policy.isEnabled(for: zotero))

        defaults.set(
            ["org.zotero.zotero"],
            forKey: ClipboardAssistedSelectionDefaults.appIdentifiersKey
        )
        #expect(policy.isEnabled(for: zotero))
        #expect(!policy.isEnabled(for: SelectionSourceApplication(
            processIdentifier: 43,
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari"
        )))
        #expect(!policy.isEnabled(for: nil))
    }

    @Test("An app without a bundle identifier is matched by its name")
    func fallsBackToTheApplicationName() {
        let suite = "ClipboardAssistedSelectionPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ClipboardAssistedSelectionDefaults.enabledKey)
        defaults.set(["Zotero"], forKey: ClipboardAssistedSelectionDefaults.appIdentifiersKey)

        let policy = UserDefaultsClipboardAssistedSelectionPolicy(defaults: defaults)

        #expect(policy.isEnabled(for: SelectionSourceApplication(
            processIdentifier: 42,
            bundleIdentifier: nil,
            localizedName: "Zotero"
        )))
    }
}

@Suite("Copy command triggering")
struct SelectionCopyTriggerTests {
    @Test("The ⌘C menu item is pressed, not the localized Copy title")
    func pressesTheCommandCMenuItem() {
        let fixture = CopyMenuFixture()
        fixture.setUpMenuBar()
        let trigger = fixture.makeTrigger()

        trigger.triggerCopy(in: fixture.applicationElement)

        #expect(fixture.actions.performed == [.init(action: kAXPressAction as String, element: fixture.copyItem)])
        #expect(fixture.keyEventSender.copyShortcutCount == 0)
    }

    @Test("An app without a pressable Copy menu item falls back to a synthetic ⌘C")
    func fallsBackToTheKeyboardShortcut() {
        let withoutMenuBar = CopyMenuFixture()
        withoutMenuBar.makeTrigger().triggerCopy(in: withoutMenuBar.applicationElement)

        let failingPress = CopyMenuFixture()
        failingPress.setUpMenuBar()
        failingPress.actions.error = AccessibilityAdapterError.ax(.actionUnsupported)
        failingPress.makeTrigger().triggerCopy(in: failingPress.applicationElement)

        let withoutCopyItem = CopyMenuFixture()
        withoutCopyItem.setUpMenuBar(includingCopyItem: false)
        withoutCopyItem.makeTrigger().triggerCopy(in: withoutCopyItem.applicationElement)

        #expect(withoutMenuBar.keyEventSender.copyShortcutCount == 1)
        #expect(failingPress.keyEventSender.copyShortcutCount == 1)
        #expect(withoutCopyItem.keyEventSender.copyShortcutCount == 1)
    }

    private final class CopyMenuFixture {
        let applicationElement = AccessibilityElementID(rawValue: 100)
        let elementReader = FakeAccessibilityElementReader()
        let actions = FakeAccessibilityActionPerformer()
        let keyEventSender = FakeCommandKeyEventSender()

        private let menuBar = AccessibilityElementID(rawValue: 200)
        private let barItem = AccessibilityElementID(rawValue: 300)
        private let menu = AccessibilityElementID(rawValue: 400)
        private let cutItem = AccessibilityElementID(rawValue: 401)
        let copyItem = AccessibilityElementID(rawValue: 402)
        private let copyPathItem = AccessibilityElementID(rawValue: 403)

        init() {
            elementReader.set(.element(menuBar), attribute: kAXMenuBarAttribute as String, element: applicationElement)
            elementReader.set(.elements([barItem]), attribute: kAXChildrenAttribute as String, element: menuBar)
            elementReader.set(.elements([menu]), attribute: kAXChildrenAttribute as String, element: barItem)
            elementReader.set(
                .string("X"),
                attribute: kAXMenuItemCmdCharAttribute as String,
                element: cutItem
            )
            elementReader.set(
                .number(0),
                attribute: kAXMenuItemCmdModifiersAttribute as String,
                element: cutItem
            )
            elementReader.set(
                .string("C"),
                attribute: kAXMenuItemCmdCharAttribute as String,
                element: copyItem
            )
            elementReader.set(
                .number(0),
                attribute: kAXMenuItemCmdModifiersAttribute as String,
                element: copyItem
            )
            elementReader.set(
                .string("C"),
                attribute: kAXMenuItemCmdCharAttribute as String,
                element: copyPathItem
            )
            elementReader.set(
                .number(2),
                attribute: kAXMenuItemCmdModifiersAttribute as String,
                element: copyPathItem
            )
        }

        /// Menu items are published without opening the menu, which is how the
        /// trigger finds them: a ⌘C character plus no extra modifier bits.
        func setUpMenuBar(includingCopyItem: Bool = true) {
            var items = [cutItem]
            if includingCopyItem {
                items.append(copyItem)
            }
            items.append(copyPathItem)
            elementReader.set(.elements(items), attribute: kAXChildrenAttribute as String, element: menu)
        }

        func makeTrigger() -> MacOSSelectionCopyTrigger {
            MacOSSelectionCopyTrigger(
                reader: elementReader,
                actions: actions,
                keyEventSender: keyEventSender
            )
        }
    }
}

private final class FakeAccessibilityActionPerformer: AccessibilityElementActionPerforming, @unchecked Sendable {
    struct Call: Equatable {
        let action: String
        let element: AccessibilityElementID
    }

    private let lock = NSLock()
    private var calls: [Call] = []
    var error: AccessibilityAdapterError?

    var performed: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func performAction(_ action: String, on element: AccessibilityElementID) throws {
        lock.lock()
        calls.append(Call(action: action, element: element))
        let error = error
        lock.unlock()
        if let error {
            throw error
        }
    }
}

private final class FakeCommandKeyEventSender: CommandKeyEventSending, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var copyShortcutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func sendCopyShortcut() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
