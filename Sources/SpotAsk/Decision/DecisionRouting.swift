import Foundation

/// Routing backend. Only System One is implemented. OpenAI Decision API and
/// generative LLM providers should be additional cases with their own client,
/// not branches inside `SystemOneRequestBuilder`.
enum DecisionProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemOne

    var id: String { rawValue }
}

enum DecisionConfirmationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case always
    case threshold

    var id: String { rawValue }
}

enum DecisionTimeoutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualSelection
    case inApp

    var id: String { rawValue }
}

enum DecisionCredentialSlot {
    /// Single System One credential. Matches the previous official slot so an existing TypeSafe key keeps working.
    static let systemOne = UUID(uuidString: "D3C15100-0000-4000-8000-0000000000E1")!
    /// Previous custom-endpoint slot. Kept so an old backup can restore without wiping that key.
    static let legacyCustom = UUID(uuidString: "D3C15100-0000-4000-8000-0000000000E2")!
    static let all: Set<UUID> = [systemOne, legacyCustom]
    static let preferLegacyCustomKey = "decisionRoutingPreferLegacyCustomCredential"

    static func activeAPIKey(systemOne key: String?, legacyCustom: String?, preferLegacyCustom: Bool) -> String? {
        if preferLegacyCustom, let legacy = DecisionRoutingPolicy.normalizedAPIKey(legacyCustom) {
            return legacy
        }
        return DecisionRoutingPolicy.normalizedAPIKey(key)
    }
}

enum DecisionRouteID {
    static let inApp = "in_app"

    static func external(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}

enum DecisionRelease: Equatable, Sendable {
    case autoSend
    case confirm
}

enum DecisionRoutingPolicy {
    static let defaultServiceURL = "https://api.typesafe.ai"
    static let defaultOfficialModel = "jev-1.13.0"
    static let defaultThreshold = 0.8
    static let defaultTimeoutSeconds = 2.0
    static let minimumTimeoutSeconds = 0.5
    static let maximumTimeoutSeconds = 5.0
    static let timeoutStepSeconds = 0.1
    static let routeQuestionID = "route"
    static let routeInstructions = "Choose the single best destination for this question. Each option starts with its channel name, then any preference. If no preference is present, use the channel name. Do not invent an option."

    static func normalizedThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultThreshold }
        return min(max(value, 0), 1)
    }

    static func normalizedTimeout(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTimeoutSeconds }
        return min(max(value, minimumTimeoutSeconds), maximumTimeoutSeconds)
    }

    /// Channel force-confirm wins. Otherwise the global mode applies.
    /// Threshold mode auto-sends only when confidence is strictly above the threshold.
    static func release(
        forceConfirm: Bool,
        mode: DecisionConfirmationMode,
        confidence: Double,
        threshold: Double
    ) -> DecisionRelease {
        if forceConfirm { return .confirm }
        switch mode {
        case .always:
            return .confirm
        case .threshold:
            return confidence > normalizedThreshold(threshold) ? .autoSend : .confirm
        }
    }

    /// A manually mounted channel is never rewritten. One candidate is not a choice.
    static func shouldConsultModel(
        routingEnabled: Bool,
        hasManualChannel: Bool,
        candidateCount: Int
    ) -> Bool {
        routingEnabled && !hasManualChannel && candidateCount >= 2
    }

    static func modelName(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultOfficialModel : trimmed
    }

    static func normalizedAPIKey(_ value: String?) -> String? {
        let trimmed = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\_", with: "_")
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DecisionRoutingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var provider: DecisionProviderKind
    var serviceURL: String
    var model: String
    var confirmationMode: DecisionConfirmationMode
    var confidenceThreshold: Double
    var timeoutSeconds: Double
    var timeoutAction: DecisionTimeoutAction
    var inAppDescription: String

    static let disabled = DecisionRoutingSettings(
        isEnabled: false,
        provider: .systemOne,
        serviceURL: DecisionRoutingPolicy.defaultServiceURL,
        model: DecisionRoutingPolicy.defaultOfficialModel,
        confirmationMode: .always,
        confidenceThreshold: DecisionRoutingPolicy.defaultThreshold,
        timeoutSeconds: DecisionRoutingPolicy.defaultTimeoutSeconds,
        timeoutAction: .manualSelection,
        inAppDescription: ""
    )
}

