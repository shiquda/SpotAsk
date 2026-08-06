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
}
