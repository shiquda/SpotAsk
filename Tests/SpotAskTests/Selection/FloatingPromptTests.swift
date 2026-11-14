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
        for request in [FloatingPromptCloseRequest.escape, .closeButton, .commandW, .continueInConversation] {
            #expect(FloatingPromptDismissal.shouldClose(isPinned: true, request: request))
        }
    }

    @Test("Only plain Command-W is the close chord")
    func commandWMatchesOnlyPlainCommandW() {
        #expect(FloatingPromptCloseChord.isCloseWindow(modifiers: .command, charactersIgnoringModifiers: "w"))
        #expect(FloatingPromptCloseChord.isCloseWindow(modifiers: [.command, .capsLock], charactersIgnoringModifiers: "W"))
        #expect(!FloatingPromptCloseChord.isCloseWindow(modifiers: [.command, .shift], charactersIgnoringModifiers: "w"))
        #expect(!FloatingPromptCloseChord.isCloseWindow(modifiers: [.command, .option], charactersIgnoringModifiers: "w"))
        #expect(!FloatingPromptCloseChord.isCloseWindow(modifiers: [.command, .control], charactersIgnoringModifiers: "w"))
        #expect(!FloatingPromptCloseChord.isCloseWindow(modifiers: [], charactersIgnoringModifiers: "w"))
        #expect(!FloatingPromptCloseChord.isCloseWindow(modifiers: .command, charactersIgnoringModifiers: "c"))
        #expect(!FloatingPromptCloseChord.isCloseWindow(modifiers: .command, charactersIgnoringModifiers: nil))
    }

    @Test("Command-W closes the key floating window even while pinned")
    func commandWClosesPinnedFloatingWindow() async throws {
        let box = RequestBox()
        let settings = makeSettings()
        let snapshot = SelectedTextSnapshot(
            text: "selected passage",
            source: SelectionSourceApplication(processIdentifier: 7, bundleIdentifier: "com.example.Source", localizedName: "Source"),
            selectedRange: SelectionCharacterRange(location: 0, length: 16),
            anchor: .pointer(CGPoint(x: 300, y: 500))
        )
        let session = FloatingPromptSession(
            snapshot: snapshot,
            preset: PromptPreset.builtIn[0],
            settings: settings,
            providerFactory: ScriptedFactory(box: box, events: [.answerDelta("explained")]),
            modelID: nil
        )
        var closeCount = 0
        let controller = FloatingPromptWindowController(
            session: session,
            settings: settings,
            onContinue: { _ in },
            onClosed: { closeCount += 1 }
        )
        session.isPinned = true
        session.start()
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        controller.show(near: snapshot.anchor)
        // Tests run in parallel and each one shows a panel, so find the one
        // this controller owns (it is the panel's delegate).
        let panel = try #require(NSApp.windows.first { $0.delegate === controller && $0.isVisible })
        // The handler only acts on the key window, so claim it first.
        panel.makeKey()
        #expect(panel.isKeyWindow)

        let shiftedCommandW = try #require(floatingKeyEvent(key: "w", keyCode: 13, modifiers: [.command, .shift], window: panel))
        let commandC = try #require(floatingKeyEvent(key: "c", keyCode: 8, modifiers: [.command], window: panel))
        #expect(controller.handleLocalEvent(shiftedCommandW) === shiftedCommandW)
        #expect(controller.handleLocalEvent(commandC) === commandC)
        #expect(closeCount == 0)
        #expect(panel.isVisible)

        let commandW = try #require(floatingKeyEvent(key: "w", keyCode: 13, modifiers: [.command], window: panel))
        panel.makeKey()
        #expect(panel.isKeyWindow)
        #expect(controller.handleLocalEvent(commandW) == nil)
        // The close fades out on the main run loop, which other tests share.
        for _ in 0 ..< 100 where closeCount == 0 || panel.isVisible {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(closeCount == 1)
        #expect(!panel.isVisible)
    }

    @Test("A click in the model menu is not an outside click")
    func modelMenuClickStaysInside() {
        let panel = CGRect(x: 100, y: 100, width: 380, height: 460)
        let menu = CGRect(x: 180, y: 540, width: 220, height: 280)
        let pick = CGPoint(x: 240, y: 700)
        #expect(!FloatingPromptOutsideClick.isOutside(mouse: pick, panelFrame: panel, attachedFrames: [menu]))
        #expect(FloatingPromptOutsideClick.isOutside(mouse: CGPoint(x: 20, y: 20), panelFrame: panel, attachedFrames: [menu]))
        #expect(!FloatingPromptOutsideClick.isOutside(mouse: CGPoint(x: 120, y: 140), panelFrame: panel, attachedFrames: []))
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

    @Test("Render floating prompt window to image")
    func renderFloatingPromptWindow() async throws {
        let box = RequestBox()
        let factory = ScriptedFactory(box: box, events: [
            .answerDelta("当您按下 Option-Space 时，SpotAsk 会打开一个小提问窗口，因此您无需离开当前任务即可提出问题。")
        ])
        let settings = makeSettings()
        let snapshot = SelectedTextSnapshot(
            text: "SpotAsk opens a small question window when you press Option-Space, so you can ask a question without leaving your current task.",
            source: SelectionSourceApplication(processIdentifier: 7, bundleIdentifier: "com.apple.Safari", localizedName: "Safari"),
            selectedRange: SelectionCharacterRange(location: 0, length: 114),
            anchor: .pointer(CGPoint(x: 200, y: 400))
        )
        let session = FloatingPromptSession(
            snapshot: snapshot,
            preset: PromptPreset.builtIn[0],
            settings: settings,
            providerFactory: factory,
            modelID: nil
        )
        let controller = FloatingPromptWindowController(
            session: session,
            settings: settings,
            onContinue: { _ in },
            onClosed: {}
        )
        session.start()
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        controller.show(near: snapshot.anchor)
        if let panel = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("FloatingPromptPanel") }),
           let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: "/tmp/floating_prompt_translate.png"))
                }
            }
        }
        controller.close()
    }

    @Test("Render Polish floating prompt window to image")
    func renderPolishFloatingPromptWindow() async throws {
        let box = RequestBox()
        let factory = ScriptedFactory(box: box, events: [
            .answerDelta("Could you please send me the revised document when you have a moment?")
        ])
        let settings = makeSettings()
        let snapshot = SelectedTextSnapshot(
            text: "I was wondering if you might possibly be able to send me the revised document when you have a moment.",
            source: SelectionSourceApplication(processIdentifier: 8, bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
            selectedRange: SelectionCharacterRange(location: 0, length: 99),
            anchor: .pointer(CGPoint(x: 200, y: 400))
        )
        let session = FloatingPromptSession(
            snapshot: snapshot,
            preset: PromptPreset.builtIn[3],
            settings: settings,
            providerFactory: factory,
            modelID: nil
        )
        let controller = FloatingPromptWindowController(
            session: session,
            settings: settings,
            onContinue: { _ in },
            onClosed: {}
        )
        session.start()
        for _ in 0 ..< 30 where session.phase != .complete {
            await Task.yield()
        }
        controller.show(near: snapshot.anchor)
        if let panel = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("FloatingPromptPanel") }),
           let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: "/tmp/floating_prompt_polish.png"))
                }
            }
        }
        controller.close()
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "FloatingPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private func floatingKeyEvent(
        key: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        window: NSWindow
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        )
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
