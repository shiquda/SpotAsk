---
title: Getting Started
description: Install SpotAsk, connect an AI service, and ask your first question.
---

# Getting Started

SpotAsk runs as a native macOS menu bar app. You can start immediately in browser mode with **no API key**, or connect your own API key / local model for streamed answers inside the window:

1. Press `⌥ + Space` (or your configured hotkey) to open the question window.

   [ChatGPT took ⌥Space on your Mac?](/guides/chatgpt-option-space)
2. Type your question.
3. Click **Ask ChatGPT** (or Perplexity, Grok, or a local CLI agent) to hand it off with zero API setup — or press `↩` to stream an answer in the window once a service is configured.
4. Press `⎋` to dismiss the window and return to what you were doing.

## Requirements

- macOS 15 or later (Apple silicon `arm64` or Intel `x86_64`)
- **One of the following** (no API key is required to get started):
  - **No API key (External Ask)**: An active browser login (such as free or Plus `chatgpt.com`) or a local CLI tool to receive hand-offs from the ask box. *(Consumer subscriptions like ChatGPT Plus or Claude Pro do not include developer API access for in-window streaming.)*
  - **In-window streaming answers (optional BYOK / local model)**: An OpenAI-compatible, Anthropic, or Gemini API access key, or a local runner such as Ollama (`http://localhost:11434/v1`).

## Install SpotAsk

Download the matching `v0.3.4` package from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest):

- **Apple silicon**: [`SpotAsk-0.3.4-arm64.dmg`](https://github.com/shiquda/SpotAsk/releases/download/v0.3.4/SpotAsk-0.3.4-arm64.dmg)
- **Intel**: [`SpotAsk-0.3.4-x86_64.dmg`](https://github.com/shiquda/SpotAsk/releases/download/v0.3.4/SpotAsk-0.3.4-x86_64.dmg)

Open the DMG and move SpotAsk to Applications. The official release is signed with a Developer ID and notarized by Apple. After launch, SpotAsk appears only in the menu bar.

Or install with Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

## Option 1: Start immediately without an API key (External Ask)

If you do not want to create or fund a developer API key yet, you can use SpotAsk right away in browser or CLI hand-off mode:

1. Click the menu bar icon or press `⌥ + Space`.
2. Type your question.
3. Click **Ask ChatGPT** (or **Ask Perplexity** / **Ask Grok**, or press its shortcut shown in **Settings > Shortcuts**).

SpotAsk opens `chatgpt.com` in your default browser with the question pre-filled using the web session you already have signed in — no API key needed, and zero SpotAsk API token usage. See [External Ask](/guides/external-ask) to customize web targets or add local CLI agents.

## Option 2: Connect your AI service for in-window answers (BYOK)

To stream answers directly inside SpotAsk's floating window, open Settings from the menu bar (or press `⌘ + ,`), then open **Services**:

1. Add or select a service.
2. Choose **API Format**: **OpenAI**, **Anthropic**, or **Gemini**.
3. Enter the service address (for local Ollama, use `http://localhost:11434/v1`).
4. Choose **Address Type**: **Service Root** or **Full Request Address**.
5. Enter your **Access Key** (saved locally in `~/Library/Application Support/SpotAsk/credentials.json` with `0600` permissions; the current implementation does not use Keychain).
6. Add or select the **Model ID** your provider expects.
7. Click **Test Connection**.

If the test succeeds, close Settings and press `↩` in the question window to stream answers directly. Most connection problems are address, key, or model ID mistakes; see [Troubleshooting](/troubleshooting) when the test fails.

<SpotAskSettingsLink section="provider" />

## Ask your first question

Click the menu bar icon or press `⌥ + Space`, type a question, and choose how to send it:

- **Without an API key**: click an **External Ask** button such as **Ask ChatGPT** to open the question in your browser or CLI agent.
- **With a configured BYOK or local service**: press `↩` to stream the answer in the window. You can:
  - Click **Copy** on an answer or code block.
  - Press `⎋` to stop a response or close the window.
  - Press `⌘ + N` to start a new conversation.

## Explore next

- [Explore SpotAsk](/explore) shows what else the app can do.
- [Service Root vs Full Request Address](/guides/service-addresses) explains which address type to enter.
- [Connect an OpenAI-Compatible Service](/guides/connect-openai-compatible) explains provider setup in more detail.
- [Privacy & Local Data](/privacy) explains where your keys, conversations, and selection data stay.
