import AppKit
import Foundation

/// A finished floating-prompt exchange, ready to join the main conversation
/// without sending another request.
struct CompletedConversationTurn: Equatable, Sendable {
    var userText: String
    var answer: String
    var preset: PromptPreset?
    var selectionSnapshot: SelectedTextSnapshot?
    var modelDisplayName: String?
    var providerName: String?
}

enum FloatingPromptCloseRequest: Equatable, Sendable {
    case outsideClick
    case escape
    case closeButton
    case commandW
    case continueInConversation
}

enum FloatingPromptDismissal {
    /// Outside clicks dismiss only an unpinned window. Escape, Command-W, the
    /// close button, and continue always dismiss, including when pinned.
    static func shouldClose(isPinned: Bool, request: FloatingPromptCloseRequest) -> Bool {
        switch request {
        case .outsideClick:
            return !isPinned
        case .escape, .closeButton, .commandW, .continueInConversation:
            return true
        }
    }
}

enum FloatingPromptCloseChord {
    /// Command-W is AppKit's close chord, but the borderless panel has no
    /// `.closable` style mask, so `performClose:` never sees it. The window
    /// controller matches the key event itself. Only plain Command counts, and
    /// the character (not the physical key) must be `w`, so alternate layouts
    /// and chords such as Command-Shift-W keep their system meaning.
    static func isCloseWindow(modifiers: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        guard modifiers.intersection(relevant) == .command else { return false }
        return charactersIgnoringModifiers?.lowercased() == "w"
    }
}

enum FloatingPromptOutsideClick {
    /// A click in the model menu is outside the panel frame, but that menu is
    /// an attached window. Only a click in neither frame is an outside click.
    static func isOutside(mouse: CGPoint, panelFrame: CGRect, attachedFrames: [CGRect]) -> Bool {
        if panelFrame.contains(mouse) { return false }
        return !attachedFrames.contains { $0.contains(mouse) }
    }
}

enum FloatingPromptShortcut {
    /// The focused floating window reuses the main chat shortcut set.
    /// Copy, retry, pin, zoom, and settings apply here. Other targets stay
    /// unhandled so a text selection keeps system keys such as Command-C.
    @MainActor
    static func perform(
        _ target: InAppShortcutTarget,
        session: FloatingPromptSession,
        settings: AppSettings,
        copy: () -> Bool,
        showSettings: () -> Void
    ) -> Bool {
        switch target {
        case .operation(.copyAnswer):
            return copy()
        case .operation(.regenerateOrRetry):
            guard session.phase == .complete || session.phase == .failed else { return false }
            session.retry()
            return true
        case .operation(.toggleWindowOnTop):
            session.isPinned.toggle()
            return true
        case .operation(.zoomIn):
            adjustZoom(settings, by: 1)
            return true
        case .operation(.zoomOut):
            adjustZoom(settings, by: -1)
            return true
        case .operation(.showSettings):
            showSettings()
            return true
        default:
            return false
        }
    }

    @MainActor
    private static func adjustZoom(_ settings: AppSettings, by delta: Int) {
        let next = InterfaceZoomLevel.adjusted(from: settings.interfaceZoomLevel, by: delta)
        guard next != settings.interfaceZoomLevel else { return }
        settings.interfaceZoomLevel = next
    }
}

enum FloatingPromptPlacement {
    static let defaultSize = NSSize(width: 380, height: 460)
    static let minSize = NSSize(width: 300, height: 240)

