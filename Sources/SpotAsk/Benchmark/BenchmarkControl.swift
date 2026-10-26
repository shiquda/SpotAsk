#if SPOTASK_BENCHMARK
import AppKit
import Foundation

/// Control channel for the benchmark build only.
///
/// Compiled behind `-D SPOTASK_BENCHMARK`, it never ships in the release
/// binary, answers only inside the dedicated benchmark bundle, and each command
/// is bound to one request file so the harness can prove the action completed.
///
/// The channel is a directory poll, not a distributed notification: notification
/// delivery goes through `distnoted` and drops under load, which showed up as
/// spurious command timeouts. Every timer is torn down when the chat view
/// disappears.
@MainActor
final class BenchmarkControl {
    static let shared = BenchmarkControl()

    static let bundleIdentifier = "com.spotask.benchmark"
    static let commandNotification = Notification.Name("com.spotask.benchmark.command")

    private var pollTimer: Timer?
    private let pollInterval: Double = 0.05
    private weak var viewModel: ChatViewModel?
    private var clearCaches: @MainActor () -> Void = {}
    private let stalls = MainThreadStallRecorder()

    private var isActive: Bool {
        Bundle.main.bundleIdentifier == Self.bundleIdentifier
    }

    private var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SPOTASK_BENCHMARK_OUT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("spotask-benchmark", isDirectory: true)
    }

    private func trace(_ message: String) {
        let url = outputDirectory.appendingPathComponent("control.log")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    func install(
        viewModel: ChatViewModel,
        clearCaches: @escaping @MainActor () -> Void = {}
    ) {
        trace("install active=\(isActive) bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
        guard isActive else { return }
        self.viewModel = viewModel
        self.clearCaches = clearCaches

        // Re-installing must not stack timers: appear/disappear repeats.
        uninstall(clearingViewModel: false)

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drainRequests() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        stalls.start()
    }

    func uninstall(clearingViewModel: Bool = true) {
        pollTimer?.invalidate()
        pollTimer = nil
        stalls.stop()
        if clearingViewModel {
            viewModel = nil
        }
    }

    private func drainRequests() {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: outputDirectory.path) else {
            return
        }
        for name in names.filter({ $0.hasSuffix(".request.json") }).sorted() {
            let request = String(name.dropLast(".request.json".count))
            handleCommand(request: request)
            try? fileManager.removeItem(at: outputDirectory.appendingPathComponent(name))
        }
    }

    private func handleCommand(request: String?) {
        trace("command \(request ?? "nil")")
        guard let request, !request.isEmpty else { return }
        guard let data = try? Data(contentsOf: outputDirectory.appendingPathComponent("\(request).request.json")),
              let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = command["action"] as? String else {
            writeAck(request: request, payload: ["ok": false, "error": "unreadable request"])
            return
        }
        let payload = command["payload"] as? [String: Any] ?? [:]

        switch action {
        case "reload":
            guard let viewModel else {
                writeAck(request: request, payload: ["ok": false, "error": "no view model"])
                return
            }
            let identity = viewModel.benchmarkReloadSession()
            writeAck(request: request, payload: [
                "ok": true,
                "sessionIdentity": identity,
                "messageCount": viewModel.benchmarkMessageCount
            ])

        case "clearCache":
            clearCaches()
            writeAck(request: request, payload: ["ok": true, "cleared": true])

        case "resetStats":
            stalls.start()
            writeAck(request: request, payload: ["ok": true])

        case "stats":
            var stats = stalls.snapshot()
            stats["ok"] = true
            writeAck(request: request, payload: stats)

        case "replay":
            guard let viewModel else {
                writeAck(request: request, payload: ["ok": false, "error": "no view model"])
                return
            }
            guard let question = payload["question"] as? String,
                  let chunks = payload["chunks"] as? [String] else {
                writeAck(request: request, payload: ["ok": false, "error": "bad replay payload"])
                return
            }
            let interval = payload["intervalMs"] as? Int ?? 30
            viewModel.benchmarkReplayStream(
                question: question,
                chunks: chunks,
                intervalMs: interval
            )
            writeAck(request: request, payload: ["ok": true, "chunks": chunks.count])

        case "fail":
            guard let viewModel else {
                writeAck(request: request, payload: ["ok": false, "error": "no view model"])
                return
            }
            viewModel.benchmarkFailStream(question: payload["question"] as? String ?? "Failure probe")
            writeAck(request: request, payload: ["ok": true])

        case "newConversation":
            guard let viewModel else {
                writeAck(request: request, payload: ["ok": false, "error": "no view model"])
                return
            }
            viewModel.newConversation()
            writeAck(request: request, payload: ["ok": true, "messageCount": viewModel.benchmarkMessageCount])

        default:
            writeAck(request: request, payload: ["ok": false, "error": "unknown action \(action)"])
        }
    }

    private func writeAck(request: String, payload: [String: Any]) {
        let directory = outputDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(request).json")
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

/// Samples main-thread responsiveness with a 50 ms timer: timer lateness is the
/// stall metric, and an idle app still fires on schedule.
@MainActor
final class MainThreadStallRecorder {
    private let interval: Double = 0.05
    private var timer: Timer?
    private var expected: CFAbsoluteTime = 0
    private var maxDriftMs: Double = 0
    private var samples: Int = 0
    private var over50ms: Int = 0

    func start() {
        stop()
        maxDriftMs = 0
        samples = 0
        over50ms = 0
        expected = CFAbsoluteTimeGetCurrent() + interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let drift = max(0, (now - expected) * 1000)
        expected = now + interval
        samples += 1
        if drift > maxDriftMs { maxDriftMs = drift }
        if drift > 50 { over50ms += 1 }
    }

    func snapshot() -> [String: Any] {
        ["samples": samples, "maxDriftMs": maxDriftMs, "over50ms": over50ms]
    }
}
#endif
