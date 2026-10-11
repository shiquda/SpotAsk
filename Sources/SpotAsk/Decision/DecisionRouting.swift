import Foundation

enum DecisionEndpointKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case official
    case custom

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
    static let official = UUID(uuidString: "D3C15100-0000-4000-8000-0000000000E1")!
    static let custom = UUID(uuidString: "D3C15100-0000-4000-8000-0000000000E2")!
    static let all: Set<UUID> = [official, custom]

    static func slot(for endpoint: DecisionEndpointKind) -> UUID {
        switch endpoint {
        case .official: official
        case .custom: custom
        }
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
    static let defaultOfficialModel = "jev-1.13.0"
    static let defaultThreshold = 0.8
    static let defaultTimeoutSeconds = 2.0
    static let minimumTimeoutSeconds = 0.5
    static let maximumTimeoutSeconds = 30.0
    static let routeQuestionID = "route"
    static let routeInstructions = "Choose the single best destination for this question. Use only the option descriptions. Do not invent an option."

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

    static func modelName(
        endpoint: DecisionEndpointKind,
        officialModel: String,
        customModel: String
    ) -> String? {
        switch endpoint {
        case .official:
            let trimmed = officialModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? defaultOfficialModel : trimmed
        case .custom:
            let trimmed = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Official and custom credentials never cross. A missing custom key is allowed.
    static func apiKey(
        endpoint: DecisionEndpointKind,
        official: String?,
        custom: String?
    ) -> String? {
        let selected: String?
        switch endpoint {
        case .official:
            selected = official
        case .custom:
            selected = custom
        }
        let trimmed = (selected ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\_", with: "_")
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DecisionRoutingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var endpoint: DecisionEndpointKind
    var officialModel: String
    var customBaseURL: String
    var customModel: String
    var confirmationMode: DecisionConfirmationMode
    var confidenceThreshold: Double
    var timeoutSeconds: Double
    var timeoutAction: DecisionTimeoutAction
    var inAppDescription: String

    static let disabled = DecisionRoutingSettings(
        isEnabled: false,
        endpoint: .official,
        officialModel: DecisionRoutingPolicy.defaultOfficialModel,
        customBaseURL: "",
        customModel: "",
        confirmationMode: .always,
        confidenceThreshold: DecisionRoutingPolicy.defaultThreshold,
        timeoutSeconds: DecisionRoutingPolicy.defaultTimeoutSeconds,
        timeoutAction: .manualSelection,
        inAppDescription: ""
    )
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

    static func criteria(for candidates: [DecisionRouteCandidate]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            (candidate.id, "\(candidate.title). \(candidate.applicableDescription)")
        })
    }

    static func candidate(matching choice: String, in candidates: [DecisionRouteCandidate]) -> DecisionRouteCandidate? {
        candidates.first { $0.id.caseInsensitiveCompare(choice) == .orderedSame }
    }
}

enum SystemOneEndpoint {
    static let officialEvaluationURL = URL(string: "https://api.typesafe.ai/v1/systemone")!

    static func evaluationURL(endpoint: DecisionEndpointKind, customBaseURL: String) -> URL? {
        switch endpoint {
        case .official:
            return officialEvaluationURL
        case .custom:
            return customEvaluationURL(customBaseURL)
        }
    }

    static func customEvaluationURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
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
        officialKey: String?,
        customKey: String?,
        transport: any SystemOneTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> DecisionPreviewResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, candidates.count >= 2 else { return .unavailable }
        guard let url = SystemOneEndpoint.evaluationURL(
            endpoint: settings.endpoint,
            customBaseURL: settings.customBaseURL
        ) else {
            return .invalidEndpoint
        }
        guard let model = DecisionRoutingPolicy.modelName(
            endpoint: settings.endpoint,
            officialModel: settings.officialModel,
            customModel: settings.customModel
        ) else {
            return .missingModel
        }
        let key = DecisionRoutingPolicy.apiKey(
            endpoint: settings.endpoint,
            official: officialKey,
            custom: customKey
        )
        if settings.endpoint == .official, key == nil {
            return .missingCredential
        }
        let client = SystemOneClient(transport: transport, sleep: sleep)
        do {
            let answer = try await client.evaluate(
                question: trimmed,
                model: model,
                criteria: DecisionRouteCatalog.criteria(for: candidates),
                url: url,
                apiKey: key,
                timeout: DecisionRoutingPolicy.normalizedTimeout(settings.timeoutSeconds)
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
