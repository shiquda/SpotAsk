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
        #expect(fixture.settings.shortcut(for: .operation(.zoomIn)) == .command("="))
        #expect(fixture.settings.shortcut(for: .operation(.zoomOut)) == .command("-"))
        #expect(fixture.settings.shortcutTarget(for: .commandShift("=")) == .operation(.zoomIn))
        #expect(fixture.settings.shortcut(for: .operation(.toggleWindowOnTop)) == nil)
        #expect(fixture.settings.shortcut(for: .operation(.sendOrCancel)) == nil)
        #expect(fixture.defaults.data(forKey: "inAppShortcutConfiguration") == nil)
    }

    @Test("Command plus maps to zoom unless Command+Shift+= is assigned elsewhere")
    func commandPlusAliasRespectsExplicitAssignment() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let sendTarget = InAppShortcutTarget.operation(.sendOrCancel)

        #expect(fixture.settings.shortcutTarget(for: .commandShift("=")) == .operation(.zoomIn))
        #expect(fixture.settings.assignShortcut(.commandShift("="), to: sendTarget) == nil)
        #expect(fixture.settings.shortcutTarget(for: .commandShift("=")) == sendTarget)
    }

    @Test("Built-in and custom prompt mappings follow their stable order")
    func promptMappingsAndCustomOrdering() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        // Disable built-in quick actions to isolate prompt preset derived defaults testing
        fixture.settings.setQuickActionEnabled(id: QuickAction.BuiltInID.chatGPT, isEnabled: false)
        fixture.settings.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: false)

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

    @Test("Disabling a custom prompt blocks its shortcut without losing the persisted mapping")
    func disabledCustomPromptShortcutIsRestoredAfterReload() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let preset = PromptPreset(title: "Custom", instruction: "Instruction")
        #expect(fixture.settings.saveCustomPromptPreset(preset))
        let target = InAppShortcutTarget.promptPreset(preset.id)

        #expect(fixture.settings.assignShortcut(.command("z"), to: target) == nil)
        #expect(fixture.settings.shortcutTarget(for: .command("z")) == target)
        fixture.settings.setPromptPresetEnabled(id: preset.id, isEnabled: false)

        #expect(fixture.settings.shortcut(for: target) == nil)
        #expect(fixture.settings.shortcutTarget(for: .command("z")) == nil)
        let reloaded = AppSettings(defaults: fixture.defaults)
        #expect(reloaded.shortcut(for: target) == nil)
        #expect(!reloaded.shortcutAssignments.contains { $0.target == target })

        reloaded.setPromptPresetEnabled(id: preset.id, isEnabled: true)
        #expect(reloaded.shortcut(for: target) == .command("z"))
        #expect(reloaded.shortcutTarget(for: .command("z")) == target)
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
        #expect(InAppShortcutDisplay.labels(for: InAppShortcut(key: " ", modifiers: .option)) == ["⌥", "Space"])
    }

    @Test("Recorder parses supported combinations and rejects modifier-only events")
    func recorderParsesSupportedCombinations() throws {
        let commandShiftK = try #require(keyEvent(key: "K", keyCode: 40, modifiers: [.command, .shift]))
        #expect(ShortcutRecorderEventParser.shortcut(from: commandShiftK) ==
            InAppShortcut(key: "k", modifiers: [.command, .shift]))

        let commandComma = try #require(keyEvent(key: ",", keyCode: 43, modifiers: [.command]))
        #expect(ShortcutRecorderEventParser.shortcut(from: commandComma) == .command(","))

        let plainK = try #require(keyEvent(key: "k", keyCode: 40, modifiers: []))
        #expect(ShortcutRecorderEventParser.shortcut(from: plainK) == nil)

        let commandOnly = try #require(NSEvent.keyEvent(
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
        #expect(ShortcutRecorderEventParser.shortcut(from: commandOnly) == nil)
    }

    @Test("Recorder treats Escape as cancel")
    func recorderCancelsWithEscape() throws {
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        #expect(ShortcutRecorderEventParser.isCancelKey(escape))
    }

    @Test("Quick Actions receive derived defaults sequential to enabled presets")
    func quickActionDerivedDefaultsSequentialToPresets() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        // 4 built-in prompt presets are enabled by default (Command+1...4)
        // ChatGPT is enabled by default (Command+5), Grok is disabled by default (nil)
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.chatGPT)) == .command("5"))
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.grok)) == nil)
        #expect(fixture.settings.shortcutTarget(for: .command("5")) == .quickAction(QuickAction.BuiltInID.chatGPT))
        #expect(fixture.settings.shortcutTarget(for: .command("6")) == nil)

        // When Grok is enabled, it receives Command+6
        fixture.settings.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: true)
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.grok)) == .command("6"))
        #expect(fixture.settings.shortcutTarget(for: .command("6")) == .quickAction(QuickAction.BuiltInID.grok))
    }

    @Test("Quick Action reordering updates derived default shortcut numbers")
    func quickActionReorderingUpdatesDerivedDefaults() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.settings.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: true)

        // Initially: ChatGPT -> 5, Grok -> 6
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.chatGPT)) == .command("5"))
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.grok)) == .command("6"))

        // Move Grok up by -1 to make Grok first in catalog
        #expect(fixture.settings.moveQuickAction(id: QuickAction.BuiltInID.grok, by: -1))
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.grok)) == .command("5"))
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.chatGPT)) == .command("6"))
        #expect(fixture.settings.shortcutTarget(for: .command("5")) == .quickAction(QuickAction.BuiltInID.grok))
        #expect(fixture.settings.shortcutTarget(for: .command("6")) == .quickAction(QuickAction.BuiltInID.chatGPT))
    }

    @Test("Disabling a preset recalculates derived defaults for quick actions")
    func disablingPresetRecalculatesQuickActionDerivedDefaults() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let firstPresetID = PromptPreset.builtIn[0].id
        fixture.settings.setPromptPresetEnabled(id: firstPresetID, isEnabled: false)
        fixture.settings.setQuickActionEnabled(id: QuickAction.BuiltInID.grok, isEnabled: true)

        // Now 3 presets are enabled (Command+1...3) -> ChatGPT is Command+4, Grok is Command+5
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.chatGPT)) == .command("4"))
        #expect(fixture.settings.shortcut(for: .quickAction(QuickAction.BuiltInID.grok)) == .command("5"))
        #expect(fixture.settings.shortcutTarget(for: .command("4")) == .quickAction(QuickAction.BuiltInID.chatGPT))
        #expect(fixture.settings.shortcutTarget(for: .command("5")) == .quickAction(QuickAction.BuiltInID.grok))
    }

    @Test("Explicit shortcut assignment on quick action takes priority")
    func explicitAssignmentOverridesDerivedDefault() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let chatGPTTarget = InAppShortcutTarget.quickAction(QuickAction.BuiltInID.chatGPT)
        let customShortcut = InAppShortcut(key: "g", modifiers: [.command, .option])

        #expect(fixture.settings.assignShortcut(customShortcut, to: chatGPTTarget) == nil)
        #expect(fixture.settings.shortcut(for: chatGPTTarget) == customShortcut)
        #expect(fixture.settings.shortcutTarget(for: customShortcut) == chatGPTTarget)
        // Default Command+5 slot is now free
        #expect(fixture.settings.shortcutTarget(for: .command("5")) == nil)
    }

    @Test("Shortcut conflict between preset and quick action returns duplicateShortcut error")
    func shortcutConflictBetweenPresetAndQuickAction() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let presetTarget = InAppShortcutTarget.promptPreset(PromptPreset.builtIn[0].id)
        let chatGPTTarget = InAppShortcutTarget.quickAction(QuickAction.BuiltInID.chatGPT)

        // Try assigning Command+1 (already held by preset 1) to ChatGPT
        #expect(
            fixture.settings.assignShortcut(.command("1"), to: chatGPTTarget) ==
                .duplicateShortcut(presetTarget)
        )

        // Try assigning Command+5 (derived default for ChatGPT) to preset 1
        #expect(
            fixture.settings.assignShortcut(.command("5"), to: presetTarget) ==
                .duplicateShortcut(chatGPTTarget)
        )
    }

    @Test("Legacy webQuickAsk shortcut JSON decodes to quickAction target")
    func legacyWebQuickAskShortcutJSONDecodesToQuickAction() throws {
        let customID = UUID()
        let legacyJSON = """
        {
            "kind": "webQuickAsk",
            "webQuickAskProviderID": "\(customID.uuidString)"
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let target = try JSONDecoder().decode(InAppShortcutTarget.self, from: data)
        #expect(target == .quickAction(customID))
    }
    @Test("Disabling quick action removes active resolution and restores on re-enable")
    func disablingQuickActionRemovesActiveResolutionAndRestoresOnReEnable() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let chatGPTTarget = InAppShortcutTarget.quickAction(QuickAction.BuiltInID.chatGPT)
        let customShortcut = InAppShortcut(key: "w", modifiers: [.command, .shift])

        #expect(fixture.settings.assignShortcut(customShortcut, to: chatGPTTarget) == nil)
        #expect(fixture.settings.shortcut(for: chatGPTTarget) == customShortcut)
        #expect(fixture.settings.shortcutTarget(for: customShortcut) == chatGPTTarget)

        // Disable ChatGPT
        fixture.settings.setQuickActionEnabled(id: QuickAction.BuiltInID.chatGPT, isEnabled: false)
        #expect(fixture.settings.shortcut(for: chatGPTTarget) == nil)
        #expect(fixture.settings.shortcutTarget(for: customShortcut) == nil)
        #expect(!fixture.settings.shortcutAssignments.contains { $0.target == chatGPTTarget })

        // Reload from UserDefaults: stored assignment must still exist in configuration
        let reloaded = AppSettings(defaults: fixture.defaults)
        #expect(reloaded.shortcut(for: chatGPTTarget) == nil)
        #expect(!reloaded.shortcutAssignments.contains { $0.target == chatGPTTarget })

        // Re-enable ChatGPT: custom assignment should be restored
        reloaded.setQuickActionEnabled(id: QuickAction.BuiltInID.chatGPT, isEnabled: true)
        #expect(reloaded.shortcut(for: chatGPTTarget) == customShortcut)
        #expect(reloaded.shortcutTarget(for: customShortcut) == chatGPTTarget)
    }

    @Test("Deleting custom quick action cleans up dangling shortcut assignment")
    func deletingCustomQuickActionCleansUpAssignment() {
        let fixture = makeSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let customAction = QuickAction(
            name: "Custom Search",
            kind: .web(urlTemplate: "https://example.com/?q={query}")
        )
        #expect(fixture.settings.saveCustomQuickAction(customAction))
        let target = InAppShortcutTarget.quickAction(customAction.id)

        let customShortcut = InAppShortcut(key: "e", modifiers: [.command, .option])
        #expect(fixture.settings.assignShortcut(customShortcut, to: target) == nil)
        #expect(fixture.settings.shortcut(for: target) == customShortcut)

        // Deleting the custom action should clean up its shortcut assignment
        fixture.settings.deleteCustomQuickAction(id: customAction.id)
        #expect(fixture.settings.shortcut(for: target) == nil)
        #expect(fixture.settings.shortcutTarget(for: customShortcut) == nil)
    }

    @Test("QuickAction target round trips via Codable")
    func quickActionTargetCodableRoundTrip() throws {
        let actionID = UUID()
        let target = InAppShortcutTarget.quickAction(actionID)
        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(InAppShortcutTarget.self, from: encoded)
        #expect(decoded == target)
        #expect(decoded.id == "quickAction.\(actionID.uuidString.lowercased())")
    }

    @Test("Legacy shortcut configuration JSON without web targets decodes cleanly")
    func legacyShortcutConfigurationDecodesCleanly() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "overrides": [
                {
                    "target": {
                        "kind": "operation",
                        "operation": "focusInput"
                    },
                    "shortcut": {
                        "key": "k",
                        "modifiers": 1
                    }
                }
            ],
            "disabledTargets": [
                {
                    "kind": "operation",
                    "operation": "zoomIn"
                }
            ]
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(InAppShortcutConfiguration.self, from: legacyJSON)
        #expect(configuration.overrides.count == 1)
        #expect(configuration.disabledTargets.count == 1)
        #expect(configuration.disabledTargets.contains(.operation(.zoomIn)))
    }

    private func keyEvent(key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [.command]) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
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
