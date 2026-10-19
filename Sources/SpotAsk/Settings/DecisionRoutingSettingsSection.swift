import SwiftUI

struct DecisionRoutingSettingsSection: View {
    let settings: AppSettings
    let keyStore: any APIKeyStoring

    @State private var apiKey = ""
    /// Last value the field wrote or restored, so a programmatic restore is not re-saved.
    @State private var restoredAPIKey = ""
    @State private var isAPIKeyVisible = false
    @State private var testQuestion = ""
    @State private var testResult: DecisionPreviewResult?
    @State private var testElapsedMs: Int?
    @State private var isTesting = false

    @State private var editingHintsAction: QuickAction?
    var body: some View {
        SettingsGroup(
            title: L10n.string("decisionRouting.sectionTitle"),
            documentation: DocumentationLinks.url(
                for: .externalAsk,
                language: settings.language,
                fragment: DocumentationLinks.decisionRoutingFragment
            )
        ) {
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
                routingLogicSyntaxSection
                Divider()
                engineConfigurationSection
                Divider()
                testFields
            }
        }
        .onAppear(perform: loadKeys)
        .sheet(item: $editingHintsAction) { action in
            RoutingHintsEditorSheet(action: action) { purpose, scenario, forceConfirm in
                settings.updateQuickActionRouting(
                    id: action.id,
                    purpose: purpose,
                    scenario: scenario,
                    requiresConfirmation: forceConfirm
                )
                editingHintsAction = nil
            }
        }
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
        }
    }

    private var routingLogicSyntaxSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("decisionRouting.routingLogicTitle"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.string("decisionRouting.routingLogicDescription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.enabledQuickActions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(L10n.string("decisionRouting.noChannelsHint"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(settings.enabledQuickActions.enumerated()), id: \.element.id) { index, action in
                        sequentialRouteCard(action: action, index: index, totalCount: settings.enabledQuickActions.count)
                    }
                }
            }

            fallbackRouteCard
        }
    }

    private func sequentialRouteCard(action: QuickAction, index: Int, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                Text(L10n.string("decisionRouting.if"))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(conditionDisplayText(for: action))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(L10n.string("decisionRouting.thenGoTo"))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 32)
                    .clipShape(Capsule())

                ProviderBrandIconView(
                    slug: action.brandIconSlug,
                    size: 16,
                    fallbackSymbol: action.symbolName
                )
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.displayName)
                            .font(.system(size: 13, weight: .semibold))

                        Text(action.kind.localizedLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())

                        if action.requiresConfirmationOnAutoRoute {
                            Label(L10n.string("decisionRouting.requiresConfirmBadge"), systemImage: "hand.raised.fill")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.1), in: Capsule())
                        } else {
                            Label(L10n.string("decisionRouting.autoRouteBadge"), systemImage: "bolt.fill")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                    }

                    if !action.routingPurpose.isEmpty {
                        Text(action.routingPurpose)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    editingHintsAction = action
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help(L10n.string("decisionRouting.editHints"))

                routeReorderControls(for: action, index: index, totalCount: totalCount)
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private func conditionDisplayText(for action: QuickAction) -> String {
        let scenario = action.routingScenario.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scenario.isEmpty {
            return "“\(scenario)”"
        }
        let purpose = action.routingPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
        if !purpose.isEmpty {
            return "“\(purpose)”"
        }
        return L10n.string("decisionRouting.defaultConditionForChannel", action.displayName)
    }

    private func routeReorderControls(for action: QuickAction, index: Int, totalCount: Int) -> some View {
        ListReorderControls(
            title: action.displayName,
            position: index + 1,
            totalCount: totalCount,
            onMoveUp: index > 0 ? { settings.moveQuickAction(id: action.id, by: -1) } : nil,
            onMoveDown: index + 1 < totalCount ? { settings.moveQuickAction(id: action.id, by: 1) } : nil
        )
    }

    private var fallbackRouteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("decisionRouting.fallbackTitle"))
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 3, height: 32)
                        .clipShape(Capsule())

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.string("decisionRouting.inAppTitle"))
                                .font(.system(size: 13, weight: .semibold))

                            Text(L10n.string("decisionRouting.defaultFallbackBadge"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }

                        Text(L10n.string("decisionRouting.fallbackDescription"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                Divider()

                SettingsFieldRow(label: L10n.string("decisionRouting.inAppDescription")) {
                    styledInputField(
                        L10n.string("decisionRouting.defaultInApp"),
                        text: Bindable(settings).decisionRoutingInAppDescription
                    )
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
            .padding(12)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private var engineConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("decisionRouting.engineSettingsTitle"))
                .font(.system(size: 13, weight: .semibold))

            SettingsToggleRow(
                label: L10n.string("decisionRouting.showToolbarToggle"),
                description: L10n.string("decisionRouting.showToolbarToggleDescription"),
                isOn: Bindable(settings).decisionRoutingShowsToolbarToggle
            )

            endpointFields
            confirmationFields
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
        let preferLegacy = settings.defaults.bool(forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        let outcome = DecisionCredentialMigration.resolve(
            readSystemOne: { try keyStore.readAPIKey(for: DecisionCredentialSlot.systemOne) },
            readLegacyCustom: { try keyStore.readAPIKey(for: DecisionCredentialSlot.legacyCustom) },
            preferLegacyCustom: preferLegacy,
            saveToSystemOne: { key in
                try keyStore.saveAPIKey(key, for: DecisionCredentialSlot.systemOne)
            }
        )
        apiKey = outcome.apiKey
        // The restore already wrote (or failed) above, so the field's change handler
        // must not repeat the same write and report the failure twice.
        restoredAPIKey = outcome.apiKey
        if outcome.clearLegacyCustomPreference {
            settings.defaults.set(false, forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        }
        switch outcome.failure {
        case .read:
            // Report read failures separately from failed migration saves.
            StatusToastCenter.shared.show(L10n.string("decisionRouting.credentialReadFailed"), isError: true)
        case .save:
            StatusToastCenter.shared.show(L10n.string("decisionRouting.credentialSaveFailed"), isError: true)
        case nil:
            break
        }
    }

    private func persist(_ key: String, slot: UUID) {
        guard key != restoredAPIKey else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keyStore.deleteAPIKey(for: slot)
            } else {
                try keyStore.saveAPIKey(trimmed, for: slot)
            }
            restoredAPIKey = key
            settings.defaults.set(false, forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        } catch {
            StatusToastCenter.shared.show(L10n.string("decisionRouting.credentialSaveFailed"), isError: true)
        }
    }

    private func runTest() {
        let question = testQuestion
        testResult = nil
        testElapsedMs = nil
        guard settings.externalAskEnabled else {
            testResult = .failed(.notEnabled)
            return
        }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            testResult = .failed(.emptyQuestion)
            return
        }
        let snapshot = settings.decisionRoutingSettings()
        let candidates = settings.decisionRoutingCandidates()
        guard candidates.count >= 2 else {
            testResult = .failed(.notEnoughCandidates(available: candidates.count))
            return
        }
        let key = apiKey
        isTesting = true
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
            // Prerequisites and configuration problems never reach the service.
            testElapsedMs = result.showsElapsedTime ? ms : nil
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
        case let .failed(failure):
            return failure.localizedText
        }
    }
}