enum DecisionRoutingMigration {
    static func serviceFields(
        hasStoredServiceURL: Bool,
        storedServiceURL: String,
        storedModel: String,
        legacyEndpoint: String?,
        legacyOfficialModel: String?,
        legacyCustomURL: String?,
        legacyCustomModel: String?
    ) -> (serviceURL: String, model: String, preferLegacyCustomCredential: Bool) {
        if hasStoredServiceURL {
            return (storedServiceURL, DecisionRoutingPolicy.modelName(storedModel), false)
        }
        if legacyEndpoint == "custom" {
            let url = (legacyCustomURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (legacyCustomModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                url.isEmpty ? DecisionRoutingPolicy.defaultServiceURL : url,
                model.isEmpty ? DecisionRoutingPolicy.defaultOfficialModel : model,
                true
            )
        }
        let officialModel = (legacyOfficialModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            DecisionRoutingPolicy.defaultServiceURL,
            officialModel.isEmpty ? DecisionRoutingPolicy.defaultOfficialModel : officialModel,
            false
        )
    }
}

struct DecisionRouteCandidate: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var symbolName: String
    var brandIconSlug: String?
    var applicableDescription: String
    var forceConfirm: Bool
    var externalActionID: UUID?

    var isInApp: Bool { id == DecisionRouteID.inApp }
}

enum DecisionRouteCatalog {
    static func applicableDescription(for action: QuickAction) -> String {
        let custom = [action.routingPurpose, action.routingScenario]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !custom.isEmpty { return custom }
        switch action.id {
        case QuickAction.BuiltInID.chatGPT:
            return L10n.string("decisionRouting.defaultChatGPT")
        case QuickAction.BuiltInID.grok:
            return L10n.string("decisionRouting.defaultGrok")
        default:
            return L10n.string("decisionRouting.defaultGeneric", action.displayName, action.kind.localizedLabel)
        }
    }

    static func inAppDescription(_ custom: String) -> String {
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return L10n.string("decisionRouting.defaultInApp")
    }

    static func candidates(
        actions: [QuickAction],
        inAppDescription customInApp: String
    ) -> [DecisionRouteCandidate] {
        var routes = [
            DecisionRouteCandidate(
                id: DecisionRouteID.inApp,
                title: L10n.string("decisionRouting.inAppTitle"),
                symbolName: "bubble.left.and.bubble.right",
                brandIconSlug: nil,
                applicableDescription: inAppDescription(customInApp),
                forceConfirm: false,
                externalActionID: nil
            )
        ]
        for action in actions where action.isEnabled {
            routes.append(
                DecisionRouteCandidate(
                    id: DecisionRouteID.external(action.id),
                    title: action.displayName,
                    symbolName: action.symbolName,
                    brandIconSlug: action.brandIconSlug,
                    applicableDescription: applicableDescription(for: action),
                    forceConfirm: action.requiresConfirmationOnAutoRoute,
                    externalActionID: action.id
                )
            )
        }
        return routes
    }

    static func criterionText(name: String, description: String) -> String {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return detail }
        if detail.isEmpty { return title }
        return "\(title). \(detail)"
    }

    static func criteria(for candidates: [DecisionRouteCandidate]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            (candidate.id, criterionText(name: candidate.title, description: candidate.applicableDescription))
        })
    }

    static func candidate(matching choice: String, in candidates: [DecisionRouteCandidate]) -> DecisionRouteCandidate? {
        candidates.first { $0.id.caseInsensitiveCompare(choice) == .orderedSame }
    }
}

enum SystemOneEndpoint {
    static let officialEvaluationURL = URL(string: "https://api.typesafe.ai/v1/systemone")!

