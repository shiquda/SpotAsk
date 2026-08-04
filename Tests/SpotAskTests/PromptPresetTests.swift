import Foundation
import Testing
@testable import SpotAsk

@Suite("Prompt presets")
@MainActor
struct PromptPresetTests {
    @Test("Pressing the selected prompt shortcut clears the prompt")
    func selectedPromptShortcutClearsSelection() {
        let translate = PromptPreset.builtIn[0]

        #expect(shortcutPresetSelection(current: translate, requested: translate) == nil)
        #expect(shortcutPresetSelection(current: translate, requested: PromptPreset.builtIn[1]) == PromptPreset.builtIn[1])
    }

    @Test("Custom presets persist, update, and delete")
    func customPresetsPersist() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let preset = PromptPreset(title: "邮件改写", instruction: "请将内容改写为简洁、专业的邮件。")

        #expect(settings.saveCustomPromptPreset(preset))
        #expect(AppSettings(defaults: defaults).customPromptPresets == [preset])

        let edited = PromptPreset(id: preset.id, title: "邮件润色", instruction: "请润色为自然、专业的邮件。")
        #expect(settings.saveCustomPromptPreset(edited))
        #expect(settings.customPromptPresets == [edited])

        settings.deleteCustomPromptPreset(id: preset.id)
        #expect(settings.customPromptPresets.isEmpty)
    }

    @Test("Legacy custom presets migrate into one persistent prompt catalog")
    func legacyCustomPresetsMigrateIdempotently() throws {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyPreset = PromptPreset(title: "邮件改写", instruction: "改写为简洁邮件。")
        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode([legacyPreset])) as? [[String: Any]]
        )
        legacyJSON[0].removeValue(forKey: "isEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        defaults.set(legacyData, forKey: "customPromptPresets")

        let migrated = AppSettings(defaults: defaults)
        #expect(migrated.promptPresets.map(\.id) == PromptPreset.builtIn.map(\.id) + [legacyPreset.id])
        #expect(migrated.customPromptPresets == [legacyPreset])
        #expect(defaults.data(forKey: "promptPresetCatalog") != nil)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.promptPresets == migrated.promptPresets)
        #expect(reloaded.customPromptPresets == [legacyPreset])
    }

    @Test("Prompt catalog order and enabled state persist")
    func promptCatalogOrderAndEnabledStatePersist() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let custom = PromptPreset(title: "邮件改写", instruction: "改写为简洁邮件。")
        #expect(settings.saveCustomPromptPreset(custom))

        let translate = PromptPreset.builtIn[0]
        settings.movePromptPreset(id: custom.id, before: translate.id)
        settings.setPromptPresetEnabled(id: translate.id, isEnabled: false)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.promptPresets.first?.id == custom.id)
        #expect(reloaded.enabledPromptPreset(id: translate.id) == nil)
        #expect(!reloaded.enabledPromptPresets.contains(where: { $0.id == translate.id }))
    }

    @Test("System shortcut prompt lookup stops at disabled built-in prompts")
    func disabledBuiltInPromptsAreUnavailableToSystemShortcuts() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let translate = PromptPreset.builtIn[0]

        #expect(enabledBuiltInPromptPreset(id: translate.id, settings: settings)?.id == translate.id)
        settings.setPromptPresetEnabled(id: translate.id, isEnabled: false)
        #expect(enabledBuiltInPromptPreset(id: translate.id, settings: settings) == nil)
        #expect(settings.promptPresetAllowedForUse(translate) == nil)
    }

    @Test("A selected preset applies to one request only")
    func selectedPresetAppliesToOneRequestOnly() async {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let recorder = PromptPresetRequestRecorder()
        let viewModel = ChatViewModel(
            settings: settings,
            providerFactory: PromptPresetFactory(recorder: recorder),
            sessionStore: SessionStore(bundleIdentifier: suiteName)
        )

        viewModel.selectedPromptPreset = PromptPreset.builtIn[0]
        viewModel.input = "Hello"
        viewModel.send()
        await waitForIdle(viewModel)

        #expect(viewModel.selectedPromptPreset == nil)
        #expect(viewModel.messages.first?.appliedPresetTitle == PromptPreset.builtIn[0].title)
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests[0].messages.first?.role == .system)
        #expect(recorder.requests[0].messages.first?.content.contains(PromptPreset.builtIn[0].instruction) == true)
        #expect(recorder.requests[0].messages.last?.content == "Hello")

        viewModel.input = "How are you?"
        viewModel.send()
        await waitForIdle(viewModel)

        #expect(recorder.requests.count == 2)
        #expect(recorder.requests[1].messages.first?.content == settings.systemPrompt)
    }

    @Test("Messages without a preset label or icon remain readable")
    func legacyMessageDecoding() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try JSONEncoder().encode(
            LegacyChatMessage(id: id, role: .user, content: "Hello", createdAt: date, state: .complete)
        )

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(message.id == id)
        #expect(message.appliedPresetTitle == nil)
        #expect(message.appliedPresetSymbolName == nil)
        #expect(message.appliedPresetIcon == "sparkles")
        #expect(message.reasoningContent == nil)
    }

    @Test("Prompt presets have stable message icons")
    func promptPresetSymbolNames() {
        #expect(PromptPreset.builtIn[0].symbolName == "globe")
        #expect(PromptPreset.builtIn[1].symbolName == "lightbulb")
        #expect(PromptPreset(title: "Custom", instruction: "Do it").symbolName == "sparkles")
    }

    private func waitForIdle(_ viewModel: ChatViewModel) async {
        for _ in 0 ..< 100 {
            if viewModel.generationState == .idle { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the request to finish")
    }
}

private struct LegacyChatMessage: Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let createdAt: Date
    let state: MessageState
}

private final class PromptPresetRequestRecorder: @unchecked Sendable {
    var requests: [ChatRequest] = []
}

@MainActor
private struct PromptPresetFactory: ChatProviderFactory {
    let recorder: PromptPresetRequestRecorder

    func makeProvider() throws -> any ChatProvider {
        PromptPresetProvider(recorder: recorder)
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        PromptPresetProvider(recorder: recorder)
    }
}

private struct PromptPresetProvider: ChatProvider {
    let recorder: PromptPresetRequestRecorder

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        recorder.requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta("done"))
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}
