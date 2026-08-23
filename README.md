<p align="center">
  <img src="images/spotask-icon.png" width="104" alt="SpotAsk app icon">
</p>

<h1 align="center">SpotAsk</h1>

<p align="center">
  A native macOS menu-bar AI assistant & query router. Ask instantly with a hotkey — get fast in-app answers with your own AI service (BYOK) or route queries to ChatGPT, local CLI agents, and other external tools in 1 click.

<p align="center">
  <a href="https://github.com/shiquda/SpotAsk/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/shiquda/SpotAsk?display_name=tag&sort=semver"></a>
  <a href="https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/github/license/shiquda/SpotAsk"></a>
</p>

<p align="center">
  Pure Swift · ~10 MB installer · No Electron · Privacy-first · macOS 15+ · Apple silicon & Intel · AGPL-3.0
</p>

<p align="center">
  <a href="#download">Download</a> · <a href="https://shiquda.github.io/SpotAsk/">Documentation</a> · <a href="#quick-start">Build from source</a> · <a href="#development">Development</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="images/spotask-chat.png" width="640" alt="SpotAsk question window in light and dark appearance with prompts and External Ask buttons">
</p>

## What SpotAsk does

- **Route queries in 1 click (External Ask)** — hand off questions to 3 concrete destinations without consuming API tokens or saving history:
  - **Web platforms** — launch queries directly in ChatGPT, Perplexity, Grok, and more.
  - **Desktop apps** — trigger installed desktop applications via custom URI schemes.
  - **Terminal & CLI agents** — wake up local CLI agents directly in Terminal.
- **Instant hotkey capture** — press `Option + Space` (customizable) to summon a focused input window from anywhere; get direct streaming answers using your own API key (BYOK), or press `Esc` to instantly close the window when done.
- **Selection assistant** — highlight text in Safari, Notes, Xcode, or any other app; translate, explain, summarize, polish, or run custom prompts from a floating quick action bar.
- **Ask with attachments** — paste screenshots or drop in images, text, and code files; follow-up questions seamlessly retain the attached context.
- **Prompt presets & shortcuts** — built-in prompts for everyday workflows plus custom prompt creation; record custom shortcuts for every frequent action.
- **Featherweight pure native** — built entirely in Swift and AppKit; cold-starts instantly, idles quietly in the menu bar, and uses minimal memory.

## Core philosophy & typical use cases

SpotAsk is designed around **"Ask first. Decide where it goes after"** and **"Done and gone"** — keeping everyday AI interactions lightweight, keyboard-first, and zero-overhead.

### 1. Core interaction: Summon, ask, and close

Press your global hotkey (default `Option + Space`) to summon the question window from anywhere, get streaming answers directly in the window, and press `Esc` to instantly close it when done.

<p align="center">
  <img src="images/spotask-hotkey.gif" width="480" alt="SpotAsk chat window summoned with a hotkey, streaming answers, and closing with Escape">
</p>

### 2. Everyday extensions: Selection assistant & External routing

<table>
  <tr>
    <td width="50%" align="center"><strong>Ask about selected text</strong></td>
    <td width="50%" align="center"><strong>External Ask (CLI agents & tools)</strong></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="images/spotask-selection.gif" width="480" alt="SpotAsk quick action bar next to selected text in another app"></td>
    <td width="50%" align="center"><img src="images/spotask-external.gif" width="480" alt="SpotAsk routing a question to a local CLI agent in Terminal"></td>
  </tr>
  <tr>
    <td width="50%" align="center">Select text in any app to trigger the floating action bar for instant translation, explanation, or custom prompts.</td>
    <td width="50%" align="center">Press a shortcut to hand off questions to local CLI agents (e.g. omp) or web AI platforms in 1 click without API keys.</td>
  </tr>
</table>

## Download

Install with Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

Or download the matching package from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases):

