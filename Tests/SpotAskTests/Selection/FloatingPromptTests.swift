import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpotAsk

@Suite("Floating prompt isolation")
@MainActor
struct FloatingPromptTests {
    @Test("Outside clicks close only an unpinned window")
    func outsideClickRespectsPin() {
        #expect(FloatingPromptDismissal.shouldClose(isPinned: false, request: .outsideClick))
        #expect(!FloatingPromptDismissal.shouldClose(isPinned: true, request: .outsideClick))
        for request in [FloatingPromptCloseRequest.escape, .closeButton, .continueInConversation] {
            #expect(FloatingPromptDismissal.shouldClose(isPinned: true, request: request))
        }
    }

    @Test("The window prefers the pointer side and stays on screen")
    func placementFlipsAndClamps() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: 380, height: 460)
        let below = FloatingPromptPlacement.origin(
            anchor: .pointer(CGPoint(x: 100, y: 500)),
            size: size,
            visibleFrame: visible
        )
        #expect(below == CGPoint(x: 112, y: 28))

        let clampedAbove = FloatingPromptPlacement.origin(
            anchor: .pointer(CGPoint(x: 100, y: 200)),
            size: size,
            visibleFrame: visible
        )
        #expect(clampedAbove.y == 132)

        let flipped = FloatingPromptPlacement.origin(
            anchor: .pointer(CGPoint(x: 100, y: 200)),
            size: size,
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 900)
        )
        #expect(flipped == CGPoint(x: 112, y: 212))

        let clamped = FloatingPromptPlacement.origin(
            anchor: .pointer(CGPoint(x: 790, y: 500)),
            size: size,
            visibleFrame: visible
        )
        #expect(clamped.x == 412)
        #expect(clamped.y == 28)
    }

    @Test("The request contains only the preset and the selection")
    func requestOmitsConversation() {
        let preset = PromptPreset(title: "Explain", instruction: "Explain the selection")
        let messages = FloatingPromptRequestBuilder.messages(
            selectedText: "selected passage",
            preset: preset,
            systemPrompt: "Be concise"
        )
        #expect(messages.map(\.role) == [.system, .user])
        #expect(messages[0].content == "Be concise\n\nExplain the selection")
        #expect(messages[1].content == "selected passage")
        #expect(!messages.contains { $0.content.contains("earlier question") })
    }

    @Test("A floating session does not read the main conversation")
    func sessionRequestStaysIsolated() async {
        let box = RequestBox()
        let factory = ScriptedFactory(box: box, events: [.answerDelta("explained")])
        let settings = makeSettings()
        settings.systemPrompt = "Be concise"
        let snapshot = SelectedTextSnapshot(
            text: "selected passage",
            source: SelectionSourceApplication(processIdentifier: 7, bundleIdentifier: "com.example.Source", localizedName: "Source"),
            selectedRange: SelectionCharacterRange(location: 0, length: 17),
            anchor: .pointer(CGPoint(x: 12, y: 12))
        )
        let session = FloatingPromptSession(
            snapshot: snapshot,
            preset: PromptPreset(title: "Explain", instruction: "Explain the selection"),
            settings: settings,
            providerFactory: factory,
            modelID: nil
        )
        session.start()
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        #expect(session.phase == .complete)
        #expect(session.answer == "explained")
        #expect(box.request?.messages.map(\.role) == [.system, .user])
        #expect(box.request?.messages.last?.content == "selected passage")
        #expect(session.completedTurn()?.answer == "explained")
    }

    @Test("Continue enqueues the finished turn without asking")
    func continueEnqueuesCompletedTurn() {
        let center = SpotAskCommandCenter()
        let recorder = FloatingCommandRecorder()
        center.configure(panelController: FloatingPanelSpy())
        center.setPanelContent { EmptyView() }
        center.setActionConsumer { recorder.actions.append($0) }
        let turn = CompletedConversationTurn(userText: "selected", answer: "explained")
        center.appendCompletedTurn(turn)
        #expect(recorder.actions == [.appendCompletedTurn(turn)])
    }

    @Test("Each click opens another window and closing one leaves the other")
    func windowsAreIndependent() {
        var made: [FakeFloatingWindow] = []
        let coordinator = FloatingPromptCoordinator(
            settings: makeSettings(),
            providerFactory: ScriptedFactory(box: RequestBox(), events: [.answerDelta("ok")]),
            commandCenter: SpotAskCommandCenter(),
            modelID: { nil },
            makeWindow: { _, _, _, onClosed in
                let window = FakeFloatingWindow(onClosed: onClosed)
                made.append(window)
                return window
            }
        )
        let snapshot = SelectedTextSnapshot(
            text: "one",
            source: SelectionSourceApplication(processIdentifier: 7, bundleIdentifier: "com.example.Source", localizedName: "Source"),
            selectedRange: SelectionCharacterRange(location: 0, length: 3),
            anchor: .pointer(.zero)
        )
        let preset = PromptPreset(title: "Explain", instruction: "Explain")
        coordinator.present(snapshot: snapshot, preset: preset)
        coordinator.present(snapshot: snapshot, preset: preset)
        #expect(coordinator.openWindowCount == 2)
        #expect(made.count == 2)
        made[0].close()
        #expect(coordinator.openWindowCount == 1)
    }

    @Test("Preset tooltips name both clicks")
    func presetTooltipIncludesClickHint() {
        let hint = L10n.string("selection.actionBar.promptPresetClickHint")
        #expect(SelectionActionBarLayout.promptPresetTooltip(name: "Explain", shortcut: nil) == "Explain (\(hint))")
    }

    @Test("A reversed prompt click setting changes the button hint")
    func reversedPresetTooltipSwapsTheClickHint() {
        let hint = L10n.string("selection.actionBar.promptPresetClickHintReversed")
        #expect(
            SelectionActionBarLayout.promptPresetTooltip(
                name: "Explain",
                shortcut: nil,
                behavior: .mainChatOnLeft
            ) == "Explain (\(hint))"
        )
    }

    @Test("A focused floating window reuses the main chat shortcuts")
    func shortcutsReuseChatActions() async {
        let box = RequestBox()
        let settings = makeSettings()
        let session = FloatingPromptSession(
            snapshot: SelectedTextSnapshot(
                text: "selected passage",
                source: SelectionSourceApplication(processIdentifier: 7, bundleIdentifier: "com.example.Source", localizedName: "Source"),
                selectedRange: SelectionCharacterRange(location: 0, length: 17),
                anchor: .pointer(.zero)
            ),
            preset: PromptPreset(title: "Explain", instruction: "Explain"),
            settings: settings,
            providerFactory: ScriptedFactory(box: box, events: [.answerDelta("explained")]),
            modelID: nil
        )
        var copied = false
        var settingsShown = false
        #expect(!FloatingPromptShortcut.perform(
            .operation(.copyAnswer),
            session: session,
            settings: settings,
            copy: { copied = true; return false },
            showSettings: { settingsShown = true }
        ))
        #expect(copied)
        #expect(!FloatingPromptShortcut.perform(
            .operation(.regenerateOrRetry),
            session: session,
            settings: settings,
            copy: { false },
            showSettings: {}
        ))
        #expect(session.phase == .idle)
        #expect(!session.isPinned)
        #expect(FloatingPromptShortcut.perform(
            .operation(.toggleWindowOnTop),
            session: session,
            settings: settings,
            copy: { false },
            showSettings: {}
        ))
        #expect(session.isPinned)
        let zoom = settings.interfaceZoomLevel
        #expect(FloatingPromptShortcut.perform(
            .operation(.zoomIn),
            session: session,
            settings: settings,
            copy: { false },
            showSettings: {}
        ))
        #expect(settings.interfaceZoomLevel == InterfaceZoomLevel.adjusted(from: zoom, by: 1))
        #expect(FloatingPromptShortcut.perform(
            .operation(.showSettings),
            session: session,
            settings: settings,
            copy: { false },
            showSettings: { settingsShown = true }
        ))
        #expect(settingsShown)
        #expect(!FloatingPromptShortcut.perform(
            .operation(.newConversation),
            session: session,
            settings: settings,
            copy: { false },
            showSettings: {}
        ))

        session.start()
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        #expect(session.phase == .complete)
        let requestsBeforeRetry = box.count
        #expect(FloatingPromptShortcut.perform(
            .operation(.regenerateOrRetry),
            session: session,
            settings: settings,
            copy: { false },
            showSettings: {}
        ))
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        #expect(session.phase == .complete)
        #expect(box.count == requestsBeforeRetry + 1)
    }

    @Test("Choosing another model answers again with that model")
    func answeringWithAnotherModelRestarts() async {
        let box = RequestBox()
        let factory = ScriptedFactory(box: box, events: [.answerDelta("explained")])
        let settings = makeSettings()
        let session = FloatingPromptSession(
            snapshot: SelectedTextSnapshot(
                text: "selected passage",
                source: SelectionSourceApplication(processIdentifier: 7, bundleIdentifier: "com.example.Source", localizedName: "Source"),
                selectedRange: SelectionCharacterRange(location: 0, length: 17),
                anchor: .pointer(CGPoint(x: 12, y: 12))
            ),
            preset: PromptPreset(title: "Explain", instruction: "Explain the selection"),
            settings: settings,
            providerFactory: factory,
            modelID: nil
        )
        session.start()
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        let chosen = UUID()
        session.answer(using: chosen)
        for _ in 0 ..< 30 where session.phase != .complete || box.modelIDs != [chosen] {
            await Task.yield()
        }
        #expect(session.phase == .complete)
        #expect(session.modelID == chosen)
        #expect(box.modelIDs == [chosen])
        session.answer(using: nil)
        for _ in 0 ..< 30 where box.count < 3 {
            await Task.yield()
        }
        #expect(session.modelID == nil)
        #expect(box.count == 3)
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "FloatingPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    var request: ChatRequest?
    var modelIDs: [UUID] = []
    var count = 0

    func store(_ request: ChatRequest) {
        lock.lock()
        count += 1
        self.request = request
        lock.unlock()
    }

    func record(modelID: UUID) {
        lock.lock()
        modelIDs.append(modelID)
        lock.unlock()
    }
}

