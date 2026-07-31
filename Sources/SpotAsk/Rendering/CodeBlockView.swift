import SwiftUI
import Textual

struct CodeBlockView: StructuredText.CodeBlockStyle {

    @State private var didCopy = false

    private let toolbarHeight: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.225))
                .textual.fontScale(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .padding(.horizontal, 12)
                .padding(.top, toolbarHeight + 10)
                .padding(.bottom, 12)
        }
        .accessibilityLabel(L10n.string("code.accessibility"))
        .background(Color(nsColor: .textBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            toolbar(configuration: configuration)
        }
        .textual.blockSpacing(.fontScaled(top: 0, bottom: 1))
    }

    @MainActor
    private func toolbar(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Text(configuration.languageHint ?? L10n.string("code.defaultLanguage"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                configuration.codeBlock.copyToPasteboard()
                didCopy = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1_500))
                    guard !Task.isCancelled else { return }
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help(didCopy ? L10n.string("chat.copied") : L10n.string("code.copy"))
            .accessibilityLabel(didCopy ? L10n.string("code.copied") : L10n.string("code.copy"))
        }
        .padding(.horizontal, 10)
        .frame(height: toolbarHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
                .allowsHitTesting(false)
        }
    }
}
