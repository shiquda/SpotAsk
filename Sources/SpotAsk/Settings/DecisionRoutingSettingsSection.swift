import SwiftUI

struct DecisionRoutingSettingsSection: View {
    let settings: AppSettings
    let keyStore: any APIKeyStoring

    @State private var apiKey = ""
    @State private var isAPIKeyVisible = false
    @State private var testQuestion = ""
    @State private var testResult: DecisionPreviewResult?
    @State private var testElapsedMs: Int?
    @State private var isTesting = false

    var body: some View {
        SettingsGroup(title: L10n.string("decisionRouting.sectionTitle")) {
            SettingsToggleRow(
                label: L10n.string("decisionRouting.enabled"),
                description: L10n.string("decisionRouting.enabledDescription"),
                isOn: Bindable(settings).decisionRoutingEnabled
            )
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(L10n.string("decisionRouting.preferenceHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if settings.decisionRoutingEnabled {
                Divider()
                endpointFields
                Divider()
                confirmationFields
                inAppFields
                Divider()
                testFields
            }
        }
        .onAppear(perform: loadKeys)
    }

    private var endpointFields: some View {
        Group {
            SettingsFieldRow(label: L10n.string("decisionRouting.serviceURL")) {
                styledInputField(DecisionRoutingPolicy.defaultServiceURL, text: Bindable(settings).decisionRoutingServiceURL)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.model")) {
                styledInputField(DecisionRoutingPolicy.defaultOfficialModel, text: Bindable(settings).decisionRoutingModel)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.credential")) {
                HStack(spacing: 6) {
                    Group {
                        if isAPIKeyVisible {
                            TextField(L10n.string("decisionRouting.credentialPlaceholder"), text: $apiKey)
                        } else {
                            SecureField(L10n.string("decisionRouting.credentialPlaceholder"), text: $apiKey)
                                .textContentType(.password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, idealWidth: 200, maxWidth: .infinity)
                    .onChange(of: apiKey) { _, _ in
                        persist(apiKey, slot: DecisionCredentialSlot.systemOne)
                    }

                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text(L10n.string("decisionRouting.serviceNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 148)
                .padding(.top, -6)
        }
    }

    private var confirmationFields: some View {
        Group {
            SettingsFieldRow(label: L10n.string("decisionRouting.confirmationMode")) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Picker(L10n.string("decisionRouting.confirmationMode"), selection: Bindable(settings).decisionRoutingConfirmationMode) {
                        Text(L10n.string("decisionRouting.confirmAlways")).tag(DecisionConfirmationMode.always)
                        Text(L10n.string("decisionRouting.confirmThreshold")).tag(DecisionConfirmationMode.threshold)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if settings.decisionRoutingConfirmationMode == .threshold {
                SettingsFieldRow(label: L10n.string("decisionRouting.threshold")) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Bindable(settings).decisionRoutingConfidenceThreshold,
                            in: 0...1,
                            step: 0.05
                        )
                        Text(DecisionRoutingCard.confidenceText(settings.decisionRoutingConfidenceThreshold))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                Text(L10n.string("decisionRouting.thresholdNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 148)
                    .padding(.top, -6)
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.timeout")) {
                HStack(spacing: 10) {
                    Slider(
                        value: Bindable(settings).decisionRoutingTimeoutSeconds,
                        in: DecisionRoutingPolicy.minimumTimeoutSeconds...DecisionRoutingPolicy.maximumTimeoutSeconds,
                        step: DecisionRoutingPolicy.timeoutStepSeconds
                    )
                    Text(String(format: "%.1fs", locale: AppLanguage.current.locale, settings.decisionRoutingTimeoutSeconds))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
            SettingsFieldRow(label: L10n.string("decisionRouting.timeoutAction")) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Picker(L10n.string("decisionRouting.timeoutAction"), selection: Bindable(settings).decisionRoutingTimeoutAction) {
                        Text(L10n.string("decisionRouting.timeoutManualAction")).tag(DecisionTimeoutAction.manualSelection)
                        Text(L10n.string("decisionRouting.timeoutInAppAction")).tag(DecisionTimeoutAction.inApp)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }

    private var inAppFields: some View {
        SettingsFieldRow(label: L10n.string("decisionRouting.inAppDescription")) {
            styledInputField(L10n.string("decisionRouting.defaultInApp"), text: Bindable(settings).decisionRoutingInAppDescription)
        }
    }

    private var testFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsFieldRow(label: L10n.string("decisionRouting.testAsk")) {
                HStack(spacing: 8) {
                    styledInputField(L10n.string("decisionRouting.testPlaceholder"), text: $testQuestion)
                        .onSubmit {
                            if !isTesting && !testQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                runTest()
                            }
                        }
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(L10n.string("decisionRouting.testRun")) {
                        runTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || testQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Text(L10n.string("decisionRouting.testNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 148)
                .padding(.top, -4)
            if let testResult {
                testResultCard(testResult)
            }
        }
    }

    private func styledInputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120, idealWidth: 200, maxWidth: .infinity)
    }

    @ViewBuilder
    private func testResultCard(_ result: DecisionPreviewResult) -> some View {
        HStack(spacing: 8) {
            switch result {
            case let .recommendation(candidate, confidence, release):
                ProviderBrandIconView(
                    slug: candidate.brandIconSlug,
                    size: 14,
                    fallbackSymbol: candidate.symbolName
                )
                .frame(width: 14, height: 14)
                Text(candidate.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(L10n.string("decisionRouting.confidenceBadge", DecisionRoutingCard.confidenceText(confidence)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Text(release == .autoSend ? L10n.string("decisionRouting.testWouldSend") : L10n.string("decisionRouting.testWouldConfirm"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(release == .autoSend ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (release == .autoSend ? Color.accentColor : Color.primary).opacity(0.1),
                        in: Capsule()
                    )
            default:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(resultText(result))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let testElapsedMs {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(L10n.string("decisionRouting.testElapsed", testElapsedMs))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resultText(result))
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
            testElapsedMs = 0
            testResult = .unavailable
            return
        }
        let key = apiKey
        isTesting = true
        testResult = nil
        testElapsedMs = nil
        let proxy = ChatNetworking.proxyConfiguration(settings: settings, keyStore: keyStore)
        Task {
            let clock = ContinuousClock()
            let startedAt = clock.now
            let result = await DecisionRoutingPreview.run(
                question: question,
                settings: snapshot,
                candidates: candidates,
                apiKey: key,
                transport: URLSessionSystemOneTransport(
                    session: ChatNetworking.urlSession(proxyConfiguration: proxy)
                )
            )
            let elapsed = clock.now - startedAt
            let ms = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            isTesting = false
            testElapsedMs = ms
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

