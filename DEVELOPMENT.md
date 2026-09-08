# Development

This guide is for people who build, test, package, localize, or release SpotAsk. If you are a user, see [README.md](README.md) instead.

## Requirements

- macOS 15 or later
- Xcode 16 or later
- A service account with an OpenAI-compatible or Anthropic endpoint to exercise chat features

## Documentation site

The user documentation lives in `docs/site` and is built with VitePress. The source is bilingual: English at `/`, Simplified Chinese under `/zh-CN/`.

```sh
npm install
npm run docs:dev
npm run docs:build
npm run docs:preview
```

The GitHub Pages workflow in `.github/workflows/docs.yml` builds `docs/site` and deploys it to `https://shiquda.github.io/SpotAsk/`.

## Build and test

```sh
# Run the test suite
swift test

# Build a release binary
swift build -c release

# Build, install, and open an isolated local Debug app
./Scripts/install-debug-app.sh
```

## App bundle and DMG

`Scripts/make-app-bundle.sh` creates `build/SpotAsk.app`. The default entitlements (`Config/SpotAsk.selection-assistant.entitlements`) disable App Sandbox so the selection assistant can read selected text with Accessibility permission.

For day-to-day development, use `Scripts/install-debug-app.sh`. It installs `~/Applications/SpotAsk Debug.app` with bundle ID `com.spotask.app.debug` and an Apple Development signature. This keeps its Accessibility permission and Launch Services identity separate from the official `SpotAsk.app`. Set `SPOTASK_DEBUG_CODESIGN_IDENTITY` only when you need to choose a different Apple Development certificate.

`Scripts/make-app-bundle.sh` remains the lower-level Release bundler used by the DMG workflow. It also accepts `--configuration Debug` for custom local workflows.

`Scripts/make-release-dmg.sh` packages DMGs for each architecture:

```sh
./Scripts/make-release-dmg.sh --arch arm64
./Scripts/make-release-dmg.sh --arch x86_64
```

Signing and notarization are optional and configured through environment variables:

- `SPOTASK_CODESIGN_IDENTITY` — Developer ID Application identity name
- `SPOTASK_REQUIRE_DEVELOPER_ID` — set to `1` to require a Developer ID signature
- `SPOTASK_REQUIRE_NOTARIZATION` — set to `1` to submit the DMG to Apple Notary
- `SPOTASK_NOTARY_KEYCHAIN_PROFILE` — local Keychain profile from `notarytool store-credentials`
- `SPOTASK_NOTARY_KEYCHAIN` — optional Keychain path when using a profile
- `SPOTASK_NOTARY_APPLE_ID` / `SPOTASK_NOTARY_TEAM_ID` / `SPOTASK_NOTARY_PASSWORD` — direct notarization credentials for CI

### Apple Developer setup

SpotAsk is distributed outside the App Store, so it needs a **Developer ID Application** certificate and Apple notarization. A free Personal Team cannot provide this; the paid Apple Developer Program is required.

1. Sign in to Xcode with the paid Apple ID: **Xcode > Settings > Accounts**.
2. In the Apple Developer website, open **Certificates, Identifiers & Profiles > Certificates**, click **+**, and choose **Developer ID Application**.
3. Select the **G2 Sub-CA**, upload a CSR generated on this Mac, download the `.cer`, and combine it with the matching private key into a `.p12` file. Import the `.p12` into the login Keychain.
4. Confirm the identity is available:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

