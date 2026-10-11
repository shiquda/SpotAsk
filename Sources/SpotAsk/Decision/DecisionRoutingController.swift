import Foundation
import Observation

struct DecisionRoutingTicket: Equatable, Sendable {
    var generation: UInt64
    var question: String
}

enum DecisionChooseReason: Equatable, Sendable {
    case changeChannel
    case timeout
    /// A precondition with no typed failure (no in-app fallback route).
    case unavailable
    /// A resolver, network or parser failure, classified and sanitized.
    case failed(DecisionRoutingFailure)
}

enum DecisionRoutingPhase: Equatable, Sendable {
    case idle
    case deciding(DecisionRoutingTicket)
    case autoSending(DecisionRoutingTicket, DecisionRouteCandidate)
    case confirming(DecisionRoutingTicket, DecisionRouteCandidate, confidence: Double)
    case choosing(DecisionRoutingTicket, DecisionChooseReason, highlightedID: String)

    var ticket: DecisionRoutingTicket? {
        switch self {
        case .idle:
            nil
        case let .deciding(ticket),
             let .autoSending(ticket, _),
             let .confirming(ticket, _, _),
             let .choosing(ticket, _, _):
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

/// What a routing decision is allowed to send for, frozen when the decision
/// starts. Consumption compares this against the live editor and revokes the
/// decision on any difference, so a route chosen for one draft can never send
/// another.
struct DecisionSendSnapshot: Equatable, Sendable {
    /// Raw composer draft. Compared untrimmed so any edit marks a difference.
    var draft: String
    /// Draft attachments of that moment, by identifier.
    var attachmentIDs: [UUID]
    /// Explicit prompt preset the send was made with, compared by value so an
    /// edited instruction revokes too. `nil` means none.
    var preset: PromptPreset?
    /// Visible conversation the decision was made in.
    var sessionIdentity: UInt64
    /// Global routing switch state.
    var routingEnabled: Bool
    /// Effective per-conversation routing state, after the hidden-toggle rule.
    var sessionRoutingEnabled: Bool
    /// Channel mounted in the composer by the user, when there is one.
    var manualChannelID: UUID?
    /// Routes offered to the decision model, availability and preferences included.
    var candidates: [DecisionRouteCandidate]

    /// First field that no longer matches `current`, in a fixed order. Names
    /// describe the condition that stopped holding: a snapshot is only taken
    /// while routing is on, so both boolean cases mean "was turned off".
    func firstDifference(comparedTo current: DecisionSendSnapshot) -> DecisionSnapshotChange? {
        if draft != current.draft { return .draft }
        if attachmentIDs != current.attachmentIDs { return .attachments }
        if preset != current.preset { return .preset }
        if sessionIdentity != current.sessionIdentity { return .session }
        if routingEnabled != current.routingEnabled { return .routingDisabled }
        if sessionRoutingEnabled != current.sessionRoutingEnabled { return .sessionRoutingDisabled }
        if manualChannelID != current.manualChannelID { return .manualChannel }
        if candidates != current.candidates { return .candidates }
        return nil
    }
}

/// Why a delivered decision can no longer be used.
enum DecisionSnapshotChange: Equatable, Sendable {
    case draft
    case attachments
    case preset
    case session
    case routingDisabled
    case sessionRoutingDisabled
    case manualChannel
    case candidates
}

/// A decided route delivered to the UI and not consumed yet.
struct DecisionPendingSend: Equatable, Sendable {
    var candidate: DecisionRouteCandidate
    var ticket: DecisionRoutingTicket
    /// The frozen send context this decision was made for.
    var snapshot: DecisionSendSnapshot
}

/// Outcome of trying to consume a delivered decision.
enum DecisionSendConsumption: Equatable, Sendable {
    case none
    case consume(DecisionPendingSend)
    case revoked(DecisionSnapshotChange)
}

@MainActor
@Observable
final class DecisionRoutingController {
    private(set) var phase: DecisionRoutingPhase = .idle
    private(set) var candidates: [DecisionRouteCandidate] = []
    /// Decided route waiting for the send path to consume it, if any.
    private(set) var pendingSend: DecisionPendingSend?
    /// Send context the active decision was started for.
    private var activeSnapshot: DecisionSendSnapshot?
    private var generation: UInt64 = 0
    private var consumed: Set<UInt64> = []
    private var task: Task<Void, Never>?

    var hasPendingSend: Bool { pendingSend != nil }

    /// Starts a decision for exactly `sendSnapshot`. The draft, attachments,
    /// preset, session, routing state and routes the decision may act on are
    /// frozen here; any later change revokes the decision and a delivered
    /// result. A new start supersedes both an active decision and any
    /// delivered-but-unconsumed result.
    func start(
        sendSnapshot: DecisionSendSnapshot,
        modelQuestion: String,
        settings: DecisionRoutingSettings,
        apiKey: String?,
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        autoSendSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        if let ticket = phase.ticket {
            invalidate(ticket.generation)
        }
        pendingSend = nil
        generation += 1
        let ticket = DecisionRoutingTicket(generation: generation, question: sendSnapshot.draft)
        candidates = sendSnapshot.candidates
        activeSnapshot = sendSnapshot
        phase = .deciding(ticket)
        let generation = ticket.generation
        task = Task { [weak self] in
            await self?.run(
                generation: generation,
                modelQuestion: modelQuestion,
                candidates: sendSnapshot.candidates,
                settings: settings,
                apiKey: apiKey,
                transport: transport,
                sleep: sleep,
                autoSendSleep: autoSendSleep
            )
        }
    }

    /// Draft edits drop a delivered-but-unconsumed result too.
    /// Returns `.draft` when that happened, so the UI can say why.
    @discardableResult
    func noteInput(_ text: String) -> DecisionSnapshotChange? {
        var revoked: DecisionSnapshotChange?
        if let pending = pendingSend, pending.snapshot.draft != text {
            pendingSend = nil
            revoked = .draft
        }
        if let ticket = phase.ticket, text != ticket.question {
            invalidate(ticket.generation)
        }
        return revoked
    }

    /// Called on every attachment, preset, session and settings change while a
    /// decision is running or a delivered result is waiting. Either difference
    /// revokes, so a change that is later reverted cannot revive them, and the
    /// user's draft and attachments are never touched.
    /// Returns why a delivered-but-unconsumed result was dropped, if it was.
    @discardableResult
    func noteSendContextChanged(_ current: DecisionSendSnapshot) -> DecisionSnapshotChange? {
        if let activeSnapshot,
           let ticket = phase.ticket,
           activeSnapshot.firstDifference(comparedTo: current) != nil {
            invalidate(ticket.generation)
        }
        guard let pending = pendingSend,
              let change = pending.snapshot.firstDifference(comparedTo: current) else { return nil }
        pendingSend = nil
        return change
    }

    /// Validates against the live send context immediately before use and
    /// consumes at most once: the pending result is cleared first, so a second
    /// call cannot send it again and a revoked result is never executed.
    func consumePendingSend(against current: DecisionSendSnapshot) -> DecisionSendConsumption {
        guard let pending = pendingSend else { return .none }
        pendingSend = nil
        guard let change = pending.snapshot.firstDifference(comparedTo: current) else {
            return .consume(pending)
        }
        return .revoked(change)
    }

    func cancel() {
        if let ticket = phase.ticket {
            invalidate(ticket.generation)
        }
        // Esc and Cancel apply to a delivered result too, not only to the
        // request that is still deciding.
        pendingSend = nil
    }

    func acceptCurrent() {
        switch phase {
        case let .autoSending(ticket, candidate),
             let .confirming(ticket, candidate, _):
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

    func moveSelection(_ delta: Int) {
        guard case let .choosing(ticket, reason, highlightedID) = phase,
              !candidates.isEmpty else { return }
        let currentIndex = candidates.firstIndex(where: { $0.id == highlightedID }) ?? 0
        let count = candidates.count
        let nextIndex = ((currentIndex + delta) % count + count) % count
        phase = .choosing(ticket, reason, highlightedID: candidates[nextIndex].id)
    }

    private func run(
        generation: UInt64,
        modelQuestion: String,
        candidates: [DecisionRouteCandidate],
        settings: DecisionRoutingSettings,
        apiKey: String?,
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        autoSendSleep: @escaping @Sendable (Duration) async throws -> Void
    ) async {
        guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed) else { return }
        let call: DecisionServiceCall
        switch DecisionServiceResolver.resolve(settings: settings, apiKey: apiKey) {
        case let .success(resolved):
            call = resolved
        case let .failure(configurationError):
            enterChoosing(generation, .failed(DecisionRoutingFailure.classify(configurationError: configurationError)))
            return
        }
        do {
            let answer = try await DecisionProviderClient.evaluate(
                call: call,
                question: modelQuestion,
                criteria: DecisionRouteCatalog.criteria(for: candidates),
                transport: transport,
                sleep: sleep
            )
            guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed),
                  !Task.isCancelled else { return }
            guard let candidate = DecisionRouteCatalog.candidate(matching: answer.choice, in: candidates) else {
                enterChoosing(generation, .failed(.unrecognizedChoice))
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
                guard DecisionRoutingGate.shouldApply(generation: generation, phase: phase, consumed: consumed) else { return }
                if candidate.isInApp {
                    deliver(candidate, generation: generation)
                    return
                }
                let ticket = DecisionRoutingTicket(
                    generation: generation,
                    question: phase.ticket?.question ?? modelQuestion
                )
                phase = .autoSending(ticket, candidate)
                let bufferMs = Int((DecisionRoutingPolicy.autoSendBufferSeconds * 1_000).rounded())
                try await autoSendSleep(.milliseconds(bufferMs))
                guard !consumed.contains(generation),
                      !Task.isCancelled,
                      case let .autoSending(activeTicket, _) = phase,
                      activeTicket.generation == generation else { return }
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
                enterChoosing(generation, .failed(DecisionRoutingFailure.classify(error)))
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
        guard !consumed.contains(generation),
              let ticket = phase.ticket,
              let snapshot = activeSnapshot else { return }
        consumed.insert(generation)
        task?.cancel()
        task = nil
        phase = .idle
        activeSnapshot = nil
        pendingSend = DecisionPendingSend(candidate: candidate, ticket: ticket, snapshot: snapshot)
    }

    private func invalidate(_ generation: UInt64) {
        consumed.insert(generation)
        task?.cancel()
        task = nil
        phase = .idle
        candidates = []
        activeSnapshot = nil
    }
}
