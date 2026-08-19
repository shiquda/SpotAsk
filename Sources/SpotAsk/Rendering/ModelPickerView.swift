import AppKit
import SwiftUI
import UniformTypeIdentifiers
// MARK: - Model picker

/// The header's quiet model selector: visually weaker than the SpotAsk brand,
/// opens a searchable popover, and stays disabled while a response is running.
struct ModelPickerHeaderButton<PopoverContent: View>: View { let modelName: String
let providerIconSlug: String?
let isDisabled: Bool
@Binding var isPresented: Bool
@ViewBuilder let popoverContent: () -> PopoverContent

@State private var isHovering = false

var body: some View {
    Button {
        isPresented.toggle()
    } label: {
        HStack(spacing: 4) {
            ProviderBrandIconView(
                slug: providerIconSlug,
                size: 14,
                fallbackSymbol: "sparkles",
                fallbackColor: isHovering ? Brand.fg : Brand.muted
            )
            Text(modelName.isEmpty ? L10n.string("chat.model") : modelName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(isHovering || isPresented ? Brand.surface : Color.clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.5 : 1)
    .help(isDisabled ? L10n.string("chat.modelChangeDisabledWhileGenerating") : L10n.string("chat.model"))
    .accessibilityLabel(L10n.string("chat.model"))
    .accessibilityValue(modelName)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
    .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
        popoverContent()
    }
} }

/// Searchable model list grouped by provider. Keyboard: arrows move the
/// highlight, Return selects, Escape closes (the popover's default).
struct ModelPickerContent: View { let catalog: ProviderModelCatalog?
let effectiveModelID: UUID?
let hasSessionOverride: Bool
let isDisabled: Bool
let onSelect: (UUID) -> Void
let onUseDefault: () -> Void

@State private var searchText = ""
@State private var highlightedID: UUID?
@FocusState private var isSearchFocused: Bool

private var filteredGroups: [(provider: ProviderConfiguration, models: [ModelConfiguration])] {
    guard let catalog else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return catalog.providers.compactMap { provider in
        let models = catalog.models
            .filter { $0.providerID == provider.id }
            .filter { model in
                guard !query.isEmpty else { return true }
                return model.displayName.lowercased().contains(query)
                    || model.upstreamModelID.lowercased().contains(query)
                    || provider.name.lowercased().contains(query)
            }
        return models.isEmpty ? nil : (provider, models)
    }
}

private var flattenedModels: [ModelConfiguration] {
    filteredGroups.flatMap(\.models)
}

private var defaultModelName: String? {
    guard let catalog else { return nil }
    return catalog.models.first(where: { $0.id == catalog.selectedModelID })?.displayName
}

var body: some View {
    VStack(alignment: .leading, spacing: 6) {
        TextField(L10n.string("chat.modelPickerSearchPlaceholder"), text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isSearchFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 0.5)
            }
            .onKeyPress(.downArrow) {
                moveHighlight(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHighlight(by: -1)
                return .handled
            }
            .onKeyPress(.return) {
                if let highlightedID {
                    onSelect(highlightedID)
                }
                return .handled
            }
            .onChange(of: searchText) { _, _ in
                highlightFirst()
            }
            .onAppear {
                highlightFirst()
                isSearchFocused = true
            }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if hasSessionOverride, let defaultModelName {
                    UseDefaultModelRow(modelName: defaultModelName) {
                        onUseDefault()
                    }
                    Divider().padding(.vertical, 4)
                }
                ForEach(filteredGroups, id: \.provider.id) { group in
                    HStack(spacing: 5) {
                        ProviderBrandIconView(
                            slug: ProviderBrandIconMatcher.match(
                                providerName: group.provider.name,
                                address: group.provider.address
                            ),
                            size: 12,
                            fallbackSymbol: "server.rack",
                            fallbackColor: Brand.muted
                        )
                        Text(group.provider.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Brand.muted)
                            .textCase(.uppercase)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    ForEach(group.models) { model in
                        modelRow(model, provider: group.provider)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
    .padding(8)
    .frame(width: 300, height: 340)
}

private func modelRow(_ model: ModelConfiguration, provider: ProviderConfiguration) -> some View {
    let isHighlighted = highlightedID == model.id
    return Button {
        guard !isDisabled else { return }
        onSelect(model.id)
    } label: {
        HStack(spacing: 8) {
            ProviderBrandIconView(
                slug: ProviderBrandIconMatcher.match(
                    providerName: provider.name,
                    address: provider.address,
                    modelName: model.displayName,
                    upstreamModelID: model.upstreamModelID
                ),
                size: 16,
                fallbackSymbol: "sparkles",
                fallbackColor: Brand.muted
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.fg)
                    .lineLimit(1)
                if model.displayName != model.upstreamModelID {
                    Text(model.upstreamModelID)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 14)
                .opacity(model.id == effectiveModelID ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Brand.surface : Color.clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .help(isDisabled ? L10n.string("chat.modelChangeDisabledWhileGenerating") : model.displayName)
    .accessibilityLabel(model.displayName)
    .accessibilityAddTraits(model.id == effectiveModelID ? .isSelected : [])
}

private func highlightFirst() {
    if let highlightedID, flattenedModels.contains(where: { $0.id == highlightedID }) {
        return
    }
    highlightedID = effectiveModelID ?? flattenedModels.first?.id
}

private func moveHighlight(by delta: Int) {
    let models = flattenedModels
    guard !models.isEmpty else { return }
    let currentIndex = models.firstIndex(where: { $0.id == highlightedID }) ?? -1
    let nextIndex = min(max(currentIndex + delta, 0), models.count - 1)
    highlightedID = models[nextIndex].id
} }

private struct UseDefaultModelRow: View {
    let modelName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.string("chat.useDefaultModel"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.fg)
                    Text(modelName)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(isHovering ? Brand.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(L10n.string("chat.useDefaultModel"))
    }
}
