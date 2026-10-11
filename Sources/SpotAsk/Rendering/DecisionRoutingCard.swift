import SwiftUI

struct DecisionRoutingCard: View {
    let phase: DecisionRoutingPhase
    let candidates: [DecisionRouteCandidate]
    let onAccept: () -> Void
    let onChangeChannel: () -> Void
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch phase {
            case .idle:
                EmptyView()
            case .deciding:
                deciding
            case let .confirming(_, candidate, confidence):
                confirmation(candidate, confidence: confidence)
            case let .choosing(_, reason, highlightedID):
                choosing(reason: reason, highlightedID: highlightedID)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var deciding: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.string("decisionRouting.deciding"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.fg)
            Spacer(minLength: 0)
            cancelButton
        }
    }

    private func confirmation(_ candidate: DecisionRouteCandidate, confidence: Double) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                routeIcon(candidate)
                Text(candidate.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.fg)
                Text(L10n.string("decisionRouting.recommendedBadge"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Brand.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Brand.accent.opacity(0.12), in: Capsule())
                Spacer(minLength: 8)
                Text(L10n.string("decisionRouting.confidenceBadge", Self.confidenceText(confidence)))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Brand.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Brand.accent.opacity(0.1), in: Capsule())
            }
            if !candidate.applicableDescription.isEmpty {
                Text(candidate.applicableDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    HStack(spacing: 5) {
                        Text(L10n.string("decisionRouting.continue"))
                        Text("↩")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .opacity(0.85)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onChangeChannel) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.string("decisionRouting.changeChannel"))
                        Text("Tab")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Brand.muted)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
                cancelButton
            }
        }
    }

    private func choosing(reason: DecisionChooseReason, highlightedID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("decisionRouting.chooseTitle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.fg)
                    Text(reasonText(reason))
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                cancelButton
            }
            VStack(spacing: 5) {
                ForEach(candidates) { candidate in
                    let isHighlighted = candidate.id == highlightedID
                    Button {
                        onSelect(candidate.id)
                    } label: {
                        HStack(spacing: 8) {
                            routeIcon(candidate)
                            Text(candidate.title)
                                .font(.system(size: 12.5, weight: isHighlighted ? .semibold : .medium))
                                .foregroundStyle(Brand.fg)
                            if !candidate.applicableDescription.isEmpty {
                                Text(candidate.applicableDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Brand.muted)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer(minLength: 8)
                            if isHighlighted {
                                Text(L10n.string("decisionRouting.enterTarget"))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Brand.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Brand.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            } else {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Brand.muted.opacity(0.75))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isHighlighted ? Brand.accent.opacity(0.14) : Brand.fg.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isHighlighted ? Brand.accent.opacity(0.45) : Brand.border,
                                    lineWidth: 1
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            HStack(spacing: 4) {
                Text(L10n.string("decisionRouting.cancel"))
                Text("Esc")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Brand.muted)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func routeIcon(_ candidate: DecisionRouteCandidate) -> some View {
        ProviderBrandIconView(
            slug: candidate.brandIconSlug,
            size: 14,
            fallbackSymbol: candidate.symbolName
        )
        .frame(width: 14, height: 14)
    }

    private func reasonText(_ reason: DecisionChooseReason) -> String {
        switch reason {
        case .changeChannel:
            L10n.string("decisionRouting.chooseHint")
        case .timeout:
            L10n.string("decisionRouting.timeoutManual")
        case .unavailable:
            L10n.string("decisionRouting.unavailable")
        }
    }

    static func confidenceText(_ value: Double) -> String {
        String(format: "%.2f", locale: AppLanguage.current.locale, value)
    }
}
