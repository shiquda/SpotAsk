---
layout: home

title: "SpotAsk – One Hotkey to Ask Any AI | Mac Menu Bar App"
titleTemplate: false
description: "Open-source Mac menu bar app: press ⌥Space to ask any AI with your own API key, ChatGPT, Perplexity, or a local CLI agent. Free and native."

hero:
  text: "One hotkey. Any AI."
  tagline: "A free, open-source menu bar assistant for Mac. Use your own API key, or send the question to ChatGPT, Perplexity, or a local CLI agent."
  actions:
    - theme: brand
      text: Download (Apple Silicon)
      link: https://github.com/shiquda/SpotAsk/releases/latest
    - theme: alt
      text: Download (Intel)
      link: https://github.com/shiquda/SpotAsk/releases/latest
    - theme: alt
      text: Get Started
      link: /getting-started

# Left info rendered by SpotAskHeroCompat; right terminal card rendered by
# SpotAskHeroInstall in #home-hero-image (see docs/site/.vitepress/theme/Layout.vue).
heroInstall:
  compat: "macOS 15+ · Apple Silicon / Intel · Native Swift"

features:
  - title: "Ask first, route anywhere"
    details: "Summon instantly with a hotkey, write your question, and choose: stream an in-app BYOK answer, or route to web AI, desktop apps, and CLI agents in 1 click or automatically with a decision model."
  - title: "Work with selected text"
    details: "Highlight text in any macOS app to translate, explain, summarize, polish, or bring directly into chat from the inline action bar."
  - title: "Bring your own AI service (BYOK)"
    details: "Connect OpenAI-compatible, Anthropic, or Gemini endpoints. Access keys stay encrypted in your Keychain with zero middle servers or telemetry."
  - title: "Lightweight & pure native"
    details: "Pure Swift/AppKit, zero Electron runtime, keyboard-first with Esc-to-close, and instant cold launch."

# Rendered below the hero install block by SpotAskHeroShowcase.
heroShowcase:
  src: /images/spotask-hero.png
  alt: "SpotAsk — one prompt routed to an in-app answer, a web AI, or a local CLI agent"
---

## What is SpotAsk

SpotAsk is a free, open-source macOS menu-bar AI assistant and query router built on a simple premise: **"Ask first. Decide where it goes after."**

Press one hotkey — `⌥ + Space` by default — and a focused question window appears instantly over whatever you are doing. Write down your thought while it is fresh, then choose how to handle it:

- **In-app quick answers**: Get rapid streaming replies using your own configured AI model (BYOK).
- **Smart & 1-click query routing (External Ask)**: Dispatch your query to web platforms (ChatGPT, Perplexity, Grok), desktop apps via URI schemes, or local CLI agents in Terminal — in 1 click or automatically with a decision model (such as `jev`), without consuming chat API tokens or saving history.

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
