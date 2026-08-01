import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    /// How long the conversation must sit idle before the user is asked whether
    /// a new question should continue it or start fresh. Deliberately fixed.
    static let staleSessionInterval: TimeInterval = 15 * 60

    var messages: [ChatMessage] = []
    var input = ""
    var generationState: GenerationState = .idle
    var error: ChatError?
    var isSettingsPresented = false
    var selectedPromptPreset: PromptPreset?
    private(set) var isSessionChoicePending = false

    private let settings: AppSettings
    private let providerFactory: any ChatProviderFactory
    private let sessionStore: SessionStore
    private var streamTask: Task<Void, Never>?
    private var pendingText = ""
    private var flushTask: Task<Void, Never>?
    private var retryPromptPreset: PromptPreset?

    init(settings: AppSettings, providerFactory: any ChatProviderFactory, sessionStore: SessionStore) {
        self.settings = settings
        self.providerFactory = providerFactory
        self.sessionStore = sessionStore
        if settings.retainSession { messages = (try? sessionStore.load()) ?? [] }
    }

    var lastAssistantMessage: ChatMessage? { messages.last(where: { $0.role == .assistant }) }
    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && generationState != .connecting
            && generationState != .streaming
            && !isSessionChoicePending
    }

    var canRegenerate: Bool {
        guard generationState == .idle,
              !isSessionChoicePending,
              let last = messages.last,
              last.role == .assistant,
              last.state == .complete else { return false }
        return messages.contains { $0.role == .user }
    }

    func send() {
        guard canSend else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptPreset = selectedPromptPreset
        selectedPromptPreset = nil
        input = ""
        messages.append(
            ChatMessage(
                role: .user,
                content: text,
                appliedPresetTitle: promptPreset?.title
            )
        )
        beginRequest(using: promptPreset)
    }

    func cancel() {
        guard generationState == .connecting || generationState == .streaming else { return }
        streamTask?.cancel()
        flushTask?.cancel()
        flushPendingText()
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.state == .streaming }) {
            messages[index].state = .cancelled
        }
        generationState = .cancelled
        persistIfNeeded()
    }

    func retry() {
        guard generationState == .failed, let assistantIndex = messages.lastIndex(where: { $0.role == .assistant && $0.state == .failed }) else { return }
        messages.remove(at: assistantIndex)
        error = nil
        beginRequest(using: retryPromptPreset)
    }

    func newConversation() {
        streamTask?.cancel()
        flushTask?.cancel()
        pendingText = ""
        messages.removeAll()
        input = ""
        error = nil
        generationState = .idle
        selectedPromptPreset = nil
        retryPromptPreset = nil
        isSessionChoicePending = false
        try? sessionStore.clear()
    }

    /// Offers the continue-or-start-fresh choice once a conversation has been
    /// idle long enough that silently appending a new question would surprise
    /// the user. Quick reopens never trigger it.
    func offerSessionChoiceIfNeeded(now: Date = .now) {
        guard !isSessionChoicePending,
              !messages.isEmpty,
              generationState != .connecting,
              generationState != .streaming,
              let lastMessage = messages.last,
              now.timeIntervalSince(lastMessage.createdAt) > Self.staleSessionInterval else { return }
        isSessionChoicePending = true
    }

    func continueSession() {
        isSessionChoicePending = false
    }

    /// Starts over but keeps the current draft so a typed question survives.
    func startFreshSession() {
        let draft = input
        newConversation()
        input = draft
    }

    /// Recalls the most recent question into an empty input without touching
    /// the original message. Returns false when there is nothing to recall.
    @discardableResult
    func recallLastQuestion() -> Bool {
        guard input.isEmpty, let lastQuestion = messages.last(where: { $0.role == .user }) else { return false }
        input = lastQuestion.content
        return true
    }

    /// Replaces the latest completed answer without repeating the question,
    /// reusing the one-shot prompt the question was asked with.
    func regenerate() {
        guard canRegenerate else { return }
        let promptPreset = promptPresetForLastUserMessage()
        messages.removeLast()
        error = nil
        beginRequest(using: promptPreset)
    }

    func clearAllLocalData() {
        newConversation()
    }

    /// Restored sessions only keep the prompt title, so look the instruction up
    /// by title; the in-memory preset wins while it is still around.
    private func promptPresetForLastUserMessage() -> PromptPreset? {
        guard let title = messages.last(where: { $0.role == .user })?.appliedPresetTitle else { return nil }
        if retryPromptPreset?.title == title { return retryPromptPreset }
        return settings.promptPresets.first { $0.title == title }
    }

    private func beginRequest(using promptPreset: PromptPreset? = nil) {
        guard messages.last?.role == .user else { return }
        error = nil
        generationState = .connecting
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", state: .streaming))
        retryPromptPreset = promptPreset
        let target: ProviderTargetSnapshot
        do {
            target = try providerFactory.makeTargetSnapshot()
        } catch let receivedError as ChatError {
            finishAfterError(receivedError, assistantID: assistantID)
            return
        } catch {
            finishAfterError(.invalidConfiguration, assistantID: assistantID)
            return
        }
        let request = ChatRequest(
            model: target.upstreamModelID,
            messages: messagesForRequest(using: promptPreset),
            stream: target.isStreamingEnabled
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let provider = try self.providerFactory.makeProvider(for: target)
                self.generationState = .streaming
                for try await event in provider.stream(request: request) {
                    guard !Task.isCancelled else { throw ChatError.cancelled }
                    switch event {
                    case let .textDelta(text): self.append(text, to: assistantID)
                    case .completed: break
                    case .usage: break
                    }
                }
                self.flushPendingText()
                self.completeAssistant(with: assistantID, state: .complete)
                self.generationState = .idle
                self.persistIfNeeded()
            } catch let receivedError as ChatError {
                self.finishAfterError(receivedError, assistantID: assistantID)
            } catch is CancellationError {
                self.finishAfterError(.cancelled, assistantID: assistantID)
            } catch {
                self.finishAfterError(.invalidResponse, assistantID: assistantID)
            }
        }
    }

    private func messagesForRequest(using promptPreset: PromptPreset?) -> [ChatMessage] {
        var result: [ChatMessage] = []
        let prompt = [
            settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            promptPreset?.instruction.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        if !prompt.isEmpty { result.append(ChatMessage(role: .system, content: prompt)) }
        let conversation = messages.filter { $0.role == .user || ($0.role == .assistant && $0.state == .complete) }
        let maximum = settings.contextLimit == 0 ? Int.max : settings.contextLimit
        let recent = Array(conversation.suffix(maximum))
        var totalCharacters = 0
        for message in recent.reversed() {
            totalCharacters += message.content.count
            if totalCharacters > 100_000 { break }
            result.insert(message, at: prompt.isEmpty ? 0 : 1)
        }
        return result
    }

    private func append(_ text: String, to assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        if messages[index].content.isEmpty {
            messages[index].content = text
            return
        }
        pendingText += text
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.flushPendingText()
        }
    }

    private func flushPendingText() {
        defer { flushTask = nil }
        guard !pendingText.isEmpty, let index = messages.lastIndex(where: { $0.role == .assistant && $0.state == .streaming }) else {
            pendingText = ""
            return
        }
        messages[index].content += pendingText
        pendingText = ""
    }

    private func completeAssistant(with id: UUID, state: MessageState) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].state = state
    }

    private func finishAfterError(_ receivedError: ChatError, assistantID: UUID) {
        flushPendingText()
        if receivedError == .cancelled {
            completeAssistant(with: assistantID, state: .cancelled)
            generationState = .cancelled
        } else {
            completeAssistant(with: assistantID, state: .failed)
            generationState = .failed
            error = receivedError
        }
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard settings.retainSession else { return }
        try? sessionStore.save(messages)
    }
}
