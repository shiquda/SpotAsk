import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class GeneralSettingsState {
    private let settings: AppSettings
    private let keyStore: any APIKeyStoring
    private let settingsWindowProvider: (() -> NSWindow?)?
    var status = ""
    var statusIsError = false
    private let onConfigurationImported: () -> Void

    var proxyPasswordDraft: String
    var isTestingProxy = false

    init(
        settings: AppSettings,
        keyStore: any APIKeyStoring,
        settingsWindowProvider: (() -> NSWindow?)? = nil,
        onConfigurationImported: @escaping () -> Void
    ) {
        self.settings = settings
        self.keyStore = keyStore
        self.settingsWindowProvider = settingsWindowProvider
        self.onConfigurationImported = onConfigurationImported
        proxyPasswordDraft = (try? keyStore.readAPIKey(for: ProxyCredentialSlot.providerID)) ?? ""
    }

    private static func makeProxyConfiguration(
        settings: AppSettings,
        keyStore: any APIKeyStoring
    ) -> [String: Any]? {
        guard settings.proxyEnabled else { return nil }
        let password = (try? keyStore.readAPIKey(for: ProxyCredentialSlot.providerID)) ?? ""
        return ChatNetworking.proxyConfiguration(
            type: settings.proxyType,
            host: settings.proxyHost,
            port: settings.proxyPort,
            username: settings.proxyUsername,
            password: password
        )
    }
    func persistProxyPasswordDraft() {
        do {
            if proxyPasswordDraft.isEmpty {
                try keyStore.deleteAPIKey(for: ProxyCredentialSlot.providerID)
            } else {
                try keyStore.saveAPIKey(proxyPasswordDraft, for: ProxyCredentialSlot.providerID)
            }
        } catch {
            setStatus(L10n.string("settings.saveKeyFailure"), isError: true)
        }
    }

    func testProxy() {
        guard !isTestingProxy else { return }
        guard let catalog = settings.providerRegistry.catalog,
              let selectedModel = catalog.models.first(where: { $0.id == catalog.selectedModelID }),
              let provider = catalog.providers.first(where: { $0.id == selectedModel.providerID }) else {
            setStatus(L10n.string("settings.proxyTestFailed"), isError: true)
            return
        }
        isTestingProxy = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = Self.makeProxyConfiguration(settings: self.settings, keyStore: self.keyStore)
                guard let configuration else {
                    throw ChatError.invalidConfiguration
                }
                let session = ChatNetworking.urlSession(proxyConfiguration: configuration)
                defer { session.invalidateAndCancel() }

                var request = URLRequest(url: try URLNormalizer.modelsEndpoint(
                    from: provider.address,
                    format: provider.format
                ))
                request.httpMethod = "GET"
                request.timeoutInterval = 15
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ChatError.invalidResponse
                }
                // Any HTTP response means the request reached the service
                // through the proxy; auth and 4xx/5xx still prove connectivity.
                _ = httpResponse.statusCode
                self.setStatus(L10n.string("settings.proxyTestSuccess"), isError: false)
            } catch {
                self.setStatus(L10n.string("settings.proxyTestFailed"), isError: true)
            }
            self.isTestingProxy = false
        }
    }
    func exportConfiguration(presentingWindow: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SpotAsk-Config.json"
        let includeKeysCheckbox = NSButton(
            checkboxWithTitle: L10n.string("settings.exportIncludeKeys"),
            target: nil,
            action: nil
        )
        includeKeysCheckbox.state = .off
        includeKeysCheckbox.sizeToFit()
        panel.accessoryView = includeKeysCheckbox
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(
                    self.settings.makeConfigurationBackup(
                        includeAccessKeys: includeKeysCheckbox.state == .on,
                        keyStore: self.keyStore
                    )
                )
                try data.write(to: url, options: .atomic)
                self.setStatus(L10n.string("settings.configExported"), isError: false)
            } catch {
                self.setStatus(
                    "\(L10n.string("settings.configExportFailed"))\n\(error.localizedDescription)",
                    isError: true
                )
            }
        }
        if let window = presentingWindow ?? settingsWindowProvider?() ?? NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }

    func importConfiguration(presentingWindow: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let backup = try JSONDecoder().decode(SpotAskConfigBackup.self, from: data)
                try self.settings.applyConfigurationBackup(backup, keyStore: self.keyStore)
                self.onConfigurationImported()
                self.setStatus(L10n.string("settings.configImported"), isError: false)
            } catch {
                self.setStatus(
                    "\(L10n.string("settings.configImportFailed"))\n\(error.localizedDescription)",
                    isError: true
                )
            }
        }
        if let window = presentingWindow ?? settingsWindowProvider?() ?? NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }

    // MARK: Global data clear

    func clearAllLocalData() {
        do {
            try keyStore.deleteAllAPIKeys()
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.spotask.app")
            setStatus(L10n.string("settings.resetSuccess"), isError: false)
        } catch {
            setStatus(L10n.string("settings.resetFailure"), isError: true)
        }
    }

    // MARK: Diagnostics

    func exportDiagnostics(presentingWindow: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "SpotAsk-Diagnostics.txt"
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return }
            do {
                try DiagnosticLogStore.shared.exportedText().write(to: url, atomically: true, encoding: .utf8)
                self.setStatus(L10n.string("settings.diagnosticsExported"), isError: false)
            } catch {
                self.setStatus(L10n.string("settings.diagnosticsExportFailed"), isError: true)
            }
        }
        if let window = presentingWindow ?? settingsWindowProvider?() ?? NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }

    func clearDiagnostics() {
        DiagnosticLogStore.shared.clear()
        setStatus(L10n.string("settings.diagnosticsCleared"), isError: false)
    }

    // MARK: Private

    private func setStatus(_ value: String, isError: Bool) {
        status = value
        statusIsError = isError
        StatusToastCenter.shared.show(value, isError: isError)
    }
}
