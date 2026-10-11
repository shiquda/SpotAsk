import SwiftUI

struct DecisionRoutingSettingsSection: View {
    let settings: AppSettings
    let keyStore: any APIKeyStoring

    @State private var apiKey = ""
    @State private var testQuestion = ""
    @State private var testResult: DecisionPreviewResult?
    @State private var isTesting = false

    var body: some View {
        SettingsGroup(title: L10n.string("decisionRouting.sectionTitle")) {
            SettingsToggleRow(
                label: L10n.string("decisionRouting.enabled"),
                description: L10n.string("decisionRouting.enabledDescription"),
                isOn: Bindable(settings).decisionRoutingEnabled
            )
            if settings.decisionRoutingEnabled {
                endpointFields
                confirmationFields
                inAppFields
                testFields
            }
        }
        .onAppear(perform: loadKeys)
    }

    private var endpointFields: some View {
        Group {
            SettingsFieldRow(label: L10n.string("decisionRouting.serviceURL")) {
                TextField(DecisionRoutingPolicy.defaultServiceURL, text: Bindable(settings).decisionRoutingServiceURL)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.model")) {
                TextField(DecisionRoutingPolicy.defaultOfficialModel, text: Bindable(settings).decisionRoutingModel)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.credential")) {
                SecureField(L10n.string("decisionRouting.credentialPlaceholder"), text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onChange(of: apiKey) { _, _ in
                        persist(apiKey, slot: DecisionCredentialSlot.systemOne)
                    }
            }
            Text(L10n.string("decisionRouting.serviceNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("decisionRouting.credentialNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmationFields: some View {
        Group {
            SettingsFieldRow(label: L10n.string("decisionRouting.confirmationMode")) {
                Picker(L10n.string("decisionRouting.confirmationMode"), selection: Bindable(settings).decisionRoutingConfirmationMode) {
                    Text(L10n.string("decisionRouting.confirmAlways")).tag(DecisionConfirmationMode.always)
                    Text(L10n.string("decisionRouting.confirmThreshold")).tag(DecisionConfirmationMode.threshold)
                }
                .labelsHidden()
            }
            if settings.decisionRoutingConfirmationMode == .threshold {
                SettingsFieldRow(label: L10n.string("decisionRouting.threshold")) {
                    HStack {
                        Slider(
                            value: Bindable(settings).decisionRoutingConfidenceThreshold,
                            in: 0...1,
                            step: 0.05
                        )
                        Text(DecisionRoutingCard.confidenceText(settings.decisionRoutingConfidenceThreshold))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Text(L10n.string("decisionRouting.thresholdNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.timeout")) {
                HStack {
                    Slider(
                        value: Bindable(settings).decisionRoutingTimeoutSeconds,
                        in: DecisionRoutingPolicy.minimumTimeoutSeconds...DecisionRoutingPolicy.maximumTimeoutSeconds,
                        step: DecisionRoutingPolicy.timeoutStepSeconds
                    )
                    Text(String(format: "%.1fs", locale: AppLanguage.current.locale, settings.decisionRoutingTimeoutSeconds))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.timeoutAction")) {
                Picker(L10n.string("decisionRouting.timeoutAction"), selection: Bindable(settings).decisionRoutingTimeoutAction) {
                    Text(L10n.string("decisionRouting.timeoutManualAction")).tag(DecisionTimeoutAction.manualSelection)
                    Text(L10n.string("decisionRouting.timeoutInAppAction")).tag(DecisionTimeoutAction.inApp)
                }
                .labelsHidden()
            }
        }
    }

    private var inAppFields: some View {
        SettingsFieldRow(label: L10n.string("decisionRouting.inAppDescription")) {
            TextField(L10n.string("decisionRouting.defaultInApp"), text: Bindable(settings).decisionRoutingInAppDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }

    private var testFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsFieldRow(label: L10n.string("decisionRouting.testAsk")) {
                TextField(L10n.string("decisionRouting.testPlaceholder"), text: $testQuestion, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            HStack {
                Button(L10n.string("decisionRouting.testRun")) {
                    runTest()
                }
                .disabled(isTesting || testQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            Text(L10n.string("decisionRouting.testNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let testResult {
                Text(resultText(testResult))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func loadKeys() {
        let legacy = (try? keyStore.readAPIKey(for: DecisionCredentialSlot.legacyCustom)) ?? ""
        let current = (try? keyStore.readAPIKey(for: DecisionCredentialSlot.systemOne)) ?? ""
        let preferLegacy = settings.defaults.bool(forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        if preferLegacy, !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apiKey = legacy
            persist(legacy, slot: DecisionCredentialSlot.systemOne)
            settings.defaults.set(false, forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        } else {
            apiKey = current
        }
    }

    private func persist(_ key: String, slot: UUID) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keyStore.deleteAPIKey(for: slot)
            } else {
                try keyStore.saveAPIKey(trimmed, for: slot)
            }
        } catch {
            StatusToastCenter.shared.show(L10n.string("decisionRouting.credentialSaveFailed"), isError: true)
        }
    }

    private func runTest() {
        let question = testQuestion
        let snapshot = settings.decisionRoutingSettings()
        let candidates = settings.decisionRoutingCandidates()
        guard candidates.count >= 2 else {
            testResult = .unavailable
            return
        }
        let key = apiKey
        isTesting = true
        testResult = nil
        let proxy = ChatNetworking.proxyConfiguration(settings: settings, keyStore: keyStore)
        Task {
            let result = await DecisionRoutingPreview.run(
                question: question,
                settings: snapshot,
                candidates: candidates,
                apiKey: key,
                transport: URLSessionSystemOneTransport(
                    session: ChatNetworking.urlSession(proxyConfiguration: proxy)
                )
            )
            isTesting = false
            testResult = result
        }
    }

    private func resultText(_ result: DecisionPreviewResult) -> String {
        switch result {
        case let .recommendation(candidate, confidence, release):
            let action = release == .autoSend
                ? L10n.string("decisionRouting.testWouldSend")
                : L10n.string("decisionRouting.testWouldConfirm")
            return L10n.string(
                "decisionRouting.testRecommendation",
                candidate.title,
                DecisionRoutingCard.confidenceText(confidence),
                action
            )
        case let .timeout(action):
            let actionText = action == .inApp
                ? L10n.string("decisionRouting.timeoutInAppAction")
                : L10n.string("decisionRouting.timeoutManualAction")
            return L10n.string("decisionRouting.testTimeout", actionText)
        case .missingCredential:
            return L10n.string("decisionRouting.missingCredential")
        case .invalidEndpoint:
            return L10n.string("decisionRouting.invalidEndpoint")
        case .missingModel:
            return L10n.string("decisionRouting.missingModel")
        case .unknownChoice:
            return L10n.string("decisionRouting.unknownChoice")
        case .unavailable:
            return L10n.string("decisionRouting.unavailable")
        }
    }
}

struct QuickActionRoutingEditor: View {
    let action: QuickAction
    let onSave: (String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var purpose: String
    @State private var scenario: String
    @State private var requiresConfirmation: Bool

    init(action: QuickAction, onSave: @escaping (String, String, Bool) -> Void) {
        self.action = action
        self.onSave = onSave
        _purpose = State(initialValue: action.routingPurpose)
        _scenario = State(initialValue: action.routingScenario)
        _requiresConfirmation = State(initialValue: action.requiresConfirmationOnAutoRoute)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("decisionRouting.editChannelTitle", action.displayName))
                .font(.headline)
            Text(L10n.string("decisionRouting.editChannelNote"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsFieldRow(label: L10n.string("decisionRouting.purpose")) {
                TextField(L10n.string("decisionRouting.purposePlaceholder"), text: $purpose, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.scenario")) {
                TextField(L10n.string("decisionRouting.scenarioPlaceholder"), text: $scenario, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            SettingsToggleRow(
                label: L10n.string("decisionRouting.forceConfirm"),
                description: L10n.string("decisionRouting.forceConfirmDescription"),
                isOn: $requiresConfirmation
            )
            HStack {
                Spacer()
                Button(L10n.string("settings.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("settings.save")) {
                    onSave(purpose, scenario, requiresConfirmation)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
