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
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests[0].messages.first?.role == .system)
        #expect(recorder.requests[0].messages.first?.content.contains(PromptPreset.builtIn[0].instruction) == true)

        viewModel.input = "How are you?"
        viewModel.send()
        await waitForIdle(viewModel)

        #expect(recorder.requests.count == 2)
        #expect(recorder.requests[1].messages.first?.content == settings.systemPrompt)
    }

    private func waitForIdle(_ viewModel: ChatViewModel) async {
        for _ in 0 ..< 100 {
            if viewModel.generationState == .idle { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the request to finish")
    }
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
