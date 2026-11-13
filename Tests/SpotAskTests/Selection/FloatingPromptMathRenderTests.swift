import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Floating prompt math rendering")
@MainActor
struct FloatingPromptMathRenderTests {
    @Test("The floating window draws inline and display formulas on the glass")
    func floatingWindowDrawsFormulas() async throws {
        let inlineTex = #"q_\phi(z|x)"#
        let displayTex = #"\int_0^1 x\,dx"#
        let markdown = "$\(inlineTex)$\n\n$$\(displayTex)$$"
        let inline = try await MathEngine.shared.render(inlineTex, display: false)
        let display = try await MathEngine.shared.render(displayTex, display: true)
        MathCache.shared.set(tex: inline.tex, display: false, rendered: inline)
        MathCache.shared.set(tex: display.tex, display: true, rendered: display)
        defer {
            MathCache.shared.clear()
            MathSegmentCache.shared.clear()
        }

        let settings = makeSettings(appearance: .dark, renderMath: true)
        let backdrop = solidBackdrop()
        backdrop.orderFrontRegardless()
        defer { backdrop.orderOut(nil) }

        let rendered = try await showFloating(markdown: markdown, settings: settings, anchor: CGPoint(x: 640, y: 640))
        defer { rendered.controller.close() }
        pump(0.7)

        // cacheDisplay hides the display integral (the glass box snapshots as
        // an opaque white bar) but still draws the inline formula. That is
        // enough to catch the reported blank gap without a screen recording.
        let cached = try #require(cacheCapture(rendered.panel))
        let cachedInline = inkCount(cached, band: 0.14 ..< 0.18, dark: false, xMax: 0.45)
        #expect(cachedInline > 60, "Inline formula is blank in the floating window (\(cachedInline))")

        let floatingImage = screenCapture(rendered.panel)
        let hasChrome = floatingImage.map(captureHasChrome) ?? false
        guard let floatingImage, hasChrome else {
            return
        }
        assertFormulas(floatingImage, dark: false)

        rendered.controller.close()
        pump(0.15)
        settings.renderMath = false
        let disabled = try await showFloating(markdown: markdown, settings: settings, anchor: CGPoint(x: 640, y: 640))
        defer { disabled.controller.close() }
        pump(0.5)
        let disabledImage = try #require(screenCapture(disabled.panel))
        let renderedInline = inkCount(floatingImage, band: 0.145 ..< 0.185, dark: false, xMax: 0.75)
        let sourceInline = inkCount(disabledImage, band: 0.145 ..< 0.185, dark: false, xMax: 0.75)
        #expect(
            sourceInline > renderedInline * 2,
            "Turning formula rendering off should show the source, not the same glyphs (\(sourceInline) vs \(renderedInline))"
        )

