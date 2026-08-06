import Observation
import SwiftUI

@MainActor
@Observable
final class StatusToastCenter {
    static let shared = StatusToastCenter()

    private(set) var items: [StatusToastItem] = []
    private var dismissalTasks: [UUID: Task<Void, Never>] = [:]

    static let displayDuration: Duration = .milliseconds(2_400)

    func show(_ message: String, isError: Bool = false) {
        let item = StatusToastItem(message: message, isError: isError)
        items.append(item)
        if items.count > 3 {
            items.removeFirst(items.count - 3)
        }
        dismissalTasks[item.id]?.cancel()
        dismissalTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss(item.id)
        }
    }

    func dismiss(_ id: UUID) {
        dismissalTasks[id]?.cancel()
        dismissalTasks[id] = nil
        items.removeAll { $0.id == id }
    }
}

struct StatusToastItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

struct StatusToastOverlay: View {
    @Bindable var center: StatusToastCenter

    init(center: StatusToastCenter = .shared) {
        self.center = center
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.items) { item in
                StatusToastCard(item: item) {
                    center.dismiss(item.id)
                }
            }
        }
        .padding(12)
        .animation(.easeOut(duration: 0.18), value: center.items)
        .allowsHitTesting(center.items.isEmpty ? false : true)
    }
}

private struct StatusToastCard: View {
    let item: StatusToastItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(item.isError ? .red : .green)
                .font(.system(size: 13, weight: .medium))
            Text(item.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: 220, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 18)
            .accessibilityLabel(Text(L10n.string("status.dismiss")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
