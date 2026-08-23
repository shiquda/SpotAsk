---
layout: home

title: SpotAsk
titleTemplate: "Native macOS AI Assistant & Query Router"
description: "SpotAsk is a free, open-source macOS menu-bar AI assistant and query router. Ask instantly with a hotkey — get fast in-app BYOK answers or route queries to ChatGPT, local CLI agents, and other external tools in 1 click."

hero:
  name: SpotAsk
  text: Docs
  tagline: "Ask first, decide where it goes after. A fast macOS menu-bar AI assistant & query router."
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started/
    - theme: alt
      text: Explore SpotAsk
      link: /explore/

features:
  - title: "Ask first, route anywhere"
    details: "Summon instantly with one hotkey, type your question, and choose: stream an in-app BYOK answer or route to web platforms, desktop apps, and CLI agents in 1 click."
  - title: "Work with selected text"
    details: "Select text in any macOS app and translate, explain, summarize, polish, or run custom prompts from the inline action bar."
  - title: "Bring your own AI service (BYOK)"
    details: "Connect OpenAI-compatible or Anthropic endpoints. Access keys stay encrypted on your Mac with zero telemetry or middle servers."
  - title: "Lightweight & pure native"
    details: "~10 MB installer, pure Swift/AppKit, zero Electron runtime, keyboard-first with Esc-to-close, and instant cold launch."
---

![SpotAsk question window in light and dark appearance with prompts and External Ask buttons](/images/spotask-chat.png)

## What is SpotAsk

SpotAsk is a free, open-source macOS menu-bar AI assistant and query router built on a simple premise: **"Ask first. Decide where it goes after."**

Press one hotkey — `Option + Space` by default — and a focused question window appears instantly over whatever you are doing. Write down your thought while it is fresh, then choose how to handle it:

1. **In-app quick answers**: Get rapid streaming replies using your own configured AI model (BYOK).
2. **1-click query routing (External Ask)**: Dispatch your query to 3 concrete destinations — web platforms (ChatGPT, Perplexity, Grok), desktop apps via URI schemes, or local CLI agents in Terminal — without consuming API tokens or saving history.

There is no account system, no telemetry, and nothing between you and your AI provider. When you close the window (`Esc`), SpotAsk is done and gone — leaving your workspace clean and uninterrupted.

The quickest way to see the core workflows is to watch the GIFs below. The hotkey workflow opens a chat window from any app; the selection workflow shows actions next to text you select; and External Ask routes queries to local CLI agents and external tools in one click.

![Quick chat with the default hotkey](/images/spotask-hotkey.gif)

![Quick actions on selected text](/images/spotask-selection.gif)

![1-click query routing to CLI agents and external tools](/images/spotask-external.gif)

## Next steps

- [Getting Started](/getting-started) walks through installation and your first question.
- [Explore SpotAsk](/explore) is a map of what you can do with the app.
- [Troubleshooting](/troubleshooting) covers connection, model, permission, and shortcut problems.
