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
            GeometryReader { geometry in
                toolbar(configuration: configuration)
                    .onAppear {
                        registerToolbarRect(geometry, configuration: configuration)
                    }
                    .onChange(of: geometry.size) { _, _ in
                        registerToolbarRect(geometry, configuration: configuration)
                    }
                    .onDisappear {
                        configuration.codeBlock.unregisterInteractiveExclusionRect(id: configuration.id)
                    }
            }
            .frame(height: toolbarHeight)
        }
        .textual.blockSpacing(.fontScaled(top: 0, bottom: 1))
    }

    @MainActor
    private func registerToolbarRect(
        _ geometry: GeometryProxy,
        configuration: Configuration
    ) {
        let rect = geometry.frame(in: .named("textContainer"))
        configuration.codeBlock.registerInteractiveExclusionRect(id: configuration.id, rect: rect)
    }

    @MainActor
    private func toolbar(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Text(configuration.languageHint ?? L10n.string("code.defaultLanguage"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            CopyCodeButton(
                didCopy: $didCopy,
                copy: { configuration.codeBlock.copyToPasteboard() },
                label: L10n.string("code.copy"),
                copiedLabel: L10n.string("code.copied")
            )
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 10)
        .frame(height: toolbarHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
                .allowsHitTesting(false)
        }
    }

    private struct CopyCodeButton: NSViewRepresentable {
        @Binding var didCopy: Bool
        let copy: () -> Void
        let label: String
        let copiedLabel: String

        func makeCoordinator() -> Coordinator {
            Coordinator(didCopy: $didCopy, copy: copy, label: label, copiedLabel: copiedLabel)
        }

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton()
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.target = context.coordinator
            button.action = #selector(Coordinator.copyCode(_:))
            context.coordinator.update(button)
            return button
        }

        func updateNSView(_ button: NSButton, context: Context) {
            context.coordinator.didCopy = $didCopy
            context.coordinator.copy = copy
            context.coordinator.update(button)
        }

        @MainActor
        final class Coordinator: NSObject {
            var didCopy: Binding<Bool>
            var copy: () -> Void
            let label: String
            let copiedLabel: String

            init(didCopy: Binding<Bool>, copy: @escaping () -> Void, label: String, copiedLabel: String) {
                self.didCopy = didCopy
                self.copy = copy
                self.label = label
                self.copiedLabel = copiedLabel
            }

            @objc func copyCode(_ sender: Any?) {
                copy()
                didCopy.wrappedValue = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1_500))
                    guard !Task.isCancelled else { return }
                    didCopy.wrappedValue = false
                }
            }

            func update(_ button: NSButton) {
                let didCopy = didCopy.wrappedValue
                button.image = NSImage(
                    systemSymbolName: didCopy ? "checkmark" : "doc.on.doc",
                    accessibilityDescription: nil
                )
                button.toolTip = didCopy ? copiedLabel : label
                button.setAccessibilityLabel(didCopy ? copiedLabel : label)
            }
        }
    }
}
