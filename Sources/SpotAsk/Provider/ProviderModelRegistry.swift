import Foundation
import Observation

enum ProviderModelRegistryError: Error, Equatable, Sendable {
    case catalogUnavailable
    case invalidSchemaVersion(Int)
    case duplicateProviderID(UUID)
    case duplicateModelID(UUID)
    case invalidProviderName
    case invalidProviderAddress
    case invalidProviderTimeout
    case invalidModelDisplayName
    case invalidUpstreamModelID
    case missingProvider(UUID)
    case missingModel(UUID)
    case modelProviderCannotChange(UUID)
    case invalidSelectedModel(UUID)
    case wouldLeaveNoSelectableModel
    case encodingFailed
}

enum ProviderModelCatalogLoadError: Error, Equatable, Sendable {
    case decodingFailed
    case invalidCatalog(ProviderModelRegistryError)
}

struct LegacyProviderConfiguration: Sendable {
    let baseURL: String
    let useFullEndpoint: Bool
    let model: String
    let streaming: Bool
    let timeout: TimeInterval
}

@MainActor
@Observable
final class ProviderModelRegistry {
    static let defaultsKey = "providerModelCatalog"
    static let pendingLegacyAPIKeyMigrationProviderIDDefaultsKey = "providerModelCatalog.pendingLegacyAPIKeyMigrationProviderID"

    private let defaults: UserDefaults
    private(set) var catalog: ProviderModelCatalog?
    private(set) var loadError: ProviderModelCatalogLoadError?
    private(set) var pendingLegacyAPIKeyMigrationProviderID: UUID?
    private var onCatalogChange: (() -> Void)?

    init(defaults: UserDefaults, legacy: LegacyProviderConfiguration) {
        self.defaults = defaults
        pendingLegacyAPIKeyMigrationProviderID = Self.pendingLegacyAPIKeyMigrationProviderID(from: defaults)
        if let data = defaults.data(forKey: Self.defaultsKey) {
            do {
                let decoded = try JSONDecoder().decode(ProviderModelCatalog.self, from: data)
                let normalized = try Self.normalized(catalog: decoded)
                if normalized != decoded { try Self.persist(normalized, to: defaults) }
                catalog = normalized
            } catch let error as ProviderModelRegistryError {
                catalog = nil
                loadError = .invalidCatalog(error)
            } catch {
                catalog = nil
                loadError = .decodingFailed
            }
        } else {
            let provider = ProviderConfiguration(
                name: "OpenAI Compatible",
                address: legacy.baseURL,
                addressMode: legacy.useFullEndpoint ? .fullEndpoint : .baseURL,
                timeout: legacy.timeout
            )
            let model = ModelConfiguration(
                displayName: legacy.model,
                upstreamModelID: legacy.model,
                providerID: provider.id,
                isStreamingEnabled: legacy.streaming
            )
            let migrated = ProviderModelCatalog(providers: [provider], models: [model], selectedModelID: model.id)
            do {
                let normalized = try Self.normalized(catalog: migrated)
                try Self.persist(normalized, to: defaults)
                catalog = normalized
                pendingLegacyAPIKeyMigrationProviderID = provider.id
                defaults.set(provider.id.uuidString, forKey: Self.pendingLegacyAPIKeyMigrationProviderIDDefaultsKey)
            } catch {
                catalog = nil
                loadError = .invalidCatalog((error as? ProviderModelRegistryError) ?? .encodingFailed)
            }
        }
    }

    @discardableResult
    func saveProvider(_ provider: ProviderConfiguration) throws -> ProviderConfiguration {
        let normalized = try Self.normalized(provider: provider)
        try update { catalog in
            if let index = catalog.providers.firstIndex(where: { $0.id == normalized.id }) {
                catalog.providers[index] = normalized
            } else {
                catalog.providers.append(normalized)
            }
        }
        return normalized
    }

    func setCatalogChangeHandler(_ handler: @escaping () -> Void) {
        onCatalogChange = handler
    }

