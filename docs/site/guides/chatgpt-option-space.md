---
title: "ChatGPT Option+Space Not Working on Mac? Fixes and an Alternative"
titleTemplate: false
description: "New ChatGPT for Mac moved Quick Chat and gave Option+Space to Mini. Fix or reassign the shortcut, keep ChatGPT Classic, or try a free alternative."
faq:
  - question: "Why doesn't Option+Space open ChatGPT anymore on Mac?"
    answer: "The new ChatGPT desktop app does not open the old Chat Bar on Option+Space; that bar remains in ChatGPT Classic. In the new app, Option+Space is used by Mini by default. Assign the Popout Window hotkey, change the Mini shortcut, or switch back to ChatGPT Classic."
  - question: "How do I change or turn off the ChatGPT Mini shortcut?"
    answer: "Open ChatGPT's settings, choose Keyboard shortcuts, and find Show Mini. Record another combination or clear it. If it is missing from the list, switch to the Codex view and search again, or edit the openAvatarOverlay binding in keybindings.json under the Codex configuration directory and restart the app."
  - question: "Is ChatGPT Classic still available for Mac?"
    answer: "Yes. OpenAI states that the previous Mac app was renamed ChatGPT Classic and remains supported alongside the new app."
  - question: "Does SpotAsk use my ChatGPT Plus subscription?"
    answer: "Not directly. Ask ChatGPT only opens chatgpt.com in your browser, using the login you already have there. Answers inside SpotAsk need your own API key, and a Plus or Pro subscription does not include API access."
  - question: "Can SpotAsk and ChatGPT both use Option+Space?"
    answer: "Don't. In our testing both apps receive the keystroke when each installs its own global handler, and the winner is unpredictable. Give Option+Space to one app and move the other to a different combination."
  - question: "Is SpotAsk made by OpenAI?"
    answer: "No. SpotAsk is an independent open-source project, unaffiliated with OpenAI."
---

# ChatGPT ⌥Space Not Working on Mac? Fixes and a One-Hotkey Alternative

If <kbd>⌥ Space</kbd> stopped opening what you expect on your Mac, the cause is usually one of two things. Since the new ChatGPT desktop app merged Chat, Work and Codex, the old Chat Bar no longer opens on <kbd>⌥ Space</kbd> — that bar still lives in **ChatGPT Classic**. And newer builds bind <kbd>⌥ Space</kbd> to **Mini** by default, which takes the key away from Raycast, Alfred, or SpotAsk.

Below: how to identify which case you have, how to reassign or restore the shortcut inside ChatGPT, and — if all you want is one hotkey to ask a quick question — a free, open-source menu bar app that does exactly that and can hand the question to ChatGPT.

*Written by the SpotAsk maintainers. SpotAsk is an independent open-source project, not affiliated with OpenAI. We make SpotAsk, so we are biased. Corrections are welcome via GitHub issues.*

## Quick answer: which ⌥Space problem do you have?

Check which app you have first: **ChatGPT** (the new merged app) or **ChatGPT Classic** (the older app, now renamed).

