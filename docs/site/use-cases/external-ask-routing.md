---
title: External Ask & Intent Routing
description: "Type your query once in SpotAsk, then route it to web services, local terminal tools, or desktop applications manually or via decision routing."
---

# External Ask & Intent Routing: Route Questions Across Tools from a Single Window

SpotAsk streamlines your query workflow: write down your question in a clean floating window, then send it off to the tool best suited to answer.

You can dispatch queries manually using in-window channel buttons or shortcuts, or optionally configure decision routing to receive destination suggestions when sending.

## Core Capabilities

- **Multiple Destination Types**: Forward queries directly to web search engines (such as Perplexity or ChatGPT), local command-line tools (such as CLI agents), or native macOS applications via URL schemes.
- **In-Window Quick Dispatch**: After typing, click a channel button or press its assigned shortcut to send; when the composer is empty, clicking or pressing the shortcut pre-selects the channel.
- **Optional Decision Routing**: You can configure and enable a decision service. When sending, SpotAsk requests a channel recommendation from your configured service, defaulting to manual confirmation before dispatch, or automatic release when confidence exceeds your threshold.

## 3-Step Quick Start

1. **Configure Channels**: Open **Settings > External Ask** to review built-in channels or click "New" to add custom web links, app schemes, or shell commands.
2. **(Optional) Configure Decision Routing**: If you want suggestions, fill in the service address, model ID, and API key under Decision Routing, and enable the toggle.
3. **Summon & Send**: Summon SpotAsk using your global hotkey, type your question, and click a channel or use its shortcut; if decision routing is active, confirm the suggested destination upon sending.

## Visual Demo

<video poster="/images/spotask-smart-routing-preview.gif" src="/videos/SpotAsk-smart-routing-v5.mp4" controls muted playsinline width="720"></video>

*Video: one question, three destinations — decision routing on real app footage (28s). [Download / Watch HD Video (1080p MP4)](/videos/SpotAsk-smart-routing-v5.mp4)*

![SpotAsk routing a question to a local CLI agent in Terminal](/images/spotask-external.gif)
*Figure 1: SpotAsk dispatching a question into a local CLI tool in Terminal.*

## Verified Boundaries & Practical Notes

- **Decision Service & Network Latency**: While the routing interface is built into the application, the classification model runs via an external decision service you configure, not locally on-device. Response time depends on network and service availability, guarded by a configurable timeout (default 2 seconds).
- **Data Transmission & Attachments**: When enabled, decision routing transmits your prompt text to the decision service for classification; prompts containing file or image attachments bypass decision routing and are handled directly by your configured conversation model (which may contact remote providers if configured).
- **Environment Dependencies**: Web channels depend on active login sessions in your default browser; terminal commands run in your user shell environment and require target CLI tools to be installed in your `$PATH`.

## Download SpotAsk

Download the latest DMG from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) (Apple Silicon and Intel supported), or install via Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### Related Guides

- [External Ask Guide](/guides/external-ask) — Custom channels, actions, and quick dispatch workflows.
- [Decision Routing Guide](/guides/decision-routing) — Intent classifier engines, dual-protocol setup, and threshold tuning.
- [macOS AI Launcher](/use-cases/mac-ai-launcher) — Instant global hotkey summoning.
- [BYOK Native AI Client](/use-cases/byok-macos-ai) — Connect your own API keys.
- [Global Selection Assistant](/use-cases/selection-assistant) — In-place text processing across apps.
