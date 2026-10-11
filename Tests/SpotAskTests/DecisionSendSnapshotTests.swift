import Foundation
import Testing
@testable import SpotAsk

private actor SnapshotScriptedTransport: SystemOneTransport {
    private(set) var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await handler(request)
    }
}

private struct DeliveryNotReached: Error {}

@MainActor
struct DecisionSendSnapshotTests {
    private static let attachmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let presetID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let manualChannelID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private static let externalActionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private static func externalCandidate(kind: QuickActionKind) -> DecisionRouteCandidate {
        let action = QuickAction(
            id: externalActionID, name: "Local Agent", kind: kind,
            symbolName: "terminal", isEnabled: true,
            routingPurpose: "Local code edits", routingScenario: "",
            requiresConfirmationOnAutoRoute: false
        )
        return DecisionRouteCatalog.candidates(actions: [action], inAppDescription: "")[1]
    }

    private static let targetEdits: [(original: QuickActionKind, edited: QuickActionKind)] = [
        (.web(urlTemplate: "https://old.example/?q={query}"),
         .web(urlTemplate: "https://new.example/?q={query}")),
        (.uriScheme(urlTemplate: "synthetic://old?q={query}"),
         .uriScheme(urlTemplate: "synthetic://new?q={query}")),
        (.terminal(commandTemplate: "agent --ask {query}"),
         .terminal(commandTemplate: "agent --ask --verbose {query}")),
        (.web(urlTemplate: "https://example.com/?q={query}"),
         .uriScheme(urlTemplate: "https://example.com/?q={query}"))
    ]

    private static func preset(instruction: String = "Summarize in one line") -> PromptPreset {
        PromptPreset(
            id: presetID,
            title: "Brief",
            instruction: instruction,
            customSymbolName: nil,
            isBuiltIn: false,
            isEnabled: true
        )
    }

    private static func candidates(
        externalKind: QuickActionKind = .terminal(commandTemplate: "agent --ask {query}")
    ) -> [DecisionRouteCandidate] {
        [
            DecisionRouteCandidate(
                id: DecisionRouteID.inApp,
                title: "In-App",
                symbolName: "bubble.left.and.bubble.right",
                brandIconSlug: nil,
                applicableDescription: "Short in-app chat",
                forceConfirm: false,
                externalActionID: nil,
                externalActionKind: nil
            ),
            externalCandidate(kind: externalKind)
        ]
    }

    /// Full send context as the composer would capture it: one draft, no
    /// attachments or preset, routing on, and the given routes.
    private static func snapshot(
        draft: String,
        candidates: [DecisionRouteCandidate],
        preset: PromptPreset? = nil
    ) -> DecisionSendSnapshot {
        DecisionSendSnapshot(
            draft: draft,
            attachmentIDs: [],
            preset: preset,
            sessionIdentity: 0,
            routingEnabled: true,
            sessionRoutingEnabled: true,
            manualChannelID: nil,
            candidates: candidates
        )
    }

    nonisolated private static func okResponse(choice: String, confidence: Double, url: URL) -> (Data, HTTPURLResponse) {
        let json = """
        {"model":"jev-1.13.0","answers":{"route":{"type":"choice","choice":"\(choice)","confidence":\(confidence)}}}
        """
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }

