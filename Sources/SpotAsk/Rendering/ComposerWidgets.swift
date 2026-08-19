import AppKit
import SwiftUI
import UniformTypeIdentifiers
// MARK: - Empty-state preset strip

/// One-tap preset chips shown only before the first message. Tapping selects
/// the preset, highlights the chip, and hands focus back to the input.
struct PresetStripView: View { let presets: [PromptPreset]
@Binding var selection: PromptPreset?
let showsShortcutHints: Bool
let shortcutForPreset: (PromptPreset) -> InAppShortcut?
let onSelect: (PromptPreset) -> Void

var body: some View {
    GeometryReader { geometry in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    ChipView(
                        title: preset.title,
                        icon: preset.symbolName,
                        isSelected: selection?.id == preset.id,
                        shortcut: showsShortcutHints ? shortcutForPreset(preset) : nil
                    ) {
                        onSelect(preset)
                    }
                }
            }
            // A horizontal ScrollView lays out short content at its leading
            // edge. Match the viewport width so the chip group is centered
            // until it needs to scroll.
            .frame(minWidth: geometry.size.width, alignment: .center)
        }
        .scrollClipDisabled()
    }
    .frame(maxWidth: 460)
    .frame(height: 38)
} }

private struct ChipView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let shortcut: InAppShortcut?
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.white : (isHovering ? Brand.fg : Brand.muted))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Brand.accent : Brand.surface)
            )
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? Brand.accent : (isHovering ? Brand.muted : Brand.border),
                    lineWidth: 1
                )
            }
            .overlay {
                if isFocused, !isSelected {
                    Capsule().strokeBorder(Brand.accent, lineWidth: 2).padding(-2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            ShortcutKeycap(shortcut: shortcut)
                .allowsHitTesting(false)
                .offset(x: 5, y: 5)
        }
        .zIndex(shortcut == nil ? 0 : 1)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .help(L10n.string("chat.usePrompt", title))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - In-conversation preset trigger + popover

/// The 36×36 circular trigger shown once a conversation has started. It opens
/// an upward popover listing "直接提问" plus every preset; the current item
/// carries a check. Selecting applies immediately and closes.
struct PresetPopoverTrigger: View { let presets: [PromptPreset]
@Binding var selection: PromptPreset?
@Binding var isPresented: Bool
let showsShortcutHints: Bool
let shortcutForPreset: (PromptPreset) -> InAppShortcut?
let onSelect: (PromptPreset?) -> Void

@State private var isHovering = false
@FocusState private var isFocused: Bool

private var hasSelection: Bool { selection != nil }

var body: some View {
    Button {
        isPresented.toggle()
    } label: {
        Image(systemName: "sparkles")
            .font(.system(size: 16))
            .foregroundStyle(hasSelection ? Brand.accent : (isHovering ? Brand.fg : Brand.muted))
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(isHovering || isPresented ? Brand.surface : Brand.bg)
            )
            .overlay {
                Circle().strokeBorder(hasSelection ? Brand.accent : Brand.border, lineWidth: 1)
            }
            .overlay {
                if isFocused {
                    Circle().strokeBorder(Brand.accent, lineWidth: 2).padding(-2)
                }
            }
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .focused($isFocused)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
    .help(L10n.string("chat.selectPrompt"))
    .accessibilityLabel(L10n.string("chat.selectPrompt"))
    .accessibilityValue(hasSelection ? selection!.title : L10n.string("chat.directQuestion"))
    .background(
        PopoverOutsideClickMonitor(isPresented: $isPresented)
    )
    .popover(
        isPresented: $isPresented,
        attachmentAnchor: .point(.top),
        arrowEdge: .bottom
    ) {
        PresetPopoverContent(
            presets: presets,
            selection: selection,
            showsShortcutHints: showsShortcutHints,
            shortcutForPreset: shortcutForPreset
        ) { preset in
            isPresented = false
            onSelect(preset)
        }
    }
} }

private struct PresetPopoverContent: View {
    let presets: [PromptPreset]
    let selection: PromptPreset?
    let showsShortcutHints: Bool
    let shortcutForPreset: (PromptPreset) -> InAppShortcut?
    let onChoose: (PromptPreset?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverRow(
                title: L10n.string("chat.directQuestion"),
                icon: "text.bubble",
                isSelected: selection == nil
            ) {
                onChoose(nil)
            }
            Divider().padding(.vertical, 4).padding(.horizontal, 6)
            ForEach(presets) { preset in
                PopoverRow(
                    title: preset.title,
                    icon: preset.symbolName,
                    isSelected: selection?.id == preset.id,
                    shortcut: showsShortcutHints ? shortcutForPreset(preset) : nil
                ) {
                    onChoose(preset)
                }
            }
        }
        .padding(5)
        .frame(minWidth: 180)
        .fixedSize()
    }
}

private struct PopoverRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var shortcut: InAppShortcut? = nil
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.fg)
                Spacer(minLength: 8)
                ShortcutKeycap(shortcut: shortcut)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(isHovering ? Brand.surface : Color.clear)
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.accent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Circular send / stop button

