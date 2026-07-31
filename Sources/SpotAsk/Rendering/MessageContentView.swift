import SwiftUI

struct MessageContentView: View {
    let message: ChatMessage

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .assistant {
                HStack {
                    Text("回答")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                    .help(didCopy ? "已复制" : "复制完整回答")
                    .accessibilityLabel(didCopy ? "完整回答已复制" : "复制完整回答")
                }
            }

            MarkdownTextView(content: message.content)
        }
    }
}
