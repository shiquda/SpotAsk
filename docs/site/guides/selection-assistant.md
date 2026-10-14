---
title: Selection Assistant
description: "Work with highlighted text across apps using inline quick actions: ask follow-ups, translate, summarize, and polish in place."
---

# Selection Assistant

The Selection Assistant eliminates repetitive copy-pasting. Highlight text anywhere to summon the inline action bar: translate, explain, summarize, polish, or bring text straight into chat.

## Quick Summary

The Selection Assistant detects highlighted text across any macOS application and summons an inline quick action bar directly beside your cursor. It enables instant translation, summarization, explanation, text polishing, and follow-up Q&A without switching application focus or copying text to the clipboard manually.

## Applicable Scenarios

- **Reading & Research Translation**: Select foreign-language paragraphs in Safari, Chrome, or Preview to read an instant translation without opening a separate dictionary or translation tab.
- **Code & Stack Trace Explanation**: Highlight error messages, compiler warnings, or unfamiliar code snippets in Xcode, VS Code, or Terminal and click **Explain** or **Ask in Chat**.
- **Writing & Communication Polishing**: Highlight draft emails, Slack messages, or documentation notes in place and click **Polish** to refine grammar, tone, and conciseness.

## Prerequisites & Compatibility

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Operating System** | macOS 15.0 (Sequoia) or later | Apple Silicon (`arm64`) and Intel (`x86_64`) |
| **Application Version** | SpotAsk `v0.1.0+` | Clipboard-assisted selection enhanced in `v0.2.8+` |
| **Required Permissions** | macOS Accessibility (**Cross-app text access**) | Configured in **System Settings > Privacy & Security > Accessibility** |
| **Hardware Architecture** | Universal binary | Native performance across M-series and Intel Macs |
| **Security Context** | Standard accessibility text selection | Blocked in secure input fields by macOS sandbox |

## Step-by-Step Instructions

1. **Enable the Assistant**: Open **Settings (`⌘ + ,`) > Selection Assistant**, or use deep-link `spotask://settings/selection-assistant`.
2. **Grant Accessibility Permission**: Toggle on **Selection Assistant**. When macOS prompts for accessibility access, open **System Settings > Privacy & Security > Accessibility** and enable **SpotAsk**.
3. **Choose Trigger Mode**:
   - **Show quick actions** (recommended): Displays the floating action bar next to your selection.
   - **Run default action**: Immediately triggers your preferred preset (e.g. Translate or Explain) upon text selection.
4. **Trigger Actions**:
   - **Automatic trigger**: Highlight text in any supported application and pause for the configured wait delay (default: 0.8 seconds).
   - **Manual shortcut trigger**: Highlight text and press `⌥ + ⇧ + Space` to summon the action bar immediately without delay.
5. **Execute Action**: Click **Ask in Chat** (speech bubble icon) to enter chat with the text pre-filled, or click **Translate**, **Explain**, **Summarize**, **Polish**, or an enabled External Ask button.

## Visual Proof

![SpotAsk Selection Assistant displaying inline quick actions next to highlighted text](/images/spotask-selection.gif)
*Figure 1: The Selection Assistant presents floating inline quick actions (Translate, Explain, Summarize, Polish, Ask in Chat) immediately beside highlighted text across macOS apps.*

## Known Limitations & Boundaries

- **Secure Input Fields**: Passwords, credentials, and secure text fields (such as Terminal sudo prompts or password managers) cannot be read by macOS Accessibility for privacy and security protection.
- **Custom UI Frameworks**: Certain applications (such as Zotero's built-in PDF viewer or non-native canvas apps) do not report standard Accessibility boundaries; enable **Clipboard-assisted selection** in Settings for these apps.
- **Empty & Whitespace Selections**: Selections containing zero characters or only blank spaces do not trigger the action bar.
- **Screen & Audio Privacy Boundary**: SpotAsk reads only the currently highlighted text string upon trigger; it does not record keystrokes, capture background screen contents, or track window history.
- **Permission Revocation**: If macOS Accessibility permissions are revoked, SpotAsk cannot inspect cross-app text and displays an inline recovery guide linking directly to System Settings.

## Enable it

1. Open Settings > **Selection Assistant**.
2. Enable **Selection Assistant**.
3. Authorize **Cross-app text access** when prompted.
4. Choose a **Trigger mode**.

SpotAsk requests this permission only when you enable the feature. It uses the permission to read text you select; it does not monitor your whole screen.

```mermaid Selection Assistant: permission first, then the trigger you chose
flowchart TD
  A{Cross-app text access?}
  A -->|Denied| B[Open System Settings from the recovery message]
  A -->|Granted| C{Trigger mode}
  C -->|Run default action| D[The default prompt runs on the selection]
  C -->|Show quick actions| E[Use the action bar or the selection shortcut]
  class A entry
  class C decision
  class B,D,E outcome
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

## Clipboard-assisted selection

Some apps (such as Zotero's PDF reader) report selected text to macOS Accessibility with missing spaces or shifted boundaries. For these apps, enable **Clipboard-assisted selection** in Settings > **Selection Assistant** and choose which apps it applies to.

Selections in those apps are still detected the usual way, and nothing is copied while the action bar waits for you. The copy happens when you use an action: SpotAsk copies the selection with the app's standard Copy command, reads the accurate text from the clipboard, and immediately restores your previous clipboard content.

This feature is off by default. It never copies when nothing is selected, and apps not on your list continue using normal Accessibility reading.

## Manual trigger

The selection shortcut works even when automatic display is off. The default is `⌥ + ⇧ + Space`.

## What can go wrong

- Empty selections do not trigger SpotAsk.
- Secure input fields cannot be read.
- Some apps do not expose selected text to macOS Accessibility; SpotAsk will tell you when that happens.
- If permission is denied, the app shows a recovery message with a link to System Settings.

Related: [Prompts](/guides/prompts), [Troubleshooting](/troubleshooting)
