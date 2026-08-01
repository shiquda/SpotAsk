import Foundation
@testable import SpotAsk

extension ProviderTargetSnapshot {
    static func testValue(
        modelID: UUID = UUID(),
        providerID: UUID = UUID(),
        upstreamModelID: String = "gpt-5-mini",
        isStreamingEnabled: Bool = true
    ) -> ProviderTargetSnapshot {
        ProviderTargetSnapshot(
            modelID: modelID,
            providerID: providerID,
            endpoint: URL(string: "http://localhost/chat/completions")!,
            apiKey: "test-key",
            upstreamModelID: upstreamModelID,
            isStreamingEnabled: isStreamingEnabled,
            timeout: 60
        )
    }
}
