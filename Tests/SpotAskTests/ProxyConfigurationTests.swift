import XCTest
@testable import SpotAsk

final class ProxyConfigurationTests: XCTestCase {
    func testHTTPProxyConfigurationCoversBothSchemesAndCredentials() throws {
        let configuration = try XCTUnwrap(
            ChatNetworking.proxyConfiguration(
                type: .http,
                host: " proxy.example.com ",
                port: 8080,
                username: "user",
                password: "secret"
            )
        )

        XCTAssertEqual(configuration["HTTPEnable"] as? Int, 1)
        XCTAssertEqual(configuration["HTTPProxy"] as? String, "proxy.example.com")
        XCTAssertEqual(configuration["HTTPPort"] as? Int, 8080)
        XCTAssertEqual(configuration["HTTPSEnable"] as? Int, 1)
        XCTAssertEqual(configuration["HTTPSProxy"] as? String, "proxy.example.com")
        XCTAssertEqual(configuration["HTTPSPort"] as? Int, 8080)
        XCTAssertEqual(configuration["HTTPProxyUsername"] as? String, "user")
        XCTAssertEqual(configuration["HTTPProxyPassword"] as? String, "secret")
        XCTAssertEqual(configuration["HTTPSProxyUsername"] as? String, "user")
        XCTAssertEqual(configuration["HTTPSProxyPassword"] as? String, "secret")
    }

    func testSOCKS5ProxyConfigurationUsesSocksKeysAndCredentials() throws {
        let configuration = try XCTUnwrap(
            ChatNetworking.proxyConfiguration(
                type: .socks5,
                host: "127.0.0.1",
                port: 1080,
                username: "socks-user",
                password: "socks-secret"
            )
        )

        XCTAssertEqual(configuration["SOCKSEnable"] as? Int, 1)
        XCTAssertEqual(configuration["SOCKSProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(configuration["SOCKSPort"] as? Int, 1080)
        XCTAssertEqual(configuration["SOCKSProxyUsername"] as? String, "socks-user")
        XCTAssertEqual(configuration["SOCKSProxyPassword"] as? String, "socks-secret")
    }

    func testEmptyHostOrInvalidPortDisablesProxy() {
        XCTAssertNil(
            ChatNetworking.proxyConfiguration(
                type: .http,
                host: "   ",
                port: 8080,
                username: "",
                password: ""
            )
        )
        XCTAssertNil(
            ChatNetworking.proxyConfiguration(
                type: .socks5,
                host: "127.0.0.1",
                port: 0,
                username: "",
                password: ""
            )
        )
    }

    func testCredentialsAreOptional() throws {
        let configuration = try XCTUnwrap(
            ChatNetworking.proxyConfiguration(
                type: .http,
                host: "proxy.example.com",
                port: 8080,
                username: "",
                password: ""
            )
        )

        XCTAssertNil(configuration["HTTPProxyUsername"])
        XCTAssertNil(configuration["HTTPProxyPassword"])
    }

    @MainActor
    func testProxyConfigurationFromSettingsAndKeyStore() throws {
        let defaults = UserDefaults(suiteName: "ProxyConfigurationTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let settings = AppSettings(defaults: defaults)
        let keyStore = TestProxyKeyStore()

        settings.proxyEnabled = false
        XCTAssertNil(ChatNetworking.proxyConfiguration(settings: settings, keyStore: keyStore))

        settings.proxyEnabled = true
        settings.proxyType = .http
        settings.proxyHost = "proxy.example.com"
        settings.proxyPort = 8080
        settings.proxyUsername = "user"
        try keyStore.saveAPIKey("secret", for: ProxyCredentialSlot.providerID)

        let config = try XCTUnwrap(ChatNetworking.proxyConfiguration(settings: settings, keyStore: keyStore))
        XCTAssertEqual(config["HTTPProxy"] as? String, "proxy.example.com")
        XCTAssertEqual(config["HTTPProxyPassword"] as? String, "secret")
    }
}

private final class TestProxyKeyStore: APIKeyStoring, @unchecked Sendable {
    private var keys: [UUID: String] = [:]

    func readAPIKey(for providerID: UUID) throws -> String? {
        keys[providerID]
    }

    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        keys[providerID] = key
    }

    func deleteAPIKey(for providerID: UUID) throws {
        keys.removeValue(forKey: providerID)
    }

    func deleteAllAPIKeys() throws {
        keys.removeAll()
    }
}
