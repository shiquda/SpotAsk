---
title: External Ask
description: "Capture queries instantly in SpotAsk, then route them to ChatGPT, Perplexity, Grok, desktop apps, or local CLI agents in 1 click or automatically with a decision model."
---

# External Ask

External Ask lets you capture thoughts while they are fresh, then hand them off to specialized platforms. SpotAsk handles global summoning and rapid input; your chosen tool handles the heavy lifting.

## Quick Summary

SpotAsk External Ask captures queries through a single global summon window and routes them to web AI services (ChatGPT, Perplexity, Grok), native macOS apps, or local CLI agents in 1 click or via automated decision models. This decouples instant thought capture from heavy execution, eliminating manual copy-pasting across browser tabs and terminal windows.

## Applicable Scenarios

- **Live Web Research & Search**: Route real-time market queries, current news, or comparative analysis directly to Perplexity, Grok, or ChatGPT when local LLM context lacks live web grounding.
- **Local Developer Agent Dispatch**: Hand off complex multi-step terminal tasks (such as code generation, git workflows, or data processing) directly to local CLI agents like `omp {query}` or `claude {query}`.
- **Intelligent Intent-Based Auto-Routing**: Let a lightweight System One decision model (`jev-1.13.0`) evaluate your prompt intent automatically and dispatch between in-app answers, browser AI, or terminal agents.

## Prerequisites & Compatibility

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Operating System** | macOS 15.0 (Sequoia) or later | Apple Silicon (`arm64`) and Intel (`x86_64`) |
| **Application Version** | SpotAsk `v0.3.0` or later | Decision Routing introduced in `v0.3.0` |
| **Required Permissions** | Automation / Terminal execution | Required only when dispatching to Terminal CLI agents |
| **Default Browser** | Any macOS default browser | Used for web questions with active session state |
| **Optional API Key** | TypeSafe or OpenRouter API key | Required only if enabling automated Decision Routing |

## Step-by-Step Instructions

1. **Open Settings**: Press `⌘ + ,` to open Settings, navigate to **External Ask**, or use the URL deep-link `spotask://settings/external-ask`.
2. **Add or Select an Action**: Click **New** in the External Ask catalog. Choose an action type:
   - **Web question**: e.g., `https://chatgpt.com/?q={query}` or `https://www.perplexity.ai/search?q={query}`.
   - **Open an app**: e.g., `quicknote://new?text={query}`.
   - **Terminal command**: e.g., `omp {query}`.
3. **Trigger from Question Window**: Summon SpotAsk using `⌥ + Space`. Type your question, then:
   - Click the target button (e.g., **Ask ChatGPT**) or press its assigned shortcut (`⌘ + 5`, `⌘ + 6`).
   - Or select the target from the `@` command palette or preset menu.
4. **Use Decision Routing (Optional)**: In **Settings > External Ask**, enable **Decision Routing**. When you press `↩`, SpotAsk evaluates intent and displays an inline confirmation card—press `↩` to confirm, `Tab` to switch channels, or `Esc` to cancel.

## Visual Proof

<video poster="/images/spotask-smart-routing-preview.gif" src="/videos/SpotAsk-smart-routing-v5.mp4" controls muted playsinline width="720"></video>
*Video 1: Decision routing demonstrated on real app footage (28s) — evaluates prompt intent and presents an inline confirmation card with one-click dispatch and Tab-to-switch capability. [Download / Watch HD Video (1080p MP4)](/videos/SpotAsk-smart-routing-v5.mp4)*

![SpotAsk routing a question to a local CLI agent in Terminal](/images/spotask-external.gif)
*Figure 2: SpotAsk dispatching a question directly into a local CLI agent in Terminal.*

## Known Limitations & Boundaries

- **Browser Authentication State**: Web questions open URLs in your default browser; automatic generation requires an active login session on the target website (e.g., ChatGPT, Perplexity, Grok).
- **Shell PATH Resolution**: Terminal commands run in your default user shell; CLI binaries (such as `omp`, `ollama`, or `claude`) must exist in your shell `$PATH`.
- **Pre-Fill vs Auto-Submit**: Web question links pre-fill the query in the target's web composer; automatic submission in ChatGPT requires a client-side userscript (see [tip below](#auto-submitting-in-chatgpt-with-a-userscript)).
- **Decision Service Security Boundary**: Remote decision services strictly require HTTPS (HTTP is allowed only for loopback `localhost`/`127.0.0.1` debugging); cross-origin and HTTPS-to-HTTP redirects are rejected prior to sending question text.
- **Attachment Exclusion**: Attaching images or files automatically bypasses External Ask and Decision Routing, keeping the conversation inside SpotAsk.

