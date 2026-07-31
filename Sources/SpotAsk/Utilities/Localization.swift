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
        string(key, language: .current, arguments: arguments)
    }

    static func string(_ key: String, language: AppLanguage, arguments: [CVarArg] = []) -> String {
        let format = localizedBundle(for: language).localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle {
        guard language != .system,
              let resourceURL = bundle.resourceURL else {
            return bundle
        }

        let localizedResourceURL = resourceURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
        guard let localizedBundle = Bundle(url: localizedResourceURL) else {
            return bundle
        }

        return localizedBundle
    }
}
