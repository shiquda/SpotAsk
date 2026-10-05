import SwiftUI

@MainActor
struct ChatHeaderView: View {
    let modelName: String
    let providerIconSlug: String?
    let isGenerating: Bool
    let isKeepWindowOnTop: Bool
    let providerCatalog: ProviderModelCatalog?
    let effectiveModelID: UUID?
    let hasSessionOverride: Bool
    @Binding var isModelPickerPresented: Bool
    let onToggleWindowOnTop: () -> Void
    let onShowSettings: () -> Void
    let onNewConversation: () -> Void
    let onSelectSessionModel: (UUID) -> Void
    let onUseDefaultModel: () -> Void
    let shortcutHint: (InAppShortcutTarget) -> InAppShortcut?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                BrandMark()
                Text("SpotAsk")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.15)
                    .foregroundStyle(Brand.fg)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("SpotAsk"))

            Spacer()
            HeaderIconButton(action: onToggleWindowOnTop) {
                Image(systemName: isKeepWindowOnTop ? "pin.fill" : "pin")
            }
            .help(L10n.string("settings.windowOnTop"))
            .accessibilityLabel(L10n.string("settings.windowOnTop"))
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(.operation(.toggleWindowOnTop)))
                    .offset(x: 5, y: 5)
            }
            HeaderIconButton(action: onShowSettings) {
                Image(systemName: "gearshape")
            }
            .help(L10n.string("settings.title"))
            .accessibilityLabel(L10n.string("settings.title"))
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(.operation(.showSettings)))
                    .offset(x: 5, y: 5)
            }
            HeaderIconButton(action: onNewConversation) {
                Image(systemName: "plus.bubble")
            }
            .help(L10n.string("chat.newConversation"))
            .accessibilityLabel(L10n.string("chat.newConversation"))
            .overlay(alignment: .bottomTrailing) {
                ShortcutKeycap(shortcut: shortcutHint(.operation(.newConversation)))
                    .offset(x: 5, y: 5)
            }
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .center) {
            HStack(spacing: 6) {
                ModelPickerHeaderButton(
                    modelName: modelName,
                    providerIconSlug: providerIconSlug,
                    isDisabled: isGenerating,
                    isPresented: $isModelPickerPresented
                ) {
                    ModelPickerContent(
                        catalog: providerCatalog,
                        effectiveModelID: effectiveModelID,
                        hasSessionOverride: hasSessionOverride,
                        isDisabled: isGenerating,
                        onSelect: onSelectSessionModel,
                        onUseDefault: onUseDefaultModel
                    )
                }
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(L10n.string("chat.generating"))
                }
            }
            .fixedSize()
        }
        .background(HeaderMaterial())
    }
}
