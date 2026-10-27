import Foundation
import SwiftDraw

public struct RenderedMath: Sendable, Hashable {
    public let tex: String
    public let display: Bool
    public let svg: SVG
    public let widthEm: Double
    public let heightEm: Double
    public let descentEm: Double

    public init(
        tex: String,
        display: Bool,
        svg: SVG,
        widthEm: Double,
        heightEm: Double,
        descentEm: Double
    ) {
        self.tex = tex
        self.display = display
        self.svg = svg
        self.widthEm = widthEm
        self.heightEm = heightEm
        self.descentEm = descentEm
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(tex)
        hasher.combine(display)
        hasher.combine(widthEm)
        hasher.combine(heightEm)
        hasher.combine(descentEm)
    }

    public static func == (lhs: RenderedMath, rhs: RenderedMath) -> Bool {
        lhs.tex == rhs.tex &&
        lhs.display == rhs.display &&
        lhs.widthEm == rhs.widthEm &&
        lhs.heightEm == rhs.heightEm &&
        lhs.descentEm == rhs.descentEm
    }
}

public enum MathFailure: LocalizedError, Sendable {
    case formulaTooLong
    case engineNotFound
    case engineScriptFailed(String)
    case evaluationFailed(String)
    case invalidOutput(String)
    case invalidSVG

    public var errorDescription: String? {
        switch self {
        case .formulaTooLong:
            return "公式过长，已保留原文。"
        case .engineNotFound:
            return "本地公式排版引擎未能加载。"
        case .engineScriptFailed(let msg):
            return "公式引擎初始化失败：\(msg)"
        case .evaluationFailed(let msg):
            return "公式排版失败：\(msg)"
        case .invalidOutput(let msg):
            return "公式解析异常：\(msg)"
        case .invalidSVG:
            return "公式图形生成失败。"
        }
    }
}