    /// Runs a decision to the confirmation card and accepts it, producing the
    /// delivered-but-unconsumed result under test.
    @MainActor
    private static func deliveredExternalPending(
        draft: String = "original question",
        preset: PromptPreset? = nil,
        candidates routes: [DecisionRouteCandidate]? = nil
    ) async throws -> (controller: DecisionRoutingController, pending: DecisionPendingSend) {
        let routes = routes ?? Self.candidates()
        let transport = SnapshotScriptedTransport { request in
            Self.okResponse(choice: routes[1].id, confidence: 0.95, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .always
        let controller = DecisionRoutingController()
        controller.start(
            sendSnapshot: Self.snapshot(draft: draft, candidates: routes, preset: preset),
            modelQuestion: draft,
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<1_000 {
            if case .confirming = controller.phase { break }
            await Task.yield()
        }
        guard case .confirming = controller.phase else {
            Issue.record("expected the confirmation card before delivery")
            throw DeliveryNotReached()
        }
        controller.acceptCurrent()
        return (controller, try #require(controller.pendingSend))
    }

    @Test("Editing the draft after delivery revokes the result and it cannot be consumed")
    func draftEditAfterDeliveryRevokesPending() async throws {
        let routes = Self.candidates()
        let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
        #expect(pending.ticket.generation == 1)
        #expect(pending.snapshot.draft == "original question")
        #expect(controller.pendingSend?.candidate == routes[1])

        #expect(controller.noteInput("edited question") == .draft)
        #expect(controller.pendingSend == nil)
        #expect(controller.phase == .idle)
        // Nothing is left to consume: the old route cannot send the new draft.
        #expect(controller.consumePendingSend(against: Self.snapshot(draft: "edited question", candidates: routes)) == .none)
    }

    @Test("Cancel after delivery revokes the unconsumed result")
    func cancelAfterDeliveryRevokesPending() async throws {
        let routes = Self.candidates()
        let (controller, _) = try await Self.deliveredExternalPending(candidates: routes)
        controller.cancel()
        #expect(controller.pendingSend == nil)
        #expect(controller.consumePendingSend(against: Self.snapshot(draft: "original question", candidates: routes)) == .none)
    }

    @Test("A change that is reverted still revokes the delivered result")
    func changeThenRevertStaysRevoked() async throws {
        let routes = Self.candidates()
        let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
        var edited = pending.snapshot
        edited.draft = "edited question"
        #expect(controller.noteSendContextChanged(edited) == .draft)
        // Reverting to the original draft must not revive the revoked route.
        #expect(controller.noteSendContextChanged(pending.snapshot) == nil)
        #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        #expect(controller.pendingSend == nil)
    }

    @Test("Attachment, preset, session, manual channel and route availability changes revoke the delivered result")
    func contextChangesRevokePending() async throws {
        let routes = Self.candidates()

        do { // attachment added
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.attachmentIDs = [Self.attachmentID]
            #expect(controller.noteSendContextChanged(current) == .attachments)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
        do { // explicit preset changed
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.preset = Self.preset()
            #expect(controller.noteSendContextChanged(current) == .preset)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
        do { // conversation replaced
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.sessionIdentity = 1
            #expect(controller.noteSendContextChanged(current) == .session)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
        do { // global routing turned off
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.routingEnabled = false
            #expect(controller.noteSendContextChanged(current) == .routingDisabled)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
        do { // per-conversation routing turned off
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.sessionRoutingEnabled = false
            #expect(controller.noteSendContextChanged(current) == .sessionRoutingDisabled)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
        do { // the user mounted a channel manually
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.manualChannelID = Self.manualChannelID
            #expect(controller.noteSendContextChanged(current) == .manualChannel)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
        do { // a route became unavailable
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.candidates = [routes[0]]
            #expect(controller.noteSendContextChanged(current) == .candidates)
            #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        }
    }

    @Test("Editing the selected preset instruction revokes the delivered result even with the same preset id")
    func presetInstructionChangeRevokesPending() async throws {
        let routes = Self.candidates()
        let (controller, pending) = try await Self.deliveredExternalPending(
            preset: Self.preset(instruction: "Summarize in one line"),
            candidates: routes
        )
        #expect(pending.snapshot.preset?.id == Self.presetID)

        // Settings synchronization replaces the preset with the same id but a
        // new instruction; the decision was made for the old prompt.
        var current = pending.snapshot
        current.preset = Self.preset(instruction: "Summarize in three bullet points")
        #expect(controller.noteSendContextChanged(current) == .preset)
        #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        #expect(controller.pendingSend == nil)
    }

    @Test("A new start supersedes a delivered-but-unconsumed result")
    func startRevokesUnconsumedPending() async throws {
        let routes = Self.candidates()
        let (controller, _) = try await Self.deliveredExternalPending(candidates: routes)
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .always
        let transport = SnapshotScriptedTransport { _ in
            try await Task.sleep(for: .seconds(60))
            return Self.okResponse(choice: routes[1].id, confidence: 0.95, url: SystemOneEndpoint.officialEvaluationURL)
        }
        controller.start(
            sendSnapshot: Self.snapshot(draft: "second question", candidates: routes),
            modelQuestion: "second question",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        #expect(controller.pendingSend == nil)
        #expect(controller.phase.ticket?.question == "second question")
        controller.cancel()
    }

    @Test("Consumption is single flight and matches exactly the frozen snapshot")
    func consumptionSingleFlight() async throws {
        let routes = Self.candidates()
        let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)

        // A drifted context revokes instead of sending, and nothing is consumed.
        var drifted = pending.snapshot
        drifted.draft = "new content typed after the decision"
        #expect(controller.consumePendingSend(against: drifted) == .revoked(.draft))
        #expect(controller.pendingSend == nil)

        // The matching snapshot consumes once and only once.
        let (controller2, pending2) = try await Self.deliveredExternalPending(candidates: routes)
        guard case let .consume(consumed) = controller2.consumePendingSend(against: pending2.snapshot) else {
            Issue.record("expected the matching snapshot to be consumable")
            return
        }
        #expect(consumed.candidate == routes[1])
        #expect(consumed.snapshot.draft == "original question")
        #expect(consumed.ticket.generation == 1)
        #expect(controller2.consumePendingSend(against: pending2.snapshot) == .none)
        #expect(controller2.pendingSend == nil)
    }

    @Test("Context changes during confirming or the 0.8s buffer invalidate the decision before delivery")
    func contextChangeInvalidatesActivePhases() async throws {
        let routes = Self.candidates()
        let transport = SnapshotScriptedTransport { request in
            Self.okResponse(choice: routes[1].id, confidence: 0.95, url: request.url!)
        }

        // While the confirmation card is up.
        var alwaysConfirm = DecisionRoutingSettings.disabled
        alwaysConfirm.isEnabled = true
        alwaysConfirm.confirmationMode = .always
        let controller = DecisionRoutingController()
        controller.start(
            sendSnapshot: Self.snapshot(draft: "help me debug", candidates: routes),
            modelQuestion: "help me debug",
            settings: alwaysConfirm,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<1_000 {
            if case .confirming = controller.phase { break }
            await Task.yield()
        }
        guard case .confirming = controller.phase else {
            Issue.record("expected the confirmation card")
            throw DeliveryNotReached()
        }
        var changed = Self.snapshot(draft: "help me debug", candidates: routes, preset: Self.preset())
        #expect(controller.noteSendContextChanged(changed) == nil)
        #expect(controller.phase == .idle)
        // Accepting afterwards must not deliver anything.
        controller.acceptCurrent()
        #expect(controller.pendingSend == nil)

        // During the 0.8s auto-send buffer.
        var threshold = DecisionRoutingSettings.disabled
        threshold.isEnabled = true
        threshold.confirmationMode = .threshold
        threshold.confidenceThreshold = 0.8
        let bufferController = DecisionRoutingController()
        bufferController.start(
            sendSnapshot: Self.snapshot(draft: "deploy check", candidates: routes),
            modelQuestion: "deploy check",
            settings: threshold,
            apiKey: "test-token",
            transport: transport,
            autoSendSleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<1_000 {
            if case .autoSending = bufferController.phase { break }
            await Task.yield()
        }
        guard case .autoSending = bufferController.phase else {
            Issue.record("expected the auto-send buffer")
            throw DeliveryNotReached()
        }
        var changedBuffer = Self.snapshot(draft: "deploy check", candidates: routes)
        changedBuffer.attachmentIDs = [Self.attachmentID]
        #expect(bufferController.noteSendContextChanged(changedBuffer) == nil)
        #expect(bufferController.phase == .idle)
        // Return during the buffer now sends nothing, and the buffer expiry
        // cannot deliver afterwards either.
        bufferController.acceptCurrent()
        #expect(bufferController.pendingSend == nil)
    }

    @Test("A revoked decision cannot be re-delivered by a late response")
    func lateResponseAfterRevocationDoesNotDeliver() async throws {
        let routes = Self.candidates()
        let transport = SnapshotScriptedTransport { request in
            try await Task.sleep(for: .milliseconds(150))
            return Self.okResponse(choice: routes[1].id, confidence: 0.95, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .always
        let controller = DecisionRoutingController()
        controller.start(
            sendSnapshot: Self.snapshot(draft: "slow check", candidates: routes),
            modelQuestion: "slow check",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        #expect(controller.phase.isActive)
        var changed = Self.snapshot(draft: "slow check", candidates: routes)
        changed.attachmentIDs = [Self.attachmentID]
        #expect(controller.noteSendContextChanged(changed) == nil)
        #expect(controller.phase == .idle)

        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.phase == .idle)
        #expect(controller.pendingSend == nil)
    }

    @Test("A delivered in-app route is revoked when the conversation changes")
    func inAppPendingRevokedOnSessionChange() async throws {
        let routes = Self.candidates()
        let transport = SnapshotScriptedTransport { request in
            Self.okResponse(choice: DecisionRouteID.inApp, confidence: 0.95, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .threshold
        settings.confidenceThreshold = 0.8
        let controller = DecisionRoutingController()
        controller.start(
            sendSnapshot: Self.snapshot(draft: "original question", candidates: routes),
            modelQuestion: "original question",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<1_000 where controller.pendingSend == nil {
            await Task.yield()
        }
        let pending = try #require(controller.pendingSend)
        #expect(pending.candidate.isInApp)

        var changed = pending.snapshot
        changed.sessionIdentity = 1
        #expect(controller.noteSendContextChanged(changed) == .session)
        #expect(controller.consumePendingSend(against: pending.snapshot) == .none)
        #expect(controller.pendingSend == nil)
    }

    @Test("Same-id action target edits revoke the delivered result")
    func actionTargetEditRevokesDeliveredResult() async throws {
        for change in Self.targetEdits {
            let routes = Self.candidates(externalKind: change.original)
            let edited = Self.candidates(externalKind: change.edited)
            let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
            var current = pending.snapshot
            current.candidates = edited
            #expect(controller.noteSendContextChanged(current) == .candidates)
            #expect(controller.pendingSend == nil)
            #expect(controller.consumePendingSend(against: current) == .none)
            #expect(current.draft == pending.snapshot.draft)
        }
    }

    @Test("A target edit hidden from the UI is still rejected at consume time and keeps the draft")
    func targetEditRejectedAtConsumeTimeWithoutObserver() async throws {
        let routes = Self.candidates(externalKind: .terminal(commandTemplate: "agent --ask {query}"))
        let (controller, pending) = try await Self.deliveredExternalPending(candidates: routes)
        // Simulate an edit that never reached noteSendContextChanged: consumption
        // must revalidate the live snapshot itself.
        var current = pending.snapshot
        current.candidates = Self.candidates(externalKind: .web(urlTemplate: "https://example.com/?q={query}"))
        #expect(controller.consumePendingSend(against: current) == .revoked(.candidates))
        #expect(controller.pendingSend == nil)
        // The rejection never rewrites the frozen draft or the decided target.
        #expect(pending.snapshot.draft == "original question")
        #expect(pending.candidate == routes[1])
    }


    @Test("Same-id target edits cancel confirmation and the 0.8s buffer")
    func targetEditInvalidatesActivePhases() async throws {
        for change in Self.targetEdits {
            let routes = Self.candidates(externalKind: change.original)
            let edited = Self.candidates(externalKind: change.edited)
            for mode in [DecisionConfirmationMode.always, .threshold] {
                let transport = SnapshotScriptedTransport { request in
                    Self.okResponse(choice: routes[1].id, confidence: 0.95, url: request.url!)
                }
                var settings = DecisionRoutingSettings.disabled
                settings.isEnabled = true
                settings.confirmationMode = mode
                settings.confidenceThreshold = 0.8
                let controller = DecisionRoutingController()
                let snapshot = Self.snapshot(draft: "retained question", candidates: routes)
                controller.start(
                    sendSnapshot: snapshot,
                    modelQuestion: snapshot.draft,
                    settings: settings,
                    apiKey: "test-token",
                    transport: transport,
                    sleep: { _ in try await Task.sleep(for: .seconds(60)) },
                    autoSendSleep: { _ in try await Task.sleep(for: .seconds(60)) }
                )
                var reachedPhase = false
                for _ in 0..<1_000 {
                    if mode == .always, case .confirming = controller.phase {
                        reachedPhase = true
                        break
                    }
                    if mode == .threshold, case .autoSending = controller.phase {
                        reachedPhase = true
                        break
                    }
                    await Task.yield()
                }
                try #require(reachedPhase)
                var current = snapshot
                current.candidates = edited
                #expect(controller.noteSendContextChanged(current) == nil)
                #expect(controller.phase == .idle)
                controller.acceptCurrent()
                #expect(controller.consumePendingSend(against: current) == .none)
                #expect(controller.pendingSend == nil)
                #expect(current.draft == snapshot.draft)
            }
        }
    }
}
