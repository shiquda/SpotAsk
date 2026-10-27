import Foundation

protocol SelectionDiagnosticsSink: Sendable {
    func record(_ event: String)
}

struct UserDefaultsSelectionDiagnosticsSink: SelectionDiagnosticsSink, @unchecked Sendable {
    static let defaultDefaultsKey = "selectionDiagnostics"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultDefaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    func record(_ event: String) {
        var events = defaults.stringArray(forKey: key) ?? []
        events.append(event)
        defaults.set(Array(events.suffix(12)), forKey: key)
    }
}
