import AppKit
import Foundation
import Observation

// MARK: - Provider Settings State

@MainActor
@Observable
final class ProviderSettingsState {
    let settings: AppSettings
    private let keyStore: any APIKeyStoring
    private let providerFactory: any ChatProviderFactory
    private let modelDiscovery: any ProviderModelDiscovering
    private var modelRefreshTask: Task<Void, Never>?
    private var modelRefreshGeneration = 0

    // MARK: Selection state

    var selectedProviderID: UUID?
    var selectedModelID: UUID?
    var expandedProviderIDs: Set<UUID> = []
    /// Observable mirror of the registry's selectedModelID so the tree
    /// and detail re-render when the active model changes.
    var activeModelID: UUID?

    // MARK: Provider draft

    var draftProviderName = ""
    var draftProviderAddress = ""
    var draftProviderAddressMode: ProviderAddressMode = .baseURL
    var draftProviderTimeout: Double = 60
    var draftProviderFormat: ProviderFormat = .openAICompatible

    // MARK: Model draft

    var draftModelDisplayName = ""
    var draftModelUpstreamID = ""
    var draftModelStreaming = true
    var draftModelCompatibilityProfile: RequestCompatibilityProfile = .genericOpenAI
    var draftModelCompatibilityProfileIsManual = false
    var draftModelThinkingMode: ModelThinkingMode = .providerDefault
    var draftModelExtraRequestParametersText = ""

    // MARK: Create/edit mode

    var isCreatingProvider = false
    var isCreatingModel = false
    var newModelParentProviderID: UUID?

    // MARK: Access key

    var apiKeyDraft = ""

    // MARK: Status

    var status = ""
    var statusIsError = false
    var testingModelID: UUID?
    var providerFieldError: String?
    var modelRefreshStatus: ModelRefreshStatus = .idle {
        didSet { notifyModelRefreshStatus() }
    }

    // MARK: Discovered model selection

    var discoveredModelCandidates: [String] = []
    var selectedDiscoveredModelIDs: Set<String> = []
    var isModelSelectionPresented = false

    var isTesting: Bool {
        testingModelID != nil
    }

    // MARK: Delete confirmation

    var pendingDeleteProviderID: UUID?
    var pendingDeleteModelID: UUID?

    // MARK: Computed properties

    var providers: [ProviderConfiguration] {
        settings.providerRegistry.catalog?.providers ?? []
    }

    var selectedModel: ModelConfiguration? {
        guard let id = selectedModelID,
              let catalog = settings.providerRegistry.catalog else { return nil }
        return catalog.models.first(where: { $0.id == id })
    }

    func modelsForProvider(_ providerID: UUID) -> [ModelConfiguration] {
        settings.providerRegistry.catalog?.models.filter { $0.providerID == providerID } ?? []
    }

    var canSaveProvider: Bool {
        let name = draftProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !address.isEmpty && providerFieldError == nil
    }

    var canSaveModel: Bool {
        let displayName = draftModelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamID = draftModelUpstreamID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !displayName.isEmpty && !upstreamID.isEmpty && draftExtraRequestParametersJSONError == nil
    }

    var draftExtraRequestParametersJSONError: String? {
        do {
            let parameters = try decodedExtraRequestParameters() ?? [:]
            if parameters.keys.contains(where: { RequestCompatibilityProfile.protectedStructuralKeys.contains($0) }) {
                return L10n.string("settings.customRequestParametersProtected")
            }
            return nil
        } catch {
            return L10n.string("settings.customRequestParametersInvalid")
        }
    }

    var canTestConnection: Bool {
        guard let pid = selectedProviderID,
              let catalog = settings.providerRegistry.catalog,
              catalog.models.contains(where: { $0.providerID == pid }) else { return false }
        let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return !address.isEmpty
            && providerFieldError == nil
            && (try? URLNormalizer.endpoint(
                from: address,
                useFullEndpoint: draftProviderAddressMode.usesFullEndpoint,
                format: draftProviderFormat
            )) != nil
    }

    var selectedProviderSupportsModelRefresh: Bool {
        guard let providerID = selectedProviderID,
              let provider = settings.providerRegistry.catalog?.providers.first(where: { $0.id == providerID }) else {
            return false
        }
        return provider.addressMode == .baseURL
    }

    var canRefreshModels: Bool {
        selectedProviderSupportsModelRefresh && !isRefreshingModels
    }

