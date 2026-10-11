---
title: External Ask
description: "Capture queries instantly in SpotAsk, then hand them off to ChatGPT, Grok, desktop apps, or terminal commands in 1 click."
---

# External Ask

External Ask lets you capture thoughts while they are fresh, then hand them off to specialized platforms. SpotAsk handles global summoning and rapid input; your chosen tool handles the heavy lifting.

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


## Decision routing

When you want SpotAsk to recommend a destination before sending, turn on **Enable automatic routing** in the **Decision Routing** section after the External Ask catalog.

![Decision routing inline confirmation and Tab channel switcher](/images/spotask-decision-routing.png)

SpotAsk asks a System One decision service which enabled channel fits the question. It does not change the chat service that writes answers. Fill **Service address**, **Decision model**, and **Access key**. The key is sent only to the address you enter.

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
