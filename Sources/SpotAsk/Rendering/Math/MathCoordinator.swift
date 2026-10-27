import Foundation
import SwiftUI

@MainActor
@Observable
public final class MathCoordinator {
    public static let shared = MathCoordinator()

    public private(set) var revision: Int = 0

    private var inFlight: [String: CFAbsoluteTime] = [:]
    private var watchdog: Timer?
    private let staleAfter: CFAbsoluteTime = 20

    private init() {}

    private func itemKey(tex: String, display: Bool) -> String {
        "\(display ? "D" : "I"):\(tex)"
    }

    public func ensureRendered(
        formulas: [(tex: String, display: Bool)],
        onComplete: (@MainActor () -> Void)? = nil
    ) {
        purgeStaleRequests()
        let uncached = formulas.filter { item in
            let key = itemKey(tex: item.tex, display: item.display)
            if inFlight[key] != nil { return false }
            if MathCache.shared.get(tex: item.tex, display: item.display) != nil { return false }
            if MathCache.shared.hasFailed(tex: item.tex, display: item.display) != nil { return false }
            return true
        }

        guard !uncached.isEmpty else {
            onComplete?()
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        for item in uncached {
            inFlight[itemKey(tex: item.tex, display: item.display)] = now
        }
        startWatchdog()

        Task.detached(priority: .userInitiated) {
            var anyChanged = false

            for item in uncached {
                do {
                    let rendered = try await MathEngine.shared.render(item.tex, display: item.display)
                    MathCache.shared.set(tex: item.tex, display: item.display, rendered: rendered)
                    anyChanged = true
                } catch {
                    MathCache.shared.setFailed(
                        tex: item.tex,
                        display: item.display,
                        error: error.localizedDescription
                    )
                    anyChanged = true
                }
            }

            await MainActor.run {
                for item in uncached {
                    self.inFlight.removeValue(forKey: self.itemKey(tex: item.tex, display: item.display))
                }
                if anyChanged {
                    self.revision &+= 1
                }
                onComplete?()
            }
        }
    }

    /// A render that never returns must not pin its formula on the placeholder
    /// forever: the key is dropped after `staleAfter` seconds and the revision
    /// bump makes every view re-request it.
    private func purgeStaleRequests() {
        guard !inFlight.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let stale = inFlight.filter { now - $0.value > staleAfter }.map(\.key)
        guard !stale.isEmpty else { return }
        for key in stale {
            inFlight.removeValue(forKey: key)
        }
        revision &+= 1
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.purgeStaleRequests()
                if self.inFlight.isEmpty {
                    self.watchdog?.invalidate()
                    self.watchdog = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }
}
