import AppKit
import Foundation
import SwiftUI
import WebKit

// MARK: - Script Bridge

private final class SessionDocumentScriptBridge: NSObject, WKScriptMessageHandler {
    private weak var host: SessionDocumentHost?

    init(host: SessionDocumentHost) {
        self.host = host
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            self?.host?.handleScriptMessage(message.body)
        }
    }
}

// MARK: - Scheme Handler

final class SessionDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var stoppedTasks: Set<ObjectIdentifier> = []
    private var attachmentImages: [String: Data] = [:]
    private var symbolCache: [String: Data] = [:]

    func registerAttachments(_ attachments: [ChatAttachment]) {
        lock.lock()
        defer { lock.unlock() }
        for att in attachments {
            if case let .image(data) = att.payload {
                attachmentImages[att.id.uuidString] = data
            }
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        attachmentImages.removeAll()
        symbolCache.removeAll()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "spotask-doc" else {
            fail(urlSchemeTask, status: 400)
            return
        }

        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch host {
        case "session":
            serveSessionFile(path: path, task: urlSchemeTask)
        case "attachment":
            serveAttachment(id: path, task: urlSchemeTask)
        case "icon":
            serveIcon(slug: path, task: urlSchemeTask)
        case "symbol":
            serveSymbol(name: path, task: urlSchemeTask)
        default:
            fail(urlSchemeTask, status: 404)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        lock.lock()
        defer { lock.unlock() }
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
    }

    private func isStopped(_ task: any WKURLSchemeTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedTasks.contains(ObjectIdentifier(task))
    }

    private func serveSessionFile(path: String, task: any WKURLSchemeTask) {
        guard let root = SessionDocumentResources.directoryURL else {
            fail(task, status: 500)
            return
        }
        let relative = path.isEmpty ? "index.html" : path
        let target = root.appendingPathComponent(relative).standardizedFileURL
        guard target.path.hasPrefix(root.standardizedFileURL.path),
              FileManager.default.fileExists(atPath: target.path) else {
            fail(task, status: 404)
            return
        }
        guard let data = try? Data(contentsOf: target) else {
            fail(task, status: 500)
            return
        }
        let mime = Self.mimeType(for: target.pathExtension)
        respond(task, data: data, mimeType: mime)
    }

    private func serveAttachment(id: String, task: any WKURLSchemeTask) {
        lock.lock()
        let data = attachmentImages[id]
        lock.unlock()
        guard let data else {
            fail(task, status: 404)
            return
        }
        respond(task, data: data, mimeType: "image/png")
    }

    private func serveIcon(slug: String, task: any WKURLSchemeTask) {
        let isDark = task.request.url?.query?.contains("dark=true") ?? false
        if let image = ProviderBrandIcon.image(for: slug, dark: isDark),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            respond(task, data: data, mimeType: "image/png")
            return
        }
        fail(task, status: 404)
    }

     private func serveSymbol(name: String, task: any WKURLSchemeTask) {
         let parts = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
         let weightName: String
         let pointSize: CGFloat
         let symbolName: String
         if parts.count >= 3, let size = Double(parts[1]) {
             weightName = parts[0]
             pointSize = CGFloat(size)
             symbolName = parts.dropFirst(2).joined(separator: "/")
         } else {
             weightName = "regular"
             pointSize = 10
             symbolName = name
         }
         let cacheKey = "\(weightName)|\(pointSize)|\(symbolName)"
         lock.lock()
         if let cached = symbolCache[cacheKey] {
             lock.unlock()
             respond(task, data: cached, mimeType: "image/png")
             return
         }
         lock.unlock()
 
         guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
             fail(task, status: 404)
             return
         }
         let weight: NSFont.Weight
         switch weightName {
         case "semibold": weight = .semibold
         case "medium": weight = .medium
         default: weight = .regular
         }
         let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
             .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
         let configured = base.withSymbolConfiguration(config) ?? base
         let pixels = max(pointSize * 4, 32)
         let pixelSize = NSSize(width: pixels, height: pixels)
         guard let rep = NSBitmapImageRep(
             bitmapDataPlanes: nil,
             pixelsWide: Int(pixels),
             pixelsHigh: Int(pixels),
             bitsPerSample: 8,
             samplesPerPixel: 4,
             hasAlpha: true,
             isPlanar: false,
             colorSpaceName: .deviceRGB,
             bytesPerRow: 0,
             bitsPerPixel: 0
         ) else {
             fail(task, status: 404)
             return
         }
         rep.size = pixelSize
         NSGraphicsContext.saveGraphicsState()
         NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
         configured.draw(in: NSRect(origin: .zero, size: pixelSize))
         NSGraphicsContext.restoreGraphicsState()
         if let data = rep.representation(using: .png, properties: [:]) {
             lock.lock()
             symbolCache[cacheKey] = data
             lock.unlock()
             respond(task, data: data, mimeType: "image/png")
             return
         }
         fail(task, status: 404)
     }

    private func respond(_ task: any WKURLSchemeTask, data: Data, mimeType: String) {
        guard !isStopped(task), let url = task.request.url else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "spotask-doc://session"
            ]
        ) ?? URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask, status: Int) {
        guard !isStopped(task), let url = task.request.url else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        ) ?? URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: "utf-8")
        task.didReceive(response)
        task.didFinish()
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "woff2": return "font/woff2"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Host Class

