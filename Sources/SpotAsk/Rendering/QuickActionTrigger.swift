import AppKit
import Foundation
import SwiftUI

// MARK: - Action Execution Abstraction

enum ResolvedQuickAction: Equatable, Sendable {
    case url(URL)
    case terminalCommand(String)
}

protocol QuickActionExecuting: Sendable {
    @MainActor
    func perform(_ resolved: ResolvedQuickAction) -> Bool
}

struct DefaultQuickActionExecutor: QuickActionExecuting {
    init() {}

    @MainActor
    func perform(_ resolved: ResolvedQuickAction) -> Bool {
        switch resolved {
        case let .url(url):
            return NSWorkspace.shared.open(url)
        case let .terminalCommand(command):
            return Self.openInTerminal(command: command)
        }
    }

    /// Writes command to a temporary .command file, makes it executable, and opens it with Terminal.app.
    @MainActor
    static func openInTerminal(command: String) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptName = "spotask-\(UUID().uuidString).command"
        let scriptURL = tempDir.appendingPathComponent(scriptName)

        let scriptContent = """
        #!/bin/bash
        \(command)
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: scriptURL.path)
        } catch {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Unified Quick Action Trigger Pipeline

@MainActor
final class QuickActionTrigger {
    let isSessionEmpty: () -> Bool
    let isGenerating: () -> Bool
    let currentInput: () -> String
    let clearInput: () -> Void
    let resolveAction: (UUID) -> QuickAction?
    let closePanel: () -> Void
    let executor: any QuickActionExecuting
    private(set) var isExecutingQuickAction: Bool = false
    private nonisolated(unsafe) var panelShowObserver: (any NSObjectProtocol)?

    init(
        isSessionEmpty: @escaping () -> Bool,
        isGenerating: @escaping () -> Bool,
        currentInput: @escaping () -> String,
        clearInput: @escaping () -> Void = {},
        resolveAction: @escaping (UUID) -> QuickAction?,
        closePanel: @escaping () -> Void,
        executor: any QuickActionExecuting = DefaultQuickActionExecutor(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.isSessionEmpty = isSessionEmpty
        self.isGenerating = isGenerating
        self.currentInput = currentInput
        self.clearInput = clearInput
        self.resolveAction = resolveAction
        self.closePanel = closePanel
        self.executor = executor
        // The panel hides via orderOut and re-shows by re-presenting the same
        // view, so SwiftUI onAppear only fires once. The panel controller posts
        // spotAskPanelDidShow on every presentation; that is the correct reset
        // point for the session-scoped duplicate-trigger guard.
        panelShowObserver = notificationCenter.addObserver(
            forName: .spotAskPanelDidShow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetForNewPanelPresentation()
            }
        }
    }

    deinit {
        if let panelShowObserver {
            NotificationCenter.default.removeObserver(panelShowObserver)
        }
    }

    /// Resets the session-scoped duplicate-trigger guard when a panel is re-presented.
    func resetForNewPanelPresentation() {
        isExecutingQuickAction = false
    }

    /// Triggers Quick Action for the given action ID following the execution pipeline.
    /// Returns `true` if the trigger was accepted and opened, `false` otherwise.
    @discardableResult
    func trigger(actionID: UUID) -> Bool {
        // 1. 确认当前仍处于现有 PresetStrip 所定义的空会话状态
        guard isSessionEmpty() else { return false }

        // 2. 确认当前没有正在发送/生成的会话动作
        guard !isGenerating() else { return false }

        // 3. 确认本次面板展示尚未成功触发
        guard !isExecutingQuickAction else { return false }

        // 4. 根据 actionID 从 AppSettings.enabledQuickAction(id:) 重新解析最新 action
        guard let action = resolveAction(actionID) else { return false }

        // 5. snapshot 当前 input
        let input = currentInput()

        // 6. 根据 kind 解析 resolved action (空 query / 无效模板会返回 nil，自然 no-op)
        let resolved: ResolvedQuickAction?
        switch action.kind {
        case let .web(urlTemplate), let .uriScheme(urlTemplate):
            if let url = QuickActionBuilder.makeURL(template: urlTemplate, query: input) {
                resolved = .url(url)
            } else {
                resolved = nil
            }
        case let .terminal(commandTemplate):
            if let cmd = QuickActionBuilder.makeTerminalCommand(template: commandTemplate, query: input) {
                resolved = .terminalCommand(cmd)
            } else {
                resolved = nil
            }
        }

        guard let target = resolved else {
            return false
        }

        // 7. 设置 session-scoped isExecutingQuickAction = true
        isExecutingQuickAction = true

        // 8. 调用 executor
        let success = executor.perform(target)

        if !success {
            // 9. 如果 executor 返回 false：清除 guard，保留面板，不修改 input/messages，允许重试
            isExecutingQuickAction = false
            return false
        }

        // 10. 如果 executor 返回 true：清除输入框，调用 closePanel()，本次面板展示期间保持 duplicate-trigger guard
        clearInput()
        closePanel()
        return true
    }
}

// MARK: - Empty-state Quick Action Strip & Chip

struct QuickActionStripView: View {
    let actions: [QuickAction]
    let showsShortcutHints: Bool
    let shortcutForAction: (QuickAction) -> InAppShortcut?
    let onSelect: (QuickAction) -> Void

    init(
        actions: [QuickAction],
        showsShortcutHints: Bool,
        shortcutForAction: @escaping (QuickAction) -> InAppShortcut?,
        onSelect: @escaping (QuickAction) -> Void
    ) {
        self.actions = actions
        self.showsShortcutHints = showsShortcutHints
        self.shortcutForAction = shortcutForAction
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        QuickActionChipView(
                            title: action.displayName,
                            icon: action.symbolName,
                            brandIconSlug: action.brandIconSlug,
                            shortcut: showsShortcutHints ? shortcutForAction(action) : nil
                        ) {
                            onSelect(action)
                        }
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .center)
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: 460)
        .frame(height: 38)
    }
}

struct QuickActionChipView: View {
    let title: String
    let icon: String
    var brandIconSlug: String? = nil
    let shortcut: InAppShortcut?
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    init(
        title: String,
        icon: String,
        brandIconSlug: String? = nil,
        shortcut: InAppShortcut?,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.brandIconSlug = brandIconSlug
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ProviderBrandIconView(
                    slug: brandIconSlug,
                    size: 13,
                    fallbackSymbol: icon
                )
                .frame(width: 14, height: 14)
                .foregroundStyle(isHovering || isFocused ? Color.primary : Color.secondary)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isHovering || isFocused ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.9 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor : Color.primary.opacity(isHovering ? 0.2 : 0.1),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            ShortcutKeycap(shortcut: shortcut)
                .offset(x: 5, y: 5)
        }
        .zIndex(shortcut == nil ? 0 : 1)
        .focusable()
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .help(shortcut.map { "\(title) (\(InAppShortcutDisplay.labels(for: $0).joined()))" } ?? title)
        .accessibilityLabel(title)
    }
}
