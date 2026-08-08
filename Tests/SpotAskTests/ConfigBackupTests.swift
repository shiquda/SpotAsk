import XCTest
@testable import SpotAsk

@MainActor
final class ConfigBackupTests: XCTestCase {
    func testConfigurationBackupRoundTrip() throws {
        let sourceSuite = "ConfigBackupSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        source.defaultExpandReasoning = true
        source.chatMessageStyle = .im
        source.systemPrompt = "custom system prompt"
        source.contextLimit = 40
        source.proxyEnabled = true
        source.proxyType = .socks5
        source.proxyHost = "proxy.example.com"
        source.proxyPort = 7890
        source.proxyUsername = "backup-user"

        let provider = ProviderConfiguration(
            name: "Test Service",
            address: "https://example.com/v1",
            addressMode: .baseURL,
            timeout: 30
        )
        let model = ModelConfiguration(
            displayName: "Test Model",
            upstreamModelID: "test-model",
            providerID: provider.id,
            isStreamingEnabled: false
        )
        let catalog = ProviderModelCatalog(
            providers: [provider],
            models: [model],
            selectedModelID: model.id
        )
        try source.providerRegistry.replaceCatalog(with: catalog)
        XCTAssertTrue(source.saveCustomPromptPreset(PromptPreset(title: "My Preset", instruction: "Do it")))

        let backup = try source.makeConfigurationBackup()
        XCTAssertNil(backup.apiKeys)
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)

        let destination = AppSettings(defaults: destinationDefaults)
        try destination.applyConfigurationBackup(decoded)

        XCTAssertTrue(destination.defaultExpandReasoning)
        XCTAssertEqual(destination.chatMessageStyle, .im)
        XCTAssertEqual(destination.systemPrompt, "custom system prompt")
        XCTAssertEqual(destination.contextLimit, 40)
        XCTAssertTrue(destination.proxyEnabled)
        XCTAssertEqual(destination.proxyType, .socks5)
        XCTAssertEqual(destination.proxyHost, "proxy.example.com")
        XCTAssertEqual(destination.proxyPort, 7890)
        XCTAssertEqual(destination.proxyUsername, "backup-user")
        XCTAssertEqual(destination.providerRegistry.catalog, catalog)
        XCTAssertEqual(destination.promptPresets.first(where: { $0.title == "My Preset" })?.instruction, "Do it")
    }

    func testBackupOmitsStoredAccessKeys() throws {
        let suite = "ConfigBackupKeys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: credentialsURL) }

        let settings = AppSettings(defaults: defaults)
        let provider = settings.providerRegistry.catalog?.providers.first
        let providerID = try XCTUnwrap(provider?.id)
        let keyStore = LocalAPIKeyStore(fileURL: credentialsURL)
        try keyStore.saveAPIKey("super-secret-key", for: providerID)

        let json = String(data: try JSONEncoder().encode(settings.makeConfigurationBackup()), encoding: .utf8)

        XCTAssertFalse(try XCTUnwrap(json).contains("super-secret-key"))
        XCTAssertFalse(try XCTUnwrap(json).contains("\"apiKeys\""))
    }

    func testBackupCanIncludeAndRestoreAccessKeysWhenRequested() throws {
        let sourceSuite = "ConfigBackupIncludeKeysSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupIncludeKeysDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }
        let sourceCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupIncludeSource-\(UUID().uuidString).json")
        let destinationCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotAskConfigBackupIncludeDestination-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: sourceCredentialsURL)
            try? FileManager.default.removeItem(at: destinationCredentialsURL)
        }

        let source = AppSettings(defaults: sourceDefaults)
        let provider = try XCTUnwrap(source.providerRegistry.catalog?.providers.first)
        let sourceKeyStore = LocalAPIKeyStore(fileURL: sourceCredentialsURL)
        try sourceKeyStore.saveAPIKey("exported-secret", for: provider.id)

        let backup = try source.makeConfigurationBackup(includeAccessKeys: true, keyStore: sourceKeyStore)
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)

        XCTAssertEqual(decoded.apiKeys?[provider.id.uuidString], "exported-secret")

        let destination = AppSettings(defaults: destinationDefaults)
        let destinationKeyStore = LocalAPIKeyStore(fileURL: destinationCredentialsURL)
        try destination.applyConfigurationBackup(decoded, keyStore: destinationKeyStore)
        XCTAssertEqual(try destinationKeyStore.readAPIKey(for: provider.id), "exported-secret")
    }

    func testApplyingUnsupportedBackupVersionFails() throws {
        let sourceSuite = "ConfigBackupVersionSource.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ConfigBackupVersionDestination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        let backup = try source.makeConfigurationBackup()
        let futureBackup = SpotAskConfigBackup(
            schemaVersion: 99,
            general: backup.general,
            promptPresetCatalog: backup.promptPresetCatalog,
            shortcutConfiguration: backup.shortcutConfiguration,
            providerCatalog: backup.providerCatalog
        )

        XCTAssertThrowsError(try AppSettings(defaults: destinationDefaults).applyConfigurationBackup(futureBackup)) { error in
            XCTAssertEqual(error as? SpotAskConfigBackupError, .unsupportedSchemaVersion(99))
        }
    }
}