        disabled.controller.close()
        pump(0.15)
        settings.appearance = .light
        settings.renderMath = true
        let light = try await showFloating(markdown: markdown, settings: settings, anchor: CGPoint(x: 640, y: 200))
        defer { light.controller.close() }
        pump(0.5)
        let lightImage = try #require(screenCapture(light.panel))
        assertFormulas(lightImage, dark: true)
    }

    /// Default 380×460 window, formula-only answer. Inline sits just under the
    /// header; the display box is the next band. The copy button is on the right.
    private func assertFormulas(_ image: NSImage, dark: Bool) {
        let inline = inkCount(image, band: 0.145 ..< 0.185, dark: dark, xMax: 0.75)
        let display = inkCount(image, band: 0.20 ..< 0.32, dark: dark, xMax: 0.75)
        let empty = inkCount(image, band: 0.45 ..< 0.75, dark: dark, xMax: 0.75)
        #expect(inline > 80, "Inline formula ink \(inline) is missing")
        #expect(display > 150, "Display formula ink \(display) is missing")
        #expect(empty < 40, "Formula ink leaked into the empty answer area (\(empty))")
    }

    private func makeSettings(appearance: AppearanceMode, renderMath: Bool) -> AppSettings {
        let suiteName = "FloatingPromptMathRender.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.appearance = appearance
        settings.renderMath = renderMath
        return settings
    }

    private func showFloating(
        markdown: String,
        settings: AppSettings,
        anchor: CGPoint
    ) async throws -> (controller: FloatingPromptWindowController, panel: NSWindow) {
        let snapshot = SelectedTextSnapshot(
            text: "VAE",
            source: SelectionSourceApplication(
                processIdentifier: 1,
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit"
            ),
            selectedRange: SelectionCharacterRange(location: 0, length: 3),
            anchor: .pointer(anchor)
        )
        let session = FloatingPromptSession(
            snapshot: snapshot,
            preset: PromptPreset.builtIn[1],
            settings: settings,
            providerFactory: MathProbeFactory(answer: markdown),
            modelID: nil
        )
        let controller = FloatingPromptWindowController(
            session: session,
            settings: settings,
            onContinue: { _ in },
            onClosed: {}
        )
        session.start()
        for _ in 0 ..< 40 where session.phase != .complete {
            await Task.yield()
        }
        #expect(session.phase == .complete)
        controller.show(near: snapshot.anchor)
        pump(0.2)
        let panel = try #require(
            NSApp.windows.first(where: { String(describing: type(of: $0)).contains("FloatingPromptPanel") && $0.isVisible })
        )
        return (controller, panel)
    }

    private func solidBackdrop() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 1400, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 1)
        window.isOpaque = true
        window.level = .normal
        window.ignoresMouseEvents = true
        return window
    }

    private func pump(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func cacheCapture(_ window: NSWindow) -> NSImage? {
        guard let view = window.contentView else { return nil }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func screenCapture(_ window: NSWindow) -> NSImage? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotask-math-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", String(window.windowNumber), "-o", url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let image = NSImage(contentsOf: url),
              image.size.width > 40, image.size.height > 40 else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return image
    }

    private func captureHasChrome(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.bitmapData else {
            return false
        }
        let bytesPerPixel = max(1, rep.bitsPerPixel / 8)
        let y1 = max(1, rep.pixelsHigh * 12 / 100)
        var blue = 0
        for y in 0 ..< y1 {
            for x in 0 ..< rep.pixelsWide {
                let offset = y * rep.bytesPerRow + x * bytesPerPixel
                let r = Int(data[offset])
                let g = Int(data[offset + 1])
                let b = Int(data[offset + 2])
                if b > 140, b > r + 40, b > g + 20 { blue += 1 }
            }
        }
        return blue > 200
    }

    private func inkCount(_ image: NSImage, band: Range<Double>, dark: Bool, xMax: Double) -> Int {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.bitmapData else {
            return 0
        }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let bytesPerPixel = max(1, rep.bitsPerPixel / 8)
        let y0 = min(height, max(0, Int(Double(height) * band.lowerBound)))
        let y1 = min(height, max(y0, Int(Double(height) * band.upperBound)))
        let x0 = width / 25
        let x1 = min(width, max(x0, Int(Double(width) * xMax)))
        var count = 0
        for y in y0 ..< y1 {
            for x in x0 ..< x1 {
                let offset = y * rep.bytesPerRow + x * bytesPerPixel
                let sum = Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2])
                if dark ? sum < 220 : sum > 500 { count += 1 }
            }
        }
        return count
    }
}

private struct MathProbeProvider: ChatProvider {
    let answer: String

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta(answer))
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}

@MainActor
private final class MathProbeFactory: ChatProviderFactory {
    let answer: String
    init(answer: String) { self.answer = answer }
    func makeProvider() throws -> any ChatProvider { MathProbeProvider(answer: answer) }
    func makeTargetSnapshot() throws -> ProviderTargetSnapshot { .testValue() }
    func makeTargetSnapshot(modelID: UUID) throws -> ProviderTargetSnapshot { .testValue(modelID: modelID) }
    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        MathProbeProvider(answer: answer)
    }
}
