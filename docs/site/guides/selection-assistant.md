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

## Trigger modes

**Run default action** sends the selected text directly to the default prompt you choose.

**Show quick actions** displays the action bar next to the selection. You can also enable labels beside the action icons.

## Automatic display

In **Show quick actions** mode, turn on **Show quick actions after selecting text** to avoid pressing the shortcut each time.

Use **Auto-show apps** to control where it appears:

- **All apps**: show in every app that exposes selected text.
- **Whitelist**: show only in selected apps.
- **Blacklist**: hide in selected apps.

The default delay is 0.8 seconds. Set **Wait** from 0 to 3 seconds so the actions do not appear while you are still selecting.

## Manual trigger

The selection shortcut works even when automatic display is off. The default is `⌥ + ⇧ + Space`.

## What can go wrong

- Empty selections do not trigger SpotAsk.
- Secure input fields cannot be read.
- Some apps do not expose selected text to macOS Accessibility; SpotAsk will tell you when that happens.
- If permission is denied, the app shows a recovery message with a link to System Settings.

Related: [Prompts](/guides/prompts), [Troubleshooting](/troubleshooting)
