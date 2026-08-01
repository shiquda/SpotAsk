import Foundation
import XCTest
@testable import SpotAsk

final class ProviderModelDiscoveryTests: XCTestCase {
    func testRequestsModelsWithProviderCredentialsAndTimeout() async throws {
        let transport = RecordingDiscoveryTransport(
            result: .success((Data("{\"data\":[{\"id\":\" z \"},{\"id\":\"a\"},{\"id\":\"a\"},{\"id\":\" \"}]}".utf8), response(status: 200)))
        )
        let provider = ProviderConfiguration(
            name: "Service",
            address: "https://example.com/v1/",
            addressMode: .baseURL,
            timeout: 42
        )

        let models = try await OpenAICompatibleModelDiscovery(transport: transport).models(for: provider, apiKey: " token ")

        XCTAssertEqual(models, ["a", "z"])
        let request = try XCTUnwrap(transport.request)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 42)
    }

    func testRejectsInvalidPayloadAndUnsuccessfulStatus() async throws {
        let provider = ProviderConfiguration(name: "Service", address: "https://example.com/v1", addressMode: .baseURL, timeout: 30)
        let invalidPayload = OpenAICompatibleModelDiscovery(
            transport: RecordingDiscoveryTransport(result: .success((Data("{}".utf8), response(status: 200))))
        )
        let unsuccessful = OpenAICompatibleModelDiscovery(
            transport: RecordingDiscoveryTransport(result: .success((Data(), response(status: 503))))
        )

        do {
            _ = try await invalidPayload.models(for: provider, apiKey: "key")
            XCTFail("Expected invalid payload to fail")
        } catch {
            XCTAssertEqual(error as? ProviderModelDiscoveryError, .invalidResponse)
        }
        do {
            _ = try await unsuccessful.models(for: provider, apiKey: "key")
            XCTFail("Expected status failure")
        } catch {
            XCTAssertEqual(error as? ProviderModelDiscoveryError, .unsuccessfulStatus(503))
        }
    }

    func testMapsNetworkErrorsAndCancellation() async throws {
        let provider = ProviderConfiguration(name: "Service", address: "https://example.com/v1", addressMode: .baseURL, timeout: 30)
        let network = OpenAICompatibleModelDiscovery(
            transport: RecordingDiscoveryTransport(result: .failure(URLError(.notConnectedToInternet)))
        )
        let cancelled = OpenAICompatibleModelDiscovery(
            transport: RecordingDiscoveryTransport(result: .failure(CancellationError()))
        )

        do {
            _ = try await network.models(for: provider, apiKey: "key")
            XCTFail("Expected network failure")
        } catch {
            XCTAssertEqual(error as? ProviderModelDiscoveryError, .networkUnavailable)
        }
        do {
            _ = try await cancelled.models(for: provider, apiKey: "key")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ProviderModelDiscoveryError, .cancelled)
        }
    }

    func testFullEndpointAndMissingKeyDoNotSendRequest() async throws {
        let transport = RecordingDiscoveryTransport(result: .success((Data(), response(status: 200))) )
        let discovery = OpenAICompatibleModelDiscovery(transport: transport)
        let fullEndpoint = ProviderConfiguration(
            name: "Service",
            address: "https://example.com/v1/chat/completions",
            addressMode: .fullEndpoint,
            timeout: 30
        )
        let baseURL = ProviderConfiguration(name: "Service", address: "https://example.com/v1", addressMode: .baseURL, timeout: 30)

        do {
            _ = try await discovery.models(for: fullEndpoint, apiKey: "key")
            XCTFail("Expected full endpoint mode to be unavailable")
        } catch {
            XCTAssertEqual(error as? ProviderModelDiscoveryError, .unavailableForFullEndpoint)
        }
        do {
            _ = try await discovery.models(for: baseURL, apiKey: "   ")
            XCTFail("Expected missing access key")
        } catch {
            XCTAssertEqual(error as? ProviderModelDiscoveryError, .missingAPIKey)
        }
        XCTAssertEqual(transport.callCount, 0)
    }

    private func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private final class RecordingDiscoveryTransport: ProviderModelDiscoveryTransport, @unchecked Sendable {
    let result: Result<(Data, URLResponse), Error>
    private(set) var request: URLRequest?
    private(set) var callCount = 0

    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        callCount += 1
        return try result.get()
    }
}
