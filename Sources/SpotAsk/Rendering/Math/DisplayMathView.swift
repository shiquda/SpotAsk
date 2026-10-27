import AppKit
import SwiftUI
import SwiftDraw

/// A display formula rendered as a native block: the SVG is centred in the
/// message column and, when it is wider than the window, scrolls horizontally
/// instead of clipping.
public struct DisplayMathView: View {
    public let tex: String
    public let fontSize: Double
    private let pasteboard: NSPasteboard
    @State private var didCopy = false
    @Environment(AppSettings.self) private var settings: AppSettings?

    public init(tex: String, fontSize: Double, pasteboard: NSPasteboard = .general) {
        self.tex = tex
        self.fontSize = fontSize
        self.pasteboard = pasteboard
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
        .frame(minHeight: 36)
        .overlay(alignment: .topTrailing) {
            Button {
                pasteboard.clearContents()
                let copyWithDelimiters = settings?.copyMathWithDelimiters ?? AppSettings.shared.copyMathWithDelimiters
                let textToCopy = copyWithDelimiters ? "$$\n" + tex + "\n$$" : tex
                if pasteboard.setString(textToCopy, forType: .string) {
                    didCopy = true
                }
            } label: {
                Label(
                    L10n.string(didCopy ? "chat.copied" : "math.copy"),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(L10n.string(didCopy ? "chat.copied" : "math.copy"))
            .padding(6)
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled else { return }
                didCopy = false
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
                    .frame(minWidth: max(0, proxy.size.width - 72), alignment: .center)
                    .accessibilityLabel("公式：" + tex)
            }
            .padding(.horizontal, 36)
        }
        .frame(height: max(height + 12, 36))
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
            .padding(.horizontal, 36)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("公式排版中：" + tex)
    }

    private func failureBody(_ error: String) -> some View {
        Text("$$\(tex)$$")
            .font(.system(size: fontSize * 0.95, design: .monospaced))
            .foregroundStyle(Color.red.opacity(0.9))
            .padding(.horizontal, 36)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .help(error)
            .accessibilityLabel("公式排版失败：" + tex)
    }
}
