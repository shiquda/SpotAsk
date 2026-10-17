import Foundation
import Testing
@testable import SpotAsk

@MainActor
struct DecisionRoutingSequentialSyntaxTests {
    @Test("Candidate list preserves the sequential order of enabled actions with In-App as root")
    func candidatesPreserveOrder() {
        let suiteName = "DecisionRoutingSequentialSyntaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        // Add 2 templates
        guard let claude = QuickActionTemplate.allTemplates.first(where: { $0.id == "claude" }),
              let perplexity = QuickActionTemplate.allTemplates.first(where: { $0.id == "perplexity" }) else {
            Issue.record("Templates missing")
            return
        }

        let claudeAction = settings.addQuickAction(from: claude)!
        let perplexityAction = settings.addQuickAction(from: perplexity)!

        let candidates = settings.decisionRoutingCandidates()
        // Index 0 must be In-App
        #expect(candidates.first?.id == DecisionRouteID.inApp)

        // The external candidates follow in order of enabledQuickActions
        let externalIDs = candidates.compactMap(\.externalActionID)
        let enabledIDs = settings.enabledQuickActions.map(\.id)
        #expect(externalIDs == enabledIDs)
        #expect(externalIDs.contains(claudeAction.id))
        #expect(externalIDs.contains(perplexityAction.id))

        // Moving perplexity up changes the order
        let initialIndex = settings.quickActions.firstIndex(where: { $0.id == perplexityAction.id })!
        if initialIndex > 0 {
            #expect(settings.moveQuickAction(id: perplexityAction.id, by: -1))
            let reorderedCandidates = settings.decisionRoutingCandidates()
            let reorderedExternalIDs = reorderedCandidates.compactMap(\.externalActionID)
            #expect(reorderedExternalIDs == settings.enabledQuickActions.map(\.id))
        }
    }

    @Test("Custom In-App description is used in fallback candidate")
    func customInAppDescriptionIsUsedInFallbackCandidate() {
        let suiteName = "DecisionRoutingSequentialSyntaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.decisionRoutingInAppDescription = "Custom in-app fallback instructions"

        let candidates = settings.decisionRoutingCandidates()
        let inAppCandidate = candidates.first { $0.id == DecisionRouteID.inApp }
        #expect(inAppCandidate?.applicableDescription == "Custom in-app fallback instructions")
    }

    @Test("Action routing hints update modifies candidate criteria")
    func routingHintsUpdateModifiesCriteria() {
        let suiteName = "DecisionRoutingSequentialSyntaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let action = settings.quickActions[0]

        settings.updateQuickActionRouting(
            id: action.id,
            purpose: "Refined coding agent purpose",
            scenario: "Refined coding debugging scenario",
            requiresConfirmation: true
        )

        let updatedAction = settings.quickActions.first { $0.id == action.id }!
        #expect(updatedAction.routingPurpose == "Refined coding agent purpose")
        #expect(updatedAction.routingScenario == "Refined coding debugging scenario")
        #expect(updatedAction.requiresConfirmationOnAutoRoute == true)

        let candidates = settings.decisionRoutingCandidates()
        let candidate = candidates.first { $0.externalActionID == action.id }!
        #expect(candidate.applicableDescription.contains("Refined coding agent purpose"))
        #expect(candidate.applicableDescription.contains("Refined coding debugging scenario"))
        #expect(candidate.forceConfirm == true)
    }
}
