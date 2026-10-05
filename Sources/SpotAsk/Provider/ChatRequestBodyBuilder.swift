import Foundation

enum ChatRequestBodyBuilder {
    /// Formats a single chat message with a role and Encodable content into a ModelJSONValue object.
    static func formatMessage(role: String, content: some Encodable) throws -> ModelJSONValue {
        try ModelJSONValue.object([
            "role": .string(role),
            "content": .wrapping(content)
        ])
    }

    /// Merges automatic reasoning parameters and extra request parameters into the request body dictionary.
    /// Protects against overriding structural keys and strips automatic reasoning when reasoningControlKeys are present.
    static func mergeParameters(
        into body: inout [String: ModelJSONValue],
        compatibilityProfile: RequestCompatibilityProfile,
        thinkingMode: ModelThinkingMode,
        extraParameters: [String: ModelJSONValue]?
    ) throws {
        let automatic = compatibilityProfile.automaticReasoningParameters(for: thinkingMode)
        let extras = extraParameters ?? [:]
        if extras.keys.contains(where: { RequestCompatibilityProfile.reasoningControlKeys.contains($0) }) {
            for key in automatic.keys { body.removeValue(forKey: key) }
        } else {
            for (key, value) in automatic {
                body[key] = value
            }
        }
        if extras.keys.contains(where: { RequestCompatibilityProfile.protectedStructuralKeys.contains($0) }) {
            throw ChatError.invalidConfiguration
        }
        body.mergeModelJSON(extras)
    }

    /// Merges reasoning and extra parameters into the body dictionary, then encodes the entire dictionary to JSON Data.
    static func buildJSONData(
        body: inout [String: ModelJSONValue],
        compatibilityProfile: RequestCompatibilityProfile,
        thinkingMode: ModelThinkingMode,
        extraParameters: [String: ModelJSONValue]?
    ) throws -> Data {
        try mergeParameters(
            into: &body,
            compatibilityProfile: compatibilityProfile,
            thinkingMode: thinkingMode,
            extraParameters: extraParameters
        )
        return try JSONEncoder().encode(body)
    }
}