private struct ScriptedProvider: ChatProvider {
    let events: [ChatStreamEvent]
    let box: RequestBox

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        box.store(request)
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}

@MainActor
private final class ScriptedFactory: ChatProviderFactory {
    let box: RequestBox
    let events: [ChatStreamEvent]

    init(box: RequestBox, events: [ChatStreamEvent]) {
        self.box = box
        self.events = events
    }

    func makeProvider() throws -> any ChatProvider { ScriptedProvider(events: events, box: box) }
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot { .testValue() }
    func makeTargetSnapshot(modelID: UUID) throws -> ProviderTargetSnapshot {
        box.record(modelID: modelID)
        return .testValue()
    }
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        ScriptedProvider(events: events, box: box)
    }
}

@MainActor
private final class FakeFloatingWindow: FloatingPromptWindowing {
    let onClosed: () -> Void
    init(onClosed: @escaping () -> Void) { self.onClosed = onClosed }
    func show(near anchor: SelectionAnchor) {}
    func close() { onClosed() }
}

@MainActor
private final class FloatingPanelSpy: SpotAskPanelControlling {
    func setContent(_ content: @escaping () -> AnyView) {}
    func show() {}
    func hide() {}
    func toggle() {}
    func toggleWindowOnTop() {}
    var isVisible = false
}

@MainActor
private final class FloatingCommandRecorder {
    var actions: [SpotAskCommandAction] = []
}