The project uses team ID `6UR4V5Z3N7` and bundle ID `com.spotask.app`. Confirm these values under **Certificates, Identifiers & Profiles** in the [Apple Developer site](https://developer.apple.com/account/).

Create an app-specific password at [account.apple.com](https://account.apple.com/sign-in) under **Sign-In and Security > App-Specific Passwords**. Use that password only for notarization; your normal Apple ID password cannot be used.

### Local signed and notarized DMG

Store the notarization credentials in the macOS login Keychain once:

```sh
xcrun notarytool store-credentials "SpotAskNotary" \
  --apple-id "you@example.com" \
  --team-id "6UR4V5Z3N7"
```

Then build, sign, and notarize locally:

```sh
SPOTASK_CODESIGN_IDENTITY="Developer ID Application: your name (TEAMID)" \
SPOTASK_REQUIRE_DEVELOPER_ID=1 \
SPOTASK_REQUIRE_NOTARIZATION=1 \
SPOTASK_NOTARY_KEYCHAIN_PROFILE=SpotAskNotary \
./Scripts/make-release-dmg.sh --arch arm64
```

The result is `dist/SpotAsk-<version>-arm64.dmg`. If notarization succeeds, `spctl` passes and opening the DMG no longer shows the "unidentified developer" Gatekeeper warning.

For a one-off CI-style local test without a Keychain profile, the script also accepts:

```sh
SPOTASK_NOTARY_APPLE_ID="you@example.com" \
SPOTASK_NOTARY_TEAM_ID="6UR4V5Z3N7" \
SPOTASK_NOTARY_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
SPOTASK_REQUIRE_DEVELOPER_ID=1 \
SPOTASK_REQUIRE_NOTARIZATION=1 \
./Scripts/make-release-dmg.sh --arch arm64
```

Prefer the Keychain profile on your own Mac; the direct environment variables exist mainly for GitHub Actions secrets.

### GitHub Actions signing

Export the Developer ID identity as a PKCS#12 file for the runner. Select **Developer ID Application** in Keychain Access, choose **Export**, and set a password for the `.p12`.

Encode the file without line breaks:

```sh
base64 -i DeveloperID.p12 -o DeveloperID.p12.base64
```

Add these secrets to **Settings > Secrets and variables > Actions** (or to the `release` environment used by the workflow):

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | contents of `DeveloperID.p12.base64` |
| `APPLE_CERTIFICATE_PASSWORD` | password chosen when exporting the `.p12` |
| `APPLE_NOTARIZATION_APPLE_ID` | paid Apple ID used for notarization |
| `APPLE_NOTARIZATION_TEAM_ID` | `6UR4V5Z3N7` |
| `APPLE_NOTARIZATION_APP_PASSWORD` | app-specific password created above |

The Release workflow runs automatically on tag push (`v*`) or manual `workflow_dispatch`. It imports the Developer ID certificate into a temporary Keychain, builds both signed DMGs (`arm64` and `x86_64`), submits them concurrently to Apple Notary Service with `notarytool submit --wait --timeout 30m`, staples the notarization tickets, writes basename SHA-256 checksums, publishes the GitHub Release from a draft only after those assets are uploaded, and updates the Homebrew Cask formula on `main` from the published DMGs. Workflow helpers (`Scripts/notarize-dmg.sh` and the publish script) are taken from the workflow commit, not the app tag, so manually publishing an older tag still waits for notarization.

The 30-minute `--timeout` only ends local polling. Apple Notary Service can keep processing after the runner gives up, so a timeout is not a rejection and there is no promised wall-clock time to publication. If the wait times out or a later step fails, the GitHub Release stays missing or draft. Re-run the same tag with `workflow_dispatch`: a published release is never overwritten (Cask recovery reuses the published DMGs); a missing or draft release rebuilds, resubmits, and publishes only after a complete upload. `shasum -a 256 -c SpotAsk-vX.Y.Z-SHA256SUMS.txt` is expected to work in the same directory as the downloaded DMGs.

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

For local diagnosis, run:

```sh
uv run Scripts/check-localization.py
```

The script reports `L10n.string` keys missing from `Localizable.strings`, localization tables that do not match English, and optional unused English keys with `--include-unused`. It is intentionally not part of CI.

## Accessibility

The selection assistant reads selected text through the macOS Accessibility API. When a user enables the feature in Settings, the app requests permission once; reads run on a background queue. See `research/macos-accessibility-permission-guidance.md` for details.

Local Release rebuilds change the code signature even when the Developer ID stays the same. Accessibility permission is bound to that signature, so System Settings can still show SpotAsk as allowed while the new process cannot read selected text. At launch the app records the current code-directory hash, clears a leftover Accessibility grant with `tccutil` when the hash no longer matches a previously trusted install, and asks the user to allow the current install again.

## Release checklist

1. Update `CHANGELOG.md`: rename `## [Unreleased]` to the new version with today's date, then open a fresh `## [Unreleased]` section.
2. Bump `MARKETING_VERSION` in `SpotAsk.xcodeproj/project.pbxproj` and `CFBundleShortVersionString` in `Resources/Info.plist`.
3. Run `swift test` and build both DMGs with `Scripts/make-release-dmg.sh`. If Apple secrets are configured, the Release workflow signs and notarizes them automatically.
4. Tag the release `vX.Y.Z` and push the tag.
5. GitHub Actions creates the GitHub Release, attaches both DMGs plus the SHA256SUMS file, and copies the changelog section into the release notes.

## Contributing

Use Conventional Commits (`feat:`, `fix:`, `docs:`, ...). Keep user-visible changes in sync with `CHANGELOG.md`, and run `swift test` before pushing. See `AGENTS.md` for the repository's collaboration rules.