| What happens when you press <kbd>⌥ Space</kbd> | Likely cause | Fix |
| --- | --- | --- |
| Nothing happens | ChatGPT Classic is not running, its Chat Bar shortcut was changed, or no app owns the key | [Using ChatGPT Classic](#using-chatgpt-classic) |
| A small floating panel, a pet, or a Codex task appears instead of a chat window | Mini owns <kbd>⌥ Space</kbd> in the new app | [Mini took ⌥Space](#mini-took-space-from-another-app) |
| A different launcher stopped responding | Mini registered the key first, or that launcher did not get the key | [Set up SpotAsk on ⌥Space without fighting ChatGPT](#set-up-spotask-on-space-without-fighting-chatgpt) |

## Why ChatGPT's ⌥Space changed in 2026

The new ChatGPT desktop app combines Chat, Work and Codex in one window. OpenAI's documentation states that the previous Mac app was renamed **ChatGPT Classic** and remains supported alongside the new app ([system requirements](https://help.openai.com/en/articles/9395554-what-are-the-system-requirements-for-the-chatgpt-macos-app), [moving to the new desktop app](https://help.openai.com/en/articles/20001276/)). In ChatGPT Classic, the Chat Bar still launches with <kbd>⌥ Space</kbd> by default and can be changed in its settings ([how to launch the Chat Bar](https://help.openai.com/en/articles/9295241-how-to-launch-the-chat-bar)).

The new app does not open that Chat Bar on <kbd>⌥ Space</kbd>. Users have reported the change since the merge (openai/codex issue [#31925](https://github.com/openai/codex/issues/31925), still open as of Oct 27, 2026).

Separately, the new app's **Mini** floating panel registers <kbd>⌥ Space</kbd> globally on macOS by default. OpenAI documents that the shortcut can be changed in the app's keyboard shortcut settings ([ChatGPT Learn: Pets](https://learn.chatgpt.com/docs/pets)). Some users report that the Mini entry is missing from that list in certain builds (openai/codex issue [#48756](https://github.com/openai/codex/issues/48756), still open as of Oct 27, 2026).

These are two different problems that arrived months apart. If <kbd>⌥ Space</kbd> opens a small panel or a pet rather than a chat, you have the Mini problem. If nothing happens at all, you have the Chat Bar problem.

## Fix it inside ChatGPT

This section solves the problem without installing anything else.

### Using ChatGPT Classic

1. Open **ChatGPT Classic**.
2. Open its settings and find the **Chat Bar** shortcut.
3. Record <kbd>⌥ Space</kbd> if it is not already set.

ChatGPT Classic keeps the Chat Bar behavior you are used to. If it is not installed, see [Go back to ChatGPT Classic](#go-back-to-chatgpt-classic).

### Using the new ChatGPT app: get a quick window back

The new app has its own floating window command, **Popout Window**, with an assignable **Popout Window hotkey**.

1. Open ChatGPT's settings and choose **Keyboard shortcuts**.
2. Find **Popout Window hotkey** and record <kbd>⌥ Space</kbd>.

Community reports in [#31925](https://github.com/openai/codex/issues/31925) note that this may open a Codex task rather than a plain chat, depending on which view is active. Menu names in this app change between releases, so check the wording in your installed version.

### Mini took ⌥Space from another app

Mini is the small floating Codex panel. It takes <kbd>⌥ Space</kbd> globally, ahead of other apps' shortcuts, because ChatGPT watches the keystroke at the system level rather than registering it exclusively.

The official route is to change or clear the shortcut:

1. Open ChatGPT's settings and choose **Keyboard shortcuts**.
2. Find **Show Mini** and record a different combination, or clear it.

If **Show Mini** is not in the list — users reported this on builds 26.924 and later in [#48756](https://github.com/openai/codex/issues/48756) — try these workarounds:

- **Switch views first.** Switch to the Codex view, then search the **Keyboard shortcuts** list for "Show Mini" (reported in a comment on that issue).
- **Edit the keybindings file.** The app reads command bindings from `keybindings.json` inside its Codex configuration directory (usually `~/.codex`). Add a binding for the `openAvatarOverlay` command that maps it to a different key (reported in a comment on that issue). Fully quit and reopen ChatGPT for the change to take effect.

::: warning Community workaround, not official
The file-based route is a user-reported workaround, not a documented OpenAI feature. Back up `~/.codex/keybindings.json` before editing it, and expect the file format to change between releases. Setting the binding to `null` did not work for at least one user in that thread.
:::

```json
[
  { "command": "openAvatarOverlay", "key": "Alt+Shift+Space" }
]
```

The file is a JSON array of bindings; each entry has a `command`, a `key` (or `null` to unbind it), and an optional `version`. If `keybindings.json` already exists, change the `openAvatarOverlay` entry instead of replacing the file, and keep the other entries.

### Go back to ChatGPT Classic

If you mainly used the old floating Chat Bar, ChatGPT Classic may simply be the better fit. OpenAI states it remains supported and can run alongside the new app. Download it from OpenAI's ChatGPT download page and set its Chat Bar shortcut to <kbd>⌥ Space</kbd>.

## If you just want one hotkey to ask anything: SpotAsk

SpotAsk is a native macOS menu bar app built around one idea: a single hotkey opens a small question window, over whatever you are doing, and closes as soon as you are done.

There are three ways to use that window:

- **Answer in SpotAsk.** Configure your own API key for an OpenAI-compatible service, Anthropic, or Gemini, and the answer streams in the window. This needs a key and is billed by whichever provider you choose — see [use your own API key](/use-cases/byok-macos-ai).
- **Ask ChatGPT.** One click opens `chatgpt.com` in your default browser with the question filled in, using the ChatGPT session you are already signed in to. It opens the **web** version, not the desktop app. It does not consume API tokens from SpotAsk, and the question is not saved in SpotAsk's history. By default ChatGPT only **pre-fills** the question — you press send yourself. Auto-submitting requires a userscript, described in the [External Ask guide](/guides/external-ask).
- **Hand it to another tool.** Route the same question to Perplexity, Grok, a desktop app, or a local CLI agent. See [send a question to ChatGPT, Perplexity or a CLI agent](/guides/external-ask).

A ChatGPT Plus or Pro subscription does not include API access. If you want answers inside SpotAsk's own window, you need a separate API key; if you want to use your subscription, use **Ask ChatGPT** and let the browser handle it.

![SpotAsk instant hotkey summoning and question window popup on macOS](/images/spotask-hotkey.gif)

SpotAsk is a [menu bar AI launcher](/use-cases/mac-ai-launcher): free, open source, menu bar only, no Dock icon.

## Set up SpotAsk on ⌥Space without fighting ChatGPT

The rule that matters: **give <kbd>⌥ Space</kbd> to one app only.**

In our own testing, when two apps both install a global <kbd>⌥ Space</kbd> handler, macOS does not arbitrate between them — both apps receive the keystroke, and whichever reacts first wins. The result is unpredictable and can differ between presses. Pick one owner instead of relying on luck.

### Option A: give ⌥Space to SpotAsk

1. In ChatGPT, clear or reassign the Mini shortcut (**Keyboard shortcuts** > **Show Mini**) and the Popout Window hotkey.
2. In SpotAsk, open **Settings > Shortcuts > Global Shortcut** and confirm it is <kbd>⌥ Space</kbd>.

### Option B: keep ⌥Space for ChatGPT

1. In SpotAsk, open **Settings > Shortcuts > Global Shortcut** and record a different combination, such as <kbd>⌃ ⌥ Space</kbd> or <kbd>⌥ ⇧ A</kbd>.
2. Avoid <kbd>⌥ ⇧ Space</kbd> if you use the Selection Assistant — that is its fixed trigger while the assistant is enabled.

You can also clear SpotAsk's global shortcut entirely and open it from the menu bar icon, from Spotlight, or through a URL or Shortcut — see [open SpotAsk from Spotlight or a URL](/guides/macos-integration).

SpotAsk checks for conflicts **within its own shortcuts** only. It cannot tell that ChatGPT, Raycast, or another app already owns a key, so it will not warn you about an external owner. If the system refuses to register a combination, SpotAsk shows a generic error instead.

### Install and first question

1. Download the DMG from [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest), or run `brew install --cask shiquda/spotask/spotask`.
2. Launch SpotAsk. It stays in the menu bar.
3. Optionally, add an API key for in-app answers, or leave it empty and use **Ask ChatGPT**.
4. Press <kbd>⌥ Space</kbd>, type, and press <kbd>↩</kbd>.

Detailed first-run steps: [install SpotAsk and ask your first question](/getting-started). Full list of shortcuts: [Settings & Shortcuts Reference](/reference).

## ChatGPT app vs SpotAsk: when to use which

| | ChatGPT desktop app | SpotAsk |
| --- | --- | --- |
| Hotkey question window | Popout Window / Mini, when the shortcut is assigned | <kbd>⌥ Space</kbd> by default, fully customizable or clearable |
| In-app answers | Yes, with your account | Yes, with your own API key |
| Files and screenshots | Yes, native | Images and text files as context |
| Account features (memory, Projects, GPTs, Work, Codex, voice) | Yes | No — hand the question to the web app instead |
| Choose the model or provider | Limited to OpenAI | Any OpenAI-compatible service, Anthropic, Gemini |
| Price | Free tier plus paid plans | Free and open source; you pay only your provider |
| Source available | No | Yes, AGPL-3.0 |
| System requirements | See OpenAI's system requirements | macOS 15 or later, Apple Silicon and Intel |

**Use ChatGPT** when you need what lives in your ChatGPT account — memory, Projects, GPTs, Work, Codex, voice, or the native app experience — or when you simply prefer it. Nothing here asks you to give that up.

**Use SpotAsk** when you want one key for a quick question, want to pick the model or provider yourself, want the same key to reach ChatGPT or a local agent, or want an open-source app with no telemetry.

Many people use both: SpotAsk owns <kbd>⌥ Space</kbd> for quick questions, and **Ask ChatGPT** hands the ones that need your account to the browser.

::: tip
SpotAsk is free and open source. [Download for Mac](https://github.com/shiquda/SpotAsk/releases/latest) or run `brew install --cask shiquda/spotask/spotask`. Keep ChatGPT for everything else.
:::

## FAQ

**Why doesn't Option+Space open ChatGPT anymore on Mac?**
The new ChatGPT desktop app does not open the old Chat Bar on <kbd>⌥ Space</kbd>; that bar remains in ChatGPT Classic. In the new app, <kbd>⌥ Space</kbd> is used by Mini by default. Assign the **Popout Window hotkey**, change the Mini shortcut, or switch back to ChatGPT Classic.

**How do I change or turn off the ChatGPT Mini shortcut?**
Open ChatGPT's settings, choose **Keyboard shortcuts**, and find **Show Mini**. Record another combination or clear it. If it is missing from the list, switch to the Codex view and search again, or edit the `openAvatarOverlay` binding in `~/.codex/keybindings.json` and restart the app.

**Is ChatGPT Classic still available for Mac?**
Yes. OpenAI states that the previous Mac app was renamed ChatGPT Classic and remains supported alongside the new app.

**Does SpotAsk use my ChatGPT Plus subscription?**
Not directly. **Ask ChatGPT** only opens `chatgpt.com` in your browser, using the login you already have there. Answers inside SpotAsk need your own API key, and a Plus or Pro subscription does not include API access.

**Can SpotAsk and ChatGPT both use ⌥Space?**
Don't. In our testing both apps receive the keystroke when each installs its own global handler, and the winner is unpredictable. Give <kbd>⌥ Space</kbd> to one app and move the other to a different combination.

**Is SpotAsk made by OpenAI?**
No. SpotAsk is an independent open-source project, unaffiliated with OpenAI.

---

*Last updated: Oct 27, 2026. ChatGPT details were checked against OpenAI's help pages and public GitHub issues on that date. ChatGPT updates often, so menu names may change.*

Related: [Troubleshooting](/troubleshooting), [External Ask](/guides/external-ask), [Settings & Shortcuts Reference](/reference)