    var isRefreshingModels: Bool {
        if case .loading = modelRefreshStatus { return true }
        return false
    }

    var modelRefreshStatusText: String? {
        switch modelRefreshStatus {
        case .idle, .loading: return nil
        case let .success(count): return L10n.string("settings.modelRefreshSuccess", count)
        case .missingAccessKey: return L10n.string("settings.modelRefreshNeedsKey")
        case .cancelled: return L10n.string("settings.modelRefreshCancelled")
        case .failed: return L10n.string("settings.modelRefreshFailed")
        case .unavailable: return L10n.string("settings.modelRefreshUnavailable")
        }
    }

    var modelRefreshStatusIsError: Bool {
        switch modelRefreshStatus {
        case .missingAccessKey, .failed: true
        case .idle, .loading, .success, .cancelled, .unavailable: false
        }
    }

    // MARK: Init

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        providerFactory: any ChatProviderFactory,
        modelDiscovery: (any ProviderModelDiscovering)? = nil
    ) {
        self.settings = settings
        self.keyStore = keyStore
        self.providerFactory = providerFactory
        self.modelDiscovery = modelDiscovery ?? ProviderModelDiscoveryRouter(
            urlSession: ChatNetworking.urlSession(
                proxyConfiguration: Self.makeProxyConfiguration(settings: settings, keyStore: keyStore)
            )
        )
        self.activeModelID = settings.providerRegistry.catalog?.selectedModelID

        // Auto-select first provider on init
        if let firstProvider = settings.providerRegistry.catalog?.providers.first {
            selectProvider(firstProvider.id)
        }
    }

    func reloadCatalogSelection() {
        selectedProviderID = nil
        selectedModelID = nil
        syncActiveModelID()
        if let firstProvider = settings.providerRegistry.catalog?.providers.first {
            selectProvider(firstProvider.id)
        }
    }

    // MARK: Selection

    func selectProvider(_ id: UUID) {
        guard let catalog = settings.providerRegistry.catalog,
              let provider = catalog.providers.first(where: { $0.id == id }) else { return }

        invalidateModelRefresh()
        cancelEditing()
        selectedProviderID = id
        selectedModelID = nil
        expandedProviderIDs.insert(id)

        draftProviderName = provider.name
        draftProviderAddress = provider.address
        draftProviderAddressMode = provider.addressMode
        draftProviderTimeout = provider.timeout
        draftProviderFormat = provider.format

        draftModelDisplayName = ""
        draftModelUpstreamID = ""
        draftModelStreaming = true
        draftModelCompatibilityProfileIsManual = false
        draftModelCompatibilityProfile = .inferred(
            modelName: "",
            upstreamModelID: "",
            providerName: provider.name,
            providerAddress: provider.address,
            providerFormat: provider.format
        )
        draftModelThinkingMode = .providerDefault
        draftModelExtraRequestParametersText = ""

        apiKeyDraft = (try? keyStore.readAPIKey(for: id)) ?? ""
        status = ""
        statusIsError = false
        providerFieldError = validateProviderAddress(provider.address)
    }

    func selectModel(_ id: UUID) {
        guard let catalog = settings.providerRegistry.catalog,
              let model = catalog.models.first(where: { $0.id == id }),
              catalog.providers.contains(where: { $0.id == model.providerID }) else { return }

        invalidateModelRefresh()
        cancelEditing()
        selectedModelID = id
        selectedProviderID = nil
        expandedProviderIDs.insert(model.providerID)

        draftModelDisplayName = model.displayName
        draftModelUpstreamID = model.upstreamModelID
        draftModelStreaming = model.isStreamingEnabled
        draftModelCompatibilityProfile = model.compatibilityProfile
        draftModelCompatibilityProfileIsManual = model.isCompatibilityProfileManuallySet
        draftModelThinkingMode = model.thinkingMode
        draftModelExtraRequestParametersText = Self.requestParametersText(model.extraRequestParameters)

        draftProviderName = ""
        draftProviderAddress = ""
        draftProviderAddressMode = .baseURL
        draftProviderTimeout = 60
        draftProviderFormat = .openAICompatible

        apiKeyDraft = ""
        status = ""
        statusIsError = false
        providerFieldError = nil
    }

    func toggleProviderExpansion(_ id: UUID) {
        if expandedProviderIDs.contains(id) {
            expandedProviderIDs.remove(id)
        } else {
            expandedProviderIDs.insert(id)
        }
    }

    /// Collapses a Service even when it is the one being edited. Editing
    /// selection must be cleared, otherwise the card stays expanded because
    /// its detail form is considered part of the expanded content.
    func collapseProvider(_ id: UUID) {
        let ownsEditingSelection: Bool
        if selectedProviderID == id {
            ownsEditingSelection = true
        } else if let selectedModelID,
                  let catalog = settings.providerRegistry.catalog,
                  catalog.models.first(where: { $0.id == selectedModelID })?.providerID == id {
            ownsEditingSelection = true
        } else {
            ownsEditingSelection = false
        }
        if ownsEditingSelection {
            selectedProviderID = nil
            selectedModelID = nil
        }
        cancelEditing()
        expandedProviderIDs.remove(id)
    }

    // MARK: Create

    func startNewProvider() {
        invalidateModelRefresh()
        cancelEditing()
        isCreatingProvider = true
        selectedProviderID = nil
        selectedModelID = nil

        draftProviderName = ""
        draftProviderAddress = ""
        draftProviderAddressMode = .baseURL
        draftProviderTimeout = 60
        draftProviderFormat = .openAICompatible
        apiKeyDraft = ""
        status = ""
        statusIsError = false
        providerFieldError = nil
    }

    func startNewModel(for providerID: UUID) {
        invalidateModelRefresh()
        cancelEditing()
        isCreatingModel = true
        newModelParentProviderID = providerID
        selectedModelID = nil
        selectedProviderID = nil
        expandedProviderIDs.insert(providerID)

        draftModelDisplayName = ""
        draftModelUpstreamID = ""
        draftModelStreaming = true
        let newModelProvider = settings.providerRegistry.catalog?.providers.first(where: { $0.id == providerID })
        draftModelCompatibilityProfileIsManual = false
        draftModelCompatibilityProfile = Self.inferredCompatibilityProfile(
            modelName: "",
            upstreamModelID: "",
            provider: newModelProvider
        )
        draftModelThinkingMode = .providerDefault
        draftModelExtraRequestParametersText = ""
        status = ""
        statusIsError = false
        providerFieldError = nil
    }

    func cancelEditing() {
        isCreatingProvider = false
        isCreatingModel = false
        newModelParentProviderID = nil
        status = ""
        statusIsError = false
        providerFieldError = nil

        // Restore draft from current selection without re-triggering selection
        if let pid = selectedProviderID,
           let catalog = settings.providerRegistry.catalog,
           let provider = catalog.providers.first(where: { $0.id == pid }) {
            apiKeyDraft = (try? keyStore.readAPIKey(for: pid)) ?? ""
            draftProviderName = provider.name
            draftProviderAddress = provider.address
            draftProviderAddressMode = provider.addressMode
            draftProviderTimeout = provider.timeout
            draftProviderFormat = provider.format
            draftModelDisplayName = ""
            draftModelUpstreamID = ""
            draftModelStreaming = true
            draftModelCompatibilityProfileIsManual = false
            draftModelCompatibilityProfile = Self.inferredCompatibilityProfile(
                modelName: "",
                upstreamModelID: "",
                provider: provider
            )
            draftModelThinkingMode = .providerDefault
            draftModelExtraRequestParametersText = ""
        } else if let mid = selectedModelID,
                  let catalog = settings.providerRegistry.catalog,
                  let model = catalog.models.first(where: { $0.id == mid }) {
            draftModelDisplayName = model.displayName
            draftModelUpstreamID = model.upstreamModelID
            draftModelStreaming = model.isStreamingEnabled
            draftModelCompatibilityProfile = model.compatibilityProfile
            draftModelCompatibilityProfileIsManual = model.isCompatibilityProfileManuallySet
            draftModelThinkingMode = model.thinkingMode
            draftModelExtraRequestParametersText = Self.requestParametersText(model.extraRequestParameters)
            draftProviderName = ""
            draftProviderAddress = ""
            draftProviderAddressMode = .baseURL
            draftProviderTimeout = 60
            draftProviderFormat = .openAICompatible
            apiKeyDraft = ""
        } else {
            selectedProviderID = nil
            selectedModelID = nil
            draftProviderName = ""
            draftProviderAddress = ""
            draftProviderAddressMode = .baseURL
            draftProviderTimeout = 60
            draftProviderFormat = .openAICompatible
            draftModelDisplayName = ""
            draftModelUpstreamID = ""
            draftModelStreaming = true
            draftModelCompatibilityProfile = .genericOpenAI
            draftModelCompatibilityProfileIsManual = false
            draftModelThinkingMode = .providerDefault
            draftModelExtraRequestParametersText = ""
            apiKeyDraft = ""
        }
    }

    // MARK: Save

    func saveProvider() {
        let name = draftProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draftProviderAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            setStatus(L10n.string("settings.providerNameRequired"), isError: true)
            return
        }
        guard !address.isEmpty else {
            setStatus(L10n.string("settings.providerAddressRequired"), isError: true)
            return
        }
        guard providerFieldError == nil else { return }

        invalidateModelRefresh()
        do {
            let id = isCreatingProvider ? UUID() : (selectedProviderID ?? UUID())
            let provider = ProviderConfiguration(
                id: id,
                name: name,
                address: address,
                addressMode: draftProviderAddressMode,
                timeout: draftProviderTimeout,
                format: draftProviderFormat
            )
            let saved = try settings.providerRegistry.saveProvider(provider)
            isCreatingProvider = false
            selectProvider(saved.id)
            setStatus(L10n.string("settings.providerSaved"), isError: false)
        } catch {
            setStatus(L10n.string("settings.providerSaveFailed"), isError: true)
        }
    }

    func saveModel() {
        let displayName = draftModelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamID = draftModelUpstreamID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !displayName.isEmpty else {
            setStatus(L10n.string("settings.modelDisplayNameRequired"), isError: true)
            return
        }
        guard !upstreamID.isEmpty else {
            setStatus(L10n.string("settings.modelUpstreamIDRequired"), isError: true)
            return
        }
        guard draftExtraRequestParametersJSONError == nil else {
            setStatus(L10n.string("settings.customRequestParametersInvalid"), isError: true)
            return
        }

        do {
            let id = isCreatingModel ? UUID() : (selectedModelID ?? UUID())
            let providerID: UUID
            if isCreatingModel, let parentID = newModelParentProviderID {
                providerID = parentID
            } else if let existing = selectedModel {
                providerID = existing.providerID
            } else {
                setStatus(L10n.string("settings.modelProviderRequired"), isError: true)
                return
            }

            let model = ModelConfiguration(
                id: id,
                displayName: displayName,
                upstreamModelID: upstreamID,
                providerID: providerID,
                isStreamingEnabled: draftModelStreaming,
                source: .manual,
                compatibilityProfile: draftModelCompatibilityProfile,
                isCompatibilityProfileManuallySet: draftModelCompatibilityProfileIsManual ||
                    draftModelCompatibilityProfile != Self.inferredCompatibilityProfile(
                        modelName: displayName,
                        upstreamModelID: upstreamID,
                        provider: settings.providerRegistry.catalog?.providers.first(where: { $0.id == providerID })
                    ),
                thinkingMode: draftModelThinkingMode,
                extraRequestParameters: try decodedExtraRequestParameters()
            )
            let saved = try settings.providerRegistry.saveModel(model)
            isCreatingModel = false
            newModelParentProviderID = nil
            selectModel(saved.id)
            setStatus(L10n.string("settings.modelSaved"), isError: false)
        } catch {
            setStatus(L10n.string("settings.modelSaveFailed"), isError: true)
        }
    }

    func setDraftModelCompatibilityProfile(_ profile: RequestCompatibilityProfile) {
        draftModelCompatibilityProfile = profile
        draftModelCompatibilityProfileIsManual = true
        clearStatus()
    }

    func updateDraftModelCompatibilityProfileIfNeeded() {
        guard !draftModelCompatibilityProfileIsManual else { return }
        let provider = newModelParentProviderID.flatMap { id in
            settings.providerRegistry.catalog?.providers.first(where: { $0.id == id })
        } ?? selectedModel.flatMap { model in
            settings.providerRegistry.catalog?.providers.first(where: { $0.id == model.providerID })
        }
        draftModelCompatibilityProfile = Self.inferredCompatibilityProfile(
            modelName: draftModelDisplayName,
            upstreamModelID: draftModelUpstreamID,
            provider: provider
        )
    }

    private static func inferredCompatibilityProfile(
        modelName: String,
        upstreamModelID: String,
        provider: ProviderConfiguration?
    ) -> RequestCompatibilityProfile {
        .inferred(
            modelName: modelName,
            upstreamModelID: upstreamModelID,
            providerName: provider?.name ?? "",
            providerAddress: provider?.address ?? "",
            providerFormat: provider?.format ?? .openAICompatible
        )
    }

    /// Set a model as the active chat model without switching editing context.
    func useModelForChat(_ id: UUID) {
        do {
            try settings.providerRegistry.selectModel(id: id)
            syncActiveModelID()
            setStatus(L10n.string("settings.modelActivated"), isError: false)
        } catch {
            setStatus(L10n.string("settings.modelActivateFailed"), isError: true)
        }
    }

    // MARK: Delete

    func requestDeleteProvider(_ id: UUID) {
        pendingDeleteProviderID = id
    }

    func requestDeleteModel(_ id: UUID) {
        pendingDeleteModelID = id
    }

    func confirmDeleteProvider() {
        guard let id = pendingDeleteProviderID else { return }
        pendingDeleteProviderID = nil
        if selectedProviderID == id {
            invalidateModelRefresh()
        }

        // Capture affected editing selection before the provider
        // (and its models) are removed from the catalog.
        let wasEditingThisProvider = (selectedProviderID == id)
        let modelOwnedByThisProvider: UUID? = {
            if let mid = selectedModelID,
               let catalog = settings.providerRegistry.catalog,
               let model = catalog.models.first(where: { $0.id == mid }),
               model.providerID == id {
                return mid
            }
            return nil
        }()

        do {
            try settings.providerRegistry.deleteProvider(id: id, keyStore: keyStore)
            syncActiveModelID()

            if wasEditingThisProvider || modelOwnedByThisProvider != nil {
                if let catalog = settings.providerRegistry.catalog,
                   let newModel = catalog.models.first(where: { $0.id == catalog.selectedModelID }) {
                    selectModel(newModel.id)
                } else if let firstProvider = settings.providerRegistry.catalog?.providers.first {
                    selectProvider(firstProvider.id)
                }
            }
            setStatus(L10n.string("settings.providerDeleted"), isError: false)
        } catch let error as ProviderModelRegistryError {
            switch error {
            case .wouldLeaveNoSelectableModel:
                setStatus(L10n.string("settings.cannotDeleteLastProvider"), isError: true)
            default:
                setStatus(L10n.string("settings.providerDeleteFailed"), isError: true)
            }
        } catch {
            setStatus(L10n.string("settings.providerDeleteFailed"), isError: true)
        }
    }

    func confirmDeleteModel() {
        guard let id = pendingDeleteModelID else { return }
        pendingDeleteModelID = nil
        do {
            try settings.providerRegistry.deleteModel(id: id)
            syncActiveModelID()
            if selectedModelID == id {
                if let catalog = settings.providerRegistry.catalog,
                   let newModel = catalog.models.first(where: { $0.id == catalog.selectedModelID }) {
                    selectModel(newModel.id)
                } else if let firstProvider = settings.providerRegistry.catalog?.providers.first {
                    selectProvider(firstProvider.id)
                }
            }
            setStatus(L10n.string("settings.modelDeleted"), isError: false)
        } catch let error as ProviderModelRegistryError {
            switch error {
            case .wouldLeaveNoSelectableModel:
                setStatus(L10n.string("settings.cannotDeleteLastModel"), isError: true)
            default:
                setStatus(L10n.string("settings.modelDeleteFailed"), isError: true)
            }
        } catch {
            setStatus(L10n.string("settings.modelDeleteFailed"), isError: true)
        }
    }

    // MARK: Access key

    func persistAPIKeyDraft() {
        guard let providerID = selectedProviderID else { return }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if key.isEmpty {
                try keyStore.deleteAPIKey(for: providerID)
            } else {
                try keyStore.saveAPIKey(key, for: providerID)
            }
        } catch {
            setStatus(L10n.string("settings.saveKeyFailure"), isError: true)
        }
    }


    func testConnection(modelID: UUID? = nil) {
        guard !isTesting else { return }
        guard let catalog = settings.providerRegistry.catalog else { return }

        let providerID: UUID
        let model: ModelConfiguration
        if let modelID {
            guard let matchedModel = catalog.models.first(where: { $0.id == modelID }),
                  catalog.providers.contains(where: { $0.id == matchedModel.providerID }) else { return }
            providerID = matchedModel.providerID
            model = matchedModel
        } else {
            guard let selectedProviderID else { return }
            guard let matchedModel = catalog.models.first(where: { $0.providerID == selectedProviderID }) else { return }
            providerID = selectedProviderID
            model = matchedModel
        }
        guard let provider = catalog.providers.first(where: { $0.id == providerID }) else { return }

        let isDraftProvider = selectedProviderID == providerID
        let address = (isDraftProvider ? draftProviderAddress : provider.address)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = isDraftProvider ? draftProviderAddressMode : provider.addressMode
        let timeout = isDraftProvider ? draftProviderTimeout : provider.timeout

        testingModelID = model.id
        status = ""
        statusIsError = false

        Task {
            do {
                if isDraftProvider { persistAPIKeyDraft() }
                let draftKey = isDraftProvider
                    ? apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                let storedKey = try keyStore.readAPIKey(for: providerID)

                // Require an API key before constructing the target
                guard let apiKey = (storedKey ?? (draftKey.isEmpty ? nil : draftKey)),
                      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatError.missingAPIKey
                }

                let endpoint = try URLNormalizer.endpoint(
                    from: address,
                    useFullEndpoint: mode.usesFullEndpoint,
                    format: isDraftProvider ? draftProviderFormat : provider.format
                )
                let target = ProviderTargetSnapshot(
                    modelID: model.id,
                    providerID: providerID,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    displayName: model.displayName,
                    upstreamModelID: model.upstreamModelID,
                    isStreamingEnabled: model.isStreamingEnabled,
                    timeout: timeout,
                    format: isDraftProvider ? draftProviderFormat : provider.format,
                    compatibilityProfile: model.compatibilityProfile,
                    thinkingMode: model.thinkingMode,
                    extraRequestParameters: model.extraRequestParameters
                )
                let chatProvider = try providerFactory.makeProvider(for: target)
                try await chatProvider.testConnection()
                setStatus(L10n.string("settings.modelConnectionSuccess"), isError: false)
            } catch let error as ChatError {
                setStatus(error.localizedDescription, isError: true)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                setStatus(message, isError: true)
            }
            testingModelID = nil
        }
    }

    // MARK: Model discovery

    func refreshModels() {
        guard let providerID = selectedProviderID,
              let provider = settings.providerRegistry.catalog?.providers.first(where: { $0.id == providerID }) else {
            return
        }
        guard provider.addressMode == .baseURL else {
            modelRefreshStatus = .unavailable
            return
        }

        invalidateModelRefresh(status: .loading)
        let generation = modelRefreshGeneration
        let keyStore = keyStore
        let modelDiscovery = effectiveModelDiscovery
        modelRefreshTask = Task { [weak self] in
            do {
                guard let apiKey = try keyStore.readAPIKey(for: providerID),
                      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProviderModelDiscoveryError.missingAPIKey
                }
                let upstreamModelIDs = try await modelDiscovery.models(for: provider, apiKey: apiKey)
                try Task.checkCancellation()
                guard let self, self.modelRefreshGeneration == generation else { return }
                let normalizedIDs = Set(
                    upstreamModelIDs
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                ).sorted()
                self.discoveredModelCandidates = normalizedIDs
                self.selectedDiscoveredModelIDs = Set(normalizedIDs)
                self.isModelSelectionPresented = !normalizedIDs.isEmpty
                self.modelRefreshStatus = .success(normalizedIDs.count)
            } catch let error as ProviderModelDiscoveryError {
                guard let self, self.modelRefreshGeneration == generation else { return }
                switch error {
                case .missingAPIKey:
                    self.modelRefreshStatus = .missingAccessKey
                case .unavailableForFullEndpoint:
                    self.modelRefreshStatus = .unavailable
                case .cancelled:
                    self.modelRefreshStatus = .cancelled
                case .invalidResponse, .unsuccessfulStatus, .networkUnavailable, .timeout:
                    self.modelRefreshStatus = .failed
                }
            } catch is CancellationError {
                guard let self, self.modelRefreshGeneration == generation else { return }
                self.modelRefreshStatus = .cancelled
            } catch {
                guard let self, self.modelRefreshGeneration == generation else { return }
                self.modelRefreshStatus = .failed
            }
            if let self, self.modelRefreshGeneration == generation {
                self.modelRefreshTask = nil
            }
        }
    }

    func cancelModelRefresh() {
        invalidateModelRefresh(status: .cancelled)
    }

    func toggleDiscoveredModel(_ upstreamModelID: String) {
        if selectedDiscoveredModelIDs.contains(upstreamModelID) {
            selectedDiscoveredModelIDs.remove(upstreamModelID)
        } else {
            selectedDiscoveredModelIDs.insert(upstreamModelID)
        }
    }

    func selectAllDiscoveredModels() {
        selectedDiscoveredModelIDs = Set(discoveredModelCandidates)
    }

    func deselectAllDiscoveredModels() {
        selectedDiscoveredModelIDs.removeAll()
    }

    func applySelectedDiscoveredModels() {
        guard let providerID = selectedProviderID else {
            cancelModelSelection()
            return
        }
        do {
            try settings.providerRegistry.replaceDiscoveredModels(
                for: providerID,
                upstreamModelIDs: selectedDiscoveredModelIDs.sorted()
            )
            syncActiveModelID()
            let addedCount = selectedDiscoveredModelIDs.count
            cancelModelSelection()
            setStatus(L10n.string("settings.modelsAdded", addedCount), isError: false)
        } catch {
            setStatus(L10n.string("settings.modelAddFailed"), isError: true)
        }
    }

    func cancelModelSelection() {
        isModelSelectionPresented = false
        discoveredModelCandidates = []
        selectedDiscoveredModelIDs.removeAll()
        if case .success = modelRefreshStatus { modelRefreshStatus = .idle }
    }

    // MARK: Validation

    func validateProviderURL(_ value: String) {
        providerFieldError = validateProviderAddress(value)
    }

    private func validateProviderAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try URLNormalizer.endpoint(
                from: trimmed,
                useFullEndpoint: draftProviderAddressMode.usesFullEndpoint,
                format: draftProviderFormat
            )
            return nil
        } catch {
            return L10n.string("settings.endpointInvalid")
        }
    }

    private static func makeProxyConfiguration(
        settings: AppSettings,
        keyStore: any APIKeyStoring
    ) -> [String: Any]? {
        guard settings.proxyEnabled else { return nil }
        let password = (try? keyStore.readAPIKey(for: ProxyCredentialSlot.providerID)) ?? ""
        return ChatNetworking.proxyConfiguration(
            type: settings.proxyType,
            host: settings.proxyHost,
            port: settings.proxyPort,
            username: settings.proxyUsername,
            password: password
        )
    }

    private var effectiveModelDiscovery: any ProviderModelDiscovering {
        guard modelDiscovery is ProviderModelDiscoveryRouter else { return modelDiscovery }
        return ProviderModelDiscoveryRouter(
            urlSession: ChatNetworking.urlSession(
                proxyConfiguration: Self.makeProxyConfiguration(settings: settings, keyStore: keyStore)
            )
        )
    }

    private func invalidateModelRefresh(status: ModelRefreshStatus = .idle) {
        modelRefreshGeneration &+= 1
        modelRefreshTask?.cancel()
        modelRefreshTask = nil
        modelRefreshStatus = status
    }

    private func decodedExtraRequestParameters() throws -> [String: ModelJSONValue]? {
        let text = draftModelExtraRequestParametersText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let value = try JSONDecoder().decode(ModelJSONValue.self, from: Data(text.utf8))
        guard case let .object(object) = value else {
            throw ChatError.invalidResponse
        }
        return object
    }

    private static func requestParametersText(_ parameters: [String: ModelJSONValue]?) -> String {
        guard let parameters, !parameters.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(parameters) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func clearStatus() {
        status = ""
        statusIsError = false
    }

    private func syncActiveModelID() {
        activeModelID = settings.providerRegistry.catalog?.selectedModelID
    }

    private func setStatus(_ value: String, isError: Bool) {
        status = value
        statusIsError = isError
        StatusToastCenter.shared.show(value, isError: isError)
    }

    // MARK: Configuration backup


    private func notifyModelRefreshStatus() {
        guard modelRefreshStatus != .idle,
              modelRefreshStatus != .loading,
              let text = modelRefreshStatusText else { return }
        StatusToastCenter.shared.show(text, isError: modelRefreshStatusIsError)
    }
}

