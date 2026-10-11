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
    static let autoSendBufferSeconds = 0.8
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
    /// `sessionRoutingEnabled` is the per-conversation toolbar state. Pass `true` when
    /// that control is hidden so a stuck-off session cannot block routing.
    static func shouldConsultModel(
        routingEnabled: Bool,
        hasManualChannel: Bool,
        candidateCount: Int,
        sessionRoutingEnabled: Bool = true
    ) -> Bool {
        routingEnabled && sessionRoutingEnabled && !hasManualChannel && candidateCount >= 2
    }

    /// The toolbar toggle is the only way to turn a session off. Hiding it
    /// follows global routing instead of keeping a state the user cannot see.
    static func effectiveSessionRouting(showsToolbarToggle: Bool, sessionRoutingEnabled: Bool) -> Bool {
        showsToolbarToggle ? sessionRoutingEnabled : true
    }

    /// The official service keeps its prefilled default. A custom service must name
    /// its own model: an empty stored value is a configuration error, never a silent
    /// fallback to the official model.
    static func resolvedModel(_ model: String, isOfficialService: Bool) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isOfficialService ? defaultOfficialModel : nil
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
            return (storedServiceURL, storedModel.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }
        if legacyEndpoint == "custom" {
            let url = (legacyCustomURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (legacyCustomModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // The custom model is carried over as stored, including empty, so the
            // settings validation reports it instead of adopting the official model.
            return (
                url.isEmpty ? DecisionRoutingPolicy.defaultServiceURL : url,
                model,
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
    var externalActionKind: QuickActionKind?

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
                externalActionID: nil,
                externalActionKind: nil
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
                    externalActionID: action.id,
                    externalActionKind: action.kind
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
        try? evaluationURLResult(raw).get()
    }

    static func requiresCredential(_ url: URL) -> Bool {
        url.host?.lowercased() == officialEvaluationURL.host?.lowercased()
    }

    /// Cleartext HTTP is kept for local debugging on this machine only. Anything
    /// else must use HTTPS so a decision body and key never leave in the clear.
    static func isLoopbackHost(_ host: String?) -> Bool {
        let host = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host == "localhost" || host == "::1" || host == "[::1]" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets[0] == "127" else { return false }
        return octets.allSatisfy { part in
            guard let value = Int(part), part.allSatisfy(\.isNumber), value >= 0, value <= 255 else { return false }
            return true
        }
    }

    /// `evaluationURL` collapses every rejection to `nil`. This keeps the reason so
    /// the settings page and chat can name the actual configuration problem.
    static func evaluationURLResult(_ raw: String) -> Result<URL, DecisionServiceResolver.Failure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? DecisionRoutingPolicy.defaultServiceURL : trimmed
        guard var components = URLComponents(string: source),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return .failure(.invalidEndpoint)
        }
        if scheme == "http", !isLoopbackHost(host) {
            return .failure(.insecureRemoteHTTP)
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
        guard let url = components.url else { return .failure(.invalidEndpoint) }
        return .success(url)
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
        case insecureRemoteHTTP
        case missingModel
        case missingCredential
    }

    static func resolve(settings: DecisionRoutingSettings, apiKey: String?) -> Result<DecisionServiceCall, Failure> {
        let url: URL
        switch SystemOneEndpoint.evaluationURLResult(settings.serviceURL) {
        case let .success(resolved):
            url = resolved
        case let .failure(failure):
            return .failure(failure)
        }
        let isOfficial = SystemOneEndpoint.requiresCredential(url)
        guard let model = DecisionRoutingPolicy.resolvedModel(settings.model, isOfficialService: isOfficial) else {
            return .failure(.missingModel)
        }
        let key = DecisionRoutingPolicy.normalizedAPIKey(apiKey)
        if isOfficial, key == nil {
            return .failure(.missingCredential)
        }
        return .success(
            DecisionServiceCall(
                provider: settings.provider,
                url: url,
                model: model,
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
    /// The transport refused a redirect that left the request's origin.
    case unsafeRedirect
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
        let encoder = JSONEncoder()
        // Stable key order keeps the request reproducible across launches.
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(payload)
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

/// Sanitized reason a routing attempt could not produce a recommendation. It never
/// carries a response body, access key, request URL, or authorization material, so it
/// is safe to show in settings and chat.
enum DecisionRoutingFailure: Equatable, Sendable {
    /// External Ask is off, so routing cannot run at all.
    case notEnabled
    /// Fewer than two routing channels, so there is nothing to choose between.
    case notEnoughCandidates(available: Int)
    case emptyQuestion
    case missingCredential
    case invalidEndpoint
    /// Remote cleartext HTTP. Only localhost, 127.0.0.0/8, and ::1 may use HTTP.
    case insecureRemoteHTTP
    /// The custom service has no model; the official model is not substituted.
    case missingModel
    case httpUnauthorized
    case httpForbidden
    case httpNotFound
    case httpRateLimited
    case httpStatus(Int)
    case networkUnavailable
    case timedOut
    case invalidResponse
    case unrecognizedChoice
    case unsafeRedirect

    var localizationKey: String {
        switch self {
        case .notEnabled: "decisionRouting.notEnabled"
        case .notEnoughCandidates: "decisionRouting.notEnoughCandidates"
        case .emptyQuestion: "decisionRouting.emptyQuestion"
        case .missingCredential: "decisionRouting.missingCredential"
        case .invalidEndpoint: "decisionRouting.invalidEndpoint"
        case .insecureRemoteHTTP: "decisionRouting.insecureRemoteHTTP"
        case .missingModel: "decisionRouting.missingModel"
        case .httpUnauthorized: "decisionRouting.httpUnauthorized"
        case .httpForbidden: "decisionRouting.httpForbidden"
        case .httpNotFound: "decisionRouting.httpNotFound"
        case .httpRateLimited: "decisionRouting.httpRateLimited"
        case .httpStatus: "decisionRouting.httpFailed"
        case .networkUnavailable: "decisionRouting.networkUnavailable"
        case .timedOut: "decisionRouting.timedOut"
        case .invalidResponse: "decisionRouting.invalidResponse"
        case .unrecognizedChoice: "decisionRouting.unknownChoice"
        case .unsafeRedirect: "decisionRouting.unsafeRedirect"
        }
    }

    var localizedText: String {
        switch self {
        case let .notEnoughCandidates(available):
            L10n.string(localizationKey, available)
        case let .httpStatus(code):
            L10n.string(localizationKey, code)
        default:
            L10n.string(localizationKey)
        }
    }

    /// True once a request could have left the app, so an elapsed time is meaningful.
    /// Prerequisites and configuration problems never reach the service.
    var reachedService: Bool {
        switch self {
        case .notEnabled, .notEnoughCandidates, .emptyQuestion,
             .missingCredential, .invalidEndpoint, .insecureRemoteHTTP, .missingModel:
            false
        case .httpUnauthorized, .httpForbidden, .httpNotFound, .httpRateLimited,
             .httpStatus, .networkUnavailable, .timedOut, .invalidResponse,
             .unrecognizedChoice, .unsafeRedirect:
            true
        }
    }

    static func classify(configurationError: DecisionServiceResolver.Failure) -> DecisionRoutingFailure {
        switch configurationError {
        case .invalidEndpoint: .invalidEndpoint
        case .insecureRemoteHTTP: .insecureRemoteHTTP
        case .missingModel: .missingModel
        case .missingCredential: .missingCredential
        }
    }

    static func classify(_ error: Error) -> DecisionRoutingFailure {
        if let clientError = error as? SystemOneClientError {
            switch clientError {
            case .timedOut:
                return .timedOut
            case .unsafeRedirect:
                return .unsafeRedirect
            case .invalidResponse, .confidenceOutOfRange:
                return .invalidResponse
            case .unknownChoice:
                return .unrecognizedChoice
            case let .httpStatus(code):
                switch code {
                case 401: return .httpUnauthorized
                case 403: return .httpForbidden
                case 404: return .httpNotFound
                case 429: return .httpRateLimited
                default: return .httpStatus(code)
                }
            }
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .timedOut : .networkUnavailable
        }
        return .invalidResponse
    }
}

enum DecisionPreviewResult: Equatable, Sendable {
    case recommendation(DecisionRouteCandidate, confidence: Double, release: DecisionRelease)
    case timeout(DecisionTimeoutAction)
    case failed(DecisionRoutingFailure)

    /// Prerequisites and configuration problems never reach the service, so the
    /// preview shows the reason without a misleading elapsed time.
    var showsElapsedTime: Bool {
        switch self {
        case .recommendation, .timeout:
            true
        case let .failed(failure):
            failure.reachedService
        }
    }
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
        guard !trimmed.isEmpty else { return .failed(.emptyQuestion) }
        guard candidates.count >= 2 else {
            return .failed(.notEnoughCandidates(available: candidates.count))
        }
        let call: DecisionServiceCall
        switch DecisionServiceResolver.resolve(settings: settings, apiKey: apiKey) {
        case let .success(resolved):
            call = resolved
        case let .failure(failure):
            return .failed(DecisionRoutingFailure.classify(configurationError: failure))
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
                return .failed(.unrecognizedChoice)
            }
            let release = DecisionRoutingPolicy.release(
                forceConfirm: candidate.forceConfirm,
                mode: settings.confirmationMode,
                confidence: answer.confidence,
                threshold: settings.confidenceThreshold
            )
            return .recommendation(candidate, confidence: answer.confidence, release: release)
        } catch {
            let failure = DecisionRoutingFailure.classify(error)
            return failure == .timedOut ? .timeout(settings.timeoutAction) : .failed(failure)
        }
    }
}

/// Prefills the settings credential and decides whether the legacy slot may stop
/// being preferred. The legacy slot keeps winning until the new slot actually
/// persists the key, so a failed save never drops the working credential.
///
/// Reads are injected as throwing closures rather than optional strings so a failed
/// read is never mistaken for an absent credential: an unreadable legacy file keeps
/// the preference in place and never triggers a migration save.
enum DecisionCredentialMigration {
    struct Outcome: Equatable {
        /// Sanitized failure class, so the settings view can pick localized copy without
        /// exposing key material or a raw error.
        enum Failure: Equatable {
            /// A credential could not be read; absence was never confirmed.
            case read
            /// The legacy credential was readable but could not persist in the new slot.
            case save
        }

        var apiKey: String
        var clearLegacyCustomPreference: Bool
        var failure: Failure?

        init(apiKey: String, clearLegacyCustomPreference: Bool, failure: Failure? = nil) {
            self.apiKey = apiKey
            self.clearLegacyCustomPreference = clearLegacyCustomPreference
            self.failure = failure
        }
    }

    static func resolve(
        readSystemOne: () throws -> String?,
        readLegacyCustom: () throws -> String?,
        preferLegacyCustom: Bool,
        saveToSystemOne: (String) throws -> Void
    ) -> Outcome {
        let current = read(readSystemOne)
        guard preferLegacyCustom else {
            return Outcome(
                apiKey: current.text,
                clearLegacyCustomPreference: false,
                failure: current.failed ? .read : nil
            )
        }
        let legacy = read(readLegacyCustom)
        // A failed legacy read is not absence: keep the preference, surface the failure,
        // and never attempt a migration save from an unreadable value.
        guard !legacy.failed else {
            return Outcome(apiKey: current.text, clearLegacyCustomPreference: false, failure: .read)
        }
        guard !legacy.text.isEmpty else {
            // Confirmed absence, so a stale preference can be dropped even though a
            // current-slot read failure keeps the field empty.
            return Outcome(
                apiKey: current.text,
                clearLegacyCustomPreference: true,
                failure: current.failed ? .read : nil
            )
        }
        let legacyValue = legacy.text
        do {
            try saveToSystemOne(legacyValue)
        } catch {
            return Outcome(apiKey: legacyValue, clearLegacyCustomPreference: false, failure: .save)
        }
        return Outcome(apiKey: legacyValue, clearLegacyCustomPreference: true)
    }

    /// Trims a throwing read into an explicit value/absence versus read failure.
    private static func read(_ closure: () throws -> String?) -> (text: String, failed: Bool) {
        do {
            let value = try closure()?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value ?? "", false)
        } catch {
            return ("", true)
        }
    }
}
