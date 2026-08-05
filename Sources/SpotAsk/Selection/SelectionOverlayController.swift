import AppKit
import SwiftUI

@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayControlling {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func showActions(snapshot: SelectedTextSnapshot, presets: [PromptPreset], onSelect: @escaping (PromptPreset) -> Void) {
        dismissWorkItem?.cancel()
        let content = SelectionActionBarView(presets: presets, onSelect: onSelect)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let panel = makePanel(size: size)
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: panelOrigin(for: snapshot.anchor, size: size), size: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func showMessage(_ message: SelectionFeedback) {
        let content = Text(message.title).font(.callout).padding(.horizontal, 12).padding(.vertical, 8)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let panel = makePanel(size: size)
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: NSEvent.mouseLocation, size: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }

    private func panelOrigin(for anchor: SelectionAnchor, size: NSSize) -> NSPoint {
        let point: NSPoint
        switch anchor {
        case let .selectionRect(rect), let .elementRect(rect): point = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        case let .pointer(pointValue): point = NSPoint(x: pointValue.x + 8, y: pointValue.y - size.height - 8)
        }
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return point }
        return NSPoint(x: min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8), y: min(max(point.y, visible.minY + 8), visible.maxY - size.height - 8))
    }
}

private extension SelectionFeedback {
    var title: String {
        switch self {
        case .permissionDenied: "需要允许 SpotAsk 读取你主动选中的文字。"
        case .noSelection: "请先选中文字，再试一次。"
        case .unsupported: "无法读取这个应用中的选中文字。"
        case .temporaryFailure: "暂时无法读取选中的文字，请重试。"
        case .selectionChanged: "选区已改变，请重新触发。"
        case .sensitiveField: "无法处理安全输入区域中的内容。"
        }
    }
}
