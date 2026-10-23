import Foundation
import Testing
@testable import SpotAsk

private actor CapturingDecisionTransport: SystemOneTransport {
    private(set) var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await handler(request)
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }
}

struct OpenAIDecisionsTests {
    private static func settings(
        provider: DecisionProviderKind = .openAIDecisions,
        serviceURL: String = "",
        model: String = ""
    ) -> DecisionRoutingSettings {
        DecisionRoutingSettings(
            isEnabled: true,
            provider: provider,
            serviceURL: serviceURL,
            model: model,
            confirmationMode: .always,
            confidenceThreshold: DecisionRoutingPolicy.defaultThreshold,
            timeoutSeconds: DecisionRoutingPolicy.defaultTimeoutSeconds,
            timeoutAction: .manualSelection,
            inAppDescription: ""
        )
    }

    private static func candidates() -> [DecisionRouteCandidate] {
        [
            DecisionRouteCandidate(
                id: DecisionRouteID.inApp,
                title: "In-App",
                symbolName: "bubble.left",
                brandIconSlug: nil,
                applicableDescription: "Short answers",
                forceConfirm: false,
                externalActionID: nil,
                externalActionKind: nil
            ),
            DecisionRouteCandidate(
                id: "ext_agent",
                title: "Local Agent",
                symbolName: "terminal",
                brandIconSlug: nil,
                applicableDescription: "Local edits",
                forceConfirm: false,
                externalActionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                externalActionKind: .terminal(commandTemplate: "omp {query}")
            )
        ]
    }

    @Test("Decisions request is a single choice question named route")
    func requestBodyUsesChoiceQuestion() throws {
        let data = try OpenAIDecisionsRequestBuilder.body(
            model: "gpt-6-luna",
            input: "route this",
            criteria: ["b": "Bee", "a": "Aye"]
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["model"] as? String == "gpt-6-luna")
        #expect(object["input"] as? String == "route this")
        #expect(object["state"] == nil)
        let questions = try #require(object["questions"] as? [[String: Any]])
        #expect(questions.count == 1)
        let question = try #require(questions.first)
        #expect(question["type"] as? String == "choice")
        #expect(question["name"] as? String == DecisionRoutingPolicy.routeQuestionID)
        #expect(question["instructions"] as? String == DecisionRoutingPolicy.routeInstructions)
        let choices = try #require(question["choices"] as? [[String: Any]])
        #expect(choices.map { $0["value"] as? String } == ["a", "b"])
        #expect(choices.map { $0["description"] as? String } == ["Aye", "Bee"])
    }

