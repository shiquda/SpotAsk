import Foundation
import Testing
@testable import SpotAsk

@Suite("Prompt presets")
@MainActor
struct PromptPresetTests {
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

    @Test("Messages without a preset label remain readable")
    func legacyMessageDecoding() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try JSONEncoder().encode(
            LegacyChatMessage(id: id, role: .user, content: "Hello", createdAt: date, state: .complete)
        )

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(message.id == id)
        #expect(message.appliedPresetTitle == nil)
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
            continuation.yield(.textDelta("done"))
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}