    static func evaluationURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? DecisionRoutingPolicy.defaultServiceURL : trimmed
        return normalizedEvaluationURL(source)
    }

    static func requiresCredential(_ url: URL) -> Bool {
        url.host?.lowercased() == officialEvaluationURL.host?.lowercased()
    }

    static func normalizedEvaluationURL(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        var path = components.path
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" { path = "" }
        if path.hasSuffix("/v1/systemone") {
            // already the evaluation path
        } else if path.hasSuffix("/v1") {
            path += "/systemone"
        } else {
            path += "/v1/systemone"
        }
        components.scheme = scheme
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct DecisionServiceCall: Equatable, Sendable {
    var provider: DecisionProviderKind
    var url: URL
    var model: String
    var apiKey: String?
    var timeout: TimeInterval
}

enum DecisionServiceResolver {
    enum Failure: Error, Equatable {
        case invalidEndpoint
        case missingCredential
    }

    static func resolve(settings: DecisionRoutingSettings, apiKey: String?) -> Result<DecisionServiceCall, Failure> {
        guard let url = SystemOneEndpoint.evaluationURL(settings.serviceURL) else {
            return .failure(.invalidEndpoint)
        }
        let key = DecisionRoutingPolicy.normalizedAPIKey(apiKey)
        if SystemOneEndpoint.requiresCredential(url), key == nil {
            return .failure(.missingCredential)
        }
        return .success(
            DecisionServiceCall(
                provider: settings.provider,
                url: url,
                model: DecisionRoutingPolicy.modelName(settings.model),
                apiKey: key,
                timeout: DecisionRoutingPolicy.normalizedTimeout(settings.timeoutSeconds)
            )
        )
    }
}

enum DecisionProviderClient {
    static func evaluate(
        call: DecisionServiceCall,
        question: String,
        criteria: [String: String],
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async throws -> SystemOneChoiceAnswer {
        switch call.provider {
        case .systemOne:
            let client = SystemOneClient(transport: transport, sleep: sleep)
            return try await client.evaluate(
                question: question,
                model: call.model,
                criteria: criteria,
                url: call.url,
                apiKey: call.apiKey,
                timeout: call.timeout
            )
        }
    }
}

struct SystemOneChoiceAnswer: Equatable, Sendable {
    var choice: String
    var confidence: Double
}

enum SystemOneClientError: Error, Equatable {
    case timedOut
    case httpStatus(Int)
    case invalidResponse
    case unknownChoice
    case confidenceOutOfRange
}

enum SystemOneRequestBuilder {
    struct Body: Encodable {
        var model: String
        var state: String
        var questions: [String: Question]
    }

    struct Question: Encodable {
        var type = "choice"
        var instructions: String
        var criteria: [String: String]
    }

    static func body(model: String, state: String, criteria: [String: String]) throws -> Data {
        let payload = Body(
            model: model,
            state: state,
            questions: [
                DecisionRoutingPolicy.routeQuestionID: Question(
                    instructions: DecisionRoutingPolicy.routeInstructions,
                    criteria: criteria
                )
            ]
        )
        return try JSONEncoder().encode(payload)
    }

    static func request(url: URL, apiKey: String?, timeout: TimeInterval, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }
}

enum SystemOneResponseParser {
    struct Envelope: Decodable {
        var answers: [String: Answer]
    }

    struct Answer: Decodable {
        var type: String?
        var choice: String
        var confidence: Double
    }

    static func parse(_ data: Data, allowedChoices: Set<String>) throws -> SystemOneChoiceAnswer {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw SystemOneClientError.invalidResponse
        }
        guard let answer = envelope.answers[DecisionRoutingPolicy.routeQuestionID] else {
            throw SystemOneClientError.invalidResponse
        }
        if let type = answer.type, type != "choice" {
            throw SystemOneClientError.invalidResponse
        }
        guard answer.confidence.isFinite, (0...1).contains(answer.confidence) else {
            throw SystemOneClientError.confidenceOutOfRange
        }
        guard allowedChoices.contains(where: { $0.caseInsensitiveCompare(answer.choice) == .orderedSame }) else {
            throw SystemOneClientError.unknownChoice
        }
        return SystemOneChoiceAnswer(choice: answer.choice, confidence: answer.confidence)
    }
}

enum DecisionPreviewResult: Equatable, Sendable {
    case recommendation(DecisionRouteCandidate, confidence: Double, release: DecisionRelease)
    case timeout(DecisionTimeoutAction)
    case missingCredential
    case invalidEndpoint
    case missingModel
    case unavailable
    case unknownChoice
}

enum DecisionRoutingPreview {
    static func run(
        question: String,
        settings: DecisionRoutingSettings,
        candidates: [DecisionRouteCandidate],
        apiKey: String?,
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> DecisionPreviewResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, candidates.count >= 2 else { return .unavailable }
        let call: DecisionServiceCall
        switch DecisionServiceResolver.resolve(settings: settings, apiKey: apiKey) {
        case let .success(resolved):
            call = resolved
        case .failure(.invalidEndpoint):
            return .invalidEndpoint
        case .failure(.missingCredential):
            return .missingCredential
        }
        do {
            let answer = try await DecisionProviderClient.evaluate(
                call: call,
                question: trimmed,
                criteria: DecisionRouteCatalog.criteria(for: candidates),
                transport: transport,
                sleep: sleep
            )
            guard let candidate = DecisionRouteCatalog.candidate(matching: answer.choice, in: candidates) else {
                return .unknownChoice
            }
            let release = DecisionRoutingPolicy.release(
                forceConfirm: candidate.forceConfirm,
                mode: settings.confirmationMode,
                confidence: answer.confidence,
                threshold: settings.confidenceThreshold
            )
            return .recommendation(candidate, confidence: answer.confidence, release: release)
        } catch let error as SystemOneClientError {
            switch error {
            case .timedOut:
                return .timeout(settings.timeoutAction)
            case .unknownChoice:
                return .unknownChoice
            case .httpStatus, .invalidResponse, .confidenceOutOfRange:
                return .unavailable
            }
        } catch {
            if SystemOneClient.isTimeout(error) {
                return .timeout(settings.timeoutAction)
            }
            return .unavailable
        }
    }
}
