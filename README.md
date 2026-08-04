# SpotAsk

A focused AI chat companion that lives in your macOS menu bar. Connect a compatible service and ask from anywhere.

[简体中文](README.zh-CN.md)

![SpotAsk showing the chat composer and built-in prompt actions](images/spotask-chat.png)

## What SpotAsk does

- **Ask from anywhere** — press Option + Space to open a focused chat window, ready for a question.
- **Use your own service** — connect a service compatible with the OpenAI Chat Completions API. You control the service address, model, and access key.
- **See answers as they arrive** — stop a response, retry a failed request, or regenerate the latest answer.
- **Copy what you need** — grab the full answer, or copy individual code blocks in one click.
- **Automate common tasks** — built-in prompts for translate, explain, summarize, and polish. Create your own for repeated workflows.
- **Work with Spotlight, Siri, and Shortcuts** — ask a question, start a new conversation, or run a prompt directly from macOS.

## Download

Download the matching package from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases):

- **Apple silicon** — choose the `arm64` DMG for M-series Macs.
- **Intel** — choose the `x86_64` DMG for Intel Macs.

The packages do not yet have a Developer ID, so macOS asks you to confirm the first launch. To use SpotAsk from Spotlight, Siri, or Shortcuts, build it from source with your own Apple development team by following [Build with system integrations](#build-with-system-integrations).

## Quick start

You can also build SpotAsk from source.

**Requirements**

- macOS 15 or later
- Xcode 16 or later
- An account with a service that provides an OpenAI-compatible chat completions endpoint

**Build and run**

```sh
./scripts/make-app-bundle.sh
open build/SpotAsk.app
```

After launch, SpotAsk appears in your menu bar. The app has no Dock icon.

### Build with system integrations

Spotlight, Siri, and Shortcuts require a build signed with an Apple development team. A free Apple Account is sufficient for a personal build:

1. Open `SpotAsk.xcodeproj` in Xcode.
2. Select the SpotAsk target, then open **Signing & Capabilities**.
3. Choose your Personal Team under **Team** and keep **Automatically manage signing** enabled.
4. If Xcode reports that the bundle identifier is unavailable, change **Bundle Identifier** to a unique value.
5. Run the app from Xcode once before using its actions in Shortcuts.

Personal Team builds are intended for personal use and may need to be rebuilt periodically.

## First-run configuration

Open Settings from the menu bar (or press Cmd + ,) and fill in:

1. **Service address** — the full chat endpoint URL for your provider.
2. **Model** — the model name your provider expects (for example, `gpt-5-mini`).
3. **Access key** — your service credential, stored only on this Mac.

Use **Test Connection** to confirm the values work, then close Settings and start asking.

## Everyday use

| Action | How |
|---|---|
| Open the chat window | Click the menu bar icon, or press **Option + Space** |
| Send a question | Type your question and press Return |
| Add a line break | Shift + Return |
| Stop generating | Press Escape, or click Stop |
| Copy an answer | Right-click the answer, or use the copy button |
| Copy a code block | Click the copy icon on any code block |
| Start a new conversation | Choose New Conversation from the menu bar |
| Use a prompt | With content in the input, select a prompt to send immediately. With an empty input, select one, enter your question, then press Return. |

The window remembers its size and position across launches.

## Privacy

Questions, custom instructions, and responses are sent to the service you configure. Review that provider's privacy and data-retention policies before handling sensitive information.

Your access key and settings stay on this Mac. When conversation retention is enabled, recent conversations are stored locally as well.

## For developers

### Build and test

```sh
# Run the test suite
swift test

# Build a release binary
swift build -c release

# Create an app bundle
./scripts/make-app-bundle.sh
open build/SpotAsk.app

# Create an Apple silicon or Intel DMG
./scripts/make-release-dmg.sh --arch arm64
./scripts/make-release-dmg.sh --arch x86_64
```

### Project overview

SpotAsk is a SwiftUI app that targets macOS 15 as a menu-bar accessory (`LSUIElement`). It uses [Textual](https://github.com/gonzalezreal/textual) to render rich-text responses.

The entry point is `Sources/SpotAsk/App/SpotAskApp.swift`. Tests live under `Tests/SpotAskTests/`.

### Distribution

When preparing the app for distribution, configure the signing, permissions, and network access required by your delivery method.

## License

SpotAsk is licensed under the [GNU AGPL v3](LICENSE).
