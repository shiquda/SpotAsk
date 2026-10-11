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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                routeIcon(candidate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.fg)
                    Text(L10n.string("decisionRouting.applicableLabel"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 8)
                Text(Self.confidenceText(confidence))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Brand.accent)
            }
            Text(candidate.applicableDescription)
                .font(.system(size: 12))
                .foregroundStyle(Brand.fg)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("decisionRouting.confidenceNote", Self.confidenceText(confidence)))
                .font(.system(size: 11))
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L10n.string("decisionRouting.continue"), action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L10n.string("decisionRouting.changeChannel"), action: onChangeChannel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer(minLength: 0)
                cancelButton
            }
            Text(L10n.string("decisionRouting.confirmHint"))
                .font(.system(size: 10))
                .foregroundStyle(Brand.muted)
        }
    }

    private func choosing(reason: DecisionChooseReason, highlightedID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("decisionRouting.chooseTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.fg)
                Spacer(minLength: 0)
                cancelButton
            }
            Text(reasonText(reason))
                .font(.system(size: 11))
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(candidates) { candidate in
                Button {
                    onSelect(candidate.id)
                } label: {
                    HStack(spacing: 8) {
                        routeIcon(candidate)
                        Text(candidate.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Brand.fg)
                        Spacer(minLength: 0)
                        if candidate.id == highlightedID {
                            Text(L10n.string("decisionRouting.enterTarget"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Brand.muted)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        candidate.id == highlightedID ? Brand.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text(L10n.string("decisionRouting.cancel"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.muted)
        }
        .buttonStyle(.plain)
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
