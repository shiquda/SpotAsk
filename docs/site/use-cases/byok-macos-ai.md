---
title: BYOK Native macOS AI Client
description: "SpotAsk is a native bring-your-own-key (BYOK) macOS AI client. Connect OpenAI, Anthropic, Gemini, DeepSeek, or local Ollama with zero middleman servers and local credential storage."
---

# BYOK Native macOS AI Client: Connect Your Own Models and API Keys

SpotAsk is built on a Bring-Your-Own-Key (BYOK) architecture, connecting directly to your own API keys or locally hosted models.

Requests travel directly to your provider's official endpoints with zero proxy servers in between, no user accounts, and billing governed solely by your chosen provider and actual compute usage.

## Core Capabilities

- **Multi-Provider & Protocol Support**: Native support for OpenAI-compatible endpoints, Anthropic Messages API, and Google Gemini REST API, switchable via the model picker in the composer.
- **Direct Communication & Local Credential Storage**: Requests are dispatched directly to provider endpoints without intermediate relay servers. API access keys are stored in a local credentials file restricted to the current user (`0600`); the current implementation does not use Keychain.
- **Local Offline Model Execution**: Built-in support for loopback services like Ollama or LM Studio, allowing full offline operation when traveling or disconnected.

## 3-Step Quick Start

1. **Open Services Settings**: Launch SpotAsk, press <kbd>⌘ + ,</kbd> to open Settings, and select the **Services** tab.
2. **Configure Provider & Key**: Click "Add Service", select your API format, enter your endpoint address, access key, and model ID, then click "Test Connection".
3. **Select Model & Ask**: Summon SpotAsk using your global hotkey, pick your configured service from the top model picker, and start asking.

## Visual Demo

![SpotAsk conversation window showing model selector with deepseek-v4-flash and prompt presets](/images/spotask-chat.png)
*Figure 1: SpotAsk floating conversation window displaying on-the-fly model selection across configured BYOK providers.*

## Verified Boundaries & Practical Notes

- **Provider Account Required**: SpotAsk is a BYOK client and does not sell or distribute API credits. You supply your own API key from OpenAI, Anthropic, Google, or host a local model like Ollama.
- **Billing & Quotas**: Compute costs are billed directly by your model provider based on your actual token usage; rate limits and concurrency limits are governed by your provider account tier.
- **Service Address Formatting**: OpenAI-compatible services distinguish between a Service Root (`https://api.openai.com/v1`) and a Full Request Address (`https://api.openai.com/v1/chat/completions`). See our documentation for endpoint conventions.

## Download SpotAsk

Download the latest DMG from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) (Apple Silicon and Intel supported), or install via Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### Related Guides

- [Connect an OpenAI-Compatible Service](/guides/connect-openai-compatible) — Setup for OpenAI, DeepSeek, and Groq.
- [Connect Anthropic](/guides/connect-anthropic) — Claude API keys and streaming configuration.
- [Service Root vs Full Request Address](/guides/service-addresses) — Endpoint URL guidelines.
- [Zero-Telemetry Privacy Architecture](/use-cases/privacy-architecture) — Credential storage and data routing.
