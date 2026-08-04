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

    private func makeSettings() -> (settings: AppSettings, defaults: UserDefaults, suiteName: String) {
        let suiteName = "InAppShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppSettings(defaults: defaults), defaults, suiteName)
    }
}
