import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("In-app shortcuts")
@MainActor
struct InAppShortcutTests {
    @Test("Existing command shortcuts remain stable for migrated settings")
    func stableDefaults() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        #expect(fixture.settings.shortcut(for: .operation(.focusInput)) == .command("l"))
        #expect(fixture.settings.shortcut(for: .operation(.regenerateOrRetry)) == .command("r"))
        #expect(fixture.settings.shortcut(for: .operation(.copyAnswer)) == .commandShift("c"))
        #expect(fixture.settings.shortcut(for: .operation(.showSettings)) == .command(","))
        #expect(fixture.settings.shortcut(for: .operation(.newConversation)) == .command("n"))
        #expect(fixture.settings.shortcut(for: .operation(.toggleWindowOnTop)) == nil)
        #expect(fixture.settings.shortcut(for: .operation(.sendOrCancel)) == nil)
        #expect(fixture.defaults.data(forKey: "inAppShortcutConfiguration") == nil)
    }

    @Test("Built-in and custom prompt mappings follow their stable order")
    func promptMappingsAndCustomOrdering() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let custom = (1 ... 6).map {
            PromptPreset(title: "Custom \($0)", instruction: "Instruction \($0)")
        }
        for preset in custom {
            #expect(fixture.settings.saveCustomPromptPreset(preset))
        }

        for (index, preset) in PromptPreset.builtIn.enumerated() {
            #expect(fixture.settings.shortcut(for: .promptPreset(preset.id)) == .command("\(index + 1)"))
        }
        for (index, preset) in custom.enumerated() {
            let expected = index < 5 ? InAppShortcut.command("\(index + 5)") : nil
            #expect(fixture.settings.shortcut(for: .promptPreset(preset.id)) == expected)
        }
        #expect(fixture.settings.shortcutTarget(for: .command("7")) == .promptPreset(custom[2].id))
    }

    @Test("Assignments persist, reject conflicts, and can be reset or removed")
    func persistenceValidationAndReset() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let target = InAppShortcutTarget.operation(.toggleWindowOnTop)
        let sendTarget = InAppShortcutTarget.operation(.sendOrCancel)
        let copyTarget = InAppShortcutTarget.operation(.copyAnswer)

        #expect(fixture.settings.assignShortcut(.command("l"), to: .operation(.focusInput)) == nil)
        #expect(fixture.settings.shortcut(for: .operation(.focusInput)) == .command("l"))
        #expect(fixture.settings.assignShortcut(InAppShortcut(key: "t", modifiers: .option), to: target) == nil)
        #expect(fixture.settings.assignShortcut(InAppShortcut(key: "k", modifiers: .control), to: sendTarget) == nil)
        #expect(fixture.settings.assignShortcut(InAppShortcut(key: "y", modifiers: .shift), to: copyTarget) == nil)
        let reloaded = AppSettings(defaults: fixture.defaults)
        #expect(reloaded.shortcut(for: target) == InAppShortcut(key: "t", modifiers: .option))
        #expect(reloaded.shortcut(for: sendTarget) == InAppShortcut(key: "k", modifiers: .control))
        #expect(reloaded.shortcut(for: copyTarget) == InAppShortcut(key: "y", modifiers: .shift))
        #expect(
            fixture.settings.assignShortcut(InAppShortcut(key: "t", modifiers: .option), to: sendTarget) ==
                .duplicateShortcut(target)
        )
        #expect(
            fixture.settings.assignShortcut(InAppShortcut(key: "return"), to: .operation(.sendOrCancel)) ==
                .unsupportedShortcut
        )
        #expect(
            fixture.settings.assignShortcut(InAppShortcut(key: "", modifiers: .command), to: .operation(.sendOrCancel)) ==
                .unsupportedShortcut
        )

        #expect(fixture.settings.removeShortcut(for: .operation(.focusInput)) == nil)
        #expect(fixture.settings.shortcut(for: .operation(.focusInput)) == nil)
        #expect(fixture.settings.resetShortcut(for: .operation(.focusInput)) == nil)
        #expect(fixture.settings.shortcut(for: .operation(.focusInput)) == .command("l"))
        fixture.settings.resetAllShortcuts()
        #expect(fixture.settings.shortcut(for: target) == nil)
        #expect(fixture.settings.shortcut(for: .operation(.focusInput)) == .command("l"))
    }

    @Test("Deleting a custom prompt removes its persisted assignment")
    func staleCustomPromptAssignmentsAreCleanedUp() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let preset = PromptPreset(title: "Custom", instruction: "Instruction")
        #expect(fixture.settings.saveCustomPromptPreset(preset))
        let target = InAppShortcutTarget.promptPreset(preset.id)

        #expect(fixture.settings.assignShortcut(.command("z"), to: target) == nil)
        fixture.settings.deleteCustomPromptPreset(id: preset.id)

        let reloaded = AppSettings(defaults: fixture.defaults)
        #expect(reloaded.shortcut(for: target) == nil)
        #expect(!reloaded.shortcutAssignments.contains { $0.target == target })
    }

    @Test("Disabling a prompt removes its shortcut from every resolution path")
    func disabledPromptShortcutsAreCleanedUp() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let preset = PromptPreset.builtIn[0]
        let target = InAppShortcutTarget.promptPreset(preset.id)

        #expect(fixture.settings.assignShortcut(.command("z"), to: target) == nil)
        #expect(fixture.settings.shortcutTarget(for: .command("z")) == target)
        fixture.settings.setPromptPresetEnabled(id: preset.id, isEnabled: false)

        #expect(fixture.settings.shortcut(for: target) == nil)
        #expect(fixture.settings.shortcutTarget(for: .command("z")) == nil)
        let reloaded = AppSettings(defaults: fixture.defaults)
        #expect(reloaded.shortcut(for: target) == nil)
        #expect(!reloaded.shortcutAssignments.contains { $0.target == target })
    }

    @Test("Dispatcher resolves current assignments and leaves unavailable events alone")
    func dispatcherResolvesDynamicallyWithoutConsumingUnavailableEvents() throws {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let sendTarget = InAppShortcutTarget.operation(.sendOrCancel)
        #expect(fixture.settings.assignShortcut(.command("z"), to: sendTarget) == nil)

        var handledTargets: [InAppShortcutTarget] = []
        var hintsVisible = false
        let dispatcher = InAppShortcutDispatcher(
            settings: fixture.settings,
            isForeground: { true },
            hasMarkedText: { false },
            handleTarget: { target in
                handledTargets.append(target)
                return target == sendTarget
            },
            setHintsVisible: { hintsVisible = $0 }
        )
        let remappedEvent = try #require(keyEvent(key: "z", keyCode: 6))
        #expect(dispatcher.process(remappedEvent) == nil)
        #expect(handledTargets == [sendTarget])

        let unavailableEvent = try #require(keyEvent(key: "l", keyCode: 37))
        let unchanged = dispatcher.process(unavailableEvent)
        #expect(unchanged === unavailableEvent)

        let commandDown = try #require(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 55
        ))
        #expect(dispatcher.process(commandDown) === commandDown)
        #expect(hintsVisible)
    }

    @Test("Dispatcher preserves marked text events")
    func dispatcherPreservesMarkedText() throws {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        var handled = false
        let dispatcher = InAppShortcutDispatcher(
            settings: fixture.settings,
            isForeground: { true },
            hasMarkedText: { true },
            handleTarget: { _ in
                handled = true
                return true
            },
            setHintsVisible: { _ in }
        )
        let event = try #require(keyEvent(key: "l", keyCode: 37))
        #expect(dispatcher.process(event) === event)
        #expect(!handled)
    }

    @Test("Command-held hints include non-Command assignments")
    func commandHeldHintsIncludeAllConfiguredModifiers() {
        let optionShortcut = InAppShortcut(key: "t", modifiers: .option)
        let controlShortcut = InAppShortcut(key: "k", modifiers: .control)
        let shiftShortcut = InAppShortcut(key: "y", modifiers: .shift)

        #expect(inAppShortcutHint(optionShortcut, commandHintsVisible: true) == optionShortcut)
        #expect(inAppShortcutHint(controlShortcut, commandHintsVisible: true) == controlShortcut)
        #expect(inAppShortcutHint(shiftShortcut, commandHintsVisible: true) == shiftShortcut)
        #expect(inAppShortcutHint(optionShortcut, commandHintsVisible: false) == nil)
    }

    @Test("Shortcut labels use standard macOS modifier symbols")
    func shortcutLabelsUseStandardModifierSymbols() {
        let shortcut = InAppShortcut(key: "k", modifiers: [.command, .shift, .option, .control])
        #expect(InAppShortcutDisplay.labels(for: shortcut) == ["⌘", "⇧", "⌥", "⌃", "K"])
        #expect(InAppShortcutDisplay.labels(for: shortcut, includeCommand: false) == ["⇧", "⌥", "⌃", "K"])
    }

    @Test("Recorder captures only in its active key window")
    func recorderCaptureEligibilityRequiresActiveKeyWindow() {
        #expect(ShortcutRecorderCaptureEligibility.shouldCapture(
            isRecorderWindowKey: true,
            isActiveWindowRecorderWindow: true,
            isRecorderFirstResponder: true
        ))
        #expect(!ShortcutRecorderCaptureEligibility.shouldCapture(
            isRecorderWindowKey: false,
            isActiveWindowRecorderWindow: true,
            isRecorderFirstResponder: true
        ))
        #expect(!ShortcutRecorderCaptureEligibility.shouldCapture(
            isRecorderWindowKey: true,
            isActiveWindowRecorderWindow: false,
            isRecorderFirstResponder: true
        ))
        #expect(!ShortcutRecorderCaptureEligibility.shouldCapture(
            isRecorderWindowKey: true,
            isActiveWindowRecorderWindow: true,
            isRecorderFirstResponder: false
        ))
    }

    private func keyEvent(key: String, keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func makeSettings() -> (settings: AppSettings, defaults: UserDefaults, suiteName: String) {
        let suiteName = "InAppShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppSettings(defaults: defaults), defaults, suiteName)
    }
}
