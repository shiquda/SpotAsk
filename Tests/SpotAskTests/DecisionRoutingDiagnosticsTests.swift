import Foundation
import Testing
@testable import SpotAsk

private actor DiagnosticScriptedTransport: SystemOneTransport {
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
}

/// Synthetic key store. Never reads a real credential; read and save paths can be made
/// to fail so credential migration is exercised without touching user data.
private final class SyntheticKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: String]
    private let failingSlots: Set<UUID>
    private let unreadableSlots: Set<UUID>
    private var savedKeys: [String] = []

    init(
        storage: [UUID: String] = [:],
        failingSlots: Set<UUID> = [],
        unreadableSlots: Set<UUID> = []
    ) {
        self.storage = storage
        self.failingSlots = failingSlots
        self.unreadableSlots = unreadableSlots
    }

    func readAPIKey(for providerID: UUID) throws -> String? {
        try lock.withLock {
            if unreadableSlots.contains(providerID) { throw KeyStoreTestError.readFailed }
            return storage[providerID]
        }
    }

    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        try lock.withLock {
            if failingSlots.contains(providerID) { throw KeyStoreTestError.saveFailed }
            storage[providerID] = key
            savedKeys.append(key)
        }
    }

    func deleteAPIKey(for providerID: UUID) throws {
        lock.withLock { storage[providerID] = nil }
    }

    func deleteAllAPIKeys() throws {
        lock.withLock { storage.removeAll() }
    }

    func savedSnapshot() -> [String] {
        lock.withLock { savedKeys }
    }
}

private enum KeyStoreTestError: Error, Equatable {
    case readFailed
    case saveFailed
}

/// Synthetic markers only. The tests never read or print a real credential.
private let syntheticKey = "synthetic-token-not-a-real-credential"
private let bodyMarker = "SYNTHETIC-BODY-MARKER"