## Ask another AI

External Ask buttons appear below the prompt presets in a new question window, and can also be triggered via the `@` command palette or the preset popover menu:

- **When the input is empty**: Clicking an External Ask button, pressing its shortcut (e.g. `⌘ + 5`), or selecting it from the `@` palette pins a pending target badge at the top-left above the composer. Enter your question and press `↩` to send; nothing has left yet, so the window stays open. Click its `×`, press `Esc`, or clear the input to cancel.
- **When input is already present**: Selecting an External Ask button, pressing its shortcut, or choosing it from a menu immediately sends the question to the target and closes the question window. If the target cannot be opened, the window stays open with your question and an error, ready to send again.
- **In ongoing conversations**: Click the preset popover menu at the bottom-left of the composer to access enabled External Ask targets alongside prompt presets.
- **Retrying an answer elsewhere**: Picking an External Ask target in an answer's model picker sends the question that answer was generated for and keeps the window open, so you can compare the other platform's answer with this conversation.

External Ask does not consume API tokens from your configured AI providers, and queries are not stored in conversation history.

## Action types

Each External Ask entry is one of three action types.

**Web question** opens a link in your browser with the question filled in. The link needs a `{query}` placeholder where the question goes:

| Name | Link |
| --- | --- |
| Ask ChatGPT | `https://chatgpt.com/?q={query}` |
| Ask Grok | `https://grok.com/?q={query}` |
| Ask Perplexity | `https://www.perplexity.ai/search?q={query}` |

