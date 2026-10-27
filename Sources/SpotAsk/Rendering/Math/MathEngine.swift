import Foundation
import JavaScriptCore
import SwiftDraw

public actor MathEngine {
    public static let shared = MathEngine()

    private var context: JSContext?
    private var isInitialized = false

    public init() {}

    private func ensureInitialized() throws {
        if isInitialized, context != nil { return }

        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let scriptURL = bundle.url(
            forResource: "mathjax",
            withExtension: "js",
            subdirectory: "MathJax"
        ) ?? bundle.url(
            forResource: "mathjax",
            withExtension: "js"
        ) else {
            throw MathFailure.engineNotFound
        }

        guard let newContext = JSContext() else {
            throw MathFailure.engineNotFound
        }

        let script: String
        do {
            script = try String(contentsOf: scriptURL, encoding: .utf8)
        } catch {
            throw MathFailure.engineScriptFailed(error.localizedDescription)
        }

        newContext.evaluateScript(script)
        if let error = newContext.exception {
            throw MathFailure.engineScriptFailed(error.toString() ?? "JSContext 执行异常")
        }

        self.context = newContext
        self.isInitialized = true
    }

    public func render(_ tex: String, display: Bool) throws -> RenderedMath {
        guard tex.utf8.count <= 16_384 else {
            throw MathFailure.formulaTooLong
        }

        try ensureInitialized()

        guard let context else {
            throw MathFailure.engineNotFound
        }

        context.exception = nil
        guard let renderFn = context.objectForKeyedSubscript("renderMath"), !renderFn.isUndefined else {
            throw MathFailure.engineScriptFailed("renderMath 函数未找到")
        }

        let result = renderFn.call(withArguments: [tex, display])
        if let error = context.exception {
            throw MathFailure.evaluationFailed(error.toString() ?? "公式排版出错")
        }

        guard let jsonString = result?.toString(),
              let data = jsonString.data(using: .utf8) else {
            throw MathFailure.invalidOutput("公式引擎未返回有效数据")
        }

        struct Payload: Decodable {
            let svg: String?
            let widthEm: Double?
            let heightEm: Double?
            let descentEm: Double?
            let error: String?
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw MathFailure.invalidOutput("JSON 解析失败: \(error.localizedDescription)")
        }

        if let error = payload.error, !error.isEmpty {
            throw MathFailure.evaluationFailed(error)
        }

        guard let xml = payload.svg,
              let width = payload.widthEm,
              let height = payload.heightEm,
              let descent = payload.descentEm,
              width.isFinite, height.isFinite, descent.isFinite,
              width > 0, height > 0, width <= 2_000, height <= 2_000,
              let svg = SVG(xml: xml) else {
            throw MathFailure.invalidSVG
        }

        return RenderedMath(
            tex: tex,
            display: display,
            svg: svg,
            widthEm: width,
            heightEm: height,
            descentEm: descent
        )
    }
}
