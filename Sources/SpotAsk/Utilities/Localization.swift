import Foundation

enum L10n {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var bundleCache: [AppLanguage: Bundle] = [:]

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

    static func localizedBundle(for language: AppLanguage) -> Bundle {
        guard language != .system,
              let resourceURL = bundle.resourceURL else {
            return bundle
        }

        cacheLock.lock()
        if let cached = bundleCache[language] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let localizedResourceURL = try? FileManager.default
            .contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            .first {
                $0.pathExtension == "lproj"
                    && $0.deletingPathExtension().lastPathComponent
                        .caseInsensitiveCompare(language.rawValue) == .orderedSame
            }
        guard let localizedResourceURL,
              let localizedBundle = Bundle(url: localizedResourceURL) else {
            return bundle
        }

        cacheLock.lock()
        bundleCache[language] = localizedBundle
        cacheLock.unlock()

        return localizedBundle
    }
}