::: tip Auto-submitting in ChatGPT with a userscript
By default, ChatGPT only **pre-fills** the query in the composer and requires clicking send manually. If you want ChatGPT to **pre-fill and automatically submit** the question upon opening, you can install this userscript:
- **[ChatGPT URL Prompt Auto Submit](https://greasyfork.org/en/scripts/592577-chatgpt-url-prompt-auto-submit)** (Greasy Fork)

Once installed, visiting ChatGPT with a `?q=` parameter will automatically trigger the submit button as soon as the composer is ready.
:::
**Open an app** sends the question to another app on your Mac through the link format that app provides, for example a notes app that accepts `quicknote://new?text={query}`.

**Terminal command** runs a command in Terminal with your question filled in, such as:

```text
omp {query}
```

![SpotAsk routing a question to a local CLI agent in Terminal](/images/spotask-external.gif)
## Add your own

1. Open Settings > **External Ask**.
2. Select **New**.
3. Enter a **Name**, choose an **Action Type**, and fill in the link or command with `{query}` where the question goes.
4. Save it. A matching brand icon is picked automatically when one is available.

Entries can be reordered, disabled, edited, or deleted from the same settings page. Built-in entries use the same edit and delete controls as ones you add. Deleting one asks for confirmation and cannot be undone. Disabled entries keep their place but no longer appear in the question window.

<SpotAskSettingsLink section="external-ask" />


## Decision routing {#decision-routing}

When you want SpotAsk to recommend a destination before sending, turn on **Enable automatic routing** in the **Decision Routing** section after the External Ask catalog.

<SpotAskSettingsLink section="external-ask" />

SpotAsk asks a System One decision service which enabled channel fits the question. It does not change the chat service that writes answers. Fill **Service address**, **Decision model**, and **Access key**. The key is sent only to the address you enter.

<video poster="/images/spotask-smart-routing-preview.gif" src="/videos/SpotAsk-smart-routing-v5.mp4" controls muted playsinline width="720"></video>

*Video: one question, three destinations — decision routing demonstrated on real app footage (28s): an in-app answer, an auto-send route notice to Web Chat, and a Local Agent confirmation card with confidence score. [Download / Watch HD Video (1080p MP4)](/videos/SpotAsk-smart-routing-v5.mp4)*

Two setups are recommended. Run **Test question** in that section before relying on either one.

### TypeSafe official

These values are already filled in. Add a TypeSafe key. This address will not send a request without one.

| Field | Value |
| --- | --- |
| Service address | `https://api.typesafe.ai` |
| Decision model | `jev-1.13.0` |
| Access key | A TypeSafe API key |

### OpenRouter

OpenRouter serves the same System One request at `https://openrouter.ai/api/v1/systemone`. Use an OpenRouter key, not a TypeSafe key. Enter the base address below; SpotAsk adds `/v1/systemone`. Do not paste a chat-completions URL.

| Field | Value |
| --- | --- |
| Service address | `https://openrouter.ai/api` |
| Decision model | `typesafe/jev-1.13` |
| Access key | An OpenRouter API key |

Pin `typesafe/jev-1.13` if you want a fixed model. `~typesafe/jev-latest` follows OpenRouter’s newest Jev alias and can change. Access and pricing are OpenRouter’s: [Jev on OpenRouter](https://openrouter.ai/docs/guides/community/jev).

- **Routing hints**: Edit any entry to set its link or command, **What it does**, **When to use**, and whether it uses **Always confirm first**. With that switch on, every routed send to the channel asks you first; with it off, your **Confirmation** setting applies. If you leave these fields blank, routing still sends the channel name to the decision model.
- **Confirmation, confidence & auto-send notice**: The default mode confirms every routed send on an inline card above the composer (`↩` to continue, `Tab` for other channels, `Esc` to cancel and keep the question). In the channel list, Tab and Shift-Tab move the highlight, the arrow keys work too, and Return sends the highlighted channel. In threshold mode, scores strictly above your threshold answer immediately when routed to **In SpotAsk**, or show a brief 0.8-second notice before opening an external channel (`↩` sends immediately, `Esc` or editing cancels); confidence reflects option certainty, not accuracy.
- **Per-conversation toolbar toggle**: When automatic routing is enabled, a smart-routing icon in the chat toolbar (`⌘ + ⇧ + R` by default) lets you turn automatic routing off for the current conversation without changing Settings. Starting a new conversation resets it to on. Turn off **Show routing toggle in toolbar** in **Settings > External Ask** to hide this icon.
- **Timeout & manual priority**: The default timeout is 2 seconds. You can set it from 0.5 to 5 seconds in 0.1-second steps. Timeout falls back to manual channel selection (or In SpotAsk if configured). Manually selecting an External Ask target or attaching files always bypasses the decision model.
- **Test question**: Preview the recommended destination, confidence, and release rule directly in Settings without opening any external app or browser tab.
- **Service boundary**: Remote services must use HTTPS. HTTP is allowed only for loopback debugging (`localhost`, `127.0.0.0/8`, or `::1`), not other LAN addresses. Redirects may stay within the same scheme, host, and effective port; redirects to another origin or from HTTPS to HTTP are rejected before forwarding the question. Custom services need an explicit decision model; a blank custom model is not replaced with TypeSafe's model.
- **Cancel stale recommendations**: Editing, changing attachments or a prompt preset, or changing routing/channel availability invalidates an outstanding recommendation, including the 0.8-second notice. Editing a channel's link, URI, or command also cancels its pending recommendation, even if its name stays the same. This happens silently; your draft and attachments stay in place, and you can send again for a fresh decision. Starting a new conversation cancels the recommendation and follows the usual new-conversation clearing behavior. A cancelled recommendation does not open an external channel.

The settings test requires External Ask to be enabled and at least two destinations (In SpotAsk plus an enabled external channel). Prerequisite and configuration failures show a specific reason without an evaluation time. Service errors distinguish authentication (401/403), endpoint (404), rate limiting (429), other HTTP rejections, network failures, timeout, and invalid or unrecognized responses. Diagnostic messages do not include question text or credentials.

![Decision routing settings and live route test](/images/spotask-decision-routing-settings.png)

## Shortcuts

Enabled entries get in-app shortcuts that continue after your prompt shortcuts: with the four built-in prompts enabled, the first two External Ask entries are `⌘ + 5` and `⌘ + 6`. Reassign or clear them in Settings > **Shortcuts**.

## Turn it off

Settings > **External Ask** has a single switch for the whole feature. When it is off, the buttons and shortcuts disappear; your entries are kept.

External Ask entries are included in configuration backups, and restoring an older backup without them works as before.

## Common questions

**Why are Claude and Gemini not built in?** Only services that reliably open and answer a question from a link are built in. Claude opens with the question filled in but waits for you to send it; Gemini does not accept a question in its link at all. You can still add Claude as a custom entry and press send yourself.

**What happens to my question?** A manual External Ask send goes only to the destination you pick. When automatic routing runs, the question text and the candidate channel names and descriptions are also sent to the decision address you configured, so it can choose a destination. Routing does not run if you already picked a channel, the message has attachments, or the toolbar routing switch for this conversation is off.

Related: [Prompts](/guides/prompts), [Privacy & Local Data](/privacy), [Settings & Shortcuts Reference](/reference)
