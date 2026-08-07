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

The Release workflow does not wait on Apple's notarization queue. It imports the certificate into a temporary Keychain, builds both signed DMGs, submits them with `notarytool submit --no-wait`, and stores the submission IDs as `notary-*.json` assets on a **Draft Release**.

The `notarize-poll.yml` workflow checks draft releases every 30 minutes. While a draft has `notary-*.json` markers, it queries Apple and waits. Once both submissions are `Accepted`, it dispatches `release-finalize.yml`, which:

1. Downloads the draft DMGs.
2. Runs `xcrun stapler staple` and validates the notarization ticket.
3. Replaces the checksum file with the stapled artifacts.
4. Removes the `notary-*.json` markers.
5. Publishes the release.

The public release is only created after Apple accepts both architectures. To finalize a draft manually:

```sh
gh workflow run release-finalize.yml \
  --repo shiquda/SpotAsk \
  --field release_tag=v0.1.4
```

Notarization can occasionally take much longer than the usual few minutes. A new account or a submission Apple holds for review can remain `In Progress` for hours, so leaving the Draft Release in place and letting the poll workflow retry is expected.

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
3. Run `swift test` and build both DMGs with `Scripts/make-release-dmg.sh`. If Apple secrets are configured, the Release workflow signs and notarizes them automatically.
4. Tag the release `vX.Y.Z` and push the tag.
5. GitHub Actions creates the GitHub Release, attaches both DMGs plus the SHA256SUMS file, and copies the changelog section into the release notes.

## Contributing

Use Conventional Commits (`feat:`, `fix:`, `docs:`, ...). Keep user-visible changes in sync with `CHANGELOG.md`, and run `swift test` before pushing. See `AGENTS.md` for the repository's collaboration rules.
