import AppKit
import SwiftUI
import SwiftDraw
import Textual

/// Inline math attachment.
///
/// Textual draws attachments inside a `Canvas` symbol, so an attachment can
/// only be a static picture: scroll views do not lay out there and buttons do
/// not receive clicks. Display math therefore lives in `DisplayMathView`;
/// this type stays a plain SVG run that flows with the surrounding sentence.
public struct NativeMathAttachment: Attachment {
    public let math: RenderedMath
    public let fontSize: Double

    public init(math: RenderedMath, fontSize: Double = 14.5) {
        self.math = math
        self.fontSize = fontSize
    }

    public var description: String {
        "$\(math.tex)$"
    }

    public var selectionStyle: AttachmentSelectionStyle {
        .text
    }

    public var body: some View {
        NativeMathAttachmentView(math: math, fontSize: fontSize)
    }

    public func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
        -math.descentEm * fontSize
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let naturalWidth = math.widthEm * fontSize
        let height = math.heightEm * fontSize
        guard let proposedWidth = proposal.width, proposedWidth > 0, naturalWidth > proposedWidth else {
            return CGSize(width: naturalWidth, height: height)
        }
        // A formula wider than the line is scaled down instead of overflowing
        // the message bubble.
        return CGSize(width: proposedWidth, height: height * proposedWidth / naturalWidth)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        sizeThatFits(proposal)
    }
}

public struct NativeMathAttachmentView: View {
    public let math: RenderedMath
    public let fontSize: Double

    public init(math: RenderedMath, fontSize: Double) {
        self.math = math
        self.fontSize = fontSize
    }

    public var body: some View {
        SVGView(svg: math.svg)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(.primary)
            .accessibilityLabel("公式：" + math.tex)
    }
}
