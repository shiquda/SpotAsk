---
title: "Use Your Own AI API Key in a Mac Menu Bar App | SpotAsk"
titleTemplate: false
description: "Add an OpenAI, Anthropic, or Gemini API key, test the connection, and ask from a Mac hotkey. Free and open source, with direct requests and local credentials."
---

# BYOK Mac menu bar AI assistant for quick questions

SpotAsk is a free, open-source Mac menu bar AI assistant for quick questions, built on a Bring-Your-Own-Key (BYOK) architecture. Summoned with <kbd>⌥ Space</kbd>, it answers questions, explains selected text, and routes prompts. API keys are stored locally on your Mac in a user-only file with `0600` permissions—never in macOS Keychain and never synced to external servers. Requests connect directly to your configured provider endpoint with zero SpotAsk intermediary servers, accounts, or telemetry. You pay only your model provider for consumed tokens.

## Why Bring Your Own Key for menu bar AI?

Most desktop AI tools require a $20/month subscription or route prompts through proprietary proxies that add markup, log prompts, and limit vendor choice. If you already maintain developer keys with OpenAI, OpenRouter, Anthropic, or Google—or run local models through Ollama—paying for another subscription just for desktop lookups is redundant.

SpotAsk decouples the native macOS interface from model providers:
- **No subscription markup**: Tokens cost exactly what your provider charges on developer billing tiers.
- **Direct requests**: Prompts travel straight to the provider API. With local runners like Ollama, prompts stay on loopback and never touch the Internet.
- **Provider flexibility**: Switch between cloud providers (OpenAI, Anthropic, Gemini) and local models directly from the top model picker.

## Verify your first answer in under a minute

SpotAsk lets you verify your connection and receive your first answer in seconds once your service is configured. 

The timeline below measures interaction after saving your endpoint and running **Test Connection**: summoning the window with <kbd>⌥ Space</kbd>, selecting your model, submitting a prompt, and receiving the first streaming token. It excludes one-time setup such as creating provider accounts, funding developer credits, or downloading local model weights.

![SpotAsk first answer demonstration showing model selection and streaming response](/images/spotask-byok-first-answer.gif)
*Figure 1: Complete quick-ask flow in SpotAsk with deepseek-v4-flash: selecting a configured model, submitting a test question, and receiving a streaming response.*

### Verified test prompt and response

We use a concise, predictable test prompt across verified configurations:

```text
Give me three concise names for a menu bar app that answers quick questions. Return one per line.
```

When tested against an OpenAI-compatible endpoint with `deepseek-v4-flash`, SpotAsk produced:

```text
QuickAsk QBar AnswerBar
```

- **Observed first-token latency**: ~700 ms from clicking send.
- **Observed total stream duration**: ~2.5 s.
- **Dismiss**: Press <kbd>Esc</kbd> to return to your active application.

## Prerequisites & Requirements

- **Operating System**: macOS 15.0 (Sequoia) or later. Universal binary for Apple Silicon (`arm64`) and Intel (`x86_64`).
- **Credentials or Local Runner**: An active API key from an OpenAI-compatible provider (OpenAI, OpenRouter, DeepSeek, Groq), Anthropic, or Google Gemini; or a running local runner like Ollama (`http://localhost:11434/v1`) or LM Studio (`http://localhost:1234/v1`).
- **Network**: Direct HTTPS access to provider endpoints, or HTTP to `localhost` for local runners. Proxy settings can be configured in **Settings > General**.

## Reproduce the setup: Step-by-step walkthrough

Follow these steps to configure an OpenAI-compatible service:

1. **Open Services Settings**: Open SpotAsk, press <kbd>⌘ ,</kbd> for Settings, and select **Services** in the sidebar (deep link: `spotask://settings/provider`).
2. **Add a service**: Click **Add Service**, select **OpenAI Compatible**, and name the service (e.g., `OpenRouter`).
3. **Configure endpoint address**:
   - **Service Root (Recommended)**: Enter the base URL (e.g., `https://openrouter.ai/api/v1`). SpotAsk appends `/chat/completions` for chat and queries `/models` for model discovery.
   - **Full Request Address**: Enter the completions URL (e.g., `https://openrouter.ai/api/v1/chat/completions`). Model discovery is disabled; model IDs must be entered manually.
4. **Save Access Key**: Paste your key into **Access Key** and click **Save Key**. The key is masked in the UI and written to `~/Library/Application Support/SpotAsk/credentials.json` with `0600` permissions (current user only). SpotAsk does not use macOS Keychain, avoiding signing-identity keychain prompt lockouts.
5. **Select model ID**: In Service Root mode, click **Refresh Models** to fetch models via `GET /models` and pick your model (e.g., `openai/gpt-4o-mini`). In Full Request Address mode, click **Add Model** and enter the model ID manually.
6. **Test Connection**: Click **Test Connection** before closing settings. SpotAsk sends a lightweight ping to verify address syntax, authentication, and model availability. A green message confirms success. If it fails, check for HTTP 401 (invalid key), HTTP 404 (address mismatch or invalid model ID), HTTP 429 (quota exhausted), or timeout.
7. **Summon and ask**: Press <kbd>⌥ Space</kbd>, verify your model in the top picker, enter your prompt, and press <kbd>Return</kbd> to stream the answer. Press <kbd>⌘ C</kbd> to copy or <kbd>Esc</kbd> to dismiss.

