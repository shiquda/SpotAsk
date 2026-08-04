import Foundation
import Testing
@testable import SpotAsk

@Suite("Prompt presets")
@MainActor
struct PromptPresetTests {
    @Test("Pressing the selected prompt shortcut clears the prompt")
    func selectedPromptShortcutClearsSelection() {
        let translate = PromptPreset.builtIn[0]

        #expect(shortcutPresetSelection(current: translate, requested: translate) == nil)
        #expect(shortcutPresetSelection(current: translate, requested: PromptPreset.builtIn[1]) == PromptPreset.builtIn[1])
    }

    @Test("Custom presets persist, update, and delete")
    func customPresetsPersist() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let preset = PromptPreset(title: "邮件改写", instruction: "请将内容改写为简洁、专业的邮件。")

        #expect(settings.saveCustomPromptPreset(preset))
        #expect(AppSettings(defaults: defaults).customPromptPresets == [preset])

        let edited = PromptPreset(id: preset.id, title: "邮件润色", instruction: "请润色为自然、专业的邮件。")
        #expect(settings.saveCustomPromptPreset(edited))
        #expect(settings.customPromptPresets == [edited])

        settings.deleteCustomPromptPreset(id: preset.id)
        #expect(settings.customPromptPresets.isEmpty)
    }

    @Test("Legacy custom presets migrate into one persistent prompt catalog")
    func legacyCustomPresetsMigrateIdempotently() throws {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyPreset = PromptPreset(title: "邮件改写", instruction: "改写为简洁邮件。")
        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode([legacyPreset])) as? [[String: Any]]
        )
        legacyJSON[0].removeValue(forKey: "isEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        defaults.set(legacyData, forKey: "customPromptPresets")

        let migrated = AppSettings(defaults: defaults)
        #expect(migrated.promptPresets.map(\.id) == PromptPreset.builtIn.map(\.id) + [legacyPreset.id])
        #expect(migrated.customPromptPresets == [legacyPreset])
        #expect(defaults.data(forKey: "promptPresetCatalog") != nil)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.promptPresets == migrated.promptPresets)
        #expect(reloaded.customPromptPresets == [legacyPreset])
    }

    @Test("Prompt catalog order and enabled state persist")
    func promptCatalogOrderAndEnabledStatePersist() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let custom = PromptPreset(title: "邮件改写", instruction: "改写为简洁邮件。")
        #expect(settings.saveCustomPromptPreset(custom))

        let translate = PromptPreset.builtIn[0]
        settings.movePromptPreset(id: custom.id, before: translate.id)
        settings.setPromptPresetEnabled(id: translate.id, isEnabled: false)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.promptPresets.first?.id == custom.id)
        #expect(reloaded.enabledPromptPreset(id: translate.id) == nil)
        #expect(!reloaded.enabledPromptPresets.contains(where: { $0.id == translate.id }))
    }

    @Test("Prompt catalog adjacent reordering preserves every preset identity")
    func promptCatalogAdjacentReorderingPreservesIdentities() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let custom = PromptPreset(title: "邮件改写", instruction: "改写为简洁邮件。")
        #expect(settings.saveCustomPromptPreset(custom))

        let initialIDs = settings.promptPresets.map(\.id)
        let firstBuiltIn = try! #require(settings.promptPresets.first)

        settings.movePromptPreset(id: custom.id, before: firstBuiltIn.id)
        #expect(settings.promptPresets.prefix(2).map(\.id) == [custom.id, firstBuiltIn.id])

        // The UI uses this inverse move to swap a dragged item one row down.
        settings.movePromptPreset(id: firstBuiltIn.id, before: custom.id)
        #expect(settings.promptPresets.prefix(2).map(\.id) == [firstBuiltIn.id, custom.id])
        #expect(Set(settings.promptPresets.map(\.id)) == Set(initialIDs))
    }

    @Test("Invalid and self prompt catalog moves leave the order unchanged")
    func invalidPromptCatalogMovesLeaveOrderUnchanged() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let originalIDs = settings.promptPresets.map(\.id)
        let firstID = try! #require(originalIDs.first)

        settings.movePromptPreset(id: firstID, before: firstID)
        settings.movePromptPreset(id: UUID(), before: firstID)

        #expect(settings.promptPresets.map(\.id) == originalIDs)
    }

    @Test("Completed prompt reorder commits a staged first-to-last move and persists it")
    func completedPromptReorderCommitsStagedFirstToLastMove() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let custom = PromptPreset(title: "邮件改写", instruction: "改写为简洁邮件。")
        #expect(settings.saveCustomPromptPreset(custom))

        let originalIDs = settings.promptPresets.map(\.id)
        let firstID = try! #require(originalIDs.first)
        let stagedIDs = PromptPresetOrder.moving(
            settings.promptPresets,
            id: firstID,
            to: settings.promptPresets.count - 1
        ).map(\.id)

        #expect(stagedIDs == Array(originalIDs.dropFirst()) + [firstID])
        // The local drag order does not touch settings until the final commit.
        #expect(settings.promptPresets.map(\.id) == originalIDs)
        settings.commitPromptPresetOrder(stagedIDs)

        #expect(settings.promptPresets.map(\.id) == stagedIDs)
        #expect(AppSettings(defaults: defaults).promptPresets.map(\.id) == stagedIDs)
    }

    @Test("Single-frame drag target selection clamps a first item to the final row")
    func singleFrameDragTargetClampsFirstItemToFinalRow() {
        let rowMidYs: [CGFloat] = [20, 60, 100, 140]

        #expect(
            PromptPresetOrder.targetIndex(
                in: rowMidYs,
                currentIndex: 0,
                pointerY: 10_000,
                hysteresis: 6
            ) == rowMidYs.count - 1
        )
    }

    @Test("Single-frame drag target selection clamps a final item to the first row")
    func singleFrameDragTargetClampsFinalItemToFirstRow() {
        let rowMidYs: [CGFloat] = [20, 60, 100, 140]

        #expect(
            PromptPresetOrder.targetIndex(
                in: rowMidYs,
                currentIndex: rowMidYs.count - 1,
                pointerY: -10_000,
                hysteresis: 6
            ) == 0
        )
    }

    @Test("Drag target selection preserves adjacent-row hysteresis boundaries")
    func dragTargetSelectionPreservesHysteresisBoundaries() {
        let rowMidYs: [CGFloat] = [20, 60, 100]
        let rowHeight: CGFloat = 40
        let hysteresis = rowHeight * 0.15

        #expect(
            PromptPresetOrder.targetIndex(
                in: rowMidYs,
                currentIndex: 1,
                pointerY: rowMidYs[0] - hysteresis,
                hysteresis: hysteresis
            ) == 1
        )
        #expect(
            PromptPresetOrder.targetIndex(
                in: rowMidYs,
                currentIndex: 1,
                pointerY: rowMidYs[0] - hysteresis - 0.1,
                hysteresis: hysteresis
            ) == 0
        )
        #expect(
            PromptPresetOrder.targetIndex(
                in: rowMidYs,
                currentIndex: 1,
                pointerY: rowMidYs[2] + hysteresis,
                hysteresis: hysteresis
            ) == 1
        )
        #expect(
            PromptPresetOrder.targetIndex(
                in: rowMidYs,
                currentIndex: 1,
                pointerY: rowMidYs[2] + hysteresis + 0.1,
                hysteresis: hysteresis
            ) == 2
        )
    }

    @Test("Frozen drag slots keep first and final targets clamped across a long drag")
    func frozenDragSlotsClampTargetIndices() {
        let slots = PromptPresetDragSlots(frames: [
            CGRect(x: 0, y: 0, width: 300, height: 36),
            CGRect(x: 0, y: 42, width: 300, height: 82),
            CGRect(x: 0, y: 130, width: 300, height: 48),
            CGRect(x: 0, y: 184, width: 300, height: 64)
        ])

        #expect(slots.targetIndex(currentIndex: 0, pointerY: 10_000, hysteresis: 6) == 3)
        #expect(slots.targetIndex(currentIndex: 3, pointerY: -10_000, hysteresis: 6) == 0)
    }

    @Test("Frozen drag slots preserve hysteresis for uneven row heights")
    func frozenDragSlotsPreserveHysteresisForUnevenRows() {
        let slots = PromptPresetDragSlots(frames: [
            CGRect(x: 0, y: 0, width: 300, height: 36),
            CGRect(x: 0, y: 42, width: 300, height: 82),
            CGRect(x: 0, y: 130, width: 300, height: 48)
        ])
        let hysteresis: CGFloat = 12
        let firstSlot = try! #require(slots.frame(at: 0))

        #expect(
            slots.targetIndex(
                currentIndex: 1,
                pointerY: firstSlot.midY - hysteresis,
                hysteresis: hysteresis
            ) == 1
        )
        #expect(
            slots.targetIndex(
                currentIndex: 1,
                pointerY: firstSlot.midY - hysteresis - 0.1,
                hysteresis: hysteresis
            ) == 0
        )
    }

    @Test("Frozen target slot keeps a distant reordered card under the pointer")
    func frozenDragSlotsKeepDistantReorderedCardUnderPointer() {
        let ids = (0..<4).map { _ in UUID() }
        let slots = PromptPresetDragSlots(rowFrames: [
            ids[0]: CGRect(x: 0, y: 0, width: 300, height: 36),
            ids[1]: CGRect(x: 0, y: 42, width: 300, height: 82),
            ids[2]: CGRect(x: 0, y: 130, width: 300, height: 48),
            ids[3]: CGRect(x: 0, y: 184, width: 300, height: 64)
        ])
        let targetIndex = try! #require(
            slots.targetIndex(in: ids, currentIndex: 0, pointerY: 230, hysteresis: 6)
        )
        let reorderedIDs = [ids[1], ids[2], ids[3], ids[0]]
        let targetSlot = try! #require(slots.frame(for: ids[0], in: reorderedIDs))
        let offset = try! #require(slots.constrainedOffset(pointerY: 230, for: targetSlot))

        #expect(targetIndex == 3)
        #expect(targetSlot.midY + offset == 230)
    }

    @Test("Frozen drag slots recalculate the projected row for repeated crossings")
    func frozenDragSlotsRecalculateProjectedRowForRepeatedCrossings() {
        let ids = (0..<4).map { _ in UUID() }
        let slots = PromptPresetDragSlots(rowFrames: [
            ids[0]: CGRect(x: 0, y: 0, width: 300, height: 36),
            ids[1]: CGRect(x: 0, y: 42, width: 300, height: 82),
            ids[2]: CGRect(x: 0, y: 130, width: 300, height: 48),
            ids[3]: CGRect(x: 0, y: 184, width: 300, height: 64)
        ])
        let afterFirstCrossing = [ids[1], ids[2], ids[3], ids[0]]
        let targetIndex = try! #require(
            slots.targetIndex(
                in: afterFirstCrossing,
                currentIndex: 3,
                pointerY: 100,
                hysteresis: 6
            )
        )
        let afterSecondCrossing = [ids[1], ids[0], ids[2], ids[3]]
        let projectedFrame = try! #require(slots.frame(for: ids[0], in: afterSecondCrossing))
        let offset = try! #require(slots.constrainedOffset(pointerY: 100, for: projectedFrame))

        #expect(targetIndex == 1)
        #expect(projectedFrame.midY + offset == 100)
    }

    @Test("Frozen drag slots expose final row frames for an immediate next drag")
    func frozenDragSlotsExposeFinalRowFramesAfterFirstToLastMove() {
        let ids = (0..<4).map { _ in UUID() }
        let slots = PromptPresetDragSlots(rowFrames: [
            ids[0]: CGRect(x: 0, y: 0, width: 300, height: 36),
            ids[1]: CGRect(x: 0, y: 42, width: 300, height: 82),
            ids[2]: CGRect(x: 0, y: 130, width: 300, height: 48),
            ids[3]: CGRect(x: 0, y: 184, width: 300, height: 64)
        ])
        let finalOrder = [ids[1], ids[2], ids[3], ids[0]]
        let finalFrames = try! #require(slots.layoutFrames(in: finalOrder))
        let framesInFinalOrder = finalOrder.compactMap { finalFrames[$0] }

        #expect(framesInFinalOrder.count == finalOrder.count)
        #expect(framesInFinalOrder.map(\.minY) == [0, 88, 142, 212])
        #expect(framesInFinalOrder.map(\.height) == [82, 48, 64, 36])
        #expect(finalFrames[ids[0]] == CGRect(x: 0, y: 212, width: 300, height: 36))
    }

    @Test("Frozen target slot clamps a card at the list edges")
    func frozenDragSlotsClampCardOffsetAtListEdges() {
        let slots = PromptPresetDragSlots(frames: [
            CGRect(x: 0, y: 0, width: 300, height: 36),
            CGRect(x: 0, y: 42, width: 300, height: 82),
            CGRect(x: 0, y: 130, width: 300, height: 48)
        ])
        let firstSlot = try! #require(slots.frame(at: 0))
        let finalSlot = try! #require(slots.frame(at: 2))
        let upwardOffset = try! #require(slots.constrainedOffset(pointerY: -1_000, at: 0))
        let downwardOffset = try! #require(slots.constrainedOffset(pointerY: 1_000, at: 2))

        #expect(firstSlot.midY + upwardOffset == firstSlot.midY)
        #expect(finalSlot.midY + downwardOffset == finalSlot.midY)
    }

    @Test("Incomplete or duplicate staged prompt orders are rejected")
    func invalidCompletedPromptOrdersAreRejected() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let originalIDs = settings.promptPresets.map(\.id)
        let firstID = try! #require(originalIDs.first)

        settings.commitPromptPresetOrder(Array(originalIDs.dropLast()))
        settings.commitPromptPresetOrder(Array(repeating: firstID, count: originalIDs.count))

        #expect(settings.promptPresets.map(\.id) == originalIDs)
    }

    @Test("System shortcut prompt lookup stops at disabled built-in prompts")
    func disabledBuiltInPromptsAreUnavailableToSystemShortcuts() {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let translate = PromptPreset.builtIn[0]

        #expect(enabledBuiltInPromptPreset(id: translate.id, settings: settings)?.id == translate.id)
        settings.setPromptPresetEnabled(id: translate.id, isEnabled: false)
        #expect(enabledBuiltInPromptPreset(id: translate.id, settings: settings) == nil)
        #expect(settings.promptPresetAllowedForUse(translate) == nil)
    }

    @Test("A selected preset applies to one request only")
    func selectedPresetAppliesToOneRequestOnly() async {
        let suiteName = "PromptPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let recorder = PromptPresetRequestRecorder()
        let viewModel = ChatViewModel(
            settings: settings,
            providerFactory: PromptPresetFactory(recorder: recorder),
            sessionStore: SessionStore(bundleIdentifier: suiteName)
        )

        viewModel.selectedPromptPreset = PromptPreset.builtIn[0]
        viewModel.input = "Hello"
        viewModel.send()
        await waitForIdle(viewModel)

        #expect(viewModel.selectedPromptPreset == nil)
        #expect(viewModel.messages.first?.appliedPresetTitle == PromptPreset.builtIn[0].title)
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests[0].messages.first?.role == .system)
        #expect(recorder.requests[0].messages.first?.content.contains(PromptPreset.builtIn[0].instruction) == true)
        #expect(recorder.requests[0].messages.last?.content == "Hello")

        viewModel.input = "How are you?"
        viewModel.send()
        await waitForIdle(viewModel)

        #expect(recorder.requests.count == 2)
        #expect(recorder.requests[1].messages.first?.content == settings.systemPrompt)
    }

    @Test("Messages without a preset label or icon remain readable")
    func legacyMessageDecoding() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try JSONEncoder().encode(
            LegacyChatMessage(id: id, role: .user, content: "Hello", createdAt: date, state: .complete)
        )

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(message.id == id)
        #expect(message.appliedPresetTitle == nil)
        #expect(message.appliedPresetSymbolName == nil)
        #expect(message.appliedPresetIcon == "sparkles")
        #expect(message.reasoningContent == nil)
    }

    @Test("Prompt presets have stable message icons")
    func promptPresetSymbolNames() {
        #expect(PromptPreset.builtIn[0].symbolName == "globe")
        #expect(PromptPreset.builtIn[1].symbolName == "lightbulb")
        #expect(PromptPreset(title: "Custom", instruction: "Do it").symbolName == "sparkles")
    }

    @Test("Prompt position accessibility text formats numeric positions")
    func promptPositionAccessibilityTextUsesNumericArguments() {
        #expect(L10n.string("settings.promptPosition", language: .english, arguments: [2, 5]) == "2 of 5")
        #expect(L10n.string("settings.promptPosition", language: .simplifiedChinese, arguments: [2, 5]) == "第 2 项，共 5 项")
    }

    private func waitForIdle(_ viewModel: ChatViewModel) async {
        for _ in 0 ..< 100 {
            if viewModel.generationState == .idle { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the request to finish")
    }
}

private struct LegacyChatMessage: Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let createdAt: Date
    let state: MessageState
}

private final class PromptPresetRequestRecorder: @unchecked Sendable {
    var requests: [ChatRequest] = []
}

@MainActor
private struct PromptPresetFactory: ChatProviderFactory {
    let recorder: PromptPresetRequestRecorder

    func makeProvider() throws -> any ChatProvider {
        PromptPresetProvider(recorder: recorder)
    }

    func makeTargetSnapshot() throws -> ProviderTargetSnapshot {
        ProviderTargetSnapshot.testValue()
    }

    func makeProvider(for target: ProviderTargetSnapshot) throws -> any ChatProvider {
        PromptPresetProvider(recorder: recorder)
    }
}

private struct PromptPresetProvider: ChatProvider {
    let recorder: PromptPresetRequestRecorder

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        recorder.requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta("done"))
            continuation.finish()
        }
    }

    func testConnection() async throws {}
}