@MainActor
final class SessionDocumentHost: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let containerView = NSView()
    private var webView: WKWebView?
    private var schemeHandler: SessionDocumentSchemeHandler?
    private var scriptBridge: SessionDocumentScriptBridge?

    private(set) var generation = UUID().uuidString
    private var isPageLoaded = false
    private var isApplying = false
    private var pendingSnapshot: SessionDocumentSnapshot?
    private var knownMessageIDs: Set<UUID> = []

    var onCopyMessage: ((UUID) -> Void)?
    var onCopyCode: ((UUID, String) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onToggleReasoning: ((UUID) -> Void)?
     var onToggleExpand: ((UUID) -> Void)?
     var onRetryUserMessage: ((UUID) -> Void)?
    var onRetryLatestWithModel: ((UUID) -> Void)?
    var onRetryLatestWithDefaultModel: (() -> Void)?
    var onSelectExternalAsk: ((QuickAction) -> Void)?
    var onInsertSelection: ((UUID) -> Void)?
    var onRegenerate: (() -> Void)?
    var onRetry: (() -> Void)?
    var onScrollPhaseChanged: ((ScrollFollowState.Phase) -> Void)?
    var onScrollPositionChanged: ((Bool) -> Void)?

    var catalog: ProviderModelCatalog?
    var effectiveModelID: UUID?
    var hasSessionOverride: Bool = false
    var externalAsks: [QuickAction] = []

    private var modelPopover: NSPopover?

    override init() {
        super.init()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear
    }

    func prepare() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        let handler = SessionDocumentSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: "spotask-doc")
        self.schemeHandler = handler

        let bridge = SessionDocumentScriptBridge(host: self)
        self.scriptBridge = bridge
        config.userContentController.add(bridge, name: "sessionDocument")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let view = WKWebView(frame: containerView.bounds, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.autoresizingMask = [.width, .height]
        view.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            view.isInspectable = false
        }

        containerView.addSubview(view)
        self.webView = view
        self.generation = UUID().uuidString
        self.isPageLoaded = false

        if let indexURL = URL(string: "spotask-doc://session/index.html") {
            view.load(URLRequest(url: indexURL))
        }
    }

    func release() {
        guard let view = webView else { return }
        generation = UUID().uuidString
        isPageLoaded = false
        isApplying = false
        pendingSnapshot = nil
        knownMessageIDs.removeAll()
        modelPopover?.close()
        modelPopover = nil

        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.configuration.userContentController.removeAllScriptMessageHandlers()
        view.removeFromSuperview()
        self.webView = nil
        self.schemeHandler?.clear()
        self.schemeHandler = nil
        self.scriptBridge = nil
    }

    func apply(snapshot: SessionDocumentSnapshot, attachments: [ChatAttachment] = []) {
        prepare()
        schemeHandler?.registerAttachments(attachments)
        knownMessageIDs = Set(snapshot.messages.compactMap { UUID(uuidString: $0.id) })

        guard isPageLoaded, let webView, let dict = snapshot.toDictionary() else {
            pendingSnapshot = snapshot
            return
        }

        guard !isApplying else {
            pendingSnapshot = snapshot
            return
        }

        isApplying = true
        webView.callAsyncJavaScript(
            "return window.SessionDocument && window.SessionDocument.apply(snapshot);",
            arguments: ["snapshot": dict],
            in: nil,
            in: .page
        ) { [weak self] _ in
            guard let self else { return }
            self.isApplying = false
            if let next = self.pendingSnapshot {
                self.pendingSnapshot = nil
                self.apply(snapshot: next)
            }
        }
    }

    func scrollToBottom() {
        webView?.evaluateJavaScript("window.SessionDocumentScrollToBottom && window.SessionDocumentScrollToBottom();", completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        if let pending = pendingSnapshot {
            pendingSnapshot = nil
            apply(snapshot: pending)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           url.scheme == "spotask-doc",
           url.host == "session" {
            decisionHandler(.allow)
            return
        }
        if let url = navigationAction.request.url, navigationAction.navigationType == .linkActivated {
            onOpenLink?(url)
        }
        decisionHandler(.cancel)
    }

    // MARK: - Script Message Dispatch

    fileprivate func handleScriptMessage(_ body: Any) {
        guard let action = SessionDocumentAction.parse(
            body: body,
            expectedGeneration: generation,
            knownMessageIDs: knownMessageIDs
        ) else { return }

        switch action {
        case let .copyMessage(id):
            onCopyMessage?(id)
        case let .copyCode(id, code):
            onCopyCode?(id, code)
        case let .openLink(url):
            onOpenLink?(url)
        case let .toggleReasoning(id):
            onToggleReasoning?(id)
        case let .toggleExpand(id):
            onToggleExpand?(id)
        case let .retryUser(id):
            onRetryUserMessage?(id)
        case let .insertSelection(id):
            onInsertSelection?(id)
        case .regenerate:
            onRegenerate?()
        case .retry:
            onRetry?()
        case let .scroll(phase, nearBottom):
            let mapped: ScrollFollowState.Phase
            switch phase {
            case "userInteracting": mapped = .userInteracting
            default: mapped = .idle
            }
            onScrollPhaseChanged?(mapped)
            onScrollPositionChanged?(nearBottom)
        case let .showModelMenu(messageID, anchorRect):
            presentModelMenu(for: messageID, at: anchorRect)
        }
    }

    // MARK: - Popovers & Native Menus

    private func presentModelMenu(for messageID: UUID, at viewportRect: CGRect) {
        guard let webView else { return }
        modelPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        let content = ModelPickerContent(
            catalog: catalog,
            effectiveModelID: effectiveModelID,
            hasSessionOverride: hasSessionOverride,
            isDisabled: false,
            externalAsks: externalAsks,
            onSelectExternalAsk: { [weak self] action in
                self?.modelPopover?.close()
                self?.onSelectExternalAsk?(action)
            },
            onSelect: { [weak self] modelID in
                self?.modelPopover?.close()
                self?.onRetryLatestWithModel?(modelID)
            },
            onUseDefault: { [weak self] in
                self?.modelPopover?.close()
                self?.onRetryLatestWithDefaultModel?()
            }
        )
        popover.contentViewController = NSHostingController(rootView: content)
        self.modelPopover = popover

        let flippedY = webView.bounds.height - (viewportRect.origin.y + viewportRect.height)
        let rect = CGRect(x: viewportRect.origin.x, y: flippedY, width: viewportRect.width, height: viewportRect.height)
        popover.show(relativeTo: rect, of: webView, preferredEdge: .maxY)
    }

}

// MARK: - SwiftUI View Wrapper

struct SessionDocumentWebView: NSViewRepresentable {
    let host: SessionDocumentHost

    func makeNSView(context: Context) -> NSView {
        host.prepare()
        return host.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