    @discardableResult
    func saveModel(_ model: ModelConfiguration) throws -> ModelConfiguration {
        let normalized = try Self.normalized(model: model)
        try update { catalog in
            guard catalog.providers.contains(where: { $0.id == normalized.providerID }) else {
                throw ProviderModelRegistryError.missingProvider(normalized.providerID)
            }
            if let index = catalog.models.firstIndex(where: { $0.id == normalized.id }) {
                guard catalog.models[index].providerID == normalized.providerID else {
                    throw ProviderModelRegistryError.modelProviderCannotChange(normalized.id)
                }
                catalog.models[index] = normalized
            } else {
                catalog.models.append(normalized)
            }
        }
        return normalized
    }

    func selectModel(id: UUID) throws {
        try update { catalog in
            guard catalog.models.contains(where: { $0.id == id }) else {
                throw ProviderModelRegistryError.missingModel(id)
            }
            catalog.selectedModelID = id
        }
    }

    func replaceCatalog(with catalog: ProviderModelCatalog) throws {
        let normalized = try Self.normalized(catalog: catalog)
        try Self.persist(normalized, to: defaults)
        self.catalog = normalized
        loadError = nil
        onCatalogChange?()
    }

    func replaceDiscoveredModels(for providerID: UUID, upstreamModelIDs: [String]) throws {
        let normalizedIDs = Set(
            upstreamModelIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).sorted()

        try update { catalog in
            guard catalog.providers.contains(where: { $0.id == providerID }) else {
                throw ProviderModelRegistryError.missingProvider(providerID)
            }

            let manualModelIDs = Set(
                catalog.models
                    .filter { $0.providerID == providerID && $0.source == .manual }
                    .map(\.upstreamModelID)
            )
            let existingDiscoveredModels = Dictionary(
                grouping: catalog.models.filter { $0.providerID == providerID && $0.source == .discovered },
                by: \.upstreamModelID
            ).mapValues { $0[0] }

            let discoveredModels = normalizedIDs.compactMap { upstreamModelID -> ModelConfiguration? in
                guard !manualModelIDs.contains(upstreamModelID) else { return nil }
                if let existing = existingDiscoveredModels[upstreamModelID] {
                    return existing
                }
                return ModelConfiguration(
                    displayName: upstreamModelID,
                    upstreamModelID: upstreamModelID,
                    providerID: providerID,
                    isStreamingEnabled: true,
                    source: .discovered
                )
            }

            catalog.models.removeAll { $0.providerID == providerID && $0.source == .discovered }
            catalog.models.append(contentsOf: discoveredModels)

            guard !catalog.models.isEmpty else {
                throw ProviderModelRegistryError.wouldLeaveNoSelectableModel
            }
            if !catalog.models.contains(where: { $0.id == catalog.selectedModelID }) {
                catalog.selectedModelID = catalog.models[0].id
            }
        }
    }

    func deleteModel(id: UUID) throws {
        try update { catalog in
            guard let index = catalog.models.firstIndex(where: { $0.id == id }) else {
                throw ProviderModelRegistryError.missingModel(id)
            }
            guard catalog.models.count > 1 else {
                throw ProviderModelRegistryError.wouldLeaveNoSelectableModel
            }
            catalog.models.remove(at: index)
            if catalog.selectedModelID == id {
                catalog.selectedModelID = catalog.models[0].id
            }
        }
    }

    func deleteProvider(id: UUID, keyStore: any APIKeyStoring) throws {
        guard var updated = catalog else { throw ProviderModelRegistryError.catalogUnavailable }
        guard updated.providers.contains(where: { $0.id == id }) else {
            throw ProviderModelRegistryError.missingProvider(id)
        }
        let modelsToDelete = updated.models.filter { $0.providerID == id }
        guard updated.models.count > modelsToDelete.count else {
            throw ProviderModelRegistryError.wouldLeaveNoSelectableModel
        }
        updated.providers.removeAll { $0.id == id }
        updated.models.removeAll { $0.providerID == id }
        if !updated.models.contains(where: { $0.id == updated.selectedModelID }) {
            updated.selectedModelID = updated.models[0].id
        }
        updated = try Self.normalized(catalog: updated)
        try keyStore.deleteAPIKey(for: id)
        try Self.persist(updated, to: defaults)
        catalog = updated
        onCatalogChange?()
    }

