import Foundation
@testable import SpotAsk

extension ProviderTargetSnapshot {
    static func testValue(
        modelID: UUID = UUID(),
        providerID: UUID = UUID(),
        displayName: String = "GPT-5 mini",
        upstreamModelID: String = "gpt-5-mini",
        isStreamingEnabled: Bool = true
    ) -> ProviderTargetSnapshot {
        ProviderTargetSnapshot(
            modelID: modelID,
            providerID: providerID,
            endpoint: URL(string: "http://localhost/chat/completions")!,
            apiKey: "test-key",
            displayName: displayName,
            upstreamModelID: upstreamModelID,
            isStreamingEnabled: isStreamingEnabled,
            timeout: 60
        )
    }
}
