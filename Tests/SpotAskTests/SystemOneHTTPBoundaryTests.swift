import Darwin
import Foundation
import Testing
@testable import SpotAsk

/// A real loopback HTTP origin, independent of URLProtocol/session mocks.
private final class DecisionHTTPOrigin: @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var headers: String = ""
        var body: String = #"{"answers":{"route":{"choice":"in_app","confidence":0.95}}}"#
        var delay: TimeInterval = 0
    }

    private let listener: Int32
    private let lock = NSLock()
    private var received: [Data] = []
    private let worker = DispatchGroup()
    let url: URL

    init(reply: @escaping @Sendable (String) -> Reply) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        listener = fd
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw POSIXError(.EIO)
        }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))/v1/systemone")!
        worker.enter()
        DispatchQueue.global().async { [self] in
            defer { worker.leave() }
            while true {
                let connection = accept(listener, nil, nil)
                guard connection >= 0 else { break }
                var noSignal: Int32 = 1
                _ = setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                _ = setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var request = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = recv(connection, &buffer, buffer.count, 0)
                    guard count > 0 else { break }
                    request.append(contentsOf: buffer.prefix(count))
                    if let end = request.range(of: Data("\r\n\r\n".utf8)) {
                        let header = String(decoding: request[..<end.lowerBound], as: UTF8.self)
                        let length = header.components(separatedBy: "\r\n")
                            .first { $0.lowercased().hasPrefix("content-length:") }
                            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                        if request.count >= end.upperBound + length { break }
                    }
                }
                lock.withLock { received.append(request) }
                let result = reply(String(decoding: request, as: UTF8.self))
                if result.delay > 0 { Thread.sleep(forTimeInterval: result.delay) }
                let body = Data(result.body.utf8)
                let response = Data("HTTP/1.1 \(result.status) Response\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\(result.headers)\r\n".utf8) + body
                response.withUnsafeBytes { bytes in
                    var sent = 0
                    while sent < bytes.count {
                        let count = send(connection, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                        if count <= 0 { break }
                        sent += count
                    }
                }
                close(connection)
            }
        }
    }

    var requests: [Data] { lock.withLock { received } }

    func stop() {
        shutdown(listener, SHUT_RDWR)
        close(listener)
        worker.wait()
    }
}

