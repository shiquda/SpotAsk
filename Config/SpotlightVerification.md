# Spotlight and App Shortcuts Verification

## Build and install

Use a signed build for manual testing. The target has the `com.spotask.app` bundle identifier, `LSUIElement`, App Sandbox, and the outgoing-network entitlement.

```sh
cd /Users/jim/Documents/SpotAsk
xcodebuild -project SpotAsk.xcodeproj -scheme SpotAsk -configuration Release \
  -derivedDataPath build/xcode-derived build
sudo ditto build/xcode-derived/Build/Products/Release/SpotAsk.app /Applications/SpotAsk.app
sudo codesign --force --sign - --entitlements Config/SpotAsk.entitlements /Applications/SpotAsk.app
```

For distribution, replace the ad hoc signature with an Apple Development or Developer ID Application signing identity selected in Xcode's Signing & Capabilities pane.

## Register with macOS

Register the installed bundle with Launch Services, then launch it once. Launching is required because `SpotAskAppDelegate` calls `SpotAskShortcuts.updateAppShortcutParameters()`.

```sh
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f -u /Applications/SpotAsk.app
mdimport /Applications/SpotAsk.app
open -a SpotAsk
```

Quit the app from its menu-bar menu after its first launch, then use `Command-Space` and search for `SpotAsk`. The Spotlight result must open the installed app when selected.

## Verify App Shortcuts

App Shortcuts are registered with the Shortcuts and Siri system services. Open Shortcuts, create a shortcut, choose **Add Action**, and search for `SpotAsk`. The following actions must appear:

- Open SpotAsk
- Ask SpotAsk
- Start New SpotAsk Conversation

The system controls the exact set and ordering of results shown by Spotlight. A macOS app can reliably be discovered and opened from Spotlight, but it cannot add custom controls or embed an AI answer in Spotlight's private interface. App Shortcut actions are therefore verified in Shortcuts/Siri; selecting the Spotlight app result is the supported handoff into SpotAsk.

If Spotlight does not show the newly installed app, verify the bundle location with `mdls -name kMDItemDisplayName /Applications/SpotAsk.app`, rerun the Launch Services registration command above, and log out and back in before retrying.
