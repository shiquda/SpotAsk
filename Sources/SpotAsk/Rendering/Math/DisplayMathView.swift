import SwiftUI
import SwiftDraw

/// A display formula rendered as a native block: the SVG is centred in the
/// message column and, when it is wider than the window, scrolls horizontally
/// instead of clipping.
public struct DisplayMathView: View {
    public let tex: String
    public let fontSize: Double

    public init(tex: String, fontSize: Double) {
        self.tex = tex
        self.fontSize = fontSize
    }

    public var body: some View {
        // The revision is read here so the block redraws once the background
        // render finishes.
        bodyContent(revision: MathCoordinator.shared.revision)
    }

    @ViewBuilder
    private func bodyContent(revision: Int) -> some View {
        Group {
            if let rendered = MathCache.shared.get(tex: tex, display: true) {
                renderedBody(rendered)
            } else if let error = MathCache.shared.hasFailed(tex: tex, display: true) {
                failureBody(error)
            } else {
                pendingBody
                    .task(id: tex) {
                        MathCoordinator.shared.ensureRendered(formulas: [(tex, true)])
                    }
            }
        }
    }

    private func renderedBody(_ rendered: RenderedMath) -> some View {
        let width = max(1, rendered.widthEm * fontSize)
        let height = max(1, rendered.heightEm * fontSize)

        return GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                SVGView(svg: rendered.svg)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .frame(width: width, height: height)
                    .padding(.vertical, 6)
                    .frame(minWidth: proxy.size.width, alignment: .center)
                    .accessibilityLabel("公式：" + tex)
            }
        }
        .frame(height: height + 12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("公式：" + tex)
    }

    private var pendingBody: some View {
        Text("$$\(tex)$$")
            .font(.system(size: fontSize * 0.95, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("公式排版中：" + tex)
    }

    private func failureBody(_ error: String) -> some View {
        Text("$$\(tex)$$")
            .font(.system(size: fontSize * 0.95, design: .monospaced))
            .foregroundStyle(Color.red.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .help(error)
            .accessibilityLabel("公式排版失败：" + tex)
    }
}