    static func origin(anchor: SelectionAnchor, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let point: NSPoint
        switch anchor {
        case let .pointer(value):
            point = value
        }
        var origin = NSPoint(x: point.x + 12, y: point.y - size.height - 12)
        if origin.y < visibleFrame.minY + 8 {
            origin.y = point.y + 12
        }
        let minX = visibleFrame.minX + 8
        let minY = visibleFrame.minY + 8
        let maxX = max(minX, visibleFrame.maxX - size.width - 8)
        let maxY = max(minY, visibleFrame.maxY - size.height - 8)
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    static func visibleFrame(containing point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

enum FloatingPromptRequestBuilder {
    /// The floating request is the preset plus the selection. It never includes
    /// the main conversation.
    static func messages(selectedText: String, preset: PromptPreset, systemPrompt: String) -> [ChatMessage] {
        var result: [ChatMessage] = []
        let prompt = [
            systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            preset.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        if !prompt.isEmpty {
            result.append(ChatMessage(role: .system, content: prompt))
        }
        result.append(ChatMessage(role: .user, content: selectedText))
        return result
    }

    static func request(
        selectedText: String,
        preset: PromptPreset,
        systemPrompt: String,
        model: String,
        stream: Bool
    ) -> ChatRequest {
        ChatRequest(
            model: model,
            messages: messages(selectedText: selectedText, preset: preset, systemPrompt: systemPrompt),
            stream: stream
        )
    }
}

@MainActor
protocol FloatingPromptPresenting: AnyObject {
    func present(snapshot: SelectedTextSnapshot, preset: PromptPreset)
}

@MainActor
final class IgnoringFloatingPromptPresenter: FloatingPromptPresenting {
    func present(snapshot: SelectedTextSnapshot, preset: PromptPreset) {}
}

@MainActor
@Observable
final class FloatingPromptSession {
    let preset: PromptPreset
    let selectedText: String
    let selectionSnapshot: SelectedTextSnapshot
    private(set) var answer = ""
    private(set) var modelDisplayName: String?
    private(set) var providerName: String?
    private(set) var phase: Phase = .idle
    private(set) var error: ChatError?
    var isPinned = false

    enum Phase: Equatable {
        case idle
        case connecting
        case streaming
        case complete
        case failed
        case cancelled
    }

    private let settings: AppSettings
    private let providerFactory: any ChatProviderFactory
    private(set) var modelID: UUID?
    private var streamTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pendingAnswer = ""
    private var runID = UUID()

    init(
        snapshot: SelectedTextSnapshot,
        preset: PromptPreset,
        settings: AppSettings,
        providerFactory: any ChatProviderFactory,
        modelID: UUID?
    ) {
        self.selectionSnapshot = snapshot
        self.preset = preset
        self.selectedText = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.settings = settings
        self.providerFactory = providerFactory
        self.modelID = modelID
    }

    var canCopy: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canContinue: Bool { canCopy }

    var canRetry: Bool { phase == .failed }

    func start() {
        runID = UUID()
        let run = runID
        streamTask?.cancel()
        flushTask?.cancel()
        flushTask = nil
        pendingAnswer = ""
        answer = ""
        error = nil
        phase = .connecting
        let target: ProviderTargetSnapshot
        do {
            if let modelID {
                target = try providerFactory.makeTargetSnapshot(modelID: modelID)
            } else {
                target = try providerFactory.makeTargetSnapshot()
            }
        } catch let received as ChatError {
            fail(received, run: run)
            return
        } catch {
            fail(.invalidConfiguration, run: run)
            return
        }
        modelDisplayName = target.displayName
        providerName = target.providerName
        let request = FloatingPromptRequestBuilder.request(
            selectedText: selectedText,
            preset: preset,
            systemPrompt: settings.systemPrompt,
            model: target.upstreamModelID,
            stream: target.isStreamingEnabled
        )
        DiagnosticLogStore.shared.record(
            "floating-prompt-request model=\(target.upstreamModelID) question=\(DiagnosticLogStore.truncated(selectedText))"
        )
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let provider = try self.providerFactory.makeProvider(for: target)
                guard self.runID == run else { return }
                self.phase = .streaming
                for try await event in provider.stream(request: request) {
                    guard self.runID == run, !Task.isCancelled else { throw ChatError.cancelled }
                    if case let .answerDelta(delta) = event {
                        self.appendAnswer(delta, run: run)
                    }
                }
                guard self.runID == run else { return }
                self.flushPending(run: run)
                self.phase = .complete
                DiagnosticLogStore.shared.record(
                    "floating-prompt-completed model=\(target.upstreamModelID) answer=\(DiagnosticLogStore.truncated(self.answer))"
                )
            } catch let received as ChatError {
                self.fail(received, run: run)
            } catch is CancellationError {
                self.fail(.cancelled, run: run)
            } catch {
                self.fail(.invalidResponse, run: run)
            }
        }
    }

    func retry() {
        start()
    }

    /// Restarts the isolated answer with an explicit model, or the catalog default when `nil`.
    func answer(using modelID: UUID?) {
        self.modelID = modelID
        start()
    }

    func cancel() {
        runID = UUID()
        streamTask?.cancel()
        streamTask = nil
        flushTask?.cancel()
        flushTask = nil
        pendingAnswer = ""
        if phase == .connecting || phase == .streaming {
            phase = .cancelled
        }
    }

    func completedTurn() -> CompletedConversationTurn? {
        flushPending()
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty, !text.isEmpty else { return nil }
        return CompletedConversationTurn(
            userText: selectedText,
            answer: text,
            preset: preset,
            selectionSnapshot: selectionSnapshot,
            modelDisplayName: modelDisplayName,
            providerName: providerName
        )
    }

    @discardableResult
    func copyAnswer(to pasteboard: NSPasteboard) -> Bool {
        flushPending()
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func appendAnswer(_ text: String, run: UUID) {
        guard runID == run, !text.isEmpty else { return }
        if answer.isEmpty, pendingAnswer.isEmpty {
            answer = text
            return
        }
        pendingAnswer += text
        scheduleFlush(run: run)
    }

    private func scheduleFlush(run: UUID) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.flushPending(run: run)
        }
    }

    private func flushPending(run: UUID? = nil) {
        if let run, runID != run {
            return
        }
        flushTask?.cancel()
        flushTask = nil
        guard !pendingAnswer.isEmpty else { return }
        answer += pendingAnswer
        pendingAnswer = ""
    }

    private func fail(_ received: ChatError, run: UUID) {
        guard runID == run else { return }
        flushPending(run: run)
        if received == .cancelled {
            phase = .cancelled
            return
        }
        error = received
        phase = .failed
        DiagnosticLogStore.shared.record("floating-prompt-failed error=\(received.localizedDescription)")
    }
}
