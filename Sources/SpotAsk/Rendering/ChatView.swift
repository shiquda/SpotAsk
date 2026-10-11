import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let settings: AppSettings
    let decisionKeyStore: any APIKeyStoring
    let onDismiss: () -> Void
    let commandCenter: SpotAskCommandCenter
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollFollowState = ScrollFollowState()
    @State private var inputHeight = ChatInputTextView.minHeight
    @State private var composerTextView = ComposerTextViewReference()
    @State private var reconciliationCoordinator = ChatReconciliationCoordinator()
    @State private var isPresetPopoverPresented = false
    @State private var isModelPickerPresented = false
    @State private var isDropTargeted = false
    @State private var showsShortcutHints = false
    @State private var shortcutDispatcher: InAppShortcutDispatcher?
    @State private var chatWindowReference = ChatWindowReference()
    @State private var copiedMessageID: UUID?
    @State private var copyFeedbackToken = UUID()
    private let selectionReplacementWriter: any SelectionReplacementWriting = AccessibilitySelectionReplacementWriter()
    @State private var atCommandState: AtCommandState?
    @State private var atCommandSuppressed = false
    @State private var atCommandHighlightedIndex = 0
    @State private var composerModeCoordinator = ComposerModeCoordinator()
    @State private var routingController = DecisionRoutingController()
    @State private var isPanelVisible = true

    init(
        viewModel: ChatViewModel,
        settings: AppSettings,
        decisionKeyStore: any APIKeyStoring = UnavailableAPIKeyStore(),
        onDismiss: @escaping () -> Void = { NSApp.keyWindow?.orderOut(nil) },
        commandCenter: SpotAskCommandCenter = .shared
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.decisionKeyStore = decisionKeyStore
        self.onDismiss = onDismiss
        self.commandCenter = commandCenter
    }

    var body: some View {
        styledContent
            .onChange(of: viewModel.messages) { _, messages in
                reconciliationCoordinator.reconcile(
                    messages: messages,
                    prefersExpanded: settings.defaultExpandReasoning
                )
            }
            .onChange(of: settings.promptPresets) { _, _ in
                synchronizeSelectedPromptPreset()
            }
            .onChange(of: isPresetPopoverPresented) { _, presented in
                if presented { dismissAtCommandPalette() }
            }
            .onChange(of: inputFocused) { _, focused in
                if !focused { dismissAtCommandPalette() }
            }
            .onChange(of: viewModel.input) { oldValue, newValue in
                clearPendingExternalAskIfInputEmptied(from: oldValue, to: newValue)
                routingController.noteInput(newValue)
            }
            .onChange(of: routingController.pendingExecution) { _, candidate in
                guard let candidate else { return }
                routingController.clearPendingExecution()
                _ = executeDecisionRoute(candidate)
            }
    }

    /// The window chrome plus every lifecycle observer, kept separate from the
    /// observer-only tail in `body` so the type-checker sees a smaller expression.
    private var styledContent: some View {
        windowChrome
            .font(contentFont)
            .environment(\.dynamicTypeSize, settings.interfaceZoomLevel.dynamicTypeSize)
            .preferredColorScheme(colorScheme)
            .overlay(alignment: .topTrailing) {
                StatusToastOverlay()
                    .padding(.top, 36)
            }
            .environment(\.locale, settings.language.locale)
    }

    private var windowChrome: some View {
        coreLayout
            .onChange(of: isModelPickerPresented) { _, isPresented in
                if !isPresented {
                    inputFocused = true
                }
            }
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
                if (notification.object as? NSWindow) === chatWindowReference.window {
                    showsShortcutHints = false
                    dismissAtCommandPalette()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                showsShortcutHints = false
                dismissAtCommandPalette()
            }
            .onReceive(NotificationCenter.default.publisher(for: .spotAskPanelDidShow)) { _ in
                isPanelVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .spotAskPanelDidHide)) { _ in
                isPanelVisible = false
                dismissAtCommandPalette()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
                if let window = notification.object as? NSWindow, window === chatWindowReference.window {
                    isPanelVisible = window.occlusionState.contains(.visible) && window.isVisible
                }
            }
            .onExitCommand(perform: handleEscape)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Brand.accent, lineWidth: 1.5)
                        .background(Brand.accent.opacity(0.06))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDroppedProviders(providers)
                return true
            }
            .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }

    private var coreLayout: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                modelName: viewModel.effectiveModel?.displayName ?? "",
                providerIconSlug: effectiveProviderIconSlug,
                isGenerating: isGenerating,
                isKeepWindowOnTop: settings.keepWindowOnTop,
                providerCatalog: settings.providerRegistry.catalog,
                effectiveModelID: viewModel.effectiveModelID,
                hasSessionOverride: viewModel.sessionModelID != nil,
                isModelPickerPresented: $isModelPickerPresented,
                onToggleWindowOnTop: { SpotAskCommandCenter.shared.toggleWindowOnTop() },
                onShowSettings: { commandCenter.showSettings() },
                onNewConversation: newConversation,
                onSelectSessionModel: { id in
                    viewModel.selectSessionModel(id: id)
                    isModelPickerPresented = false
                    inputFocused = true
                },
                onUseDefaultModel: {
                    viewModel.useDefaultModel()
                    isModelPickerPresented = false
                    inputFocused = true
                },
                shortcutHint: shortcutHint(for:)
            )
            // A single hairline separates the elevated header material from
            // the content below. The composer reads as part of the window's
            // bottom chrome, so it is not boxed in by a second divider.
            Divider()
            ZStack(alignment: .bottom) {
                conversationList
                atCommandPaletteOverlay
            }
            composerView
        }
        // Content spans the full window; the header's Material draws the
        // chrome and the conversation insets clear of it (see below).
        .ignoresSafeArea()
        .frame(minWidth: 364, minHeight: 320)
        .background(ChatWindowReader(reference: chatWindowReference))
    }

    private var conversationList: some View {
        ChatMessageListView(
            viewModel: viewModel,
            settings: settings,
            reconciliationCoordinator: reconciliationCoordinator,
            pendingExternalAskID: composerModeCoordinator.pendingExternalAsk?.id,
            isPanelVisible: isPanelVisible,
            showsShortcutHints: showsShortcutHints,
            reduceMotion: reduceMotion,
            scrollFollowState: $scrollFollowState,
            copiedMessageID: copiedMessageID,
            onApplyPreset: { applyPreset($0) },
            onSelectExternalAsk: selectExternalAsk,
            onRetryWithExternalAsk: retryWithExternalAsk,
            onInsertSelection: insertSelection,
            onCopyMessage: copyMessage,
            onRestoreSession: {
                viewModel.restoreSession()
                inputFocused = true
            },
            onRetryLatestAnswerWithModel: retryLatestAnswer,
            onRetryLatestAnswerWithDefaultModel: retryLatestAnswerWithDefaultModel,
            shortcutHint: shortcutHint(for:)
        )
    }

    private var composerView: some View {
        ChatComposerView(
            viewModel: viewModel,
            settings: settings,
            isGenerating: isGenerating,
            pendingExternalAskID: composerModeCoordinator.pendingExternalAsk?.id,
            badge: activeComposerBadge,
            placeholderText: placeholderText,
            showsShortcutHints: showsShortcutHints,
            inputFocused: $inputFocused,
            inputHeight: $inputHeight,
            isPresetPopoverPresented: $isPresetPopoverPresented,
            isAtPalettePresented: atCommandState != nil,
            composerTextView: composerTextView,
            shortcutHint: shortcutHint(for:),
            onApplyPreset: { applyPreset($0) },
            onSelectExternalAsk: selectExternalAsk,
            onSend: sendFromComposer,
            onEscape: handleEscape,
            onPresentAttachmentPicker: presentAttachmentPicker,
            onClearComposerModeSelection: clearComposerModeSelection,
            onAtCommandStateChanged: handleAtCommandStateChanged,
            onAtCommandMoveHighlight: moveAtCommandHighlight,
            onAtCommandConfirm: confirmAtCommandSelection,
            onPrimaryAction: primaryAction,
            routingPhase: routingController.phase,
            routingCandidates: routingController.candidates,
            onAcceptRoute: { routingController.acceptCurrent() },
            onChangeRoute: { routingController.showManualChoice() },
            onSelectRoute: { routingController.select($0) },
            onCancelRoute: {
                routingController.cancel()
                inputFocused = true
            }
        )
    }

    private func handleAppear() {
        if let window = chatWindowReference.window {
            isPanelVisible = window.isVisible
        }
        inputFocused = true
        viewModel.prepareNewConversationAfterInactivity()
        commandCenter.setActionConsumer(handleCommandAction)
        reconciliationCoordinator.reconcile(
            messages: viewModel.messages,
            prefersExpanded: settings.defaultExpandReasoning,
            force: true
        )
        installShortcutDispatcher()
    }

    private func handleDisappear() {
        shortcutDispatcher?.stop()
        shortcutDispatcher = nil
        isPanelVisible = false
    }


    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task { await viewModel.addAttachment(from: url) }
            }
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    await viewModel.addAttachment(from: url)
                }
            }
        }
    }

    private var placeholderText: String {
        if let pending = composerModeCoordinator.pendingExternalAsk {
            return L10n.string("atCommand.pendingPlaceholder", pending.displayName)
        }
        guard let preset = viewModel.selectedPromptPreset else {
            return L10n.string("chat.inputPlaceholder")
        }
        return PresetPlaceholder.text(for: preset.id, title: preset.title)
    }

    private var isGenerating: Bool {
        viewModel.generationState == .connecting || viewModel.generationState == .streaming
    }

    private var effectiveProviderIconSlug: String? {
        guard let model = viewModel.effectiveModel,
              let provider = viewModel.effectiveProvider else { return nil }
        return ProviderBrandIconMatcher.match(
            providerName: provider.name,
            address: provider.address,
            modelName: model.displayName,
            upstreamModelID: model.upstreamModelID
        )
    }

    private var colorScheme: ColorScheme? {
        settings.appearance.colorScheme
    }

    private var contentFont: Font {
        let baseSize: CGFloat
        switch settings.fontSize {
        case .small: baseSize = 13
        case .standard: baseSize = 14.5
        case .large: baseSize = 17
        }
        return .system(size: baseSize * settings.interfaceZoomLevel.displayScale)
    }

    private func primaryAction() {
        if isGenerating { viewModel.cancel() }
        else {
            sendFromComposer()
        }
    }

    @discardableResult
    private func sendFromComposer() -> Bool {
        if routingController.phase.isActive {
            return handleActiveDecisionRouteSend()
        }
        if composerModeCoordinator.pendingExternalAsk == nil,
           settings.decisionRoutingEnabled {
            return sendWithDecisionRouting()
        }
        return performStandardOrManualSend()
    }

    @discardableResult
    private func performStandardOrManualSend() -> Bool {
        let outcome = composerModeCoordinator.handleSend(
            input: &viewModel.input,
            resolve: resolveEnabledQuickAction
        )
        let handled: Bool
        switch outcome {
        case .launchedExternalAsk:
            clearAtCommandTokenState()
            if let textView = composerTextView.textView, !textView.string.isEmpty {
                textView.string = ""
            }
            inputFocused = true
            handled = true
        case let .launchFailedExternalAsk(action):
            clearAtCommandTokenState()
            StatusToastCenter.shared.show(
                L10n.string("atCommand.launchFailed", action.displayName),
                isError: true
            )
            inputFocused = true
            handled = false
        case .rejectedExternalAsk:
            handled = false
        case .proceedWithStandardSend:
            synchronizeSelectedPromptPreset()
            handled = viewModel.send()
            if handled {
                scrollFollowState.resumeFollowing()
            }
        }
        // Runs for every outcome so the close rule stays in one place: only a
        // question that reached another app dismisses this window.
        if shouldDismissAfterComposerSend(outcome) {
            dismiss()
        }
        return handled
    }

    private func handleActiveDecisionRouteSend() -> Bool {
        switch routingController.phase {
        case .idle:
            return false
        case .deciding:
            return true
        case .confirming, .choosing:
            routingController.acceptCurrent()
            return true
        }
    }

    private func sendWithDecisionRouting() -> Bool {
        guard viewModel.canSend else { return false }
        if !viewModel.pendingAttachments.isEmpty {
            StatusToastCenter.shared.show(L10n.string("decisionRouting.attachmentsStayInApp"))
            return performStandardOrManualSend()
        }
        let snapshot = viewModel.input
        let question = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return false }
        let candidates = settings.decisionRoutingCandidates()
        guard DecisionRoutingPolicy.shouldConsultModel(
            routingEnabled: settings.decisionRoutingEnabled,
            hasManualChannel: composerModeCoordinator.pendingExternalAsk != nil,
            candidateCount: candidates.count
        ) else {
            return performStandardOrManualSend()
        }
        let apiKey = DecisionCredentialSlot.activeAPIKey(
            systemOne: try? decisionKeyStore.readAPIKey(for: DecisionCredentialSlot.systemOne),
            legacyCustom: try? decisionKeyStore.readAPIKey(for: DecisionCredentialSlot.legacyCustom),
            preferLegacyCustom: settings.defaults.bool(forKey: DecisionCredentialSlot.preferLegacyCustomKey)
        )
        let proxy = ChatNetworking.proxyConfiguration(settings: settings, keyStore: decisionKeyStore)
        routingController.start(
            snapshotQuestion: snapshot,
            modelQuestion: question,
            candidates: candidates,
            settings: settings.decisionRoutingSettings(),
            apiKey: apiKey,
            transport: URLSessionSystemOneTransport(
                session: ChatNetworking.urlSession(proxyConfiguration: proxy)
            )
        )
        return true
    }

    @discardableResult
    private func executeDecisionRoute(_ candidate: DecisionRouteCandidate) -> Bool {
        if candidate.isInApp {
            return performStandardOrManualSend()
        }
        let question = viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty,
              let actionID = candidate.externalActionID,
              let action = resolveEnabledQuickAction(actionID) else {
            StatusToastCenter.shared.show(L10n.string("decisionRouting.unavailable"), isError: true)
            inputFocused = true
            return false
        }
        guard QuickActionLaunch.perform(action, query: question) else {
            StatusToastCenter.shared.show(
                L10n.string("atCommand.launchFailed", action.displayName),
                isError: true
            )
            inputFocused = true
            return false
        }
        clearAtCommandTokenState()
        if let textView = composerTextView.textView, !textView.string.isEmpty {
            textView.string = ""
        }
        viewModel.input = ""
        inputFocused = true
        dismiss()
        return true
    }
    private func installShortcutDispatcher() {
        guard shortcutDispatcher == nil else { return }
        let dispatcher = InAppShortcutDispatcher(
            settings: settings,
            isForeground: {
                guard let window = chatWindowReference.window else { return false }
                return window === NSApp.keyWindow && window.isKeyWindow
            },
            hasMarkedText: composerHasMarkedText,
            handleTarget: performShortcutTarget,
            setHintsVisible: { showsShortcutHints = $0 }
        )
        dispatcher.start()
        shortcutDispatcher = dispatcher
    }

    private func composerHasMarkedText() -> Bool {
        responderHasMarkedText(chatWindowReference.window?.firstResponder)
    }

    private func focusInput() {
        inputFocused = true
        viewModel.prepareNewConversationAfterInactivity()
        guard let window = chatWindowReference.window,
              let composerTextView = composerTextView.textView,
              window.firstResponder !== composerTextView else { return }
        window.makeFirstResponder(composerTextView)
    }

    private func performShortcutTarget(_ target: InAppShortcutTarget) -> Bool {
        switch target {
        case let .promptPreset(id):
            guard let preset = settings.enabledPromptPreset(id: id) else { return false }
            applyPreset(shortcutPresetSelection(current: viewModel.selectedPromptPreset, requested: preset))
            return true
        case let .quickAction(id):
            guard let action = settings.enabledQuickAction(id: id) else { return false }
            selectExternalAsk(action)
            return true
        case let .operation(operation):
            switch operation {
            case .focusInput:
                focusInput()
                return true
            case .regenerateOrRetry:
                if viewModel.canRegenerate {
                    viewModel.regenerate()
                    return true
                }
                if viewModel.generationState == .failed {
                    viewModel.retry()
                    return true
                }
                return false
            case .copyAnswer:
                guard let answer = viewModel.lastAssistantMessage, !answer.content.isEmpty else { return false }
                copyMessage(answer)
                return true
            case .toggleWindowOnTop:
                SpotAskCommandCenter.shared.toggleWindowOnTop()
                return true
            case .showSettings:
                commandCenter.showSettings()
                return true
            case .newConversation:
                newConversation()
                return true
            case .sendOrCancel:
                guard isGenerating || viewModel.canSend else { return false }
                primaryAction()
                return true
            case .zoomIn:
                adjustZoom(by: 1)
                return true
            case .zoomOut:
                adjustZoom(by: -1)
                return true
            }
        }
    }

    private func adjustZoom(by delta: Int) {
        let current = settings.interfaceZoomLevel
        let next = InterfaceZoomLevel.adjusted(from: current, by: delta)
        guard next != current else { return }
        settings.interfaceZoomLevel = next
    }

    private func shortcutHint(for target: InAppShortcutTarget) -> InAppShortcut? {
        inAppShortcutHint(settings.shortcut(for: target), commandHintsVisible: showsShortcutHints)
    }

    private func shortcutHint(for preset: PromptPreset) -> InAppShortcut? {
        shortcutHint(for: .promptPreset(preset.id))
    }

    private func shortcutHint(for action: QuickAction) -> InAppShortcut? {
        shortcutHint(for: .quickAction(action.id))
    }

    private func copyMessage(_ message: ChatMessage) {
        Clipboard.copy(message.content)
        copiedMessageID = message.id
        let token = UUID()
        copyFeedbackToken = token
        Task {
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, copyFeedbackToken == token else { return }
            copiedMessageID = nil
        }
    }

    private func retryLatestAnswer(with modelID: UUID) {
        viewModel.regenerate(withModelID: modelID)
    }

    private func retryLatestAnswerWithDefaultModel() {
        viewModel.regenerateWithDefaultModel()
    }

    private func insertSelection(from message: ChatMessage) {
        guard let snapshot = viewModel.selectionSnapshot(for: message.id) else { return }
        Task {
            do {
                try await selectionReplacementWriter.replaceSelection(in: snapshot, with: message.content)
                StatusToastCenter.shared.show(L10n.string("chat.insertSelectionSucceeded"))
            } catch let error as SelectionReplacementError {
                let message: String
                switch error {
                case .selectionChanged: message = L10n.string("chat.insertSelectionChanged")
                case .unavailable, .failed: message = L10n.string("chat.insertSelectionUnavailable")
                }
                StatusToastCenter.shared.show(message, isError: true)
            } catch {
                StatusToastCenter.shared.show(L10n.string("chat.insertSelectionUnavailable"), isError: true)
            }
        }
    }

    /// Applies a preset from the quick-strip or the in-conversation popover.
    /// With a non-empty draft (typed text or pending attachments) it selects
    /// the preset and sends immediately, so the user skips the send button;
    /// with an empty draft it only selects the preset, swaps the placeholder,
    /// and focuses the input (Return still sends). "直接提问" passes nil and
    /// never sends.
    private func applyPreset(_ preset: PromptPreset?, sendIfReady: Bool = true) {
        guard let preset else {
            composerModeCoordinator.applyPreset(nil, selectedPreset: &viewModel.selectedPromptPreset)
            inputFocused = true
            return
        }
        guard let enabledPreset = settings.promptPresetAllowedForUse(preset) else {
            composerModeCoordinator.applyPreset(nil, selectedPreset: &viewModel.selectedPromptPreset)
            inputFocused = true
            return
        }
        composerModeCoordinator.applyPreset(
            enabledPreset,
            selectedPreset: &viewModel.selectedPromptPreset
        )
        inputFocused = true
        guard sendIfReady, viewModel.canSend else { return }
        sendFromComposer()
    }

    private func synchronizeSelectedPromptPreset() {
        guard let selectedPreset = viewModel.selectedPromptPreset else { return }
        viewModel.selectedPromptPreset = settings.promptPresetAllowedForUse(selectedPreset)
    }

    private func newConversation() {
        guard viewModel.messages.isEmpty else {
            guard settings.confirmBeforeStartingNewConversation else {
                confirmNewConversation()
                return
            }
            NewConversationConfirmation.present(
                settings: settings,
                window: ModalSheetPresenter.resolveWindow(),
                onConfirm: confirmNewConversation
            )
            return
        }
        confirmNewConversation()
    }

    private func confirmNewConversation() {
        viewModel.newConversation()
        composerModeCoordinator.reset()
        clearAtCommandTokenState()
        if let textView = composerTextView.textView, !textView.string.isEmpty {
            textView.string = ""
        }
        inputFocused = true
        scrollFollowState.resumeFollowing()
    }

    private var atCommandPresets: [PromptPreset] {
        AtCommandMatcher.ranked(
            settings.enabledPromptPresets,
            keyword: atCommandState?.keyword ?? ""
        ) { AtCommandMatcher.searchFields(for: $0) }
    }

    private var atCommandActions: [QuickAction] {
        AtCommandMatcher.ranked(
            settings.enabledQuickActions,
            keyword: atCommandState?.keyword ?? ""
        ) { AtCommandMatcher.searchFields(for: $0) }
    }

    private var atCommandRows: [AtCommandPaletteRow] {
        atCommandPresets.map(AtCommandPaletteRow.preset) + atCommandActions.map(AtCommandPaletteRow.action)
    }

    private var atCommandHighlightedID: UUID? {
        let rows = atCommandRows
        guard rows.indices.contains(atCommandHighlightedIndex) else { return rows.first?.id }
        return rows[atCommandHighlightedIndex].id
    }

    @ViewBuilder
    private var atCommandPaletteOverlay: some View {
        if let state = atCommandState {
            AtCommandPaletteView(
                keyword: state.keyword,
                presets: atCommandPresets,
                actions: atCommandActions,
                highlightedID: atCommandHighlightedID,
                onHover: hoverAtCommandRow,
                onSelectPreset: selectAtCommandPreset,
                onSelectAction: selectAtCommandAction
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .offset(y: 4))
                )
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: state.keyword
            )
        }
    }

    private func handleAtCommandStateChanged(_ state: AtCommandState?) {
        if state == nil {
            atCommandSuppressed = false
            atCommandState = nil
            return
        }
        if atCommandSuppressed {
            atCommandState = nil
            return
        }
        if isPresetPopoverPresented {
            isPresetPopoverPresented = false
        }
        let keywordChanged = atCommandState?.keyword != state?.keyword
        atCommandState = state
        if keywordChanged {
            atCommandHighlightedIndex = 0
        }
    }

    private func dismissAtCommandPalette() {
        guard atCommandState != nil else { return }
        atCommandSuppressed = true
        atCommandState = nil
    }

    private func moveAtCommandHighlight(_ delta: Int) {
        let count = atCommandRows.count
        guard count > 0 else { return }
        atCommandHighlightedIndex = ((atCommandHighlightedIndex + delta) % count + count) % count
    }

    private func confirmAtCommandSelection() {
        let rows = atCommandRows
        guard rows.indices.contains(atCommandHighlightedIndex) else { return }
        switch rows[atCommandHighlightedIndex] {
        case let .preset(preset):
            selectAtCommandPreset(preset)
        case let .action(action):
            selectAtCommandAction(action)
        }
    }

    private func hoverAtCommandRow(_ id: UUID?) {
        guard let id, let index = atCommandRows.firstIndex(where: { $0.id == id }) else { return }
        atCommandHighlightedIndex = index
    }

    private func selectAtCommandPreset(_ preset: PromptPreset) {
        guard AtCommandSelection.selectPreset(
            state: atCommandState,
            textView: composerTextView.textView
        ) == .appliedPreset else { return }
        clearAtCommandTokenState()
        applyPreset(preset, sendIfReady: false)
    }

    private func selectAtCommandAction(_ action: QuickAction) {
        applyAtCommandActionOutcome(
            AtCommandSelection.selectAction(
                action,
                state: atCommandState,
                textView: composerTextView.textView,
                resolve: resolveEnabledQuickAction
            )
        )
    }

    private func resolveEnabledQuickAction(_ id: UUID) -> QuickAction? {
        settings.enabledQuickActions.first { $0.id == id }
    }

    @discardableResult
    private func applyAtCommandActionOutcome(_ outcome: AtCommandSelection.Outcome) -> Bool {
        routingController.cancel()
        let handled: Bool
        switch outcome {
        case .rejected, .appliedPreset:
            handled = false
        case let .becamePending(action):
            clearAtCommandTokenState()
            composerModeCoordinator.attachExternalAsk(
                action,
                selectedPreset: &viewModel.selectedPromptPreset
            )
            inputFocused = true
            handled = false
        case .launched:
            clearAtCommandTokenState()
            composerModeCoordinator.pendingExternalAsk = nil
            if let textView = composerTextView.textView, !textView.string.isEmpty {
                textView.string = ""
            }
            viewModel.input = ""
            inputFocused = true
            handled = true
        case let .launchFailed(action):
            clearAtCommandTokenState()
            composerModeCoordinator.pendingExternalAsk = action
            StatusToastCenter.shared.show(
                L10n.string("atCommand.launchFailed", action.displayName),
                isError: true
            )
            inputFocused = true
            handled = false
        }
        // The `@` send that left for another app closes the window; a mounted
        // target or a launch failure keeps it, with the draft and the toast.
        if shouldDismissAfterAtCommandAction(outcome) {
            dismiss()
        }
        return handled
    }

    private func clearAtCommandTokenState() {
        atCommandSuppressed = false
        atCommandState = nil
    }

    private func clearPendingExternalAskIfInputEmptied(from oldValue: String, to newValue: String) {
        let skipOnce = composerModeCoordinator.skipEmptyPendingClear
        composerModeCoordinator.skipEmptyPendingClear = false
        if shouldClearPendingExternalAsk(from: oldValue, to: newValue, skipOnce: skipOnce) {
            composerModeCoordinator.pendingExternalAsk = nil
        }
    }

    private var activeComposerBadge: ComposerModeBadge? {
        composerModeCoordinator.badge(selectedPreset: viewModel.selectedPromptPreset)
    }

    /// Picking an External Ask in the retry popover is a side trip: the question
    /// that produced this answer travels to the other platform, while the
    /// conversation, the session model, and the composer draft stay as they are.
    /// This path never dismisses the window — the answer being compared against
    /// stays on screen — which is why its outcome type is kept out of the
    /// `shouldDismissAfter…` policies.
    private func retryWithExternalAsk(_ action: QuickAction, answering messageID: UUID) {
        switch ModelPickerExternalAsk.perform(
            action,
            answering: messageID,
            viewModel: viewModel,
            coordinator: &composerModeCoordinator
        ) {
        case .launched, .becamePending:
            inputFocused = true
        case let .launchFailed(failed):
            StatusToastCenter.shared.show(
                L10n.string("atCommand.launchFailed", failed.displayName),
                isError: true
            )
        }
    }

    private func selectExternalAsk(_ action: QuickAction) {
        routingController.cancel()
        let becamePending = composerModeCoordinator.toggleExternalAsk(
            action,
            selectedPreset: &viewModel.selectedPromptPreset
        )
        if becamePending {
            clearAtCommandTokenState()
        }
        inputFocused = true
        guard becamePending,
              shouldSendExternalAskImmediately(
                  canSend: viewModel.canSend,
                  input: viewModel.input
              ) else { return }
        sendFromComposer()
    }

    private func clearComposerModeSelection() {
        composerModeCoordinator.clearSelection(selectedPreset: &viewModel.selectedPromptPreset)
        inputFocused = true
    }

    private func handleEscape() {
        let action = chatEscapeAction(
            hasMarkedText: composerHasMarkedText(),
            isAtPalettePresented: atCommandState != nil,
            isPresetPopoverPresented: isPresetPopoverPresented,
            isModelPickerPresented: isModelPickerPresented,
            isGenerating: isGenerating,
            startsNewConversation: settings.escapeStartsNewConversation,
            hasMessages: !viewModel.messages.isEmpty
        )
        switch action {
        case .preserveMarkedText:
            return
        case .dismissAtPalette:
            dismissAtCommandPalette()
            return
        case .dismissPresetPopover:
            isPresetPopoverPresented = false
            return
        case .dismissModelPicker:
            isModelPickerPresented = false
            return
        case .cancelGeneration, .startNewConversation, .dismissWindow:
            break
        }
        if routingController.phase.isActive {
            routingController.cancel()
            inputFocused = true
            return
        }
        if composerModeCoordinator.pendingExternalAsk != nil {
            composerModeCoordinator.pendingExternalAsk = nil
            return
        }
        switch action {
        case .preserveMarkedText, .dismissAtPalette, .dismissPresetPopover, .dismissModelPicker:
            break
        case .cancelGeneration:
            viewModel.cancel()
        case .startNewConversation:
            newConversation()
        case .dismissWindow:
            dismiss()
        }
    }

    private func dismiss() {
        if settings.clearInputOnClose { viewModel.input = "" }
        onDismiss()
    }

    private func handleCommandAction(_ action: SpotAskCommandAction) {
        switch action {
        case .focusInput:
            focusInput()
        case let .compose(question, promptPreset):
            composeQuestion(question, promptPreset: promptPreset)
        case let .prepare(promptPreset):
            viewModel.selectedPromptPreset = settings.promptPresetAllowedForUse(promptPreset)
            inputFocused = true
        case .newConversation:
            newConversation()
        case let .ask(question, promptPreset, selectionSnapshot):
            receiveQuestion(question, promptPreset: promptPreset, selectionSnapshot: selectionSnapshot)
        case let .addToChat(text):
            addToChat(text)
        }
    }

    private func receiveQuestion(_ question: String, promptPreset: PromptPreset?, selectionSnapshot: SelectedTextSnapshot? = nil) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputFocused = true
            return
        }
        // External questions always use the new conversation prepared after
        // inactivity; the previous one remains available only via the banner.
        viewModel.selectedPromptPreset = promptPreset.flatMap(settings.promptPresetAllowedForUse)
        // Do not start a second request while the view model is still unwinding
        // a cancelled stream. The supplied question remains ready to send.
        guard !isGenerating else {
            viewModel.input = trimmed
            inputFocused = true
            return
        }
        viewModel.input = trimmed
        if viewModel.send(selectionSnapshot: selectionSnapshot) {
            scrollFollowState.resumeFollowing()
        }
        inputFocused = true
    }

    private func composeQuestion(_ question: String, promptPreset: PromptPreset?) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            focusInput()
            return
        }
        viewModel.selectedPromptPreset = promptPreset.flatMap(settings.promptPresetAllowedForUse)
        viewModel.input = trimmed
        focusInput()
        if let textView = composerTextView.textView {
            if textView.string != trimmed {
                textView.string = trimmed
            }
            let targetLocation = (trimmed as NSString).length
            textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
        }
    }

    private func addToChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            focusInput()
            return
        }
        let quoted = Self.quotedMarkdown(trimmed)
        let current = viewModel.input
        let formatted = current.isEmpty
            ? quoted + "\n\n"
            : current + "\n\n" + quoted + "\n\n"
        viewModel.selectedPromptPreset = nil
        viewModel.input = formatted
        focusInput()
        if let textView = composerTextView.textView {
            if textView.string != formatted {
                textView.string = formatted
            }
            let targetLocation = (formatted as NSString).length
            textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
        }
    }

    private static func quotedMarkdown(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.isEmpty ? ">" : "> \(line)"
        }.joined(separator: "\n")
    }
}
