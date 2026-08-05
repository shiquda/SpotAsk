import SwiftUI

struct MessageContentView: View {
    let message: ChatMessage

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .assistant {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.string("chat.model"))
                    Spacer()
                    Button {
                        Clipboard.copy(message.content)
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
                    .buttonStyle(.borderless)
                    .help(didCopy ? L10n.string("chat.copied") : L10n.string("chat.copyCompleteAnswer"))
                    .accessibilityLabel(didCopy ? L10n.string("chat.copyAnswer") : L10n.string("chat.copyCompleteAnswer"))
                }
            }

            MarkdownTextView(content: message.content)
        }
    }
}
