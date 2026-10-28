import AppKit
import XCTest
@testable import SpotAsk

@MainActor
final class ReadingFontTests: XCTestCase {
    func testCatalogListsInstalledFamiliesOnceEachInDisplayOrder() {
        let families = ReadingFontCatalog.families()

        XCTAssertFalse(families.isEmpty)
        XCTAssertEqual(Set(families.map(\.id)).count, families.count, "a family must appear once")
        XCTAssertEqual(
            families.map(\.displayName),
            families.map(\.displayName).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        )
        XCTAssertTrue(families.contains { $0.id == "Helvetica Neue" })
    }

    func testCatalogDropsFamiliesThatCannotSetLatinText() {
        let postScriptNames = [
            "AppleColorEmoji",
            "AppleBraille",
            "PingFangSC-Regular",
            "PingFangSC-Semibold",
        ]

        let families = ReadingFontCatalog.families(postScriptNames: postScriptNames)

        XCTAssertEqual(families.map(\.id), ["PingFang SC"])
    }

    func testCatalogUsesTheFamilysOwnLocalizedName() throws {
        let families = ReadingFontCatalog.families(postScriptNames: ["PingFangSC-Regular"])

        let family = try XCTUnwrap(families.first)
        XCTAssertEqual(family.id, "PingFang SC")
        let expected = CTFontCopyLocalizedName(
            CTFontCreateWithName("PingFangSC-Regular" as CFString, 13, nil),
            kCTFontFamilyNameKey,
            nil
        ) as String?
        XCTAssertEqual(family.displayName, try XCTUnwrap(expected))
    }

    func testStoredFamilyKeepsItsPreferenceWhenItIsNotInstalled() {
        let missing = "SpotAsk Missing Font Family"

        XCTAssertNil(ReadingFontResolver.family(for: ""))
        XCTAssertFalse(ReadingFontResolver.isInstalled(missing))
        XCTAssertTrue(ReadingFontResolver.isInstalled(""))
        XCTAssertEqual(ReadingFontResolver.displayName(for: missing), missing)

        let font = ReadingFontResolver.appKitFont(family: missing, size: 14)
        XCTAssertEqual(font.fontName, NSFont.systemFont(ofSize: 14).fontName)
    }

    func testStoredFamilyResolvesToThatFamilyAndKeepsTheRequestedSize() {
        let font = ReadingFontResolver.appKitFont(family: "Helvetica Neue", textStyle: .body)

        XCTAssertEqual(font.familyName, "Helvetica Neue")
        XCTAssertEqual(font.pointSize, NSFont.preferredFont(forTextStyle: .body).pointSize)
    }

    func testEmptyPreferenceRendersTheSystemFontAtTheReadingSize() {
        let settings = makeSettings()

        XCTAssertEqual(ReadingFontResolver.family(for: settings.readingFontFamily), nil)
        XCTAssertEqual(
            ReadingFontResolver.appKitFont(family: settings.readingFontFamily, size: 14).fontName,
            NSFont.systemFont(ofSize: 14).fontName
        )
        XCTAssertEqual(settings.readingFontSize, 14.5)
    }

    func testReadingFontSizeFollowsFontSizeAndZoom() {
        let settings = makeSettings()

        settings.fontSize = .large
        settings.interfaceZoomLevel = .compact
        XCTAssertEqual(settings.readingFontSize, 17 * 0.9, accuracy: 0.001)

        settings.fontSize = .small
        settings.interfaceZoomLevel = .large
        XCTAssertEqual(settings.readingFontSize, 13 * 1.3, accuracy: 0.001)
    }

    func testReadingFontDefaultsToSystemAndPersists() {
        let suite = "ReadingFontTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).readingFontFamily, "")

        let settings = AppSettings(defaults: defaults)
        settings.readingFontFamily = "Georgia"

        XCTAssertEqual(AppSettings(defaults: defaults).readingFontFamily, "Georgia")
    }

    func testReadingFontRoundTripsThroughConfigurationBackupAndResets() throws {
        let sourceSuite = "ReadingFontTests.source.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        let destinationSuite = "ReadingFontTests.destination.\(UUID().uuidString)"
        let destinationDefaults = UserDefaults(suiteName: destinationSuite)!
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }

        let source = AppSettings(defaults: sourceDefaults)
        source.readingFontFamily = "Georgia"
        let backup = try source.makeConfigurationBackup()

        let destination = AppSettings(defaults: destinationDefaults)
        try destination.applyConfigurationBackup(backup)
        XCTAssertEqual(destination.readingFontFamily, "Georgia")

        let descriptor = try XCTUnwrap(
            SettingRegistry.shared.descriptors.first { $0.key == "readingFontFamily" }
        )
        descriptor.reset(in: destination, defaults: destinationDefaults)
        XCTAssertEqual(destination.readingFontFamily, "")
        XCTAssertEqual(destinationDefaults.string(forKey: "readingFontFamily"), "")
    }

    func testFontSearchMatchesLocalizedNameAndFamilyName() {
        let families = [
            ReadingFontFamily(id: "PingFang SC", displayName: "PingFang SC"),
            ReadingFontFamily(id: "Helvetica Neue", displayName: "Helvetica Neue"),
        ]

        XCTAssertEqual(
            ReadingFontPickerList.filtered(families, matching: "").map(\.id),
            ["PingFang SC", "Helvetica Neue"],
            "an empty query keeps every family in catalogue order"
        )
        XCTAssertEqual(
            ReadingFontPickerList.filtered(families, matching: "  helv ").map(\.id),
            ["Helvetica Neue"]
        )
        XCTAssertEqual(
            ReadingFontPickerList.filtered(families, matching: "pingfang").map(\.id),
            ["PingFang SC"]
        )
        XCTAssertTrue(ReadingFontPickerList.filtered(families, matching: "Georgia").isEmpty)
    }

    func testFontSearchMatchesTheShownLocalizedNameNotOnlyTheStoredFamily() {
        let families = [ReadingFontFamily(id: "STSong", displayName: "华文宋体")]

        XCTAssertEqual(ReadingFontPickerList.filtered(families, matching: "华文").map(\.id), ["STSong"])
        XCTAssertEqual(ReadingFontPickerList.filtered(families, matching: "stsong").map(\.id), ["STSong"])
    }

    func testFontPickerHighlightKeepsSelectionAndStopsAtBothEnds() {
        let ids = ["", "Georgia", "Helvetica Neue"]

        XCTAssertEqual(ReadingFontPickerList.resolvedHighlight(current: "Georgia", selection: "", in: ids), "Georgia")
        XCTAssertEqual(
            ReadingFontPickerList.resolvedHighlight(current: "Arial", selection: "Helvetica Neue", in: ids),
            "Helvetica Neue"
        )
        XCTAssertEqual(
            ReadingFontPickerList.resolvedHighlight(current: "Arial", selection: "Arial", in: ids),
            "",
            "a font the search filtered away never stays highlighted"
        )
        XCTAssertNil(ReadingFontPickerList.resolvedHighlight(current: nil, selection: "", in: []))

        XCTAssertEqual(ReadingFontPickerList.movedHighlight(from: "", in: ids, by: 1), "Georgia")
        XCTAssertEqual(ReadingFontPickerList.movedHighlight(from: "Helvetica Neue", in: ids, by: 1), "Helvetica Neue")
        XCTAssertEqual(ReadingFontPickerList.movedHighlight(from: "", in: ids, by: -1), "")
        XCTAssertNil(ReadingFontPickerList.movedHighlight(from: nil, in: [], by: 1))
    }

    func testPickerRowLabelsAreLocalizedInEveryLanguage() {
        for language in AppLanguage.allCases where language != .system {
            for key in [
                "settings.readingFont",
                "settings.readingFontSystem",
                "settings.readingFontSample",
                "settings.readingFontSearchPlaceholder",
                "settings.readingFontSearchNoResults",
            ] {
                XCTAssertNotEqual(
                    L10n.string(key, language: language),
                    key,
                    "\(language.rawValue) is missing \(key)"
                )
            }
        }
    }

    private func makeSettings() -> AppSettings {
        let suite = "ReadingFontTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }
}
