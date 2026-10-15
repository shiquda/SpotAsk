---
title: Zero-Telemetry Privacy Architecture
description: "SpotAsk is built with a local-first, zero-telemetry architecture. No user accounts, no proxy servers, and local credential storage."
---

# Zero-Telemetry Privacy Architecture: Data Destinations and Local-First Design

SpotAsk is engineered from the ground up on a local-first, zero-telemetry privacy model.

The application operates without user accounts, logins, or commercial licensing servers. It maintains zero proprietary intermediate relay servers, and contains no third-party tracking or analytics SDKs in its binary.

The complete codebase is open-source under GNU AGPL-3.0 on GitHub for independent public audit.

## Data Destination Overview

| Data Type | Storage & Network Destination | Access & User Control |
| :--- | :--- | :--- |
| **API Access Keys** | Local credentials file (`credentials.json`) | File permissions restricted to the current user (`0600`; current implementation does not use Keychain); editable or deletable at any time |
| **Prompts & Attachments** | Direct connection to your configured provider (or loopback) | Dispatched via HTTPS only when actively querying; remote providers process data per their own privacy policies; on-device when using Ollama |
| **Decision Routing Text** | Your configured external decision service (disabled by default) | Transmitted only when decision routing is enabled and a prompt is sent; prompts with attachments bypass routing and go directly to conversation models |
| **Preferences & History** | Local application support directory (`~/Library/Application Support/SpotAsk/`) | Used exclusively for local display and history; never synchronized to external servers; wipeable with one click |
| **Update Checking** | Official GitHub Releases API (optional) | Single check at launch to compare version numbers; transmits zero prompt contents, device fingerprints, or keys; can be disabled in Settings |

## 3-Step Quick Start & Verification

1. **Traffic Audit**: After installation, inspect background network activity using tools like Little Snitch or Proxyman. You will observe zero background telemetry connections when idle.
2. **Configure Direct Keys or Local Models**: In **Settings > Services**, supply your own API key or configure a local Ollama endpoint for completely offline operation.
3. **Purge Local Data**: In **Settings > General**, click "Clear All Local Data" to immediately delete your local credentials file, preferences, and cached conversations.

## Verified Boundaries & Practical Notes

- **Third-Party Provider Policies**: While SpotAsk does not log or intermediate your requests, the external API provider you configure (such as OpenAI, Anthropic, or Google) handles prompts according to their published data policies. For complete data isolation, use local models via Ollama.
- **Decision Service Boundaries**: When automated Decision Routing is enabled in External Ask, prompt text and channel candidate names are sent over HTTPS to your configured decision service for classification.
- **Open-Source Transparency**: SpotAsk is written in standard Swift and AppKit and published on GitHub, allowing anyone to verify network request handling and local file operations.

## Download SpotAsk

Download the latest DMG from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) (Apple Silicon and Intel supported), or install via Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### Related Guides

- [Privacy & Local Data Official Policy](/privacy) — Detailed breakdown of local storage locations and diagnostics.
- [BYOK Native AI Client](/use-cases/byok-macos-ai) — Bring your own API keys with pay-as-you-go billing.
- [macOS AI Launcher](/use-cases/mac-ai-launcher) — Instant global hotkey summoning.
- [Explore SpotAsk](/explore) — Complete capability map for native macOS AI workflows.
