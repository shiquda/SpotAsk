import Foundation

private final class RenderedMathBox {
    let value: RenderedMath
    init(_ value: RenderedMath) {
        self.value = value
    }
}

private final class ErrorBox {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

public final class MathCache: @unchecked Sendable {
    public static let shared = MathCache()

    private let cache = NSCache<NSString, RenderedMathBox>()
    private let errorCache = NSCache<NSString, ErrorBox>()
    private let lock = NSLock()

    public init(countLimit: Int = 1_000, totalCostLimit: Int = 20 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        errorCache.countLimit = countLimit
    }

    private func cacheKey(tex: String, display: Bool) -> NSString {
        "\(display ? "D" : "I"):\(tex)" as NSString
    }

    public func get(tex: String, display: Bool) -> RenderedMath? {
        lock.lock()
        defer { lock.unlock() }
        let key = cacheKey(tex: tex, display: display)
        return cache.object(forKey: key)?.value
    }

    public func set(tex: String, display: Bool, rendered: RenderedMath) {
        lock.lock()
        defer { lock.unlock() }
        let key = cacheKey(tex: tex, display: display)
        let estimatedCost = tex.utf8.count + Int(rendered.widthEm * rendered.heightEm * 64) + 1024
        cache.setObject(RenderedMathBox(rendered), forKey: key, cost: estimatedCost)
        errorCache.removeObject(forKey: key)
    }

    public func hasFailed(tex: String, display: Bool) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let key = cacheKey(tex: tex, display: display)
        return errorCache.object(forKey: key)?.message
    }

    public func setFailed(tex: String, display: Bool, error: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = cacheKey(tex: tex, display: display)
        errorCache.setObject(ErrorBox(error), forKey: key)
        cache.removeObject(forKey: key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        errorCache.removeAllObjects()
    }
}
