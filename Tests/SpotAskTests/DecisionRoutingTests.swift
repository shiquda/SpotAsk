import Foundation
import Testing
@testable import SpotAsk

private actor ScriptedTransport: SystemOneTransport {
    private(set) var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await handler(request)
    }

    func requestCount() -> Int {
        requests.count
    }

    func firstRequest() -> URLRequest? {
        requests.first
    }
}

@MainActor
struct DecisionRoutingTests {
    private static func candidates(forceExternalConfirm: Bool = false) -> [DecisionRouteCandidate] {
        [
            DecisionRouteCandidate(
                id: DecisionRouteID.inApp,
                title: "In-App",
                symbolName: "bubble.left.and.bubble.right",
                brandIconSlug: nil,
                applicableDescription: "Short in-app chat",
                forceConfirm: false,
                externalActionID: nil
            ),
            DecisionRouteCandidate(
                id: "ext_agent",
                title: "Local Agent",
                symbolName: "terminal",
                brandIconSlug: nil,
                applicableDescription: "Local code edits",
                forceConfirm: forceExternalConfirm,
                externalActionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            )
        ]
    }

    nonisolated private static func okResponse(choice: String, confidence: Double, url: URL = SystemOneEndpoint.officialEvaluationURL) -> (Data, HTTPURLResponse) {
        let json = """
        {"model":"jev-1.13.0","answers":{"route":{"type":"choice","choice":"\(choice)","confidence":\(confidence)}}}
        """
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }

    @Test("Default routing is off, always-confirm, 0.8 threshold, and 2s manual timeout")
    func defaultsPreserveManualBehavior() {
        let suite = "DecisionRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.decisionRoutingEnabled == false)
        #expect(settings.decisionRoutingEndpoint == .official)
        #expect(settings.decisionRoutingOfficialModel == "jev-1.13.0")
        #expect(settings.decisionRoutingConfirmationMode == .always)
        #expect(settings.decisionRoutingConfidenceThreshold == 0.8)
        #expect(settings.decisionRoutingTimeoutSeconds == 2.0)
        #expect(settings.decisionRoutingTimeoutAction == .manualSelection)
    }

