import XCTest
@testable import SpotAsk

final class MathBenchmarkTests: XCTestCase {

    func testColdStartAndWarmRenderPerformance() async throws {
        // Cold start engine instance
        let coldEngine = MathEngine()
        let coldStart = CFAbsoluteTimeGetCurrent()
        let coldResult = try await coldEngine.render("x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true)
        let coldDurationMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000.0

        XCTAssertGreaterThan(coldResult.widthEm, 0)
        XCTAssertGreaterThan(coldResult.heightEm, 0)
        print("BENCHMARK [Cold Start Engine + First Formula]: \(String(format: "%.2f", coldDurationMs)) ms")

        // Warm render same formula (uncached engine call)
        let warmStart = CFAbsoluteTimeGetCurrent()
        let warmResult = try await coldEngine.render("x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true)
        let warmDurationMs = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000.0
        XCTAssertGreaterThan(warmResult.widthEm, 0)
        print("BENCHMARK [Warm Engine Render (same formula)]: \(String(format: "%.2f", warmDurationMs)) ms")

        // Cache hit
        let cache = MathCache()
        cache.set(tex: "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true, rendered: coldResult)
        let cacheStart = CFAbsoluteTimeGetCurrent()
        let cached = cache.get(tex: "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true)
        let cacheDurationMs = (CFAbsoluteTimeGetCurrent() - cacheStart) * 1000.0
        XCTAssertNotNil(cached)
        print("BENCHMARK [Cache Hit Lookup]: \(String(format: "%.4f", cacheDurationMs)) ms")
    }

    func testBatch50DistinctFormulasThroughput() async throws {
        let engine = MathEngine()
        // Pre-warm engine
        _ = try await engine.render("1+1", display: false)

        let formulas = (1...50).map { i in
            "f_\(i)(x) = \\sum_{k=1}^{\(i)} \\frac{x^k}{k!} + \\int_0^\\infty e^{-\(i)t} dt"
        }

        let start = CFAbsoluteTimeGetCurrent()
        var renderedCount = 0
        for formula in formulas {
            let res = try await engine.render(formula, display: true)
            if res.widthEm > 0 {
                renderedCount += 1
            }
        }
        let totalDurationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        let avgPerFormulaMs = totalDurationMs / Double(formulas.count)

        XCTAssertEqual(renderedCount, 50)
        print("BENCHMARK [50 Distinct Formulas Batch]: total \(String(format: "%.2f", totalDurationMs)) ms, avg \(String(format: "%.2f", avgPerFormulaMs)) ms/formula")
    }

    func testStreamingTokenIncrementalReplay() async throws {
        let fullText = """
        Here is the derivation of the Gaussian integral:
        First, consider the square of the integral:
        $$I^2 = \\left( \\int_{-\\infty}^\\infty e^{-x^2} dx \\right)^2 = \\int_{-\\infty}^\\infty \\int_{-\\infty}^\\infty e^{-(x^2+y^2)} dx dy$$
        Converting to polar coordinates $(r, \\theta)$:
        $$I^2 = \\int_0^{2\\pi} d\\theta \\int_0^\\infty r e^{-r^2} dr$$
        Evaluating the inner integral with substitution $u = r^2$:
        $$\\int_0^\\infty r e^{-r^2} dr = \\frac{1}{2} \\int_0^\\infty e^{-u} du = \\frac{1}{2}$$
        Therefore, $I^2 = 2\\pi \\cdot \\frac{1}{2} = \\pi$, which yields $I = \\sqrt{\\pi}$.
        """

        let coordinator = await MathCoordinator.shared
        let chunks = fullText.map { String($0) } // Token-by-token streaming simulation

        var accumulated = ""
        let start = CFAbsoluteTimeGetCurrent()
        var parseCount = 0

        for chunk in chunks {
            accumulated += chunk
            let isolated = MathIsolator.isolate(accumulated)
            if !isolated.formulas.isEmpty {
                await coordinator.ensureRendered(formulas: isolated.formulas.map { ($0.tex, $0.display) })
            }
            parseCount += 1
        }

        // Wait for all formulas in fullText to be rendered in MathCache
        let finalFormulas = MathIsolator.isolate(fullText).formulas
        for formula in finalFormulas {
            var retries = 0
            while MathCache.shared.get(tex: formula.tex, display: formula.display) == nil && retries < 200 {
                try await Task.sleep(nanoseconds: 10_000_000)
                retries += 1
            }
            let isCached = MathCache.shared.get(tex: formula.tex, display: formula.display) != nil
            XCTAssertTrue(isCached, "Formula should be rendered and cached: \(formula.tex)")
        }

        let parser = NativeMathMarkupParser(rendersMath: true, fontSize: 14.5)
        let attr = try parser.attributedString(for: fullText)
        let totalDurationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        XCTAssertGreaterThan(attr.characters.count, 0)

        print("BENCHMARK [Streaming Token Replay]: \(chunks.count) tokens + full async MathJax render + AttributedString in \(String(format: "%.2f", totalDurationMs)) ms")
        XCTAssertGreaterThan(parseCount, 100)
    }

    func testOversizedAndMalformedFormulaProtection() async throws {
        let engine = MathEngine()

        // 1. Oversized TeX (> 16384 bytes)
        let largeTeX = String(repeating: "x + ", count: 5000) + "1"
        XCTAssertGreaterThan(largeTeX.utf8.count, 16384)

        let startOversized = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await engine.render(largeTeX, display: true)
            XCTFail("Should have thrown formulaTooLong")
        } catch MathFailure.formulaTooLong {
            let duration = (CFAbsoluteTimeGetCurrent() - startOversized) * 1000.0
            print("BENCHMARK [Oversized Formula Guard (16KB+)]: safely rejected in \(String(format: "%.3f", duration)) ms")
        }

        // 2. Malformed TeX
        let malformed = "\\frac{1}{"
        let startMalformed = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await engine.render(malformed, display: true)
            XCTFail("Should have thrown syntax error")
        } catch {
            let duration = (CFAbsoluteTimeGetCurrent() - startMalformed) * 1000.0
            print("BENCHMARK [Malformed Formula Error Handling]: handled in \(String(format: "%.3f", duration)) ms (\(error))")
        }
    }
}
