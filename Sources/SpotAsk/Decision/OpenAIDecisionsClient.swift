import Foundation

/// OpenAI Decisions evaluation URL. Reuses `SystemOneEndpoint` normalization
/// and the loopback/HTTPS policy; only the route suffix and official host differ.
enum OpenAIDecisionsEndpoint {
    static let officialEvaluationURL = URL(string: "https://api.openai.com/v1/decisions")!

    static func evaluationURL(_ raw: String) -> URL? {
        try? evaluationURLResult(raw).get()
    }

    static func requiresCredential(_ url: URL) -> Bool {
        url.host?.lowercased() == officialEvaluationURL.host?.lowercased()
    }

    static func evaluationURLResult(_ raw: String) -> Result<URL, DecisionServiceResolver.Failure> {
        SystemOneEndpoint.normalizedEvaluationURL(
            raw,
            emptyFallback: DecisionRoutingPolicy.defaultOpenAIServiceURL,
            evaluationRoute: "decisions"
        )
    }
}

enum OpenAIDecisionsClientError: Error, Equatable {
    case timedOut
    case httpStatus(Int)
    case unsafeRedirect
    case invalidResponse
    case unknownChoice
    case confidenceOutOfRange
    /// The service answered `type == "refusal"` instead of choosing a destination.
    case refused
}

enum OpenAIDecisionsRequestBuilder {
    struct Body: Encodable {
        var model: String
        var input: String
        var questions: [Question]
    }

    struct Question: Encodable {
        var type = "choice"
        var name: String
        var instructions: String
        var choices: [Choice]
    }

    struct Choice: Encodable {
        var value: String
        var description: String
    }

    static func body(model: String, input: String, criteria: [String: String]) throws -> Data {
        let choices = criteria
            .map { Choice(value: $0.key, description: $0.value) }
            .sorted { $0.value < $1.value }
        let payload = Body(
            model: model,
            input: input,
            questions: [
                Question(
                    name: DecisionRoutingPolicy.routeQuestionID,
                    instructions: DecisionRoutingPolicy.routeInstructions,
                    choices: choices
                )
            ]
        )
        let encoder = JSONEncoder()
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

enum OpenAIDecisionsResponseParser {
    struct Envelope: Decodable {
        var answers: [Answer]
    }

    struct Answer: Decodable {
        var name: String
        var type: String?
        var choice: String?
        var confidence: Double?
    }

    static func parse(_ data: Data, allowedChoices: Set<String>) throws -> SystemOneChoiceAnswer {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw OpenAIDecisionsClientError.invalidResponse
        }
        guard let answer = envelope.answers.first(where: {
            $0.name.caseInsensitiveCompare(DecisionRoutingPolicy.routeQuestionID) == .orderedSame
        }) else {
            throw OpenAIDecisionsClientError.invalidResponse
        }
        if answer.type?.caseInsensitiveCompare("refusal") == .orderedSame {
            throw OpenAIDecisionsClientError.refused
        }
        if let type = answer.type, type.caseInsensitiveCompare("choice") != .orderedSame {
            throw OpenAIDecisionsClientError.invalidResponse
        }
        guard let choice = answer.choice?.trimmingCharacters(in: .whitespacesAndNewlines), !choice.isEmpty else {
            throw OpenAIDecisionsClientError.invalidResponse
        }
        guard let confidence = answer.confidence, confidence.isFinite, (0...1).contains(confidence) else {
            throw OpenAIDecisionsClientError.confidenceOutOfRange
        }
        guard allowedChoices.contains(where: { $0.caseInsensitiveCompare(choice) == .orderedSame }) else {
            throw OpenAIDecisionsClientError.unknownChoice
        }
        return SystemOneChoiceAnswer(choice: choice, confidence: confidence)
    }
}

/// One Decisions API evaluation. The caller owns the deadline; this client does not retry.
struct OpenAIDecisionsClient: Sendable {
    var transport: any SystemOneTransport
    var sleep: @Sendable (Duration) async throws -> Void

    func evaluate(
        question: String,
        model: String,
        criteria: [String: String],
        url: URL,
        apiKey: String?,
        timeout: TimeInterval
    ) async throws -> SystemOneChoiceAnswer {
        let body = try OpenAIDecisionsRequestBuilder.body(model: model, input: question, criteria: criteria)
        let request = OpenAIDecisionsRequestBuilder.request(
            url: url,
            apiKey: apiKey,
            timeout: timeout,
            body: body
        )
        let allowed = Set(criteria.keys)
        return try await withThrowingTaskGroup(of: SystemOneChoiceAnswer.self) { group in
            group.addTask {
                let (data, http) = try await transport.data(for: request)
                guard (200...299).contains(http.statusCode) else {
                    throw OpenAIDecisionsClientError.httpStatus(http.statusCode)
                }
                return try OpenAIDecisionsResponseParser.parse(data, allowedChoices: allowed)
            }
            group.addTask {
                try await sleep(.milliseconds(max(1, Int(timeout * 1000))))
                throw OpenAIDecisionsClientError.timedOut
            }
            do {
                guard let first = try await group.next() else {
                    group.cancelAll()
                    throw OpenAIDecisionsClientError.timedOut
                }
                group.cancelAll()
                return first
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