## Local and compatible endpoints: Support matrix

SpotAsk includes protocol drivers for OpenAI-compatible, Anthropic Messages, and Google Gemini REST APIs:

| Provider / Runner | Format | Address Convention | Status | Verified Boundaries |
| :--- | :--- | :--- | :--- | :--- |
| **OpenRouter** | OpenAI Compatible | Root: `https://openrouter.ai/api/v1` | **Tested** | Streaming SSE, model discovery (`GET /models`), connection test, and routing verified with `openai/gpt-4o-mini`. |
| **Google Gemini** | Gemini REST | Root: `https://generativelanguage.googleapis.com/v1beta` | **Tested** | Native `generateContent` with `x-goog-api-key`. Model discovery verified with Gemini 2.5 Flash and Pro. |
| **OpenAI Official** | OpenAI Compatible | Root: `https://api.openai.com/v1` | **Documented** | Reference implementation. Requires active developer credits. |
| **Anthropic** | Anthropic Messages | Root: `https://api.anthropic.com/v1` | **Documented** | Messages API with `x-api-key` and `anthropic-version: 2023-06-01` headers. |
| **Ollama** | OpenAI Compatible | Root: `http://localhost:11434/v1` | **Documented** | Loopback HTTP allowed (`localhost`, `127.0.0.1`). Runner must be running with models pulled. Chat stays on loopback. |
| **LM Studio** | OpenAI Compatible | Root: `http://localhost:1234/v1` | **Documented** | Requires local server with CORS enabled. Accepts placeholder key. |
| **Plain HTTP (Remote)** | Any | `http://...` (Non-loopback) | **Unsupported** | Rejected by URL normalizer to prevent plaintext transmission over public networks. Remote endpoints require HTTPS. |

See [Providers & Models](/guides/providers-and-models) for complete configuration parameters.

## What BYOK costs and where credentials go

- **App free vs token billing**: SpotAsk is 100% free open-source software (AGPL-3.0). Cloud AI models are billed directly by your provider per token. Quick questions consume a few hundred tokens (fractions of a cent on models like GPT-4o-mini). Connecting to a local runner like Ollama costs $0.
- **Consumer subscriptions are not API keys**: A $20/month ChatGPT Plus or Claude Pro subscription is a web product account, not an API key. Developer APIs require separate accounts funded through developer consoles. To use web subscriptions without API keys, use SpotAsk's [External Ask](/guides/external-ask) to hand off queries to browser tabs.
- **Credential storage and transmission**: API keys are saved locally in `~/Library/Application Support/SpotAsk/credentials.json` with `0600` permissions (readable only by your macOS user). Keys are sent directly over TLS to providers in HTTP headers. With local loopback models (Ollama on `127.0.0.1`), neither prompts nor credentials leave your Mac.

Review the [Zero-Telemetry Privacy Architecture](/use-cases/privacy-architecture) for local file and data flow details.

## When a full chat workspace is the better choice

SpotAsk is designed for instant answers, text selection lookups, and fast hand-offs rather than long, multi-threaded project management. A full chat workspace (such as official ChatGPT or Claude desktop apps) is the better choice when:

- **Persistent conversations**: Ongoing multi-turn chats organized into project folders, custom GPTs, or document workspaces.
- **Account-managed features**: Vendor-hosted memories, collaborative Canvas document editing, or native spoken voice modes.
- **Predictable flat subscription**: Paying $20/month rather than funding developer API credits, monitoring token usage, and rotating keys.
- **Multi-window management**: Dedicated multi-window chat organization and complex artifact panes.

SpotAsk complements full workspaces: keep your full chat workspace for deep sessions, and use SpotAsk on <kbd>⌥ Space</kbd> for quick answers, text selection, and routing. See [SpotAsk vs ChatGPT for Mac](/compare/chatgpt-mac) to compare both workflows in practice.

## Download SpotAsk

Download the latest DMG from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) (Apple Silicon and Intel supported), or install via Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### Related Guides

- [Connect an OpenAI-Compatible Service](/guides/connect-openai-compatible) — Setup for OpenAI, OpenRouter, DeepSeek, and Groq.
- [Connect Anthropic](/guides/connect-anthropic) — Claude API keys and streaming configuration.
- [Service Root vs Full Request Address](/guides/service-addresses) — Endpoint URL guidelines.
- [Zero-Telemetry Privacy Architecture](/use-cases/privacy-architecture) — Credential storage and data routing.
- [SpotAsk vs ChatGPT for Mac](/compare/chatgpt-mac) — BYOK menu bar workflow versus dedicated desktop workspace.
- [External Ask & Query Routing](/guides/external-ask) — Route questions to browser AI or terminal agents without an API key.
