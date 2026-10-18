import AppKit
import Foundation
import SwiftUI

// MARK: - Skeuomorphic Mac Keycap Components

struct MacKeycapBadge: View {
    let label: String
    var hasConflict: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold, design: .default))
            .foregroundStyle(hasConflict ? Color.red : Color.primary.opacity(0.88))
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3)
            .frame(minWidth: 22, minHeight: 22)
            .background {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.14), radius: 0.5, x: 0, y: 1.0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(hasConflict ? Color.red.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: 0.75)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    .padding(0.5)
            }
    }
}

struct MacKeycapBadgeGroup: View {
    let shortcut: InAppShortcut
    var hasConflict: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InAppShortcutDisplay.labels(for: shortcut), id: \.self) { label in
                MacKeycapBadge(label: label, hasConflict: hasConflict)
            }
        }
    }
}

struct ShortcutKeycapRecordingView: View {
    let shortcut: InAppShortcut?
    let isCapturing: Bool
    let hasConflict: Bool

    var body: some View {
        ZStack {
            if isCapturing {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.accent)
                    Text(L10n.string("settings.shortcutRecording"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Brand.accent)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Brand.accent.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.accent, lineWidth: 1.5)
                }
            } else if let shortcut {
                MacKeycapBadgeGroup(shortcut: shortcut, hasConflict: hasConflict)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(hasConflict ? Color.red.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(hasConflict ? Color.red : Color.primary.opacity(0.12), lineWidth: hasConflict ? 1.5 : 0.8)
                    }
            } else {
                Text(L10n.string("settings.shortcutUnassigned"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Shortcut Recorder View Representable

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: InAppShortcut?
    var hasConflict: Bool = false
    let onRecord: (InAppShortcut) -> Void
    let onInvalid: () -> Void
    var allowsSpace: Bool = false

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.setAccessibilityRole(.button)
        field.setAccessibilityLabel(L10n.string("settings.shortcuts"))
        field.onRecord = onRecord
        field.onInvalid = onInvalid
        field.allowsSpace = allowsSpace
        field.update(shortcut: shortcut, hasConflict: hasConflict)
        return field
    }

    func updateNSView(_ field: ShortcutRecorderField, context: Context) {
        field.update(shortcut: shortcut, hasConflict: hasConflict)
        field.onRecord = onRecord
        field.onInvalid = onInvalid
        field.allowsSpace = allowsSpace
    }
}

// MARK: - Shortcut Recorder Field (AppKit Integration)

final class ShortcutRecorderField: NSView {
    var onRecord: ((InAppShortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var allowsSpace = false
    private var monitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var displayedShortcut: InAppShortcut?
    private var isCapturing = false
    private var hasConflict = false
    private var hostingView: NSHostingView<ShortcutKeycapRecordingView>?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            removeMonitor()
            removeWindowObservers()
        }
    }

    private func setupHostingView() {
        let rootView = ShortcutKeycapRecordingView(
            shortcut: displayedShortcut,
            isCapturing: isCapturing,
            hasConflict: hasConflict
        )
        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hostingView = host
    }

    private func updateHostingView() {
        hostingView?.rootView = ShortcutKeycapRecordingView(
            shortcut: displayedShortcut,
            isCapturing: isCapturing,
            hasConflict: hasConflict
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        startCapturing()
    }

    func update(shortcut: InAppShortcut?, hasConflict: Bool = false) {
        displayedShortcut = shortcut
        self.hasConflict = hasConflict
        updateHostingView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        removeWindowObservers()
        guard let window else { return }
        windowObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.installMonitorIfNeeded()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopCapturing()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeMonitor()
                }
            }
        ]
        installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil, isCapturing, window?.isKeyWindow == true else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isCapturing, self.window?.isKeyWindow == true else { return event }
            return self.handleCaptureEvent(event)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        stopCapturing()
        return result
    }

    private func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        updateHostingView()
        window?.makeFirstResponder(self)
        installMonitorIfNeeded()
    }

    private func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false
        removeMonitor()
        updateHostingView()
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        _ = handleCaptureEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else {
            return super.performKeyEquivalent(with: event)
        }
        _ = handleCaptureEvent(event)
        return true
    }

    private func handleCaptureEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            return nil
        }
        if ShortcutRecorderEventParser.isCancelKey(event) {
            stopCapturing()
            return nil
        }
        guard let shortcut = ShortcutRecorderEventParser.shortcut(from: event, allowsSpace: allowsSpace) else {
            onInvalid?()
            NSSound.beep()
            return nil
        }
        stopCapturing()
        onRecord?(shortcut)
        return nil
    }
}

// MARK: - Shortcut Recorder Event Parser

enum ShortcutRecorderEventParser {
    static func shortcut(from event: NSEvent, allowsSpace: Bool = false) -> InAppShortcut? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var shortcutModifiers: InAppShortcutModifiers = []
        if modifiers.contains(.command) { shortcutModifiers.insert(.command) }
        if modifiers.contains(.shift) { shortcutModifiers.insert(.shift) }
        if modifiers.contains(.option) { shortcutModifiers.insert(.option) }
        if modifiers.contains(.control) { shortcutModifiers.insert(.control) }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        let shortcut = InAppShortcut(key: key, modifiers: shortcutModifiers)
        return (shortcut.isSupported || (allowsSpace && shortcut.isSupportedGlobalShortcut)) ? shortcut : nil
    }

    static func isCancelKey(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == 53
    }
}
