import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ComposerTextViewReference {
    weak var textView: NSTextView?
}

@MainActor
struct ChatComposerView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let isGenerating: Bool
    let pendingExternalAskID: UUID?
    let badge: ComposerModeBadge?
    let placeholderText: String
    let showsShortcutHints: Bool
    @FocusState.Binding var inputFocused: Bool
    @Binding var inputHeight: CGFloat
    @Binding var isPresetPopoverPresented: Bool
    let isAtPalettePresented: Bool
    let composerTextView: ComposerTextViewReference
    let shortcutHint: (InAppShortcutTarget) -> InAppShortcut?
    let onApplyPreset: (PromptPreset?) -> Void
    let onSelectExternalAsk: (QuickAction) -> Void
    let onSend: () -> Bool
    let onEscape: () -> Void
    let onPresentAttachmentPicker: () -> Void
    let onClearComposerModeSelection: () -> Void
    let onAtCommandStateChanged: (AtCommandState?) -> Void
    let onAtCommandMoveHighlight: (Int) -> Void
    let onAtCommandConfirm: () -> Void
    var onTab: (Bool) -> Bool = { _ in false }
    let onPrimaryAction: () -> Void
    var routingPhase: DecisionRoutingPhase = .idle
    var routingCandidates: [DecisionRouteCandidate] = []
    var onAcceptRoute: () -> Void = {}
    var onChangeRoute: () -> Void = {}
    var onSelectRoute: (String) -> Void = { _ in }
    var onCancelRoute: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !viewModel.pendingAttachments.isEmpty {
                attachmentStrip
            }
            if routingPhase.isActive {
                DecisionRoutingCard(
                    phase: routingPhase,
                    candidates: routingCandidates,
                    onAccept: onAcceptRoute,
                    onChangeChannel: onChangeRoute,
                    onSelect: onSelectRoute,
                    onCancel: onCancelRoute
                )
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if !viewModel.messages.isEmpty {
                    PresetPopoverTrigger(
                        presets: settings.enabledPromptPresets,
                        selection: $viewModel.selectedPromptPreset,
                        actions: settings.enabledQuickActions,
                        selectedActionID: pendingExternalAskID,
                        isPresented: $isPresetPopoverPresented,
                        showsShortcutHints: showsShortcutHints,
                        shortcutForPreset: { shortcutHint(.promptPreset($0.id)) },
                        shortcutForAction: { shortcutHint(.quickAction($0.id)) },
                        onSelect: onApplyPreset,
                        onSelectAction: onSelectExternalAsk
                    )
                    .transition(.opacity)
                }
                AttachmentPickerButton(action: onPresentAttachmentPicker)
                VStack(alignment: .leading, spacing: 6) {
                    if let badge {
                        SelectedPresetBadge(
                            title: badge.title,
                            icon: badge.icon,
                            brandIconSlug: badge.brandIconSlug,
                            onClear: onClearComposerModeSelection
                        )
                    }
                    ChatInputTextView(
                        text: $viewModel.input,
                        isFocused: $inputFocused,
                        height: $inputHeight,
                        isGenerating: isGenerating,
                        onSubmit: onSend,
                        onEscape: onEscape,
                        onPasteImage: { data in
                            Task { await viewModel.addScreenshot(data) }
                        },
                        onPasteFiles: { urls in
                            Task { @MainActor in
                                for url in urls {
                                    await viewModel.addAttachment(from: url)
                                }
                            }
                        },
                        onTextViewReady: { composerTextView.textView = $0 },
                        onRecall: { viewModel.recallLastQuestion() },
                        onAtCommandStateChanged: onAtCommandStateChanged,
                        isAtPalettePresented: isAtPalettePresented,
                        onAtCommandMoveHighlight: onAtCommandMoveHighlight,
                        onAtCommandConfirm: onAtCommandConfirm,
                        onTab: onTab
                    )
                    .frame(height: inputHeight)
                    .animation(.easeOut(duration: 0.12), value: inputHeight)
                    .background(inputFocused ? Brand.bg : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(inputFocused ? Brand.accent : Brand.border, lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Brand.accent.opacity(0.15), lineWidth: 6)
                            .blur(radius: 4)
                            .opacity(inputFocused ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topLeading) {
                        if viewModel.input.isEmpty {
                            Text(placeholderText)
                                .foregroundStyle(Brand.muted)
                                .padding(.leading, 14)
                                .padding(.top, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        ShortcutKeycap(shortcut: shortcutHint(.operation(.focusInput)))
                            .padding(8)
                    }
                    .animation(.easeOut(duration: 0.12), value: inputFocused)
                }
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.12), value: badge)
                ComposerSendButton(
                    isGenerating: isGenerating,
                    canSend: viewModel.canSend,
                    shortcut: shortcutHint(.operation(.sendOrCancel)),
                    action: onPrimaryAction
                )
            }
        }
        .animation(.easeOut(duration: 0.12), value: routingPhase)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.pendingAttachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        viewModel.removeAttachment(id: attachment.id)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(L10n.string("chat.attachments"))
    }
}
