---
title: macOS AI Launcher
description: "SpotAsk is a native Swift & AppKit macOS AI launcher. Summon instantly with a global hotkey, copy with dedicated shortcuts, and dismiss smoothly."
---

# macOS AI Launcher: Fast Hotkey Summoning and Keyboard-First Interaction

SpotAsk is a native macOS AI launcher designed for frequent, lightweight questions.

Press a global keyboard shortcut to bring up a focused floating window above your current work, stream the response in real time, and dismiss it quickly without breaking your workflow.

## Core Capabilities

- **Instant Hotkey Summoning**: A global hotkey (<kbd>⌥ + Space</kbd> by default) summons the floating window over any fullscreen application, IDE, or browser without desktop space sliding.
- **Silent Menu-Bar Residency**: Runs as a lightweight macOS accessory application, staying resident in the menu bar without taking up Dock space.
- **Keyboard-First Controls**: Supports dedicated shortcut copying (default: <kbd>⌘ + ⇧ + C</kbd>); dismiss smoothly when done, with <kbd>⎋</kbd> behavior adapted to current state and settings (such as stopping streaming, closing popovers, or dismissing the window).

## 3-Step Quick Start

1. **Confirm Hotkey**: Launch SpotAsk, check the default summoning shortcut (<kbd>⌥ + Space</kbd>) in **Settings > Shortcuts**, or record your preferred key combination.
2. **Configure Model**: Open **Settings > Services**, configure your API provider, endpoint, and model ID, then click "Test Connection".
3. **Summon & Ask**: Press your hotkey anywhere, type your prompt, and press Enter to stream answers.

## Visual Demo

![SpotAsk instant hotkey summoning and question window popup on macOS](/images/spotask-hotkey.gif)
*Figure 1: Summoning SpotAsk over active macOS applications with a global hotkey.*

## Verified Boundaries & Practical Notes

- **Operating System Requirement**: SpotAsk is built with modern Swift and AppKit, requiring macOS 15.0 (Sequoia) or later.
- **Hotkey Conflicts**: SpotAsk warns you when a shortcut collides with another SpotAsk shortcut, so you can record a conflict-free combination in Settings > **Shortcuts**. It cannot detect a key that another app already owns: if Raycast, ChatGPT, or a similar utility has claimed <kbd>⌥ + Space</kbd>, give the hotkey to one app only. See [ChatGPT ⌥Space conflicts](/guides/chatgpt-option-space).
- **Secure Input Protection**: In password prompts or secure terminal sessions where macOS activates Secure Input, global hotkey capture is temporarily suspended by the operating system for security.

## Download SpotAsk

Download the latest DMG from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) (Apple Silicon and Intel supported), or install via Homebrew:

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### Related Guides

- [BYOK Native AI Client](/use-cases/byok-macos-ai) — Bring your own API key with pay-as-you-go billing.
- [External Ask & Intent Routing](/use-cases/external-ask-routing) — Route queries to web AI or local CLI agents.
- [Global Selection Assistant](/use-cases/selection-assistant) — In-place text processing across apps.
- [Shortcuts Reference](/reference) — Complete guide to global and in-window keybindings.
