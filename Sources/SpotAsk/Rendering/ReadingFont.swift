import AppKit
import CoreText
import Foundation
import SwiftUI

/// One font family installed for the current user.
///
/// The family name is the persisted identifier: it is what Font Book shows and
/// what `Font.custom(_:size:)` and `NSFont(name:size:)` resolve to a family's
/// regular face. PostScript names are not persisted because they name a single
/// face (`HelveticaNeue-Regular`), so they cannot carry the family's bold and
/// medium faces through SwiftUI's font modifiers.
struct ReadingFontFamily: Identifiable, Hashable, Sendable {
    /// Canonical family name, e.g. `PingFang SC`.
    let id: String
    /// Name shown in the picker: the font's own localized family name when it
    /// has one, otherwise the canonical name.
    let displayName: String
}

/// Turns the stored reading-font preference into fonts for each rendering
/// surface. An empty value means the system font, and a family that is not
/// installed on this Mac falls back to the system font instead of leaving the
/// reader with an unstyled or unreadable transcript.
enum ReadingFontResolver {
    /// The stored value that selects the system font.
    static let systemDefault = ""

    /// The family to render with, or nil when the preference is the system font.
    static func family(for storedValue: String) -> String? {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether this Mac can actually render the stored family.
    static func isInstalled(_ storedValue: String) -> Bool {
        guard let family = family(for: storedValue) else { return true }
        return NSFont(name: family, size: 13) != nil
    }

    static func swiftUIFont(family storedValue: String, size: CGFloat) -> Font {
        guard let family = family(for: storedValue), NSFont(name: family, size: size) != nil else {
            return .system(size: size)
        }
        return .custom(family, size: size)
    }

    static func appKitFont(family storedValue: String, size: CGFloat) -> NSFont {
        guard let family = family(for: storedValue) else { return .systemFont(ofSize: size) }
        return NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
    }

    /// AppKit equivalent of a dynamic text style, keeping the style's point size.
    static func appKitFont(family storedValue: String, textStyle: NSFont.TextStyle) -> NSFont {
        appKitFont(family: storedValue, size: NSFont.preferredFont(forTextStyle: textStyle).pointSize)
    }

    /// The font's own family name when it is installed, otherwise the stored name.
    static func displayName(for storedValue: String) -> String {
        guard let family = family(for: storedValue),
              let font = NSFont(name: family, size: 13) else { return storedValue }
        return CTFontCopyLocalizedName(
            font as CTFont,
            kCTFontFamilyNameKey,
            nil
        ) as String? ?? family
    }
}

/// Enumerates the font families installed for the current user.
///
/// Enumeration is CoreText-only (thread-safe, no AppKit UI) and costs roughly
/// 120 ms cold, so the result is cached for the process and the settings page
/// fills its picker from a background task instead of blocking the window.
enum ReadingFontCatalog {
    private static let cache = ReadingFontCache()

    /// Families ordered by their display name.
    static func families() -> [ReadingFontFamily] {
        cache.families()
    }

    /// Builds the picker list from PostScript names, without the process cache.
    static func families(postScriptNames: [String]) -> [ReadingFontFamily] {
        // One representative face per family stands in for it: the closest to a
        // plain upright face, which is the face `Font.custom` picks for body text.
        var representatives: [String: (postScriptName: String, displayName: String, score: Int)] = [:]
        for postScriptName in postScriptNames {
            let font = CTFontCreateWithName(postScriptName as CFString, 13, nil)
            let family = CTFontCopyFamilyName(font) as String
            let traits = CTFontGetSymbolicTraits(font)
            var score = 0
            if !traits.contains(.traitItalic) { score += 2 }
            if !traits.contains(.traitBold) { score += 1 }
            if let existing = representatives[family], existing.score >= score { continue }
            let displayName = (CTFontCopyLocalizedName(font, kCTFontFamilyNameKey, nil) as String?) ?? family
            representatives[family] = (postScriptName, displayName, score)
        }

        return representatives
            .compactMap { family, info -> ReadingFontFamily? in
                // Symbol and non-Latin-only families (Apple Color Emoji, Apple
                // Braille, Hebrew, Arabic, Indic) cannot set Latin text, so they
                // would only add an unreadable entry to the picker.
                guard hasBasicLatinCoverage(postScriptName: info.postScriptName) else { return nil }
                return ReadingFontFamily(id: family, displayName: info.displayName)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func hasBasicLatinCoverage(postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 13, nil)
        var characters = Array("Aa1".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let mapped = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        return mapped && !glyphs.contains(0)
    }
}

private final class ReadingFontCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ReadingFontFamily]?

    func families() -> [ReadingFontFamily] {
        lock.lock()
        if let stored {
            lock.unlock()
            return stored
        }
        lock.unlock()

        let loaded = ReadingFontCatalog.families(
            postScriptNames: CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        )

        lock.lock()
        stored = loaded
        lock.unlock()
        return loaded
    }
}

extension AppSettings {
    /// Body size shared by the chat transcript and the settings preview, so
    /// both follow the font-size and zoom preferences.
    var readingFontSize: CGFloat {
        let baseSize: CGFloat
        switch fontSize {
        case .small: baseSize = 13
        case .standard: baseSize = 14.5
        case .large: baseSize = 17
        }
        return baseSize * interfaceZoomLevel.displayScale
    }

    var readingFont: Font {
        ReadingFontResolver.swiftUIFont(family: readingFontFamily, size: readingFontSize)
    }
}