- **Apple silicon** — choose the `arm64` DMG for M-series Macs.
- **Intel** — choose the `x86_64` DMG for Intel Macs.

The packages are signed with a Developer ID and notarized by Apple, so macOS can verify them on first launch without a manual confirmation. The official release supports SpotAsk from Spotlight, Siri, or Shortcuts. To build a custom version instead, follow [Build with system integrations](#build-with-system-integrations).

## Documentation

The [SpotAsk user guide](https://shiquda.github.io/SpotAsk/) covers installation, AI service setup, selection actions, prompts, attachments, macOS integrations, settings, and troubleshooting. It is available in [English](https://shiquda.github.io/SpotAsk/) and [Simplified Chinese](https://shiquda.github.io/SpotAsk/zh-CN/).

Start with [Getting Started](https://shiquda.github.io/SpotAsk/getting-started), or open [Troubleshooting](https://shiquda.github.io/SpotAsk/troubleshooting) when a connection, model, permission, or shortcut does not work as expected.

## Quick start

You can also build SpotAsk from source.

**Requirements**

- macOS 15 or later
- Xcode 16 or later
- A service account that provides an OpenAI-compatible or Anthropic chat API

**Build and run**

```sh
./Scripts/install-debug-app.sh
```

After launch, SpotAsk Debug appears in your menu bar. It uses a separate app identity so its macOS permissions do not replace those of the official release. The app has no Dock icon.

### Build with system integrations

The official release supports Spotlight, Siri, and Shortcuts. If you build a custom version, sign it with an Apple development team. A free Apple Account is sufficient for a personal build:

1. Open `SpotAsk.xcodeproj` in Xcode.
2. Select the SpotAsk target, then open **Signing & Capabilities**.
3. Choose your Personal Team under **Team** and keep **Automatically manage signing** enabled.
4. If Xcode reports that the bundle identifier is unavailable, change **Bundle Identifier** to a unique value.
5. Run the app from Xcode once before using its actions in Shortcuts.

Personal Team builds are intended for personal use and may need to be rebuilt periodically.

## First-run configuration

Open Settings from the menu bar (or press Cmd + ,) and fill in:

1. **Provider** — select the service you want to use (OpenAI-compatible or Anthropic), or add a new one.
2. **Model** — the model name your provider expects (for example, `gpt-5-mini`).
3. **Access key** — your service credential, stored only on this Mac.

Use **Test Connection** to confirm the values work, then close Settings and start asking.

## Everyday use

| Action | How |
| --- | --- |
| Open the chat window | Click the menu bar icon, or press your configured hotkey (default Option + Space) |
| Send a question | Type your question and press Return |
| Add a line break | Shift + Return |
| Stop generating | Press Escape, or click Stop |
| Copy an answer | Right-click the answer, or use the copy button |
| Copy a code block | Click the copy icon on any code block |
| Run a prompt on selected text | Select text in another app, then click an action in the quick action bar |
| Start a new conversation | Choose New Conversation from the menu bar |
| Use a prompt | With content in the input, select a prompt to send immediately. With an empty input, select one, enter your question, then press Return. |
| Open Settings | Click the menu bar icon and choose Settings, or press Cmd + , |

The window remembers its size and position across launches.

## Privacy

Privacy-first by design: SpotAsk is a native macOS app, your access key stays on this Mac, and your selected text is sent only to the service you configure.

Questions, custom instructions, and responses are sent to the service you configure. Review that provider's privacy and data-retention policies before handling sensitive information.

Your access key and settings stay on this Mac. When conversation retention is enabled, recent conversations are stored locally as well.

The selection assistant reads the text you select through the macOS Accessibility API. Permission is requested only when you enable the feature, and selected text is sent only to the service you configured.

## Development

Build, test, packaging, localization, and release instructions live in [DEVELOPMENT.md](DEVELOPMENT.md).

## License

SpotAsk is licensed under the [GNU AGPL v3](LICENSE).
