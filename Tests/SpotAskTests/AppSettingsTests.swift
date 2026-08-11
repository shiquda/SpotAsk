import XCTest
@testable import SpotAsk

@MainActor
final class AppSettingsTests: XCTestCase {
    func testWindowOnTopDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.keepWindowOnTop)

        settings.keepWindowOnTop = true
        XCTAssertTrue(AppSettings(defaults: defaults).keepWindowOnTop)
    }

    func testChatMessageStyleDefaultsToStandardAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).chatMessageStyle, .standard)

        let settings = AppSettings(defaults: defaults)
        settings.chatMessageStyle = .im
        XCTAssertEqual(AppSettings(defaults: defaults).chatMessageStyle, .im)
    }

    func testMenuBarIconDefaultsToVisibleAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.showsMenuBarIcon)

        settings.showsMenuBarIcon = false
        XCTAssertFalse(AppSettings(defaults: defaults).showsMenuBarIcon)
    }

    func testSilentLaunchDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).silentLaunch)

        let settings = AppSettings(defaults: defaults)
        settings.silentLaunch = true
        XCTAssertTrue(AppSettings(defaults: defaults).silentLaunch)
    }

    func testProxyDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.proxyEnabled)
        XCTAssertEqual(settings.proxyType, .http)
        XCTAssertEqual(settings.proxyHost, "")
        XCTAssertEqual(settings.proxyPort, 1080)
        XCTAssertEqual(settings.proxyUsername, "")

        settings.proxyEnabled = true
        settings.proxyType = .socks5
        settings.proxyHost = "127.0.0.1"
        settings.proxyPort = 7890
        settings.proxyUsername = "user"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.proxyEnabled)
        XCTAssertEqual(reloaded.proxyType, .socks5)
        XCTAssertEqual(reloaded.proxyHost, "127.0.0.1")
        XCTAssertEqual(reloaded.proxyPort, 7890)
        XCTAssertEqual(reloaded.proxyUsername, "user")
    }

    func testGlobalShortcutPersistsAndFallsBackToNil() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(AppSettings(defaults: defaults).globalShortcut)

        let settings = AppSettings(defaults: defaults)
        settings.globalShortcut = InAppShortcut(key: " ", modifiers: .option)
        XCTAssertEqual(AppSettings(defaults: defaults).globalShortcut, InAppShortcut(key: " ", modifiers: .option))

        settings.globalShortcut = nil
        XCTAssertNil(AppSettings(defaults: defaults).globalShortcut)
    }

    func testGlobalShortcutAcceptsSpaceWithModifier() {
        XCTAssertTrue(InAppShortcut(key: " ", modifiers: .option).isSupportedGlobalShortcut)
        XCTAssertTrue(InAppShortcut(key: "k", modifiers: .control).isSupportedGlobalShortcut)
        XCTAssertFalse(InAppShortcut(key: " ", modifiers: []).isSupportedGlobalShortcut)
    }

    func testDiagnosticsDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).diagnosticsEnabled)

        let settings = AppSettings(defaults: defaults)
        settings.diagnosticsEnabled = true
        XCTAssertTrue(AppSettings(defaults: defaults).diagnosticsEnabled)
    }

    func testChangingMenuBarIconPreferenceNotifiesTheRunningApplication() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let expectation = expectation(forNotification: .spotAskMenuBarIconVisibilityChanged, object: settings)

        settings.showsMenuBarIcon = false

        wait(for: [expectation], timeout: 0)
    }

    func testMenuBarAndDockPresentationsUseOppositeRecoveryEntrances() {
        let menuBar = AppEntryPresentation(showsMenuBarIcon: true)
        XCTAssertTrue(menuBar.showsStatusItem)
        XCTAssertEqual(menuBar.activationPolicy, .accessory)

        let dock = AppEntryPresentation(showsMenuBarIcon: false)
        XCTAssertFalse(dock.showsStatusItem)
        XCTAssertEqual(dock.activationPolicy, .regular)
    }

    func testEntryPresentationCoordinatorAppliesInitialAndLivePreference() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var statusItemVisibility: [Bool] = []
        var activationPolicies: [NSApplication.ActivationPolicy] = []

        let coordinator = AppEntryPresentationCoordinator(
            settings: settings,
            setStatusItemVisible: { statusItemVisibility.append($0) },
            setActivationPolicy: { activationPolicies.append($0) }
        )
        XCTAssertNotNil(coordinator)
        XCTAssertEqual(statusItemVisibility, [true])
        XCTAssertEqual(activationPolicies, [.accessory])

        settings.showsMenuBarIcon = false
        XCTAssertEqual(statusItemVisibility, [true, false])
        XCTAssertEqual(activationPolicies, [.accessory, .regular])

        settings.showsMenuBarIcon = true
        XCTAssertEqual(statusItemVisibility, [true, false, true])
        XCTAssertEqual(activationPolicies, [.accessory, .regular, .accessory])
    }

    func testDockReopenRequestsThePanelOnlyWhenNoWindowIsVisible() {
        var openRequests = 0

        XCTAssertTrue(handleDockReopen(hasVisibleWindows: false) { openRequests += 1 })
        XCTAssertEqual(openRequests, 1)

        XCTAssertTrue(handleDockReopen(hasVisibleWindows: true) { openRequests += 1 })
        XCTAssertEqual(openRequests, 1)
    }

    func testDraftIsKeptOnCloseByDefaultAndOptOutPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).clearInputOnClose, "The draft should survive closing the window unless the user opts out")

        let settings = AppSettings(defaults: defaults)
        settings.clearInputOnClose = true
        XCTAssertTrue(AppSettings(defaults: defaults).clearInputOnClose)
    }

    func testNewConversationConfirmationDefaultsToOnAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(AppSettings(defaults: defaults).confirmBeforeStartingNewConversation)

        let settings = AppSettings(defaults: defaults)
        settings.confirmBeforeStartingNewConversation = false
        XCTAssertFalse(AppSettings(defaults: defaults).confirmBeforeStartingNewConversation)
    }

    func testEscapeStartsNewConversationDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).escapeStartsNewConversation)

        let settings = AppSettings(defaults: defaults)
        settings.escapeStartsNewConversation = true
        XCTAssertTrue(AppSettings(defaults: defaults).escapeStartsNewConversation)

        settings.escapeStartsNewConversation = false
        XCTAssertFalse(AppSettings(defaults: defaults).escapeStartsNewConversation)
    }

    func testDefaultExpandReasoningDefaultsToOffAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).defaultExpandReasoning)

        let settings = AppSettings(defaults: defaults)
        settings.defaultExpandReasoning = true
        XCTAssertTrue(AppSettings(defaults: defaults).defaultExpandReasoning)
    }

    func testMathRenderingDefaultsToOnAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(AppSettings(defaults: defaults).renderMath)

        let settings = AppSettings(defaults: defaults)
        settings.renderMath = false
        XCTAssertFalse(AppSettings(defaults: defaults).renderMath)
    }

    func testEscapePrioritizesMarkedTextPopoverAndGeneration() {
        XCTAssertEqual(
            chatEscapeAction(
                hasMarkedText: true,
                isPresetPopoverPresented: true,
                isGenerating: true,
                startsNewConversation: true,
                hasMessages: true
            ),
            .preserveMarkedText
        )
        XCTAssertEqual(
            chatEscapeAction(
                hasMarkedText: false,
                isPresetPopoverPresented: true,
                isGenerating: true,
                startsNewConversation: true,
                hasMessages: true
            ),
            .dismissPresetPopover
        )
        XCTAssertEqual(
            chatEscapeAction(
                hasMarkedText: false,
                isPresetPopoverPresented: false,
                isGenerating: true,
                startsNewConversation: true,
                hasMessages: true
            ),
            .cancelGeneration
        )
    }

    func testEscapeUsesNewConversationOnlyWhenEnabledAndMessagesExist() {
        XCTAssertEqual(
            chatEscapeAction(
                hasMarkedText: false,
                isPresetPopoverPresented: false,
                isGenerating: false,
                startsNewConversation: false,
                hasMessages: true
            ),
            .dismissWindow
        )
        XCTAssertEqual(
            chatEscapeAction(
                hasMarkedText: false,
                isPresetPopoverPresented: false,
                isGenerating: false,
                startsNewConversation: true,
                hasMessages: true
            ),
            .startNewConversation
        )
        XCTAssertEqual(
            chatEscapeAction(
                hasMarkedText: false,
                isPresetPopoverPresented: false,
                isGenerating: false,
                startsNewConversation: true,
                hasMessages: false
            ),
            .dismissWindow
        )
    }

    func testResponderMarkedTextGuardRecognizesAndReleasesComposition() {
        let textView = NSTextView()
        textView.setMarkedText(
            "zhong",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        XCTAssertTrue(responderHasMarkedText(textView))

        textView.unmarkText()
        XCTAssertFalse(responderHasMarkedText(textView))
    }

    func testPanelOriginPersistsAndClears() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(AppSettings(defaults: defaults).panelOrigin)

        let settings = AppSettings(defaults: defaults)
        settings.panelOrigin = CGPoint(x: 120, y: 340)
        XCTAssertEqual(AppSettings(defaults: defaults).panelOrigin, CGPoint(x: 120, y: 340))

        settings.panelOrigin = nil
        XCTAssertNil(AppSettings(defaults: defaults).panelOrigin)
    }

    func testLanguageDefaultsToSystemAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).language, .system)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english
        XCTAssertEqual(AppSettings(defaults: defaults).language, .english)
    }

    func testInterfaceZoomDefaultsToStandardAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).interfaceZoomLevel, .standard)

        let settings = AppSettings(defaults: defaults)
        settings.interfaceZoomLevel = .comfortable
        XCTAssertEqual(AppSettings(defaults: defaults).interfaceZoomLevel, .comfortable)
    }

    func testInterfaceZoomAdjustmentClampsToAvailableLevels() {
        XCTAssertEqual(InterfaceZoomLevel.adjusted(from: .compact, by: -1), .compact)
        XCTAssertEqual(InterfaceZoomLevel.adjusted(from: .standard, by: -1), .compact)
        XCTAssertEqual(InterfaceZoomLevel.adjusted(from: .standard, by: 1), .comfortable)
        XCTAssertEqual(InterfaceZoomLevel.adjusted(from: .large, by: 1), .large)
    }

    func testSelectionAutoInvokeDelayNormalizedClampsAndRounds() {
        XCTAssertEqual(SelectionAutoInvokeDelay.normalized(-1), 0)
        XCTAssertEqual(SelectionAutoInvokeDelay.normalized(5), 3)
        XCTAssertEqual(SelectionAutoInvokeDelay.normalized(0.83), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SelectionAutoInvokeDelay.normalized(SelectionAutoInvokeDelay.defaultValue), SelectionAutoInvokeDelay.defaultValue)
    }

    func testSelectionAutoInvokeScopeDefaultsToAllAppsAndPersists() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).selectionAutoInvokeScope, .allApps)

        let settings = AppSettings(defaults: defaults)
        settings.selectionAutoInvokeScope = .whitelist
        XCTAssertEqual(AppSettings(defaults: defaults).selectionAutoInvokeScope, .whitelist)
    }

    func testSelectionAutoInvokeAppListsPersist() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.selectionAutoInvokeBlacklist.isEmpty)
        XCTAssertTrue(settings.selectionAutoInvokeWhitelist.isEmpty)

        settings.selectionAutoInvokeBlacklist = ["com.example.Blocked", "com.example.Another"]
        settings.selectionAutoInvokeWhitelist = ["com.example.Allowed"]

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.selectionAutoInvokeBlacklist, ["com.example.Blocked", "com.example.Another"])
        XCTAssertEqual(reloaded.selectionAutoInvokeWhitelist, ["com.example.Allowed"])
    }

    func testAutomaticInvokeFilteringUsesBundleIdentifierWithNameFallback() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        let source = SelectionSourceApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.Source",
            localizedName: "Source"
        )
        let nameOnlySource = SelectionSourceApplication(
            processIdentifier: 42,
            bundleIdentifier: nil,
            localizedName: "Notes"
        )

        XCTAssertTrue(settings.allowsAutomaticInvoke(from: source))

        settings.selectionAutoInvokeScope = .blacklist
        settings.selectionAutoInvokeBlacklist = ["com.example.Source"]
        XCTAssertFalse(settings.allowsAutomaticInvoke(from: source))
        XCTAssertTrue(settings.allowsAutomaticInvoke(from: nameOnlySource))

        settings.selectionAutoInvokeBlacklist = ["Notes"]
        XCTAssertFalse(settings.allowsAutomaticInvoke(from: nameOnlySource))
        XCTAssertTrue(settings.allowsAutomaticInvoke(from: source))

        settings.selectionAutoInvokeScope = .whitelist
        settings.selectionAutoInvokeWhitelist = ["com.example.Source"]
        XCTAssertTrue(settings.allowsAutomaticInvoke(from: source))
        XCTAssertFalse(settings.allowsAutomaticInvoke(from: nameOnlySource))
    }

    func testLocalizationUsesExplicitLanguageSelection() {
        XCTAssertEqual(L10n.string("settings.title", language: .english), "Settings")
        XCTAssertEqual(L10n.string("settings.title", language: .simplifiedChinese), "设置")
    }

    func testLanguageOptionsUseTheirNativeNames() {
        XCTAssertNil(AppLanguage.system.nativeName)
        XCTAssertEqual(AppLanguage.simplifiedChinese.nativeName, "简体中文")
        XCTAssertEqual(AppLanguage.english.nativeName, "English")
        XCTAssertEqual(AppLanguage.spanish.nativeName, "Español")
        XCTAssertEqual(AppLanguage.german.nativeName, "Deutsch")
        XCTAssertEqual(AppLanguage.japanese.nativeName, "日本語")
        XCTAssertEqual(AppLanguage.french.nativeName, "Français")
        XCTAssertEqual(AppLanguage.portuguese.nativeName, "Português")
        XCTAssertEqual(AppLanguage.russian.nativeName, "Русский")
        XCTAssertEqual(AppLanguage.allCases.count, 9)
    }

    func testDocumentationLinkUsesChineseOnlyForChineseInterface() {
        XCTAssertEqual(
            DocumentationLinks.userGuideURL(for: .simplifiedChinese),
            DocumentationLinks.simplifiedChineseUserGuide
        )
        XCTAssertEqual(
            DocumentationLinks.userGuideURL(for: .english),
            DocumentationLinks.englishUserGuide
        )
        XCTAssertEqual(
            DocumentationLinks.userGuideURL(for: .system, preferredLanguages: ["zh-Hans-CN"]),
            DocumentationLinks.simplifiedChineseUserGuide
        )
        XCTAssertEqual(
            DocumentationLinks.userGuideURL(for: .system, preferredLanguages: ["en-US"]),
            DocumentationLinks.englishUserGuide
        )
    }

    func testNewLanguagesContainEveryEnglishString() throws {
        let englishKeys = try stringsKeys(in: .english)
        let languages: [AppLanguage] = [.spanish, .german, .japanese, .french, .portuguese, .russian]

        for language in languages {
            let localizedKeys = try stringsKeys(in: language)
            XCTAssertEqual(
                localizedKeys,
                englishKeys,
                "\(language.rawValue) must contain every English localization key"
            )
        }
    }

    func testNewLanguagesResolveSettingsTitle() {
        XCTAssertEqual(L10n.string("settings.title", language: .spanish), "Configuración")
        XCTAssertEqual(L10n.string("settings.title", language: .german), "Einstellungen")
        XCTAssertEqual(L10n.string("settings.title", language: .japanese), "設定")
        XCTAssertEqual(L10n.string("settings.title", language: .french), "Réglages")
        XCTAssertEqual(L10n.string("settings.title", language: .portuguese), "Configurações")
        XCTAssertEqual(L10n.string("settings.title", language: .russian), "Настройки")
    }

    func testSilentLaunchStringsExistInEnglishAndSimplifiedChinese() {
        let keys = ["settings.silentLaunch", "settings.silentLaunchDescription"]

        for key in keys {
            XCTAssertNotEqual(L10n.string(key, language: .english), key)
            XCTAssertNotEqual(L10n.string(key, language: .simplifiedChinese), key)
        }
    }

    func testBatchTwoStringsExistInEnglishAndSimplifiedChinese() {
        let keys = [
            "settings.providerFormat",
            "settings.providerFormatOpenAI",
            "settings.providerFormatAnthropic",
            "settings.proxy",
            "settings.proxyEnabled",
            "settings.proxyType",
            "settings.proxyTypeHTTP",
            "settings.proxyTypeSOCKS5",
            "settings.proxyHost",
            "settings.proxyPort",
            "settings.proxyUsername",
            "settings.proxyPassword",
            "settings.testProxy",
            "settings.proxyTestSuccess",
            "settings.proxyTestFailed",
            "settings.modelSelectionTitle",
            "settings.modelSelectionDescription",
            "settings.modelSelectionSelectAll",
            "settings.modelSelectionAdd",
            "settings.modelsAdded",
            "settings.modelAddFailed",
            "settings.diagnostics",
            "settings.diagnosticsEnabled",
            "settings.diagnosticsDescription",
            "settings.diagnosticsExport",
            "settings.diagnosticsClear",
            "settings.diagnosticsExported",
            "settings.diagnosticsExportFailed",
            "settings.diagnosticsCleared"
        ]

        for key in keys {
            XCTAssertNotEqual(L10n.string(key, language: .english), key)
            XCTAssertNotEqual(L10n.string(key, language: .simplifiedChinese), key)
        }
    }

    func testModelRefreshStringsExistInEnglishAndSimplifiedChinese() {
        let keys = [
            "settings.availableModels",
            "settings.refreshModels",
            "settings.modelRefreshDescription",
            "settings.modelRefreshUnavailable",
            "settings.modelRefreshNeedsKey",
            "settings.modelRefreshSuccess",
            "settings.modelRefreshFailed",
            "settings.modelRefreshCancelled",
            "settings.stopRefresh",
            "settings.discoveredModel",
            "settings.discoveredModelHint"
        ]

        for key in keys {
            XCTAssertNotEqual(L10n.string(key, language: .english), key)
            XCTAssertNotEqual(L10n.string(key, language: .simplifiedChinese), key)
        }
    }

    func testSelectionFeedbackStringsExistInEnglishAndSimplifiedChinese() {
        let keys = [
            "selection.feedback.permissionDenied",
            "selection.feedback.noSelection",
            "selection.feedback.unsupported",
            "selection.feedback.temporaryFailure",
            "selection.feedback.selectionChanged",
            "selection.feedback.sensitiveField"
        ]

        for key in keys {
            XCTAssertNotEqual(L10n.string(key, language: .english), key)
            XCTAssertNotEqual(L10n.string(key, language: .simplifiedChinese), key)
        }
    }

    func testSimplifiedChineseUsesTheSwiftPMPackagedLocalizationDirectory() {
        let bundle = L10n.localizedBundle(for: .simplifiedChinese)

        XCTAssertEqual(bundle.bundleURL.lastPathComponent, "zh-hans.lproj")
        XCTAssertEqual(bundle.localizedString(forKey: "settings.title", value: nil, table: "Localizable"), "设置")
    }

    private func stringsKeys(in language: AppLanguage) throws -> Set<String> {
        let bundle = L10n.localizedBundle(for: language)
        let resourceURL = try XCTUnwrap(bundle.resourceURL)
        let fileURL = resourceURL.appendingPathComponent("Localizable.strings")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return Set(
            content.split(separator: "\n").compactMap { line -> String? in
                let parts = line.split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2 else { return nil }
                return String(parts[1])
            }
        )
    }
}