@MainActor
struct DecisionRoutingDiagnosticsTests {
    private static func candidates() -> [DecisionRouteCandidate] {
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
            DecisionRouteCandidate(
                id: "ext_agent",
                title: "Local Agent",
                symbolName: "terminal",
                brandIconSlug: nil,
                applicableDescription: "Local code edits",
                forceConfirm: false,
                externalActionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                externalActionKind: .terminal(commandTemplate: "omp {query}")
            )
        ]
    }

    private static func settings(
        serviceURL: String = DecisionRoutingPolicy.defaultServiceURL,
        model: String = DecisionRoutingPolicy.defaultOfficialModel
    ) -> DecisionRoutingSettings {
        DecisionRoutingSettings(
            isEnabled: true,
            provider: .systemOne,
            serviceURL: serviceURL,
            model: model,
            confirmationMode: .always,
            confidenceThreshold: DecisionRoutingPolicy.defaultThreshold,
            timeoutSeconds: DecisionRoutingPolicy.defaultTimeoutSeconds,
            timeoutAction: .manualSelection,
            inAppDescription: ""
        )
    }

    nonisolated private static func response(
        status: Int,
        body: String,
        url: URL = SystemOneEndpoint.officialEvaluationURL
    ) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    nonisolated private static func okBody(choice: String, confidence: Double) -> String {
        """
        {"model":"jev-1.13.0","answers":{"route":{"type":"choice","choice":"\(choice)","confidence":\(confidence)}}}
        """
    }

    private static let slowSleep: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(60))
    }

    @Test("Remote cleartext HTTP is refused while loopback HTTP keeps working")
    func cleartextHTTPBoundary() {
        #expect(SystemOneEndpoint.evaluationURL("http://192.168.1.20:8080") == nil)
        #expect(
            SystemOneEndpoint.evaluationURLResult("http://192.168.1.20:8080")
                == .failure(.insecureRemoteHTTP)
        )
        #expect(SystemOneEndpoint.evaluationURL("http://10.1.2.3") == nil)
        #expect(SystemOneEndpoint.evaluationURLResult("http://decision.example.com") == .failure(.insecureRemoteHTTP))
        #expect(
            SystemOneEndpoint.evaluationURL("http://localhost:8080")?.absoluteString
                == "http://localhost:8080/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.evaluationURL("http://127.0.0.1:18080")?.absoluteString
                == "http://127.0.0.1:18080/v1/systemone"
        )
        #expect(
            SystemOneEndpoint.evaluationURL("http://127.9.9.9:18081")?.absoluteString
                == "http://127.9.9.9:18081/v1/systemone"
        )
        #expect(SystemOneEndpoint.evaluationURL("http://[::1]:8080") != nil)
        #expect(SystemOneEndpoint.evaluationURL("https://decision.example.com")?.absoluteString == "https://decision.example.com/v1/systemone")
        #expect(SystemOneEndpoint.evaluationURL("ftp://decision.example.com") == nil)
        #expect(SystemOneEndpoint.evaluationURLResult("not a url") == .failure(.invalidEndpoint))
        #expect(!SystemOneEndpoint.isLoopbackHost("127.0.0.256"))
        #expect(!SystemOneEndpoint.isLoopbackHost("128.0.0.1"))

        let resolved = DecisionServiceResolver.resolve(
            settings: Self.settings(serviceURL: "http://192.168.1.20:8080", model: "local-jev"),
            apiKey: nil
        )
        #expect(resolved == .failure(.insecureRemoteHTTP))
    }

    @Test("Empty custom model is invalid and the official default is never substituted")
    func emptyCustomModelIsInvalid() {
        #expect(DecisionRoutingPolicy.resolvedModel("", isOfficialService: true) == DecisionRoutingPolicy.defaultOfficialModel)
        #expect(DecisionRoutingPolicy.resolvedModel("  ", isOfficialService: true) == DecisionRoutingPolicy.defaultOfficialModel)
        #expect(DecisionRoutingPolicy.resolvedModel("", isOfficialService: false) == nil)
        #expect(DecisionRoutingPolicy.resolvedModel("   ", isOfficialService: false) == nil)
        #expect(DecisionRoutingPolicy.resolvedModel(" local-jev ", isOfficialService: false) == "local-jev")

        let customEmpty = DecisionServiceResolver.resolve(
            settings: Self.settings(serviceURL: "http://127.0.0.1:18080", model: ""),
            apiKey: nil
        )
        #expect(customEmpty == .failure(.missingModel))

        let officialEmpty = DecisionServiceResolver.resolve(settings: Self.settings(model: ""), apiKey: syntheticKey)
        guard case let .success(official) = officialEmpty else {
            Issue.record("expected the official service to keep its default model")
            return
        }
        #expect(official.model == DecisionRoutingPolicy.defaultOfficialModel)

        let custom = DecisionServiceResolver.resolve(
            settings: Self.settings(serviceURL: "http://127.0.0.1:18080", model: "local-jev"),
            apiKey: nil
        )
        guard case let .success(call) = custom else {
            Issue.record("expected a custom service without a key to resolve")
            return
        }
        #expect(call.apiKey == nil)
        #expect(call.url.absoluteString == "http://127.0.0.1:18080/v1/systemone")

        let missingKey = DecisionServiceResolver.resolve(settings: Self.settings(), apiKey: nil)
        #expect(missingKey == .failure(.missingCredential))
    }

    @Test("Legacy custom migration keeps an empty model instead of adopting the official one")
    func migrationDoesNotSubstituteOfficialModel() {
        let custom = DecisionRoutingMigration.serviceFields(
            hasStoredServiceURL: false,
            storedServiceURL: "",
            storedModel: "",
            legacyEndpoint: "custom",
            legacyOfficialModel: nil,
            legacyCustomURL: "http://127.0.0.1:8080",
            legacyCustomModel: ""
        )
        #expect(custom.serviceURL == "http://127.0.0.1:8080")
        #expect(custom.model.isEmpty)
        #expect(custom.preferLegacyCustomCredential)

        let stored = DecisionRoutingMigration.serviceFields(
            hasStoredServiceURL: true,
            storedServiceURL: "https://decision.example.com",
            storedModel: "   ",
            legacyEndpoint: nil,
            legacyOfficialModel: nil,
            legacyCustomURL: nil,
            legacyCustomModel: nil
        )
        #expect(stored.model.isEmpty)

        let official = DecisionRoutingMigration.serviceFields(
            hasStoredServiceURL: false,
            storedServiceURL: "",
            storedModel: "",
            legacyEndpoint: "official",
            legacyOfficialModel: "jev-1.12.0",
            legacyCustomURL: nil,
            legacyCustomModel: nil
        )
        #expect(official.serviceURL == DecisionRoutingPolicy.defaultServiceURL)
        #expect(official.model == "jev-1.12.0")
        #expect(!official.preferLegacyCustomCredential)
    }

    @Test("HTTP rejections map to distinct sanitized diagnostics")
    func httpStatusDiagnostics() async {
        let cases: [(Int, DecisionRoutingFailure)] = [
            (401, .httpUnauthorized),
            (403, .httpForbidden),
            (404, .httpNotFound),
            (429, .httpRateLimited),
            (500, .httpStatus(500)),
            (529, .httpStatus(529))
        ]
        for (status, expected) in cases {
            let transport = DiagnosticScriptedTransport { request in
                Self.response(
                    status: status,
                    body: "{\"error\":\"\(bodyMarker)\",\"key\":\"\(syntheticKey)\"}",
                    url: request.url!
                )
            }
            let result = await DecisionRoutingPreview.run(
                question: "route this",
                settings: Self.settings(),
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: transport,
                sleep: Self.slowSleep
            )
            #expect(result == .failed(expected))
            #expect(result.showsElapsedTime)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("Parser and transport failures map to safe distinct diagnostics")
    func parserAndTransportDiagnostics() async {
        let garbage = DiagnosticScriptedTransport { request in
            Self.response(status: 200, body: "not json at all: \(bodyMarker)", url: request.url!)
        }
        let invalid = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(),
            candidates: Self.candidates(),
            apiKey: syntheticKey,
            transport: garbage,
            sleep: Self.slowSleep
        )
        #expect(invalid == .failed(.invalidResponse))

        let missingAnswer = DiagnosticScriptedTransport { request in
            Self.response(status: 200, body: "{\"answers\":{}}", url: request.url!)
        }
        #expect(
            await DecisionRoutingPreview.run(
                question: "route this",
                settings: Self.settings(),
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: missingAnswer,
                sleep: Self.slowSleep
            ) == .failed(.invalidResponse)
        )

        let confidence = DiagnosticScriptedTransport { request in
            Self.response(status: 200, body: Self.okBody(choice: "ext_agent", confidence: 4.2), url: request.url!)
        }
        #expect(
            await DecisionRoutingPreview.run(
                question: "route this",
                settings: Self.settings(),
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: confidence,
                sleep: Self.slowSleep
            ) == .failed(.invalidResponse)
        )

        let unknownChoice = DiagnosticScriptedTransport { request in
            Self.response(status: 200, body: Self.okBody(choice: "not_in_catalog", confidence: 0.9), url: request.url!)
        }
        #expect(
            await DecisionRoutingPreview.run(
                question: "route this",
                settings: Self.settings(),
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: unknownChoice,
                sleep: Self.slowSleep
            ) == .failed(.unrecognizedChoice)
        )

        let offline = DiagnosticScriptedTransport { _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(
            await DecisionRoutingPreview.run(
                question: "route this",
                settings: Self.settings(),
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: offline,
                sleep: Self.slowSleep
            ) == .failed(.networkUnavailable)
        )

        let timedOutURL = DiagnosticScriptedTransport { _ in
            throw URLError(.timedOut)
        }
        #expect(
            await DecisionRoutingPreview.run(
                question: "route this",
                settings: Self.settings(),
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: timedOutURL,
                sleep: Self.slowSleep
            ) == .timeout(.manualSelection)
        )

        let redirected = DiagnosticScriptedTransport { _ in
            throw SystemOneClientError.unsafeRedirect
        }
        let redirectResult = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(),
            candidates: Self.candidates(),
            apiKey: syntheticKey,
            transport: redirected,
            sleep: Self.slowSleep
        )
        #expect(redirectResult == .failed(.unsafeRedirect))
        #expect(redirectResult.showsElapsedTime)
    }

    @Test("Classification is total and preview timeout follows the configured fallback")
    func classificationAndTimeout() async {
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.timedOut) == .timedOut)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.httpStatus(401)) == .httpUnauthorized)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.httpStatus(403)) == .httpForbidden)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.httpStatus(404)) == .httpNotFound)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.httpStatus(429)) == .httpRateLimited)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.httpStatus(418)) == .httpStatus(418))
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.unsafeRedirect) == .unsafeRedirect)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.invalidResponse) == .invalidResponse)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.confidenceOutOfRange) == .invalidResponse)
        #expect(DecisionRoutingFailure.classify(SystemOneClientError.unknownChoice) == .unrecognizedChoice)
        #expect(DecisionRoutingFailure.classify(URLError(.timedOut)) == .timedOut)
        #expect(DecisionRoutingFailure.classify(URLError(.cannotFindHost)) == .networkUnavailable)
        #expect(DecisionRoutingFailure.classify(KeyStoreTestError.saveFailed) == .invalidResponse)
        #expect(DecisionRoutingFailure.classify(configurationError: .invalidEndpoint) == .invalidEndpoint)
        #expect(DecisionRoutingFailure.classify(configurationError: .insecureRemoteHTTP) == .insecureRemoteHTTP)
        #expect(DecisionRoutingFailure.classify(configurationError: .missingModel) == .missingModel)
        #expect(DecisionRoutingFailure.classify(configurationError: .missingCredential) == .missingCredential)

        let slow = DiagnosticScriptedTransport { request in
            try await Task.sleep(for: .seconds(60))
            return Self.response(status: 200, body: Self.okBody(choice: "ext_agent", confidence: 1.0), url: request.url!)
        }
        var settings = Self.settings()
        settings.timeoutAction = .inApp
        #expect(
            await DecisionRoutingPreview.run(
                question: "route this",
                settings: settings,
                candidates: Self.candidates(),
                apiKey: syntheticKey,
                transport: slow,
                sleep: { _ in }
            ) == .timeout(.inApp)
        )
    }

    @Test("Prerequisites and configuration problems never contact the service")
    func prerequisitesAndConfigurationPreflight() async {
        let neverCalled = DiagnosticScriptedTransport { request in
            Self.response(status: 200, body: Self.okBody(choice: "ext_agent", confidence: 0.9), url: request.url!)
        }
        let oneCandidate = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(),
            candidates: [Self.candidates()[0]],
            apiKey: syntheticKey,
            transport: neverCalled,
            sleep: Self.slowSleep
        )
        #expect(oneCandidate == .failed(.notEnoughCandidates(available: 1)))
        #expect(!oneCandidate.showsElapsedTime)

        let blankQuestion = await DecisionRoutingPreview.run(
            question: "   ",
            settings: Self.settings(),
            candidates: Self.candidates(),
            apiKey: syntheticKey,
            transport: neverCalled,
            sleep: Self.slowSleep
        )
        #expect(blankQuestion == .failed(.emptyQuestion))
        #expect(!blankQuestion.showsElapsedTime)

        let noKey = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(),
            candidates: Self.candidates(),
            apiKey: nil,
            transport: neverCalled,
            sleep: Self.slowSleep
        )
        #expect(noKey == .failed(.missingCredential))
        #expect(!noKey.showsElapsedTime)

        let badEndpoint = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(serviceURL: "http://10.0.0.9:8080", model: "local-jev"),
            candidates: Self.candidates(),
            apiKey: nil,
            transport: neverCalled,
            sleep: Self.slowSleep
        )
        #expect(badEndpoint == .failed(.insecureRemoteHTTP))
        #expect(!badEndpoint.showsElapsedTime)

        let noModel = await DecisionRoutingPreview.run(
            question: "route this",
            settings: Self.settings(serviceURL: "http://127.0.0.1:8080", model: ""),
            candidates: Self.candidates(),
            apiKey: nil,
            transport: neverCalled,
            sleep: Self.slowSleep
        )
        #expect(noModel == .failed(.missingModel))
        #expect(!noModel.showsElapsedTime)

        #expect(await neverCalled.requestCount() == 0)
        #expect(DecisionPreviewResult.recommendation(Self.candidates()[0], confidence: 0.5, release: .confirm).showsElapsedTime)
    }


    @Test("Criteria JSON encoding is stable and keeps sorted keys")
    func criteriaEncodingIsStable() throws {
        let criteria = [
            "z_route": "Zeta. Last",
            "in_app": "In App. Short answers",
            "a_route": "Alpha. First",
            "ext_agent": "Local Agent. Local code edits"
        ]
        let bodies = try (0..<40).map { _ in
            try SystemOneRequestBuilder.body(model: "jev-1.13.0", state: "route this", criteria: criteria)
        }
        #expect(Set(bodies).count == 1)

        let text = String(decoding: bodies[0], as: UTF8.self)
        let alpha = try #require(text.range(of: "\"a_route\""))
        let zeta = try #require(text.range(of: "\"z_route\""))
        let inApp = try #require(text.range(of: "\"in_app\""))
        let extAgent = try #require(text.range(of: "\"ext_agent\""))
        #expect(alpha.lowerBound < extAgent.lowerBound)
        #expect(extAgent.lowerBound < inApp.lowerBound)
        #expect(inApp.lowerBound < zeta.lowerBound)

        let raw = try JSONSerialization.jsonObject(with: bodies[0])
        let object = try #require(raw as? [String: Any])
        let questions = try #require(object["questions"] as? [String: Any])
        let route = try #require(questions[DecisionRoutingPolicy.routeQuestionID] as? [String: Any])
        #expect(route["criteria"] as? [String: String] == criteria)
        #expect(route["type"] as? String == "choice")
    }

    @Test("Credential migration clears the legacy preference only after the new slot saves")
    func credentialMigrationSaveOutcome() throws {
        let legacy = "synthetic-legacy-credential"
        let current = "synthetic-current-credential"

        var attempted: [String] = []
        let failed = DecisionCredentialMigration.resolve(
            readSystemOne: { current },
            readLegacyCustom: { legacy },
            preferLegacyCustom: true,
            saveToSystemOne: { key in
                attempted.append(key)
                throw KeyStoreTestError.saveFailed
            }
        )
        #expect(failed.apiKey == legacy)
        #expect(!failed.clearLegacyCustomPreference)
        #expect(failed.failure == .save)
        #expect(attempted == [legacy])
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                systemOne: current,
                legacyCustom: legacy,
                preferLegacyCustom: !failed.clearLegacyCustomPreference
            ) == legacy
        )

        var saved: [String] = []
        let migrated = DecisionCredentialMigration.resolve(
            readSystemOne: { current },
            readLegacyCustom: { legacy },
            preferLegacyCustom: true,
            saveToSystemOne: { saved.append($0) }
        )
        #expect(migrated.apiKey == legacy)
        #expect(migrated.clearLegacyCustomPreference)
        #expect(migrated.failure == nil)
        #expect(saved == [legacy])
    }

    @Test("No legacy preference reads nothing to migrate and never saves")
    func credentialMigrationWithoutPreference() {
        var saves: [String] = []
        let outcome = DecisionCredentialMigration.resolve(
            readSystemOne: { "synthetic-current-credential" },
            readLegacyCustom: {
                Issue.record("the legacy slot must not be read without a preference")
                return nil
            },
            preferLegacyCustom: false,
            saveToSystemOne: { saves.append($0) }
        )
        #expect(outcome.apiKey == "synthetic-current-credential")
        #expect(!outcome.clearLegacyCustomPreference)
        #expect(outcome.failure == nil)
        #expect(saves.isEmpty)
    }

    @Test("A failed legacy read keeps the preference and never saves, with or without a current key")
    func legacyReadFailureKeepsPreference() {
        let current = "synthetic-current-credential"
        let currentReads: [() throws -> String?] = [
            { current },
            { nil as String? },
            { throw KeyStoreTestError.readFailed }
        ]
        let expectedKeys = [current, "", ""]
        for (readSystemOne, expectedKey) in zip(currentReads, expectedKeys) {
            var saves: [String] = []
            let outcome = DecisionCredentialMigration.resolve(
                readSystemOne: readSystemOne,
                readLegacyCustom: { throw KeyStoreTestError.readFailed },
                preferLegacyCustom: true,
                saveToSystemOne: { saves.append($0) }
            )
            #expect(outcome.failure == .read)
            #expect(!outcome.clearLegacyCustomPreference)
            #expect(outcome.apiKey == expectedKey)
            #expect(saves.isEmpty)
        }
    }

    @Test("A confirmed legacy absence clears the preference and never saves")
    func legacyAbsenceClearsPreference() {
        let current = "synthetic-current-credential"
        let missingReads: [() throws -> String?] = [
            { nil as String? },
            { "" as String? },
            { "   " as String? }
        ]
        for legacyRead in missingReads {
            var saves: [String] = []
            let outcome = DecisionCredentialMigration.resolve(
                readSystemOne: { current },
                readLegacyCustom: legacyRead,
                preferLegacyCustom: true,
                saveToSystemOne: { saves.append($0) }
            )
            #expect(outcome.clearLegacyCustomPreference)
            #expect(outcome.failure == nil)
            #expect(outcome.apiKey == current)
            #expect(saves.isEmpty)
        }
    }

    @Test("A current-slot read failure still migrates a readable legacy key when the new slot saves")
    func currentReadFailureMigratesReadableLegacy() {
        let legacy = "synthetic-legacy-credential"

        var saved: [String] = []
        let migrated = DecisionCredentialMigration.resolve(
            readSystemOne: { throw KeyStoreTestError.readFailed },
            readLegacyCustom: { legacy },
            preferLegacyCustom: true,
            saveToSystemOne: { saved.append($0) }
        )
        #expect(migrated.apiKey == legacy)
        #expect(migrated.clearLegacyCustomPreference)
        #expect(migrated.failure == nil)
        #expect(saved == [legacy])

        var attempted: [String] = []
        let kept = DecisionCredentialMigration.resolve(
            readSystemOne: { throw KeyStoreTestError.readFailed },
            readLegacyCustom: { legacy },
            preferLegacyCustom: true,
            saveToSystemOne: { key in
                attempted.append(key)
                throw KeyStoreTestError.saveFailed
            }
        )
        #expect(kept.apiKey == legacy)
        #expect(!kept.clearLegacyCustomPreference)
        #expect(kept.failure == .save)
        #expect(attempted == [legacy])
    }

    @Test("A current-slot read failure without a legacy preference surfaces a read failure and never saves")
    func currentReadFailureWithoutPreference() {
        var saves: [String] = []
        let outcome = DecisionCredentialMigration.resolve(
            readSystemOne: { throw KeyStoreTestError.readFailed },
            readLegacyCustom: {
                Issue.record("the legacy slot must not be read without a preference")
                return nil
            },
            preferLegacyCustom: false,
            saveToSystemOne: { saves.append($0) }
        )
        #expect(outcome.apiKey.isEmpty)
        #expect(!outcome.clearLegacyCustomPreference)
        #expect(outcome.failure == .read)
        #expect(saves.isEmpty)
    }

    @Test("A store read failure keeps the preference so recovery still resolves the legacy key")
    func storeReadFailureKeepsPreferenceUntilRecovery() throws {
        let legacySlot = DecisionCredentialSlot.legacyCustom
        let currentSlot = DecisionCredentialSlot.systemOne
        let legacy = "synthetic-legacy-credential"
        let current = "synthetic-current-credential"
        let broken = SyntheticKeyStore(
            storage: [currentSlot: current, legacySlot: legacy],
            unreadableSlots: [legacySlot]
        )

        var saves: [String] = []
        let outcome = DecisionCredentialMigration.resolve(
            readSystemOne: { try broken.readAPIKey(for: currentSlot) },
            readLegacyCustom: { try broken.readAPIKey(for: legacySlot) },
            preferLegacyCustom: true,
            saveToSystemOne: { saves.append($0) }
        )
        #expect(outcome.failure == .read)
        #expect(!outcome.clearLegacyCustomPreference)
        #expect(outcome.apiKey == current)
        #expect(saves.isEmpty)

        // Recovery: the previously unreadable legacy slot reads again, and the preserved
        // preference resolves the old key.
        let recovered = SyntheticKeyStore(storage: [currentSlot: current, legacySlot: legacy])
        #expect(
            DecisionCredentialSlot.activeAPIKey(
                systemOne: try recovered.readAPIKey(for: currentSlot),
                legacyCustom: try recovered.readAPIKey(for: legacySlot),
                preferLegacyCustom: !outcome.clearLegacyCustomPreference
            ) == legacy
        )
    }

    @Test("A corrupt credential file keeps the legacy preference until the real store recovers")
    func corruptLocalKeyStoreKeepsPreferenceUntilRecovery() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = folder.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not valid credentials json".utf8).write(to: fileURL)
        let store = LocalAPIKeyStore(fileURL: fileURL)

        var saves: [String] = []
        let broken = DecisionCredentialMigration.resolve(
            readSystemOne: { try store.readAPIKey(for: DecisionCredentialSlot.systemOne) },
            readLegacyCustom: { try store.readAPIKey(for: DecisionCredentialSlot.legacyCustom) },
            preferLegacyCustom: true,
            saveToSystemOne: { saves.append($0) }
        )
        #expect(broken.failure == .read)
        #expect(!broken.clearLegacyCustomPreference)
        #expect(broken.apiKey.isEmpty)
        #expect(saves.isEmpty)

        // Recovery: rewrite the file with a valid credential in the legacy slot only.
        let legacy = "synthetic-legacy-credential"
        let legacyID = DecisionCredentialSlot.legacyCustom.uuidString
        try Data("{\"apiKeys\":{\"\(legacyID)\":\"\(legacy)\"}}".utf8).write(to: fileURL)

        let recovered = DecisionCredentialMigration.resolve(
            readSystemOne: { try store.readAPIKey(for: DecisionCredentialSlot.systemOne) },
            readLegacyCustom: { try store.readAPIKey(for: DecisionCredentialSlot.legacyCustom) },
            preferLegacyCustom: !broken.clearLegacyCustomPreference,
            saveToSystemOne: { try store.saveAPIKey($0, for: DecisionCredentialSlot.systemOne) }
        )
        #expect(recovered.apiKey == legacy)
        #expect(recovered.clearLegacyCustomPreference)
        #expect(recovered.failure == nil)
        #expect(try store.readAPIKey(for: DecisionCredentialSlot.systemOne) == legacy)
    }

    @Test("A failed new-slot save keeps the legacy key in place")
    func failedStoreSaveKeepsLegacyPreference() throws {
        let legacySlot = DecisionCredentialSlot.legacyCustom
        let currentSlot = DecisionCredentialSlot.systemOne
        let legacy = "synthetic-legacy-credential"
        let current = "synthetic-current-credential"
        let store = SyntheticKeyStore(
            storage: [currentSlot: current, legacySlot: legacy],
            failingSlots: [currentSlot]
        )

        let outcome = DecisionCredentialMigration.resolve(
            readSystemOne: { try store.readAPIKey(for: currentSlot) },
            readLegacyCustom: { try store.readAPIKey(for: legacySlot) },
            preferLegacyCustom: true,
            saveToSystemOne: { try store.saveAPIKey($0, for: currentSlot) }
        )
        #expect(outcome.failure == .save)
        #expect(!outcome.clearLegacyCustomPreference)
        #expect(outcome.apiKey == legacy)
        #expect(store.savedSnapshot().isEmpty)
        #expect(try store.readAPIKey(for: currentSlot) == current)
        #expect(try store.readAPIKey(for: legacySlot) == legacy)
    }

    @Test("Successful migration writes the synthetic key into the new slot only")
    func credentialMigrationSuccessStoresSyntheticKey() throws {
        let store = SyntheticKeyStore(storage: [
            DecisionCredentialSlot.legacyCustom: "synthetic-legacy-credential"
        ])
        let outcome = DecisionCredentialMigration.resolve(
            readSystemOne: { try store.readAPIKey(for: DecisionCredentialSlot.systemOne) },
            readLegacyCustom: { try store.readAPIKey(for: DecisionCredentialSlot.legacyCustom) },
            preferLegacyCustom: true,
            saveToSystemOne: { try store.saveAPIKey($0, for: DecisionCredentialSlot.systemOne) }
        )
        #expect(outcome.apiKey == "synthetic-legacy-credential")
        #expect(outcome.clearLegacyCustomPreference)
        #expect(outcome.failure == nil)
        #expect(store.savedSnapshot() == ["synthetic-legacy-credential"])
        #expect(try store.readAPIKey(for: DecisionCredentialSlot.systemOne) == "synthetic-legacy-credential")
        #expect(try store.readAPIKey(for: DecisionCredentialSlot.legacyCustom) == "synthetic-legacy-credential")
    }
}
