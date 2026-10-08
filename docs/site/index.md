---
layout: home

title: SpotAsk
titleTemplate: "Native macOS AI Assistant & Query Router"
description: "SpotAsk is a free, open-source macOS menu-bar AI assistant and query router. Ask instantly with a hotkey — get fast in-app BYOK answers or route queries to ChatGPT, local CLI agents, and other tools in 1 click."

hero:
  name: SpotAsk
  tagline: "Ask first, decide where it goes after. A fast, native macOS menu-bar AI assistant & query router."
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started/
    - theme: alt
      text: Explore SpotAsk
      link: /explore/

features:
  - title: "Ask first, route anywhere"
    details: "Summon instantly with a hotkey, write your question, and choose: stream an in-app BYOK answer or route to web AI, desktop apps, and CLI agents in 1 click."
  - title: "Work with selected text"
    details: "Highlight text in any macOS app to translate, explain, summarize, polish, or bring directly into chat from the inline action bar."
  - title: "Bring your own AI service (BYOK)"
    details: "Connect OpenAI-compatible or Anthropic endpoints. Access keys stay encrypted in your Keychain with zero middle servers or telemetry."
  - title: "Lightweight & pure native"
    details: "~10 MB installer, pure Swift/AppKit, zero Electron runtime, keyboard-first with Esc-to-close, and instant cold launch."

# Rendered between the hero actions and the feature cards by SpotAskHeroShowcase.
heroShowcase:
  src: /images/spotask-hero.png
  alt: "SpotAsk — one prompt routed to an in-app answer, a web AI, or a local CLI agent"
---

## What is SpotAsk

SpotAsk is a free, open-source macOS menu-bar AI assistant and query router built on a simple premise: **"Ask first. Decide where it goes after."**

Press one hotkey — `⌥ + Space` by default — and a focused question window appears instantly over whatever you are doing. Write down your thought while it is fresh, then choose how to handle it:

- **In-app quick answers**: Get rapid streaming replies using your own configured AI model (BYOK).
- **1-click query routing (External Ask)**: Dispatch your query to web platforms (ChatGPT, Perplexity, Grok), desktop apps via URI schemes, or local CLI agents in Terminal — without consuming API tokens or saving history.

There is no account system, no telemetry, and nothing between you and your AI provider. When you close the window (`Esc`), SpotAsk is done and gone — leaving your workspace clean and uninterrupted.

### Core workflows in action

#### 1. Instant hotkey summoning
![Quick chat with the default hotkey](/images/spotask-hotkey.gif)

#### 2. Inline actions on selected text
![Quick actions on selected text](/images/spotask-selection.gif)

#### 3. 1-click query routing to CLI agents & tools
![1-click query routing to CLI agents and external tools](/images/spotask-external.gif)
## Next steps

- [Getting Started](/getting-started) walks through installation and your first question.
- [Explore SpotAsk](/explore) is a map of what you can do with the app.
- [Troubleshooting](/troubleshooting) covers connection, model, permission, and shortcut problems.
