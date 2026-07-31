import Foundation

enum L10n {
    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    static func string(_ key: String, _ arguments: CVarArg...)
        -> String {
        string(key, arguments: arguments)
    }

    static func string(_ key: String, arguments: [CVarArg] = []) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: .current, arguments: arguments)
    }
}