    func completeLegacyAPIKeyMigration(to providerID: UUID) {
        guard pendingLegacyAPIKeyMigrationProviderID == providerID else { return }
        pendingLegacyAPIKeyMigrationProviderID = nil
        defaults.removeObject(forKey: Self.pendingLegacyAPIKeyMigrationProviderIDDefaultsKey)
    }

    private func update(_ mutation: (inout ProviderModelCatalog) throws -> Void) throws {
        guard var updated = catalog else { throw ProviderModelRegistryError.catalogUnavailable }
        try mutation(&updated)
        updated = try Self.normalized(catalog: updated)
        try Self.persist(updated, to: defaults)
        catalog = updated
        onCatalogChange?()
    }

    private static func pendingLegacyAPIKeyMigrationProviderID(from defaults: UserDefaults) -> UUID? {
        guard let rawValue = defaults.string(forKey: pendingLegacyAPIKeyMigrationProviderIDDefaultsKey) else {
            return nil
        }
        guard let providerID = UUID(uuidString: rawValue) else {
            defaults.removeObject(forKey: pendingLegacyAPIKeyMigrationProviderIDDefaultsKey)
            return nil
        }
        return providerID
    }

    private static func persist(_ catalog: ProviderModelCatalog, to defaults: UserDefaults) throws {
        do {
            defaults.set(try JSONEncoder().encode(catalog), forKey: defaultsKey)
        } catch {
            throw ProviderModelRegistryError.encodingFailed
        }
    }

    private static func normalized(catalog: ProviderModelCatalog) throws -> ProviderModelCatalog {
        var result = catalog
        guard result.schemaVersion == ProviderModelCatalog.currentSchemaVersion else {
            throw ProviderModelRegistryError.invalidSchemaVersion(result.schemaVersion)
        }
        guard Set(result.providers.map(\.id)).count == result.providers.count else {
            throw ProviderModelRegistryError.duplicateProviderID(result.providers.first!.id)
        }
        guard Set(result.models.map(\.id)).count == result.models.count else {
            throw ProviderModelRegistryError.duplicateModelID(result.models.first!.id)
        }
        result.providers = try result.providers.map(normalized(provider:))
        result.models = try result.models.map(normalized(model:))
        for index in result.models.indices {
            guard let provider = result.providers.first(where: { $0.id == result.models[index].providerID }),
                  provider.format == .anthropic,
                  result.models[index].compatibilityProfile == .genericOpenAI else {
                continue
            }
            result.models[index].compatibilityProfile = .anthropic
        }
        for model in result.models {
            guard result.providers.contains(where: { $0.id == model.providerID }) else {
                throw ProviderModelRegistryError.missingProvider(model.providerID)
            }
        }
        guard !result.models.isEmpty else { throw ProviderModelRegistryError.wouldLeaveNoSelectableModel }
        guard result.models.contains(where: { $0.id == result.selectedModelID }) else {
            throw ProviderModelRegistryError.invalidSelectedModel(result.selectedModelID)
        }
        return result
    }

    private static func normalized(provider: ProviderConfiguration) throws -> ProviderConfiguration {
        var result = provider
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.address = result.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty else { throw ProviderModelRegistryError.invalidProviderName }
        guard !result.address.isEmpty else { throw ProviderModelRegistryError.invalidProviderAddress }
        guard (try? URLNormalizer.endpoint(
            from: result.address,
            useFullEndpoint: result.addressMode.usesFullEndpoint,
            format: result.format
        )) != nil else {
            throw ProviderModelRegistryError.invalidProviderAddress
        }
        guard result.timeout.isFinite, result.timeout > 0 else { throw ProviderModelRegistryError.invalidProviderTimeout }
        return result
    }

    private static func normalized(model: ModelConfiguration) throws -> ModelConfiguration {
        var result = model
        result.displayName = result.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.upstreamModelID = result.upstreamModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.displayName.isEmpty else { throw ProviderModelRegistryError.invalidModelDisplayName }
        guard !result.upstreamModelID.isEmpty else { throw ProviderModelRegistryError.invalidUpstreamModelID }
        return result
    }
}
