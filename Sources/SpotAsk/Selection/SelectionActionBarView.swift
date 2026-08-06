import SwiftUI

struct SelectionActionBarView: View {
    let presets: [PromptPreset]
    let onSelect: (PromptPreset) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets) { preset in
                Button { onSelect(preset) } label: {
                    Image(systemName: preset.symbolName)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(preset.title)
                .accessibilityLabel(preset.title)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
