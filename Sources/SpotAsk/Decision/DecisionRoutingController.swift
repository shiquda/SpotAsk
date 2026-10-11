import Foundation
import Observation

struct DecisionRoutingTicket: Equatable, Sendable {
    var generation: UInt64
    var question: String
}

enum DecisionChooseReason: Equatable, Sendable {
    case changeChannel
    case timeout
    case unavailable
}

enum DecisionRoutingPhase: Equatable, Sendable {
    case idle
    case deciding(DecisionRoutingTicket)
    case confirming(DecisionRoutingTicket, DecisionRouteCandidate, confidence: Double)
    case choosing(DecisionRoutingTicket, DecisionChooseReason, highlightedID: String)

    var ticket: DecisionRoutingTicket? {
        switch self {
        case .idle:
            nil
        case let .deciding(ticket), let .confirming(ticket, _, _), let .choosing(ticket, _, _):
            ticket
        }
    }

    var isActive: Bool { ticket != nil }

    var highlightedID: String? {
        if case let .choosing(_, _, highlightedID) = self { return highlightedID }
        return nil
    }
}

enum DecisionRoutingGate {
    static func shouldApply(generation: UInt64, phase: DecisionRoutingPhase, consumed: Set<UInt64>) -> Bool {
        guard !consumed.contains(generation) else { return false }
        guard case let .deciding(ticket) = phase, ticket.generation == generation else { return false }
        return true
    }
}

@MainActor
@Observable
final class DecisionRoutingController {
    private(set) var phase: DecisionRoutingPhase = .idle
    private(set) var candidates: [DecisionRouteCandidate] = []
    private(set) var pendingExecution: DecisionRouteCandidate?
    private var generation: UInt64 = 0
    private var consumed: Set<UInt64> = []
    private var task: Task<Void, Never>?

    func start(
        snapshotQuestion: String,
        modelQuestion: String,
        candidates: [DecisionRouteCandidate],
        settings: DecisionRoutingSettings,
        officialKey: String?,
        customKey: String?,
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        if let ticket = phase.ticket {
            invalidate(ticket.generation)
        }
        generation += 1
        let ticket = DecisionRoutingTicket(generation: generation, question: snapshotQuestion)
        self.candidates = candidates
        phase = .deciding(ticket)
        let generation = ticket.generation
        task = Task { [weak self] in
            await self?.run(
                generation: generation,
                modelQuestion: modelQuestion,
                candidates: candidates,
                settings: settings,
                officialKey: officialKey,
                customKey: customKey,
                transport: transport,
                sleep: sleep
            )
        }
    }

    func noteInput(_ text: String) {
        guard let ticket = phase.ticket, text != ticket.question else { return }
        invalidate(ticket.generation)
    }

    func cancel() {
        guard let ticket = phase.ticket else { return }
        invalidate(ticket.generation)
    }

    func acceptCurrent() {
        switch phase {
        case let .confirming(ticket, candidate, _):
            deliver(candidate, generation: ticket.generation)
        case let .choosing(ticket, _, highlightedID):
            guard let candidate = candidates.first(where: { $0.id == highlightedID }) else { return }
            deliver(candidate, generation: ticket.generation)
        case .idle, .deciding:
            break
        }
    }

    func select(_ id: String) {
        guard let ticket = phase.ticket,
              let candidate = candidates.first(where: { $0.id == id }) else { return }
        deliver(candidate, generation: ticket.generation)
    }

    func showManualChoice() {
        guard case let .confirming(ticket, _, _) = phase else { return }
        phase = .choosing(ticket, .changeChannel, highlightedID: candidates.first?.id ?? DecisionRouteID.inApp)
    }

    func clearPendingExecution() {
        pendingExecution = nil
    }

    private func run(
        generation: UInt64,
        modelQuestion: String,
        candidates: [DecisionRouteCandidate],
        settings: DecisionRoutingSettings,
        officialKey: String?,
        customKey: String?,
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async {
        guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed) else { return }
        guard let url = SystemOneEndpoint.evaluationURL(
            endpoint: settings.endpoint,
            customBaseURL: settings.customBaseURL
        ) else {
            enterChoosing(generation, .unavailable)
            return
        }
        guard let model = DecisionRoutingPolicy.modelName(
            endpoint: settings.endpoint,
            officialModel: settings.officialModel,
            customModel: settings.customModel
        ) else {
            enterChoosing(generation, .unavailable)
            return
        }
        let key = DecisionRoutingPolicy.apiKey(
            endpoint: settings.endpoint,
            official: officialKey,
            custom: customKey
        )
        if settings.endpoint == .official, key == nil {
            enterChoosing(generation, .unavailable)
            return
        }
        let client = SystemOneClient(transport: transport, sleep: sleep)
        do {
            let answer = try await client.evaluate(
                question: modelQuestion,
                model: model,
                criteria: DecisionRouteCatalog.criteria(for: candidates),
                url: url,
                apiKey: key,
                timeout: DecisionRoutingPolicy.normalizedTimeout(settings.timeoutSeconds)
            )
            guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed),
                  !Task.isCancelled else { return }
            guard let candidate = DecisionRouteCatalog.candidate(matching: answer.choice, in: candidates) else {
                enterChoosing(generation, .unavailable)
                return
            }
            let release = DecisionRoutingPolicy.release(
                forceConfirm: candidate.forceConfirm,
                mode: settings.confirmationMode,
                confidence: answer.confidence,
                threshold: settings.confidenceThreshold
            )
            switch release {
            case .confirm:
                guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed) else { return }
                phase = .confirming(
                    DecisionRoutingTicket(generation: generation, question: phase.ticket?.question ?? modelQuestion),
                    candidate,
                    confidence: answer.confidence
                )
            case .autoSend:
                deliver(candidate, generation: generation)
            }
        } catch is CancellationError {
            return
        } catch {
            guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed),
                  !Task.isCancelled else { return }
            if SystemOneClient.isTimeout(error) {
                applyTimeout(generation, action: settings.timeoutAction, candidates: candidates)
            } else {
                enterChoosing(generation, .unavailable)
            }
        }
    }

    private func applyTimeout(
        _ generation: UInt64,
        action: DecisionTimeoutAction,
        candidates: [DecisionRouteCandidate]
    ) {
        guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed) else { return }
        switch action {
        case .manualSelection:
            enterChoosing(generation, .timeout)
        case .inApp:
            guard let inApp = candidates.first(where: \.isInApp) else {
                enterChoosing(generation, .unavailable)
                return
            }
            deliver(inApp, generation: generation)
        }
    }

    private func enterChoosing(_ generation: UInt64, _ reason: DecisionChooseReason) {
        guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed),
              let ticket = phase.ticket else { return }
        phase = .choosing(ticket, reason, highlightedID: candidates.first?.id ?? DecisionRouteID.inApp)
    }

    private func deliver(_ candidate: DecisionRouteCandidate, generation: UInt64) {
        guard !consumed.contains(generation) else { return }
        consumed.insert(generation)
        task?.cancel()
        task = nil
        phase = .idle
        pendingExecution = candidate
    }

    private func invalidate(_ generation: UInt64) {
        consumed.insert(generation)
        task?.cancel()
        task = nil
        phase = .idle
        candidates = []
    }
}
