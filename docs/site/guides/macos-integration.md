---
title: Spotlight, Siri & Shortcuts
description: Use SpotAsk from Spotlight, Siri, Shortcuts, or a spotask:// URL.
---

# Spotlight, Siri & Shortcuts

The official SpotAsk release registers app actions that macOS can expose to Spotlight, Siri, and Shortcuts. It also registers the `spotask://` URL scheme for Alfred, Raycast, terminal scripts, and Shortcuts.

<SpotAskSettingsLink section="shortcuts" />

## Quick Summary

SpotAsk integrates deeply with native macOS system entrypoints by registering App Intents for Spotlight, Siri, and Apple Shortcuts, alongside an authenticated `spotask://` URL scheme. This enables friction-free AI invocation from Alfred, Raycast, terminal scripts, keyboard macros, and automated macOS workflows without keeping the main chat window open.

## Applicable Scenarios

- **Launcher Automation (Raycast & Alfred)**: Summon SpotAsk with a pre-filled query directly from Raycast, Alfred, or custom hotkeys via `spotask://ask?q={query}`.
- **Hands-Free Voice Control with Siri**: Speak "Ask SpotAsk a question" or "Ask SpotAsk to translate [text]" on macOS to trigger instant voice-to-text queries.
- **Multi-Step Shortcuts Automation**: Build Apple Shortcuts workflows that capture selected files, clipboard clippings, or webpage text and pass them into SpotAsk prompts like **Translate**, **Summarize**, or **Ask AI**.

## Prerequisites & Compatibility

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Operating System** | macOS 15.0 (Sequoia) or later | App Intents and Spotlight deep integration require macOS 15+ |
| **Application Version** | SpotAsk `v0.1.0+` official signed release | Universal binary (`arm64` Apple Silicon & `x86_64` Intel) |
| **Code Signing** | Apple Developer ID signed application | Required for macOS system daemons to recognize and index App Intents |
| **Installation Path** | `/Applications/SpotAsk.app` | Launch at least once after installation to register URL schemes and intents |
| **Supported Launchers** | Apple Spotlight, Siri, Shortcuts, Raycast, Alfred | Any tool capable of opening `spotask://` URLs or running macOS Shortcuts |

## Step-by-Step Instructions

1. **Install and Register**: Place `SpotAsk.app` in `/Applications` and launch it once to register the `spotask://` URL handler and App Intents with macOS.
2. **Summon via Global Hotkey**: Press `⌥ + Space` (default) to summon the floating question window from any application.
3. **Trigger from Spotlight**: Press `⌘ + Space`, type `SpotAsk`, and choose an action such as **Ask SpotAsk a question** or **Translate**.
4. **Trigger via Terminal or URL**: Run `open "spotask://ask?q=What%20is%20Swift%20concurrency"` from Terminal or a script to launch and query SpotAsk immediately.
5. **Automate in Shortcuts**: Open the macOS **Shortcuts** app, search for **SpotAsk**, and add actions like **Ask AI**, **Summarize**, or **Translate** to your automations.
6. **Navigate to Settings Directly**: Use stable deep-links like `open "spotask://settings/shortcuts"` or `open "spotask://settings/provider"` to jump straight to specific settings panels.

## Visual Proof

![SpotAsk instant hotkey summoning and question window popup on macOS](/images/spotask-hotkey.gif)
*Figure 1: SpotAsk responds instantly to global macOS summoning hotkeys and system-level URL triggers, displaying a lightweight floating interface.*

## Known Limitations & Boundaries

- **URL Parameter Percent-Encoding**: Queries passed via `spotask://ask?q=...` must be RFC 3986 percent-encoded; raw spaces, ampersands, or non-ASCII characters without encoding may be truncated by macOS URL dispatchers.
- **Self-Built / Ad-Hoc Build Limitations**: If building SpotAsk locally from source without an Apple Developer ID certificate (using a free Personal Team), macOS Shortcuts and Spotlight will not index App Intents until the app is run from Xcode.
- **Cold Launch Behavior**: If SpotAsk is not running when a `spotask://` link is invoked, macOS launches the app first; the action executes immediately once initialization completes.
- **Background Persistence**: SpotAsk runs as an accessory menu bar application without a dock icon by default; closing the chat window hides the UI while keeping shortcuts and URL listeners active.

## Available actions

- **Open SpotAsk** opens the question window.
- **Ask AI** asks a question.
- **Translate**, **Explain**, **Summarize**, and **Polish** run the matching built-in prompt on content you provide.
- **New Conversation** clears the current conversation and opens SpotAsk.

## Spotlight

Search for SpotAsk in Spotlight and choose an action such as **Ask SpotAsk a question**, then enter your content or question.

## Siri

Ask Siri to use a SpotAsk action, for example "Ask SpotAsk to translate [text]".

## Shortcuts

Open the Shortcuts app and search for SpotAsk actions. Add an action with its required content, or build a larger shortcut that passes text, a question, or another shortcut's output to SpotAsk.

## URL scheme

Open these links from another app, a shortcut, or Terminal. Spaces and other special characters in a question must be percent-encoded.

| URL | What it does |
| --- | --- |
| `spotask://open` | Opens the question window |
| `spotask://ask?q=Your%20question` | Fills in the question and sends it |
| `spotask://ask?q=Your%20question&submit=false` | Fills in the question without sending |
| `spotask://toggle` | Shows or hides the question window |
| `spotask://settings` | Opens Settings |
| `spotask://settings/<page>` | Opens one Settings page |

`<page>` is a stable ASCII id, never a localized interface title:

| Page id | Settings page |
| --- | --- |
| `provider` | Service |
| `prompts` | Prompts |
| `external-ask` | External Ask |
| `selection-assistant` | Selection Assistant |
| `shortcuts` | Shortcuts |
| `general` | General |
| `appearance` | Appearance |
| `about` | About |

Ids are case-insensitive. A missing or unknown id, an extra path segment, or a fragment falls back to plain Settings instead of failing.

From Terminal:

```sh
open "spotask://ask?q=What%20is%20Swift%20concurrency"
```

If SpotAsk is not running, the URL launches it and then runs the command. If it is already in the menu bar, the command runs immediately.

## Custom builds

System integrations work in the official release. If you build SpotAsk yourself, the app must be signed with an Apple development team, and you should run it once from Xcode before using its actions in Shortcuts. Personal Team builds are for personal use and may need to be rebuilt periodically.

Related: [Prompts](/guides/prompts), [Getting Started](/getting-started)
