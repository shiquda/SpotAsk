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
            // Start the short deadline only after real HTTP receipt; CI scheduling
            // must not turn this late-answer regression into a pre-connect timeout.
            _ = try await evaluate(source, timeout: 0.03, sleep: { duration in
                for await _ in received.stream { break }
                try await Task.sleep(for: duration)
            })
            Issue.record("Late response replaced the deadline")
        } catch {
            #expect(SystemOneClient.isTimeout(error))
        }
        #expect(source.requests.count == 1)
    }
}