/// The 36×36 circular anchor of the composer. Accent when sending, near-black
/// when generating; hover darkens via the oklch-equivalent `darker`.
struct ComposerSendButton: View { let isGenerating: Bool
let canSend: Bool
let shortcut: InAppShortcut?
let action: () -> Void

@State private var isHovering = false
@FocusState private var isFocused: Bool

private var isEnabled: Bool { isGenerating || canSend }

private var fill: Color {
    let base = isGenerating ? Brand.fg : Brand.accent
    guard isHovering, isEnabled else { return base }
    return base.darker(isGenerating ? 0.05 : 0.08)
}

var body: some View {
    Button(action: action) {
        Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(fill))
            .overlay {
                if isFocused {
                    Circle().strokeBorder(Brand.accent, lineWidth: 2).padding(-3)
                }
            }
            .contentShape(Circle())
    }
    .buttonStyle(CircularPressButtonStyle())
    .focused($isFocused)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.35)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: fill)
    .help(isGenerating ? L10n.string("chat.stop") : L10n.string("chat.send"))
    .accessibilityLabel(isGenerating ? L10n.string("chat.stop") : L10n.string("chat.send"))
    .overlay(alignment: .bottomTrailing) {
        ShortcutKeycap(shortcut: shortcut)
            .offset(x: 5, y: 5)
    }
} }

/// Nudges the circle down 1pt while pressed, mirroring the prototype's
/// `:active { transform: translateY(1px) }`.
private struct CircularPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

// MARK: - Selected preset badge

struct SelectedPresetBadge: View { let title: String
let icon: String
let onClear: () -> Void

@State private var isClearHovering = false
@FocusState private var isClearFocused: Bool

var body: some View {
    HStack(spacing: 5) {
        Image(systemName: icon)
            .font(.system(size: 11))
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
        Button(action: onClear) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isClearHovering ? Brand.fg : Brand.muted)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(isClearHovering ? Brand.surface : Color.clear)
                )
                .overlay {
                    if isClearFocused {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Brand.accent, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isClearFocused)
        .onHover { isClearHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isClearHovering)
        .help(L10n.string("chat.clearPrompt"))
        .accessibilityLabel(L10n.string("chat.clearPrompt"))
    }
    .foregroundStyle(Brand.accent)
    .accessibilityElement(children: .contain)
} }

// MARK: - Click-outside-to-close for the preset popover

/// Installs a local event monitor while the popover is open. A left or right
/// mouse-down outside the popover's window closes it (the click also proceeds
/// to its target); clicks inside the popover pass through untouched. `esc`
/// closes separately via the composer's existing escape handling.
private struct PopoverOutsideClickMonitor: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.updateMonitoring(anchor: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.updateMonitoring(anchor: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var isPresented: Binding<Bool>
        private weak var anchor: NSView?
        private var monitor: Any?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        @MainActor
        func updateMonitoring(anchor: NSView) {
            self.anchor = anchor
            if isPresented.wrappedValue {
                start()
            } else {
                stop()
            }
        }

        @MainActor
        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.isPresented.wrappedValue else { return event }
                if let anchor = self.anchor,
                   let eventWindow = event.window,
                   let anchorWindow = anchor.window,
                   eventWindow != anchorWindow {
                    // The click landed in another window of this app — the
                    // transient popover window. Let it through without closing.
                    return event
                }
                self.isPresented.wrappedValue = false
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
// MARK: - Attachment picker button

struct AttachmentPickerButton: View { let action: () -> Void

@State private var isHovering = false

var body: some View {
    Button(action: action) {
        Image(systemName: "paperclip")
            .font(.system(size: 15))
            .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(isHovering ? Brand.surface : Brand.bg)
            )
            .overlay {
                Circle().strokeBorder(Brand.border, lineWidth: 1)
            }
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
    .help(L10n.string("chat.attachmentPicker"))
    .accessibilityLabel(L10n.string("chat.attachmentPicker"))
} }

// MARK: - Attachment chips

/// Draft attachment chip in the composer with a remove affordance.
struct AttachmentChip: View { let attachment: ChatAttachment
let onRemove: () -> Void

@State private var isHovering = false

private var thumbnail: NSImage? {
    if case let .image(data) = attachment.payload {
        return NSImage(data: data)
    }
    return nil
}

private var symbolName: String {
    attachment.kind == .code ? "chevron.left.forwardslash.chevron.right" : "doc.text"
}

var body: some View {
    HStack(spacing: 5) {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 18, height: 18)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        Text(attachment.filename)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Brand.fg)
            .lineLimit(1)
            .truncationMode(.middle)
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
                .frame(width: 12, height: 12)
                .background(
                    Circle().fill(isHovering ? Brand.surface : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(L10n.string("chat.removeAttachment"))
        .accessibilityLabel(L10n.string("chat.removeAttachment"))
    }
    .padding(.leading, 5)
    .padding(.trailing, 3)
    .padding(.vertical, 2)
    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 6))
    .overlay {
        RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.border, lineWidth: 0.5)
    }
    .help(attachmentTooltip)
    .onHover { isHovering = $0 }
    .accessibilityLabel(attachment.filename)
}

private var attachmentTooltip: String {
    if attachment.isTruncated {
        return L10n.string("chat.attachmentTruncated", "\(AttachmentLimits.maxExtractedTextPerAttachment)")
    }
    return attachment.filename
} }

/// Read-only attachment chip shown inside a sent user message.
struct MessageAttachmentThumbnail: View { let attachment: ChatAttachment

private var thumbnail: NSImage? {
    if case let .image(data) = attachment.payload {
        return NSImage(data: data)
    }
    return nil
}

private var symbolName: String {
    attachment.kind == .code ? "chevron.left.forwardslash.chevron.right" : "doc.text"
}

var body: some View {
    HStack(spacing: 5) {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 18, height: 18)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        Text(attachment.filename)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Brand.fg)
            .lineLimit(1)
    }
    .help(attachment.filename)
    .accessibilityLabel(attachment.filename)
} }
