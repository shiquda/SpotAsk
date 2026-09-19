---
title: Selection Assistant
description: Use SpotAsk on selected text in other apps with quick actions, direct mode, app scope, and automatic display.
---

# Selection Assistant

The Selection Assistant reads text you select in another app and sends it to SpotAsk for an action such as Translate, Explain, Summarize, Polish, or a custom prompt.

## Enable it

1. Open Settings > **Selection Assistant**.
2. Enable **Selection Assistant**.
3. Authorize **Cross-app text access** when prompted.
4. Choose a **Trigger mode**.

SpotAsk requests this permission only when you enable the feature. It uses the permission to read text you select; it does not monitor your whole screen.

```mermaid Selection Assistant path: permission, trigger mode, and how an action reaches the selection
flowchart TD
  A[Enable Selection Assistant] --> B{Cross-app text access}
  B -->|Denied| C[Recovery message links to System Settings]
  B -->|Granted| D{Trigger mode}
  D -->|Run default action| E[The default prompt runs on the selection]
  D -->|Show quick actions| F{Auto-show after selecting?}
  F -->|On| G[The action bar appears after the wait time]
  F -->|Off| H[Press the selection shortcut]
  G --> I[Pick a prompt, ask in chat, or an External Ask target]
  H --> I
```

<SpotAskSettingsLink section="selection-assistant" />

## Trigger modes

**Run default action** sends the selected text directly to the default prompt you choose.

**Show quick actions** displays the action bar next to the selection. You can also enable labels beside the action icons.

- **Ask in Chat icon**: A dedicated speech bubble icon appears at the start of the action bar. Clicking it opens the question window with the selected text filled in and a blank line ready for your follow-up question. This can be toggled in Settings > **Selection Assistant** (enabled by default).
- Built-in prompts, custom prompts, and enabled External Ask targets follow in the bar.
## Automatic display

In **Show quick actions** mode, turn on **Show quick actions after selecting text** to avoid pressing the shortcut each time.

Use **Auto-show apps** to control where it appears:

- **All apps**: show in every app that exposes selected text.
- **Whitelist**: show only in selected apps.
- **Blacklist**: hide in selected apps.

The default delay is 0.8 seconds. Set **Wait** from 0 to 3 seconds so the actions do not appear while you are still selecting.

## Clipboard-assisted reading

A few apps report the selected text through macOS inaccurately — the selection arrives shifted, or with the spaces between lines missing. For those apps, SpotAsk can read the selection the way the app's own Copy command does.

1. Open Settings > **Selection Assistant**.
2. Turn on **Read selections with the app's Copy command**.
3. Add each app it should apply to, for example Zotero.

SpotAsk first checks that something is selected, so an empty selection never triggers a copy. It then backs up your clipboard, runs the app's Copy command, reads the text, and puts the backed-up contents back — every item and type, so copied images and rich text survive. Apps you leave off the list keep the plain accessibility reading.

## Manual trigger

The selection shortcut works even when automatic display is off. The default is `⌥ + ⇧ + Space`.

## What can go wrong

- Empty selections do not trigger SpotAsk.
- Secure input fields cannot be read.
- Some apps do not expose selected text to macOS Accessibility; SpotAsk will tell you when that happens.
- If permission is denied, the app shows a recovery message with a link to System Settings.

Related: [Prompts](/guides/prompts), [Troubleshooting](/troubleshooting)
