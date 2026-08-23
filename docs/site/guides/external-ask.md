---
title: External Ask
description: Type your question in SpotAsk, then send it to ChatGPT, Grok, an app, or a terminal command with one shortcut.
---

# External Ask

External Ask lets you start every question in SpotAsk, then continue in any AI you like. SpotAsk handles the global hotkey and quick input; the AI you choose writes the answer.

## Ask another AI

External Ask buttons sit below the built-in prompts in a new, empty question window.

1. Open the question window with your global hotkey.
2. Type your question.
3. Choose an External Ask button, such as **Ask ChatGPT**, or press its shortcut, such as `⌘ + 5`.

SpotAsk hands the question to that AI and closes the window. If the input is empty, nothing happens.

External Ask does not use your configured AI services, and nothing is added to your conversation history.

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

Entries can be reordered, disabled, edited, or deleted from the same settings page. Disabled entries keep their place but no longer appear in the question window.

## Shortcuts

Enabled entries get in-app shortcuts that continue after your prompt shortcuts: with the four built-in prompts enabled, the first two External Ask entries are `⌘ + 5` and `⌘ + 6`. Reassign or clear them in Settings > **Shortcuts**.

## Turn it off

Settings > **External Ask** has a single switch for the whole feature. When it is off, the buttons and shortcuts disappear; your entries are kept.

External Ask entries are included in configuration backups, and restoring an older backup without them works as before.

## Common questions

**Why are Claude and Gemini not built in?** Only services that reliably open and answer a question from a link are built in. Claude opens with the question filled in but waits for you to send it; Gemini does not accept a question in its link at all. You can still add Claude as a custom entry and press send yourself.

**What happens to my question?** External Ask sends the question only to the destination you pick; SpotAsk does not send it anywhere else and does not keep it.

Related: [Prompts](/guides/prompts), [Privacy & Local Data](/privacy), [Settings & Shortcuts Reference](/reference)
