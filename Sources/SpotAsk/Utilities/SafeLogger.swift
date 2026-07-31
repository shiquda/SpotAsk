import OSLog

enum SafeLogger {
    private static let logger = Logger(subsystem: "com.spotask.app", category: "network")

    static func networkFailure(status: Int? = nil, url: URL? = nil) {
        var components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        components?.query = nil
        components?.fragment = nil
        let sanitizedURL = components?.url?.absoluteString ?? ""
        logger.error("Request failed. status=\(status ?? 0, privacy: .public) url=\(sanitizedURL, privacy: .public)")
    }
}