    @Test("Release rules enforce force-confirm, always-confirm, and strict threshold comparison")
    func releasePolicyPrecedence() {
        #expect(
            DecisionRoutingPolicy.release(
                forceConfirm: true,
                mode: .threshold,
                confidence: 1.0,
                threshold: 0.1
            ) == .confirm
        )
        #expect(
            DecisionRoutingPolicy.release(
                forceConfirm: false,
                mode: .always,
                confidence: 1.0,
                threshold: 0.1
            ) == .confirm
        )
        #expect(
            DecisionRoutingPolicy.release(
                forceConfirm: false,
                mode: .threshold,
                confidence: 0.8,
                threshold: 0.8
            ) == .confirm
        )
        #expect(
            DecisionRoutingPolicy.release(
                forceConfirm: false,
                mode: .threshold,
                confidence: 0.79,
                threshold: 0.8
            ) == .confirm
        )
        #expect(
            DecisionRoutingPolicy.release(
                forceConfirm: false,
                mode: .threshold,
                confidence: 0.81,
                threshold: 0.8
            ) == .autoSend
        )
    }

    @Test("Manual channel selection and single-candidate catalogs skip the decision model")
    func consultGuard() {
        #expect(!DecisionRoutingPolicy.shouldConsultModel(routingEnabled: false, hasManualChannel: false, candidateCount: 2))
        #expect(!DecisionRoutingPolicy.shouldConsultModel(routingEnabled: true, hasManualChannel: true, candidateCount: 2))
        #expect(!DecisionRoutingPolicy.shouldConsultModel(routingEnabled: true, hasManualChannel: false, candidateCount: 1))
        #expect(DecisionRoutingPolicy.shouldConsultModel(routingEnabled: true, hasManualChannel: false, candidateCount: 2))
    }

    @Test("Endpoint URL normalizes custom roots, /v1, and full /v1/systemone paths")
    func endpointNormalization() {
        #expect(
            SystemOneEndpoint.customEvaluationURL("http://127.0.0.1:8080")?.absoluteString
                == "http://127.0.0.1:8080/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.customEvaluationURL("https://decision.example.com/v1/")?.absoluteString
                == "https://decision.example.com/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.customEvaluationURL("https://decision.example.com/v1/systemone")?.absoluteString
                == "https://decision.example.com/v1/systemone"
        )
        #expect(SystemOneEndpoint.customEvaluationURL("ftp://decision.example.com") == nil)
        #expect(SystemOneEndpoint.customEvaluationURL("not a url") == nil)
    }

    @Test("Official and custom credentials stay isolated")
    func credentialIsolation() {
        #expect(
            DecisionRoutingPolicy.apiKey(
                endpoint: .official,
                official: "official-token",
                custom: "custom-token"
            ) == "official-token"
        )
        #expect(
            DecisionRoutingPolicy.apiKey(
                endpoint: .custom,
                official: "official-token",
                custom: nil
            ) == nil
        )
        let customRequest = SystemOneRequestBuilder.request(
            url: URL(string: "http://127.0.0.1:8080/v1/systemone")!,
            apiKey: DecisionRoutingPolicy.apiKey(endpoint: .custom, official: "official-token", custom: ""),
            timeout: 2,
            body: Data()
        )
        #expect(customRequest.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Legacy QuickAction JSON decodes routing defaults and catalog saves preserve routing edits")
    func quickActionRoutingPersistence() throws {
        let legacy = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Custom","kind":{"type":"terminal","template":"omp {query}"},"symbolName":"terminal","isBuiltIn":false,"isEnabled":true}
        """
        let decoded = try JSONDecoder().decode(QuickAction.self, from: Data(legacy.utf8))
        #expect(decoded.routingPurpose.isEmpty)
        #expect(decoded.routingScenario.isEmpty)
        #expect(decoded.requiresConfirmationOnAutoRoute == false)

        let suite = "DecisionRoutingTests.Catalog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.updateQuickActionRouting(
            id: QuickAction.BuiltInID.chatGPT,
            purpose: "Browser reasoning",
            scenario: "Open-ended web tasks",
            requiresConfirmation: true
        )
        var custom = decoded
        custom.routingPurpose = "Local CLI"
        custom.routingScenario = "Repo edits"
        custom.requiresConfirmationOnAutoRoute = true
        #expect(settings.saveCustomQuickAction(custom))

        let reloaded = AppSettings(defaults: defaults)
        let builtIn = reloaded.quickActions.first { $0.id == QuickAction.BuiltInID.chatGPT }
        let savedCustom = reloaded.quickActions.first { $0.id == custom.id }
        #expect(builtIn?.routingPurpose == "Browser reasoning")
        #expect(builtIn?.routingScenario == "Open-ended web tasks")
        #expect(builtIn?.requiresConfirmationOnAutoRoute == true)
        #expect(savedCustom?.routingPurpose == "Local CLI")
        #expect(savedCustom?.routingScenario == "Repo edits")
        #expect(savedCustom?.requiresConfirmationOnAutoRoute == true)
    }

    @Test("Unauthorized, unknown choice, and rate limit errors never retry or auto-forward")
    func errorsDoNotRetryOrAutoForward() async {
        for status in [401, 422, 429, 529] {
            let transport = ScriptedTransport { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data("{\"error\":\"denied\"}".utf8), response)
            }
            var settings = DecisionRoutingSettings.disabled
            settings.isEnabled = true
            settings.confirmationMode = .threshold
            settings.confidenceThreshold = 0.1

            let controller = DecisionRoutingController()
            controller.start(
                snapshotQuestion: "fix build",
                modelQuestion: "fix build",
                candidates: Self.candidates(),
                settings: settings,
                officialKey: "test-token",
                customKey: nil,
                transport: transport,
                sleep: { _ in try await Task.sleep(for: .seconds(60)) }
            )
            for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 1, question: "fix build")) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            #expect(await transport.requestCount() == 1)
            #expect(controller.pendingExecution == nil)
            #expect(controller.phase == .choosing(
                DecisionRoutingTicket(generation: 1, question: "fix build"),
                .unavailable,
                highlightedID: DecisionRouteID.inApp
            ))
        }
    }

    @Test("Timeout respects manual vs in-app fallback and late responses cannot execute")
    func timeoutAndLateResponseDiscard() async {
        let slowTransport = ScriptedTransport { _ in
            try await Task.sleep(for: .seconds(60))
            return Self.okResponse(choice: "ext_agent", confidence: 1.0)
        }
        var manualSettings = DecisionRoutingSettings.disabled
        manualSettings.isEnabled = true
        manualSettings.confirmationMode = .threshold
        manualSettings.confidenceThreshold = 0.5
        manualSettings.timeoutAction = .manualSelection

        let controller = DecisionRoutingController()
        controller.start(
            snapshotQuestion: "refactor parser",
            modelQuestion: "refactor parser",
            candidates: Self.candidates(),
            settings: manualSettings,
            officialKey: "test-token",
            customKey: nil,
            transport: slowTransport,
            sleep: { _ in }
        )
        for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 1, question: "refactor parser")) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.pendingExecution == nil)
        #expect(controller.phase == .choosing(
            DecisionRoutingTicket(generation: 1, question: "refactor parser"),
            .timeout,
            highlightedID: DecisionRouteID.inApp
        ))
        #expect(!DecisionRoutingGate.shouldApply(generation: 1, phase: controller.phase, consumed: []))

        var inAppSettings = manualSettings
        inAppSettings.timeoutAction = .inApp
        controller.start(
            snapshotQuestion: "quick summary",
            modelQuestion: "quick summary",
            candidates: Self.candidates(),
            settings: inAppSettings,
            officialKey: "test-token",
            customKey: nil,
            transport: slowTransport,
            sleep: { _ in }
        )
        for _ in 0..<50 where controller.pendingExecution == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.pendingExecution?.id == DecisionRouteID.inApp)
        #expect(controller.phase == .idle)
    }

    @Test("Editing the question invalidates the recommendation before it can execute")
    func inputEditInvalidatesRecommendation() async {
        let transport = ScriptedTransport { _ in
            Self.okResponse(choice: "ext_agent", confidence: 0.95)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .always

        let controller = DecisionRoutingController()
        controller.start(
            snapshotQuestion: "original question",
            modelQuestion: "original question",
            candidates: Self.candidates(),
            settings: settings,
            officialKey: "test-token",
            customKey: nil,
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 1, question: "original question")) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.phase != .idle)
        controller.noteInput("edited question")
        #expect(controller.phase == .idle)
        controller.acceptCurrent()
        #expect(controller.pendingExecution == nil)
    }

    @Test("Preview evaluates custom System One endpoint without launching any channel")
    func customEndpointPreview() async throws {
        let transport = ScriptedTransport { request in
            Self.okResponse(choice: "ext_agent", confidence: 0.91, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.endpoint = .custom
        settings.customBaseURL = "http://127.0.0.1:18080"
        settings.customModel = "local-jev"
        settings.confirmationMode = .threshold
        settings.confidenceThreshold = 0.8

        let result = await DecisionRoutingPreview.run(
            question: "inspect git status in repo",
            settings: settings,
            candidates: Self.candidates(),
            officialKey: "must-not-be-sent",
            customKey: nil,
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        let sent = try #require(await transport.firstRequest())
        #expect(sent.url?.absoluteString == "http://127.0.0.1:18080/v1/systemone")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(result == .recommendation(Self.candidates()[1], confidence: 0.91, release: .autoSend))
    }

    @Test("Unknown choice from model is rejected and never auto-sends")
    func unknownChoiceRejected() async {
        let transport = ScriptedTransport { request in
            Self.okResponse(choice: "not_in_catalog", confidence: 1.0, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .threshold
        settings.confidenceThreshold = 0.1

        let preview = await DecisionRoutingPreview.run(
            question: "open unknown tool",
            settings: settings,
            candidates: Self.candidates(),
            officialKey: "test-token",
            customKey: nil,
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        #expect(preview == .unknownChoice)
    }
}
