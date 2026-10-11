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

    private static func snapshot(_ draft: String, candidates: [DecisionRouteCandidate]? = nil) -> DecisionSendSnapshot {
        DecisionSendSnapshot(
            draft: draft, attachmentIDs: [], preset: nil, sessionIdentity: 0,
            routingEnabled: true, sessionRoutingEnabled: true, manualChannelID: nil,
            candidates: candidates ?? Self.candidates()
        )
    }

    nonisolated private static func okResponse(choice: String, confidence: Double, url: URL = SystemOneEndpoint.officialEvaluationURL) -> (Data, HTTPURLResponse) {
        let json = """
        {"model":"jev-1.13.0","answers":{"route":{"type":"choice","choice":"\(choice)","confidence":\(confidence)}}}
        """
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }


    @Test("Criteria include the channel name even when no preference is set")
    func criteriaIncludeChannelNameWithoutPreference() {
        let custom = QuickAction(name: "Perplexity", urlTemplate: "https://perplexity.ai/?q={query}")
        let candidates = DecisionRouteCatalog.candidates(actions: [custom], inAppDescription: "")
        let criteria = DecisionRouteCatalog.criteria(for: candidates)
        let externalID = DecisionRouteID.external(custom.id)
        #expect(criteria[externalID]?.hasPrefix("Perplexity") == true)
        #expect(criteria[DecisionRouteID.inApp]?.hasPrefix(L10n.string("decisionRouting.inAppTitle")) == true)
        #expect(DecisionRouteCatalog.criterionText(name: "Terminal", description: "") == "Terminal")
        #expect(DecisionRouteCatalog.criterionText(name: "Terminal", description: "Local files") == "Terminal. Local files")
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
        #expect(!DecisionRoutingPolicy.shouldConsultModel(
            routingEnabled: true,
            hasManualChannel: false,
            candidateCount: 2,
            sessionRoutingEnabled: false
        ))
        #expect(!DecisionRoutingPolicy.effectiveSessionRouting(showsToolbarToggle: true, sessionRoutingEnabled: false))
        #expect(DecisionRoutingPolicy.effectiveSessionRouting(showsToolbarToggle: false, sessionRoutingEnabled: false))
    }

    @Test("Endpoint URL normalizes roots, /v1, and full /v1/systemone paths")
    func endpointNormalization() {
        #expect(
            SystemOneEndpoint.evaluationURL("http://127.0.0.1:8080")?.absoluteString
                == "http://127.0.0.1:8080/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.evaluationURL("https://decision.example.com/v1/")?.absoluteString
                == "https://decision.example.com/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.evaluationURL("https://decision.example.com/v1/systemone")?.absoluteString
                == "https://decision.example.com/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.evaluationURL("")?.absoluteString
                == "https://api.typesafe.ai/v1/systemone"
        )
        #expect(SystemOneEndpoint.evaluationURL("ftp://decision.example.com") == nil)
        #expect(SystemOneEndpoint.evaluationURL("not a url") == nil)
    }

    @Test("The configured key is sent only to the configured service")
    func credentialFollowsConfiguredService() {
        #expect(DecisionRoutingPolicy.normalizedAPIKey(" official\\_token ") == "official_token")
        #expect(DecisionRoutingPolicy.normalizedAPIKey("  ") == nil)
        let official = SystemOneEndpoint.evaluationURL("https://api.typesafe.ai")!
        #expect(SystemOneEndpoint.requiresCredential(official))
        let local = SystemOneEndpoint.evaluationURL("http://127.0.0.1:8080")!
        #expect(!SystemOneEndpoint.requiresCredential(local))
        let request = SystemOneRequestBuilder.request(
            url: local,
            apiKey: nil,
            timeout: 2,
            body: Data()
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                systemOne: "official-token",
                legacyCustom: "custom-token",
                preferLegacyCustom: true
            ) == "custom-token"
        )
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                systemOne: "official-token",
                legacyCustom: nil,
                preferLegacyCustom: true
            ) == "official-token"
        )
    }

    @Test("Legacy custom endpoint settings migrate into the single service fields")
    func legacyCustomEndpointMigrates() {
        let suite = "DecisionRoutingTests.Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("custom", forKey: "decisionRoutingEndpoint")
        defaults.set("http://127.0.0.1:8080", forKey: "decisionRoutingCustomBaseURL")
        defaults.set("local-jev", forKey: "decisionRoutingCustomModel")
        defaults.set(12.0, forKey: "decisionRoutingTimeoutSeconds")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.decisionRoutingServiceURL == "http://127.0.0.1:8080")
        #expect(settings.decisionRoutingModel == "local-jev")
        #expect(settings.decisionRoutingTimeoutSeconds == 5)
        #expect(defaults.bool(forKey: DecisionCredentialSlot.preferLegacyCustomKey))
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
                sendSnapshot: Self.snapshot("fix build"),
                modelQuestion: "fix build",
                settings: settings,
                apiKey: "test-token",
                transport: transport,
                sleep: { _ in try await Task.sleep(for: .seconds(60)) }
            )
            for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 1, question: "fix build")) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            #expect(await transport.requestCount() == 1)
            #expect(controller.pendingSend == nil)
            #expect(controller.phase == .choosing(
                DecisionRoutingTicket(generation: 1, question: "fix build"),
                .failed(status == 401 ? .httpUnauthorized : status == 429 ? .httpRateLimited : .httpStatus(status)),
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
            sendSnapshot: Self.snapshot("refactor parser"),
            modelQuestion: "refactor parser",
            settings: manualSettings,
            apiKey: "test-token",
            transport: slowTransport,
            sleep: { _ in }
        )
        for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 1, question: "refactor parser")) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.pendingSend == nil)
        #expect(controller.phase == .choosing(
            DecisionRoutingTicket(generation: 1, question: "refactor parser"),
            .timeout,
            highlightedID: DecisionRouteID.inApp
        ))
        #expect(!DecisionRoutingGate.shouldApply(generation: 1, phase: controller.phase, consumed: []))

        var inAppSettings = manualSettings
        inAppSettings.timeoutAction = .inApp
        controller.start(
            sendSnapshot: Self.snapshot("quick summary"),
            modelQuestion: "quick summary",
            settings: inAppSettings,
            apiKey: "test-token",
            transport: slowTransport,
            sleep: { _ in }
        )
        for _ in 0..<50 where controller.pendingSend == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.pendingSend?.candidate.id == DecisionRouteID.inApp)
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
            sendSnapshot: Self.snapshot("original question"),
            modelQuestion: "original question",
            settings: settings,
            apiKey: "test-token",
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
        #expect(controller.pendingSend == nil)
    }

    @Test("Preview evaluates custom System One endpoint without launching any channel")
    func customEndpointPreview() async throws {
        let transport = ScriptedTransport { request in
            Self.okResponse(choice: "ext_agent", confidence: 0.91, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.serviceURL = "http://127.0.0.1:18080"
        settings.model = "local-jev"
        settings.confirmationMode = .threshold
        settings.confidenceThreshold = 0.8

        let result = await DecisionRoutingPreview.run(
            question: "inspect git status in repo",
            settings: settings,
            candidates: Self.candidates(),
            apiKey: nil,
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
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        #expect(preview == .failed(.unrecognizedChoice))
    }

    @Test("Channel chooser cycles highlighted candidate with moveSelection and executes on acceptCurrent")
    func choosingMoveSelectionCyclesCandidates() async {
        let candidates = Self.candidates()
        let targetID = candidates[1].id
        let transport = ScriptedTransport { request in
            Self.okResponse(choice: targetID, confidence: 0.72, url: request.url!)
        }
        let controller = DecisionRoutingController()
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        controller.start(
            sendSnapshot: Self.snapshot("help me debug", candidates: candidates),
            modelQuestion: "help me debug",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        while case .deciding = controller.phase {
            await Task.yield()
        }
        controller.showManualChoice()
        #expect(controller.phase.highlightedID == candidates[0].id)
        controller.moveSelection(1)
        #expect(controller.phase.highlightedID == candidates[1].id)
        controller.moveSelection(1)
        #expect(controller.phase.highlightedID == candidates[0].id)
        controller.moveSelection(-1)
        #expect(controller.phase.highlightedID == candidates[1].id)
        controller.acceptCurrent()
        #expect(controller.pendingSend?.candidate == candidates[1])
    }

    @Test("Auto-send enters the 0.8s buffer and supports Return immediate send or Esc/edit cancel")
    func autoSendBufferAllowsReturnOrCancel() async {
        let candidates = Self.candidates()
        let target = candidates[1]
        let transport = ScriptedTransport { request in
            Self.okResponse(choice: target.id, confidence: 0.95, url: request.url!)
        }
        var settings = DecisionRoutingSettings.disabled
        settings.isEnabled = true
        settings.confirmationMode = .threshold
        settings.confidenceThreshold = 0.8

        let controller = DecisionRoutingController()
        controller.start(
            sendSnapshot: Self.snapshot("deploy check", candidates: candidates),
            modelQuestion: "deploy check",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            autoSendSleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 1, question: "deploy check")) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.phase == .autoSending(
            DecisionRoutingTicket(generation: 1, question: "deploy check"),
            target
        ))
        #expect(controller.pendingSend == nil)

        // Return during buffer sends immediately.
        controller.acceptCurrent()
        #expect(controller.pendingSend?.candidate == target)
        #expect(controller.phase == .idle)
        controller.cancel()

        // Editing during buffer cancels and never sends.
        controller.start(
            sendSnapshot: Self.snapshot("second check", candidates: candidates),
            modelQuestion: "second check",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            autoSendSleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<50 where controller.phase == .deciding(DecisionRoutingTicket(generation: 2, question: "second check")) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.phase == .autoSending(
            DecisionRoutingTicket(generation: 2, question: "second check"),
            target
        ))
        controller.noteInput("second check edited")
        #expect(controller.phase == .idle)
        #expect(controller.pendingSend == nil)

        // Buffer expiry delivers automatically when uninterrupted.
        controller.start(
            sendSnapshot: Self.snapshot("third check", candidates: candidates),
            modelQuestion: "third check",
            settings: settings,
            apiKey: "test-token",
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            autoSendSleep: { _ in }
        )
        for _ in 0..<50 where controller.pendingSend == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.pendingSend?.candidate == target)
        #expect(controller.phase == .idle)
        controller.cancel()

        // In SpotAsk auto-send executes immediately without entering .autoSending.
        let inAppTarget = candidates[0]
        let inAppTransport = ScriptedTransport { _ in
            Self.okResponse(choice: inAppTarget.id, confidence: 0.96)
        }
        controller.start(
            sendSnapshot: Self.snapshot("in spotask question", candidates: candidates),
            modelQuestion: "in spotask question",
            settings: settings,
            apiKey: "test-token",
            transport: inAppTransport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            autoSendSleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        for _ in 0..<50 where controller.pendingSend == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.pendingSend?.candidate == inAppTarget)
        #expect(controller.phase == .idle)
    }
}
