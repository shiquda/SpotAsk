# Development

This guide is for people who build, test, package, localize, or release SpotAsk. If you are a user, see [README.md](README.md) instead.

## Requirements

- macOS 15 or later
- Xcode 16 or later
- A service account with an OpenAI-compatible or Anthropic endpoint to exercise chat features

## Build and test

```sh
# Run the test suite
swift test

# Build a release binary
swift build -c release

# Create an app bundle
./Scripts/make-app-bundle.sh
open build/SpotAsk.app
```

## App bundle and DMG

`Scripts/make-app-bundle.sh` creates `build/SpotAsk.app`. The default entitlements (`Config/SpotAsk.selection-assistant.entitlements`) disable App Sandbox so the selection assistant can read selected text with Accessibility permission.

`Scripts/make-release-dmg.sh` packages DMGs for each architecture:

```sh
./Scripts/make-release-dmg.sh --arch arm64
./Scripts/make-release-dmg.sh --arch x86_64
```

Signing and notarization are optional and configured through environment variables: `SPOTASK_CODESIGN_IDENTITY`, `SPOTASK_REQUIRE_DEVELOPER_ID`, `SPOTASK_REQUIRE_NOTARIZATION`, `SPOTASK_NOTARY_KEYCHAIN_PROFILE`, `SPOTASK_NOTARY_KEYCHAIN`.

## Project layout

- `Sources/SpotAsk/App` — app entry point, status bar, command center
- `Sources/SpotAsk/Chat` — chat models, view model, streaming
- `Sources/SpotAsk/Provider` — OpenAI-compatible and Anthropic providers, model discovery, proxy
- `Sources/SpotAsk/Rendering` — chat UI, markdown, code blocks, thinking display, toasts
- `Sources/SpotAsk/Selection` — cross-app selection assistant: accessibility reads, action bar, overlay
- `Sources/SpotAsk/Settings` — settings model and views, shortcuts
- `Sources/SpotAsk/Intents` — Spotlight, Siri, and Shortcuts integration
- `Sources/SpotAsk/Utilities` — localization, diagnostics, clipboard helpers
- `Tests/SpotAskTests` — unit tests

## Localization

Interface strings live in `Sources/SpotAsk/Resources/<lang>.lproj/Localizable.strings` and `AppShortcuts.strings`. To add a language:

1. Add a case to `AppLanguage` in `Sources/SpotAsk/Settings/AppSettings.swift`, including its `nativeName`.
2. Create the `<lang>.lproj` directory and add both string tables.
3. Use `L10n.string("key")` for UI strings and keep the English table in sync.

## Accessibility

The selection assistant reads selected text through the macOS Accessibility API. When a user enables the feature in Settings, the app requests permission once; reads run on a background queue. See `research/macos-accessibility-permission-guidance.md` for details.

## Release checklist

1. Update `CHANGELOG.md`: rename `## [Unreleased]` to the new version with today's date, then open a fresh `## [Unreleased]` section.
2. Bump `MARKETING_VERSION` in `SpotAsk.xcodeproj/project.pbxproj` and `CFBundleShortVersionString` in `Resources/Info.plist`.
3. Run `swift test` and build both DMGs with `Scripts/make-release-dmg.sh`.
4. Tag the release `vX.Y.Z` and push the tag.
5. Create a GitHub Release for the tag and attach both DMGs plus the SHA256SUMS file; copy the changelog section into the release notes.

## Contributing

Use Conventional Commits (`feat:`, `fix:`, `docs:`, ...). Keep user-visible changes in sync with `CHANGELOG.md`, and run `swift test` before pushing. See `AGENTS.md` for the repository's collaboration rules.