// MARK: - Routing Hints Editor Sheet

private struct RoutingHintsEditorSheet: View {
    let action: QuickAction
    let onSave: (String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var purpose: String
    @State private var scenario: String
    @State private var forceConfirm: Bool

    init(action: QuickAction, onSave: @escaping (String, String, Bool) -> Void) {
        self.action = action
        self.onSave = onSave
        _purpose = State(initialValue: action.routingPurpose)
        _scenario = State(initialValue: action.routingScenario)
        _forceConfirm = State(initialValue: action.requiresConfirmationOnAutoRoute)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("decisionRouting.editChannelTitle", action.displayName))
                    .font(.title3.weight(.semibold))

                Text(L10n.string("decisionRouting.editChannelNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsFieldRow(label: L10n.string("decisionRouting.purpose")) {
                    TextField(L10n.string("decisionRouting.purposePlaceholder"), text: $purpose)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsFieldRow(label: L10n.string("decisionRouting.scenario")) {
                    TextField(L10n.string("decisionRouting.scenarioPlaceholder"), text: $scenario)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                SettingsToggleRow(
                    label: L10n.string("decisionRouting.forceConfirm"),
                    description: L10n.string("decisionRouting.forceConfirmDescription"),
                    isOn: $forceConfirm
                )
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("settings.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("settings.save")) {
                    onSave(purpose, scenario, forceConfirm)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 480)
    }
}