struct SystemOneHTTPBoundaryTests {
    private func evaluate(
        _ origin: DecisionHTTPOrigin,
        timeout: TimeInterval = 1,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> SystemOneChoiceAnswer {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        return try await SystemOneClient(
            transport: URLSessionSystemOneTransport(session: session),
            sleep: sleep
        ).evaluate(question: "synthetic boundary question", model: "synthetic-model",
                   criteria: ["in_app": "Synthetic in-app", "external": "Synthetic external"],
                   url: origin.url, apiKey: "synthetic-auth-marker", timeout: timeout)
    }

    @Test("307/308 never send state or credentials to another origin", arguments: [307, 308])
    func crossOriginRedirect(status: Int) async throws {
        let sink = try DecisionHTTPOrigin { _ in .init() }
        defer { sink.stop() }
        let destination = sink.url.absoluteString
        let source = try DecisionHTTPOrigin { _ in .init(status: status, headers: "Location: \(destination)\r\n") }
        defer { source.stop() }
        await #expect(throws: SystemOneClientError.unsafeRedirect) { try await evaluate(source) }
        #expect(source.requests.count == 1)
        #expect(sink.requests.isEmpty)
    }

    @Test("Same-origin redirect remains usable and preserves the POST payload")
    func sameOriginRedirect() async throws {
        let source = try DecisionHTTPOrigin { request in
            request.hasPrefix("POST /v1/systemone ")
                ? .init(status: 307, headers: "Location: /answer\r\n") : .init()
        }
        defer { source.stop() }
        let answer = try await evaluate(source)
        #expect(answer == SystemOneChoiceAnswer(choice: "in_app", confidence: 0.95))
        #expect(source.requests.count == 2)
        let redirected = String(decoding: source.requests[1], as: UTF8.self)
        #expect(redirected.hasPrefix("POST /answer "))
        #expect(redirected.contains("synthetic boundary question"))
    }

    @Test("Real HTTP status failures stay typed", arguments: [401, 403, 404, 429, 500])
    func statuses(status: Int) async throws {
        let source = try DecisionHTTPOrigin { _ in .init(status: status, body: "synthetic refusal") }
        defer { source.stop() }
        await #expect(throws: SystemOneClientError.httpStatus(status)) { try await evaluate(source) }
        #expect(source.requests.count == 1)
    }

    @Test("Malformed successful response is rejected")
    func malformed() async throws {
        let source = try DecisionHTTPOrigin { _ in .init(body: "not JSON") }
        defer { source.stop() }
        await #expect(throws: SystemOneClientError.invalidResponse) { try await evaluate(source) }
    }

    @Test("Late HTTP answer cannot replace the timeout")
    func lateAnswer() async throws {
        let received = AsyncStream<Void>.makeStream()
        let releaseReply = DispatchSemaphore(value: 0)
        let source = try DecisionHTTPOrigin { _ in
            received.continuation.yield(())
            received.continuation.finish()
            releaseReply.wait()
            return .init()
        }
        defer {
            releaseReply.signal()
            source.stop()
        }
        do {
            // Give the socket time to connect independently of the short decision
            // clock. URLRequest also uses timeout, so gating only sleep can still
            // time out before receipt on a busy CI runner.
            _ = try await evaluate(source, timeout: 5, sleep: { _ in
                for await _ in received.stream { break }
                try await Task.sleep(for: .milliseconds(30))
            })
            Issue.record("Late response replaced the deadline")
        } catch {
            #expect(SystemOneClient.isTimeout(error))
        }
        #expect(source.requests.count == 1)
    }

    @Test("Official Decisions host round-trips a route without a credential")
    func officialFormatLoopback() async throws {
        let question = "Where should this local edit go?"
        let origin = try DecisionHTTPOrigin { request in
            Self.officialDecisionReply(request, question: question)
                ?? .init(status: 400, body: #"{"error":"not the official decisions format"}"#)
        }
        defer { origin.stop() }
        var components = URLComponents(url: origin.url, resolvingAgainstBaseURL: false)
        components?.path = ""
        let base = try #require(components?.string)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let result = await DecisionRoutingPreview.run(
            question: question,
            settings: DecisionRoutingSettings(
                isEnabled: true,
                provider: .openAIDecisions,
                serviceURL: base,
                model: "gpt-6-luna",
                confirmationMode: .always,
                confidenceThreshold: DecisionRoutingPolicy.defaultThreshold,
                timeoutSeconds: 5,
                timeoutAction: .manualSelection,
                inAppDescription: ""
            ),
            candidates: [
                DecisionRouteCandidate(
                    id: DecisionRouteID.inApp,
                    title: "In-App",
                    symbolName: "bubble.left",
                    brandIconSlug: nil,
                    applicableDescription: "Short answers",
                    forceConfirm: false,
                    externalActionID: nil,
                    externalActionKind: nil
                ),
                DecisionRouteCandidate(
                    id: "ext_agent",
                    title: "Local Agent",
                    symbolName: "terminal",
                    brandIconSlug: nil,
                    applicableDescription: "Local edits",
                    forceConfirm: false,
                    externalActionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    externalActionKind: .terminal(commandTemplate: "omp {query}")
                ),
            ],
            apiKey: nil,
            transport: URLSessionSystemOneTransport(session: session)
        )

        guard case let .recommendation(candidate, confidence, release) = result else {
            Issue.record("expected a recommendation, got \(result)")
            return
        }
        #expect(candidate.id == "ext_agent")
        #expect(confidence == 0.93)
        #expect(release == .confirm)

        let raw = String(decoding: try #require(origin.requests.first), as: UTF8.self)
        let body = try #require(raw.components(separatedBy: "\r\n\r\n").dropFirst().first)
        let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(raw.hasPrefix("POST /v1/decisions "))
        #expect(!raw.lowercased().contains("authorization:"))
        #expect(object["model"] as? String == "gpt-6-luna")
        #expect(object["input"] as? String == question)
        #expect(object["state"] == nil)
        let questions = try #require(object["questions"] as? [[String: Any]])
        #expect(questions.first?["type"] as? String == "choice")
        #expect(questions.first?["name"] as? String == "route")
    }

    /// Accepts only the official Decisions body: `input`, a `questions` array, no `state`, no credential.
    private static func officialDecisionReply(_ request: String, question: String) -> DecisionHTTPOrigin.Reply? {
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else { return nil }
        let headers = parts[0].components(separatedBy: "\r\n")
        guard headers.first?.hasPrefix("POST /v1/decisions ") == true else { return nil }
        guard !headers.contains(where: { $0.lowercased().hasPrefix("authorization:") }) else { return nil }
        guard headers.contains(where: {
            $0.lowercased().hasPrefix("content-type:") && $0.lowercased().contains("application/json")
        }) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any],
              object["state"] == nil,
              object["model"] as? String == "gpt-6-luna",
              object["input"] as? String == question,
              let questions = object["questions"] as? [[String: Any]],
              questions.count == 1,
              questions[0]["type"] as? String == "choice",
              questions[0]["name"] as? String == "route",
              let choices = questions[0]["choices"] as? [[String: Any]],
              Set(choices.compactMap { $0["value"] as? String }) == ["in_app", "ext_agent"] else {
            return nil
        }
        return .init(body: """
        {"id":"dec_local_e2e","object":"decision","model":"gpt-6-luna","answers":[{"type":"choice","name":"route","choice":"ext_agent","probabilities":[{"value":"in_app","probability":0.07},{"value":"ext_agent","probability":0.93}],"confidence":0.93}]}
        """)
    }
}