    @Test("Decisions request sends a bearer token only when a key is present")
    func requestAuthorization() {
        let url = OpenAIDecisionsEndpoint.officialEvaluationURL
        let withKey = OpenAIDecisionsRequestBuilder.request(
            url: url,
            apiKey: " sk-synthetic ",
            timeout: 2,
            body: Data()
        )
        #expect(withKey.httpMethod == "POST")
        #expect(withKey.timeoutInterval == 2)
        #expect(withKey.value(forHTTPHeaderField: "Authorization") == "Bearer sk-synthetic")
        #expect(withKey.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let withoutKey = OpenAIDecisionsRequestBuilder.request(url: url, apiKey: "  ", timeout: 2, body: Data())
        #expect(withoutKey.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Decisions parser accepts the route answer and rejects the System One envelope")
    func parserAcceptsArrayAnswer() throws {
        let body = """
        {"answers":[{"name":"other","type":"choice","choice":"nope","confidence":1},{"name":"Route","type":"choice","choice":"IN_APP","confidence":1}]}
        """
        let answer = try OpenAIDecisionsResponseParser.parse(Data(body.utf8), allowedChoices: ["in_app"])
        #expect(answer.choice == "IN_APP")
        #expect(answer.confidence == 1)

        let zero = """
        {"answers":[{"name":"route","choice":"in_app","confidence":0}]}
        """
        #expect(try OpenAIDecisionsResponseParser.parse(Data(zero.utf8), allowedChoices: ["in_app"]).confidence == 0)

        let systemOne = #"{"answers":{"route":{"type":"choice","choice":"in_app","confidence":0.9}}}"#
        #expect(throws: OpenAIDecisionsClientError.invalidResponse) {
            try OpenAIDecisionsResponseParser.parse(Data(systemOne.utf8), allowedChoices: ["in_app"])
        }
        let decisions = #"{"answers":[{"name":"route","type":"choice","choice":"in_app","confidence":0.9}]}"#
        #expect(throws: SystemOneClientError.invalidResponse) {
            try SystemOneResponseParser.parse(Data(decisions.utf8), allowedChoices: ["in_app"])
        }
    }

    @Test("Refusal, unknown choice, and bad confidence stay distinct")
    func parserFailuresStayDistinct() {
        let refused = #"{"answers":[{"name":"route","type":"refusal","confidence":0.2}]}"#
        #expect(throws: OpenAIDecisionsClientError.refused) {
            try OpenAIDecisionsResponseParser.parse(Data(refused.utf8), allowedChoices: ["in_app"])
        }
        let unknown = #"{"answers":[{"name":"route","type":"choice","choice":"missing","confidence":0.4}]}"#
        #expect(throws: OpenAIDecisionsClientError.unknownChoice) {
            try OpenAIDecisionsResponseParser.parse(Data(unknown.utf8), allowedChoices: ["in_app"])
        }
        let high = #"{"answers":[{"name":"route","type":"choice","choice":"in_app","confidence":1.01}]}"#
        #expect(throws: OpenAIDecisionsClientError.confidenceOutOfRange) {
            try OpenAIDecisionsResponseParser.parse(Data(high.utf8), allowedChoices: ["in_app"])
        }
        let wrongType = #"{"answers":[{"name":"route","type":"predicate","choice":"in_app","confidence":0.4}]}"#
        #expect(throws: OpenAIDecisionsClientError.invalidResponse) {
            try OpenAIDecisionsResponseParser.parse(Data(wrongType.utf8), allowedChoices: ["in_app"])
        }
        let missingRoute = #"{"answers":[{"name":"other","type":"choice","choice":"in_app","confidence":0.4}]}"#
        #expect(throws: OpenAIDecisionsClientError.invalidResponse) {
            try OpenAIDecisionsResponseParser.parse(Data(missingRoute.utf8), allowedChoices: ["in_app"])
        }
        #expect(DecisionRoutingFailure.classify(OpenAIDecisionsClientError.refused) == .refused)
        #expect(DecisionRoutingFailure.classify(OpenAIDecisionsClientError.httpStatus(401)) == .httpUnauthorized)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.unknownChoice) == .unrecognizedChoice)
    }

    @Test("OpenAI endpoint appends /v1/decisions and keeps the loopback rule")
    func endpointNormalization() {
        #expect(
            OpenAIDecisionsEndpoint.evaluationURL("")?.absoluteString
                == "https://api.openai.com/v1/decisions"
        )
        #expect(
            OpenAIDecisionsEndpoint.evaluationURL("https://api.openai.com/v1")?.absoluteString
                == "https://api.openai.com/v1/decisions"
        )
        #expect(
            OpenAIDecisionsEndpoint.evaluationURL("https://gateway.example/openai/")?.absoluteString
                == "https://gateway.example/openai/v1/decisions"
        )
        #expect(
            OpenAIDecisionsEndpoint.evaluationURL("http://127.0.0.1:8080")?.absoluteString
                == "http://127.0.0.1:8080/v1/decisions"
        )
        #expect(OpenAIDecisionsEndpoint.evaluationURLResult("http://10.0.0.9") == .failure(.insecureRemoteHTTP))
        #expect(OpenAIDecisionsEndpoint.requiresCredential(OpenAIDecisionsEndpoint.officialEvaluationURL))
        let custom = URL(string: "https://gateway.example/v1/decisions")!
        #expect(!OpenAIDecisionsEndpoint.requiresCredential(custom))
        let lookalike = URL(string: "https://api.openai.com.evil.example/v1/decisions")!
        #expect(!OpenAIDecisionsEndpoint.requiresCredential(lookalike))
        #expect(
            SystemOneEndpoint.evaluationURL("https://api.typesafe.ai")?.absoluteString
                == "https://api.typesafe.ai/v1/systemone"
        )
    }

    @Test("Official OpenAI fills gpt-6-luna and requires a key; a custom address does not")
    func resolverUsesOpenAIDefaults() throws {
        let official = try DecisionServiceResolver.resolve(
            settings: Self.settings(),
            apiKey: "sk-synthetic"
        ).get()
        #expect(official.provider == .openAIDecisions)
        #expect(official.url == OpenAIDecisionsEndpoint.officialEvaluationURL)
        #expect(official.model == DecisionRoutingPolicy.defaultOpenAIModel)
        #expect(official.apiKey == "sk-synthetic")

        #expect(
            DecisionServiceResolver.resolve(settings: Self.settings(), apiKey: nil)
                == .failure(.missingCredential)
        )
        #expect(
            DecisionServiceResolver.resolve(
                settings: Self.settings(serviceURL: "https://gateway.example", model: ""),
                apiKey: nil
            ) == .failure(.missingModel)
        )
        let custom = try DecisionServiceResolver.resolve(
            settings: Self.settings(serviceURL: "https://gateway.example", model: "luna-local"),
            apiKey: nil
        ).get()
        #expect(custom.url.absoluteString == "https://gateway.example/v1/decisions")
        #expect(custom.model == "luna-local")
        #expect(custom.apiKey == nil)

        let systemOne = try DecisionServiceResolver.resolve(
            settings: Self.settings(provider: .systemOne, serviceURL: "", model: ""),
            apiKey: "typesafe-synthetic"
        ).get()
        #expect(systemOne.url == SystemOneEndpoint.officialEvaluationURL)
        #expect(systemOne.model == DecisionRoutingPolicy.defaultOfficialModel)
    }

    @Test("The active engine never reads the other engine's credential")
    func credentialSlotsStaySeparate() {
        #expect(DecisionCredentialSlot.all.contains(DecisionCredentialSlot.openAIDecisions))
        #expect(DecisionCredentialSlot.slot(for: .openAIDecisions) == DecisionCredentialSlot.openAIDecisions)
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                for: .openAIDecisions,
                systemOne: "system-key",
                legacyCustom: "legacy-key",
                openAIDecisions: "openai-key",
                preferLegacyCustom: true
            ) == "openai-key"
        )
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                for: .systemOne,
                systemOne: "system-key",
                legacyCustom: "legacy-key",
                openAIDecisions: "openai-key",
                preferLegacyCustom: true
            ) == "legacy-key"
        )
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                for: .openAIDecisions,
                systemOne: "system-key",
                legacyCustom: "legacy-key",
                openAIDecisions: "  ",
                preferLegacyCustom: true
            ) == nil
        )
    }

    @Test("Switching engines keeps each address and model")
    @MainActor
    func persistedFieldsStayIndependent() {
        let suite = "OpenAIDecisionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("systemOne", forKey: "decisionRoutingProvider")
        defaults.set("https://api.typesafe.ai", forKey: "decisionRoutingServiceURL")
        defaults.set("jev-1.13.0", forKey: "decisionRoutingModel")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.decisionRoutingProvider == .systemOne)
        #expect(settings.decisionRoutingOpenAIServiceURL == DecisionRoutingPolicy.defaultOpenAIServiceURL)
        #expect(settings.decisionRoutingOpenAIModel == DecisionRoutingPolicy.defaultOpenAIModel)

        settings.decisionRoutingOpenAIServiceURL = "https://gateway.example.com"
        settings.decisionRoutingOpenAIModel = "gpt-6-luna-custom"
        settings.decisionRoutingProvider = .openAIDecisions
        let openAI = settings.decisionRoutingSettings()
        #expect(openAI.provider == .openAIDecisions)
        #expect(openAI.serviceURL == "https://gateway.example.com")
        #expect(openAI.model == "gpt-6-luna-custom")
        #expect(settings.decisionRoutingServiceURL == "https://api.typesafe.ai")
        #expect(settings.decisionRoutingModel == "jev-1.13.0")

        settings.decisionRoutingServiceURL = "https://self-hosted.example"
        settings.decisionRoutingModel = "jev-local"
        #expect(settings.decisionRoutingSettings().serviceURL == "https://gateway.example.com")
        #expect(settings.decisionRoutingSettings().model == "gpt-6-luna-custom")

        settings.decisionRoutingProvider = .systemOne
        let systemOne = settings.decisionRoutingSettings()
        #expect(systemOne.provider == .systemOne)
        #expect(systemOne.serviceURL == "https://self-hosted.example")
        #expect(systemOne.model == "jev-local")

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.decisionRoutingProvider == .systemOne)
        #expect(reloaded.decisionRoutingServiceURL == "https://self-hosted.example")
        #expect(reloaded.decisionRoutingModel == "jev-local")
        #expect(reloaded.decisionRoutingOpenAIServiceURL == "https://gateway.example.com")
        #expect(reloaded.decisionRoutingOpenAIModel == "gpt-6-luna-custom")
    }

    @Test("A Decisions preview posts to /v1/decisions and does not send a System One body")
    func previewUsesDecisionsClient() async throws {
        let transport = CapturingDecisionTransport { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"answers":[{"name":"route","type":"choice","choice":"in_app","confidence":0.91}]}"#
            return (Data(body.utf8), response)
        }
        let result = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(serviceURL: "https://api.openai.com", model: ""),
            candidates: Self.candidates(),
            apiKey: "sk-synthetic",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        guard case let .recommendation(candidate, confidence, _) = result else {
            Issue.record("expected a recommendation, got \(result)")
            return
        }
        #expect(candidate.id == DecisionRouteID.inApp)
        #expect(confidence == 0.91)
        let request = try #require(await transport.capturedRequests().first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/decisions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-synthetic")
        let payload = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(payload["input"] as? String == "route this")
        #expect(payload["state"] == nil)
        #expect(payload["model"] as? String == "gpt-6-luna")
    }
}
