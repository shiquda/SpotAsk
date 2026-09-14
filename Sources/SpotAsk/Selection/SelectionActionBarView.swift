import SwiftUI

struct SelectionActionBarView: View {
    let presets: [PromptPreset]
    let externalAsks: [QuickAction]
    let onSelectPreset: (PromptPreset) -> Void
    let onSelectExternalAsk: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(presets) { preset in
                Button { onSelectPreset(preset) } label: {
                    Image(systemName: preset.symbolName)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(preset.title)
                .accessibilityLabel(preset.title)
            }
            if !presets.isEmpty && !externalAsks.isEmpty {
                Divider().frame(height: 18).padding(.horizontal, 4)
            }
            ForEach(externalAsks) { action in
                Button { onSelectExternalAsk(action) } label: {
                    ProviderBrandIconView(
                        slug: action.brandIconSlug,
                        size: 15,
                        fallbackSymbol: action.symbolName
                    )
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(action.displayName)
                .accessibilityLabel(action.displayName)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
