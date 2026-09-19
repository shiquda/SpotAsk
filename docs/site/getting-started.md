---
title: Getting Started
description: Install SpotAsk, connect an AI service, and ask your first question.
---

# Getting Started

SpotAsk runs as a native macOS menu bar app. After you connect an AI service, the shortest workflow is:

1. Press `⌥ + Space` (or your configured hotkey) to open the question window.
2. Ask your question.
3. Copy the answer or press `⎋` to close the window and return to what you were doing.

## Requirements

- macOS 15 or later
- An OpenAI-compatible or Anthropic chat service account with an access key

## Install SpotAsk

Install with Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

Or download the matching package from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases):

- **Apple silicon** Macs use the `arm64` DMG.
- **Intel** Macs use the `x86_64` DMG.

Open the DMG and move SpotAsk to Applications. The official release is signed with a Developer ID and notarized by Apple. After launch, SpotAsk appears only in the menu bar.

## Connect your AI service

Open Settings from the menu bar (or press `⌘ + ,`), then open **Services**.

1. Add or select a service.
2. Choose **API Format**: **OpenAI Compatible** or **Anthropic**.
3. Enter the service address.
4. Choose **Address Type**: **Service Root** or **Full Request Address**.
5. Enter your **Access Key**.
6. Add or select the **Model ID** your provider expects.
7. Click **Test Connection**.

If the test succeeds, close Settings and ask your first question. Most connection problems are address, key, or model ID mistakes; see [Troubleshooting](/troubleshooting) when the test fails.

The whole setup is one path with two decisions:

```mermaid Connection setup: choose an API format, choose an address type, then test the connection
flowchart TD
  A[Add or select a service] --> B{API Format}
  B -->|OpenAI Compatible| C[Enter the service address]
  B -->|Anthropic| C
  C --> D{Address Type}
  D -->|Service Root| E[SpotAsk appends the chat path<br/>Model discovery available]
  D -->|Full Request Address| F[Use the exact chat endpoint<br/>Add models manually]
  E --> G[Save the access key]
  F --> G
  G --> H[Add the Model ID]
  H --> I{Test Connection}
  I -->|Success| J[Ask your first question]
  I -->|Failure| K[Check address, key, and model ID<br/>or see Troubleshooting]
```

<SpotAskSettingsLink section="provider" />

## Ask your first question

Click the menu bar icon or press `⌥ + Space`. Type a question and press `↩`.

The answer streams into the window when the service supports it. You can:

- Click **Copy** on an answer or code block.
- Press `⎋` to stop a response.
- Press `⌘ + N` to start a new conversation.

## Explore next

- [Explore SpotAsk](/explore) shows what else the app can do.
- [Connect an OpenAI-Compatible Service](/guides/connect-openai-compatible) explains provider setup in more detail.
- [Privacy & Local Data](/privacy) explains where your keys, conversations, and selection data stay.
