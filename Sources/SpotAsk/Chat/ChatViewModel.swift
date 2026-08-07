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
    private(set) var activeStreamingAssistantID: UUID?
    private(set) var streamingContent = ""
    private(set) var streamingReasoning: String?
    private(set) var streamingAnswerChunks: [String] = []
    /// Draft attachments for the next question. They move into the user message
    /// on send, so retry and follow-up context never depend on draft state.
    private(set) var pendingAttachments: [ChatAttachment] = []
    /// Per-conversation model override. `nil` means "use the Settings default".
    private(set) var sessionModelID: UUID?

    private let settings: AppSettings
    private let providerFactory: any ChatProviderFactory
    private let sessionStore: SessionStore
    private var streamTask: Task<Void, Never>?
    private var pendingAnswer = ""
    private var pendingReasoning = ""
    private var flushTask: Task<Void, Never>?
    private var retryPromptPreset: PromptPreset?
    private var selectionSnapshotsByAssistantID: [UUID: SelectedTextSnapshot] = [:]

    init(settings: AppSettings, providerFactory: any ChatProviderFactory, sessionStore: SessionStore) {
        self.settings = settings
        self.providerFactory = providerFactory
        self.sessionStore = sessionStore
        if settings.retainSession { messages = (try? sessionStore.load()) ?? [] }
    }

    var lastAssistantMessage: ChatMessage? {
        guard let message = messages.last(where: { $0.role == .assistant }) else { return nil }
        return liveMessage(message)
    }
    var canSend: Bool {
        let hasContent = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingAttachments.isEmpty
        return hasContent
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

    // MARK: - Session model override

    /// The model that the next request actually uses: the current conversation's
    /// override when present and still resolvable, otherwise the Settings default.
    var effectiveModel: ModelConfiguration? {
        guard let catalog = settings.providerRegistry.catalog else { return nil }
        if let sessionModelID,
           let model = catalog.models.first(where: { $0.id == sessionModelID }) {
            return model
        }
        return catalog.models.first(where: { $0.id == catalog.selectedModelID })
    }

    var effectiveModelID: UUID? { effectiveModel?.id }

    var effectiveProvider: ProviderConfiguration? {
        guard let model = effectiveModel,
              let catalog = settings.providerRegistry.catalog else { return nil }
        return catalog.providers.first(where: { $0.id == model.providerID })
    }

    /// Applies a model override for this conversation only. The Settings default
    /// is never touched; New Conversation returns to it.
    func selectSessionModel(id: UUID) {
        guard let catalog = settings.providerRegistry.catalog,
              catalog.models.contains(where: { $0.id == id }) else { return }
        sessionModelID = id
    }

    func useDefaultModel() {
        sessionModelID = nil
    }

    /// A model deleted in Settings must never wedge the conversation on a stale
    /// UUID; the override is dropped and the default model takes over.
    private func reconcileSessionModel() {
        guard let sessionModelID,
              let catalog = settings.providerRegistry.catalog,
              !catalog.models.contains(where: { $0.id == sessionModelID }) else { return }
        self.sessionModelID = nil
    }

    // MARK: - Attachments

    func addAttachments(_ newAttachments: [ChatAttachment]) {
        guard !newAttachments.isEmpty else { return }
        let available = AttachmentLimits.maxAttachmentsPerMessage - pendingAttachments.count
        guard available > 0 else {
            StatusToastCenter.shared.show(L10n.string("chat.attachmentTooMany"), isError: true)
            return
        }
        if newAttachments.count > available {
            pendingAttachments.append(contentsOf: newAttachments.prefix(available))
            StatusToastCenter.shared.show(L10n.string("chat.attachmentTooMany"), isError: true)
        } else {
            pendingAttachments.append(contentsOf: newAttachments)
        }
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Ingests one dropped/picked file through the shared processor and reports
    /// failures as a toast so the composer stays lightweight.
    func addAttachment(from url: URL) async {
        do {
            let attachment = try await AttachmentProcessor.shared.process(url: url)
            addAttachments([attachment])
        } catch let error as AttachmentError {
            StatusToastCenter.shared.show(error.localizedDescription, isError: true)
        } catch {
            StatusToastCenter.shared.show(L10n.string("chat.attachmentFileReadFailed"), isError: true)
        }
    }

    /// Ingests clipboard image data, normalized to PNG, through the same pipeline.
    func addScreenshot(_ image: Data) async {
        do {
            let attachment = try await AttachmentProcessor.shared.processScreenshot(image)
            addAttachments([attachment])
        } catch let error as AttachmentError {
            StatusToastCenter.shared.show(error.localizedDescription, isError: true)
        } catch {
            StatusToastCenter.shared.show(L10n.string("chat.attachmentImageDecodeFailed"), isError: true)
        }
    }

    /// Returns the row data the UI should render. While a message is actively
    /// streaming, the high-frequency content lives outside `messages` so an
    /// individual delta does not invalidate the whole conversation array.
    func liveMessage(_ message: ChatMessage) -> ChatMessage {
        guard message.state == .streaming, message.id == activeStreamingAssistantID else { return message }
        return ChatMessage(
            id: message.id,
            role: message.role,
            content: streamingContent,
            reasoningContent: streamingReasoning ?? message.reasoningContent,
            createdAt: message.createdAt,
            state: message.state,
            reasoningCompletedAt: message.reasoningCompletedAt,
            modelDisplayName: message.modelDisplayName,
            completedAt: message.completedAt,
            attachments: message.attachments,
            appliedPresetTitle: message.appliedPresetTitle,
            appliedPresetSymbolName: message.appliedPresetSymbolName,
            providerName: message.providerName
        )
    }

    @discardableResult
    func send(selectionSnapshot: SelectedTextSnapshot? = nil) -> Bool {
        guard canSend else { return false }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        let promptPreset = selectedPromptPreset
        selectedPromptPreset = nil
        input = ""
        pendingAttachments = []
        messages.append(
            ChatMessage(
                role: .user,
                content: text,
                attachments: attachments,
                appliedPresetTitle: promptPreset?.title,
                appliedPresetSymbolName: promptPreset?.symbolName
            )
        )
        beginRequest(using: promptPreset, selectionSnapshot: selectionSnapshot)
        return true
    }

    func cancel() {
        guard generationState == .connecting || generationState == .streaming else { return }
        DiagnosticLogStore.shared.record("chat-cancelled")
        streamTask?.cancel()
        flushTask?.cancel()
        flushPendingDeltas()
        if let activeStreamingAssistantID {
            commitStreamingContent(for: activeStreamingAssistantID)
        }
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
        pendingAnswer = ""
        pendingReasoning = ""
        activeStreamingAssistantID = nil
        streamingContent = ""
        streamingReasoning = nil
        streamingAnswerChunks = []
        messages.removeAll()
        input = ""
        pendingAttachments = []
        sessionModelID = nil
        error = nil
        generationState = .idle
        selectedPromptPreset = nil
        retryPromptPreset = nil
        selectionSnapshotsByAssistantID.removeAll()
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

    func selectionSnapshot(for assistantMessageID: UUID) -> SelectedTextSnapshot? {
        selectionSnapshotsByAssistantID[assistantMessageID]
    }

    /// Restored sessions only keep the prompt title, so look the instruction up
    /// by title; the in-memory preset wins while it is still around.
    private func promptPresetForLastUserMessage() -> PromptPreset? {
        guard let title = messages.last(where: { $0.role == .user })?.appliedPresetTitle else { return nil }
        if let retryPromptPreset, retryPromptPreset.title == title {
            return settings.promptPresetAllowedForUse(retryPromptPreset)
        }
        return settings.enabledPromptPresets.first { $0.title == title }
    }

    private func beginRequest(using promptPreset: PromptPreset? = nil, selectionSnapshot: SelectedTextSnapshot? = nil) {
        guard messages.last?.role == .user else { return }
        reconcileSessionModel()
        error = nil
        generationState = .connecting
        let assistantID = UUID()
        activeStreamingAssistantID = assistantID
        streamingContent = ""
        streamingReasoning = nil
        streamingAnswerChunks = []
        if let selectionSnapshot {
            selectionSnapshotsByAssistantID[assistantID] = selectionSnapshot
        }
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", state: .streaming))
        retryPromptPreset = promptPreset
        let target: ProviderTargetSnapshot
        do {
            if let effectiveModelID {
                target = try providerFactory.makeTargetSnapshot(modelID: effectiveModelID)
            } else {
                target = try providerFactory.makeTargetSnapshot()
            }
            if let assistantIndex = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[assistantIndex].modelDisplayName = target.displayName
                messages[assistantIndex].providerName = target.providerName
            }
        } catch let receivedError as ChatError {
            finishAfterError(receivedError, assistantID: assistantID)
            return
        } catch {
            finishAfterError(.invalidConfiguration, assistantID: assistantID)
            return
        }
        if let question = messages.last(where: { $0.role == .user })?.content {
            DiagnosticLogStore.shared.record(
                "chat-request model=\(target.upstreamModelID) question=\(DiagnosticLogStore.truncated(question))"
            )
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
                    case let .reasoningDelta(reasoning): self.appendReasoning(reasoning, to: assistantID)
                    case let .answerDelta(answer): self.appendAnswer(answer, to: assistantID)
                    case .completed: break
                    case .usage: break
                    }
                }
                self.flushPendingDeltas()
                self.completeAssistant(with: assistantID, state: .complete)
                let answer = self.messages.first(where: { $0.id == assistantID })?.content ?? ""
                DiagnosticLogStore.shared.record(
                    "chat-completed model=\(target.upstreamModelID) answer=\(DiagnosticLogStore.truncated(answer))"
                )
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
        let conversation = messages
            .filter { $0.role == .user || ($0.role == .assistant && $0.state == .complete) }
            .map { message in
                var requestMessage = ChatMessage(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    createdAt: message.createdAt,
                    state: message.state,
                    appliedPresetTitle: message.appliedPresetTitle,
                    appliedPresetSymbolName: message.appliedPresetSymbolName
                )
                // Attachments belong to the conversation context, so follow-up
                // requests resend earlier screenshots and documents.
                requestMessage.attachments = message.attachments
                // An image-only send stays silent in the UI but still gives the
                // provider a concrete instruction on the wire.
                if message.role == .user, message.content.isEmpty, !message.attachments.isEmpty {
                    requestMessage.content = L10n.string("chat.attachmentFallbackPrompt")
                }
                return requestMessage
            }
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

    private func appendAnswer(_ text: String, to assistantID: UUID) {
        guard activeStreamingAssistantID == assistantID else { return }
        if let index = messages.firstIndex(where: { $0.id == assistantID }),
           streamingReasoning?.isEmpty == false,
           messages[index].reasoningCompletedAt == nil {
            messages[index].reasoningCompletedAt = .now
        }
        if streamingContent.isEmpty {
            streamingContent = text
            streamingAnswerChunks.append(text)
            return
        }
        pendingAnswer += text
        scheduleFlush()
    }

    private func appendReasoning(_ text: String, to assistantID: UUID) {
        guard activeStreamingAssistantID == assistantID else { return }
        if streamingReasoning == nil {
            streamingReasoning = text
            return
        }
        pendingReasoning += text
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.flushPendingDeltas()
        }
    }

    private func flushPendingDeltas() {
        defer { flushTask = nil }
        guard activeStreamingAssistantID != nil else {
            pendingAnswer = ""
            pendingReasoning = ""
            return
        }
        streamingContent += pendingAnswer
        if !pendingAnswer.isEmpty {
            streamingAnswerChunks.append(pendingAnswer)
        }
        if !pendingReasoning.isEmpty {
            streamingReasoning = (streamingReasoning ?? "") + pendingReasoning
        }
        pendingAnswer = ""
        pendingReasoning = ""
    }

    private func commitStreamingContent(for id: UUID) {
        guard activeStreamingAssistantID == id,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if !streamingContent.isEmpty {
            messages[index].content = streamingContent
        }
        if let streamingReasoning, !streamingReasoning.isEmpty {
            messages[index].reasoningContent = streamingReasoning
        }
        activeStreamingAssistantID = nil
        streamingContent = ""
        streamingReasoning = nil
        // Keep the chunked answer available to the shared block renderer after
        // completion so sealing the live tail does not rebuild the document.
    }

    private func completeAssistant(with id: UUID, state: MessageState) {
        commitStreamingContent(for: id)
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].state = state
        if state == .complete {
            messages[index].completedAt = .now
        }
        if messages[index].reasoningContent?.isEmpty == false, messages[index].reasoningCompletedAt == nil {
            messages[index].reasoningCompletedAt = messages[index].completedAt ?? .now
        }
    }

    private func finishAfterError(_ receivedError: ChatError, assistantID: UUID) {
        flushPendingDeltas()
        DiagnosticLogStore.shared.record("chat-failed error=\(receivedError.localizedDescription)")
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
