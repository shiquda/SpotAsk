---
title: Settings & Shortcuts Reference
description: A compact reference for SpotAsk settings sections, default shortcuts, and supported file types.
---

# Settings & Shortcuts Reference

## Settings sections

| Section | What it configures |
| --- | --- |
| Services | AI service formats, addresses, access keys, timeouts, models, model discovery |
| Prompts | Built-in prompts, custom prompts, order, enabled state, custom instructions |
| Selection Assistant | Permission, trigger mode, default action, auto-show, app scope, delay |
| Shortcuts | Global hotkey and shortcuts used while the SpotAsk window is open |
| General | Language, launch behavior, session retention, proxy, diagnostics, local data |
| Appearance | Appearance, font size, message style, and reading size |
| About | Version, project source, and updates |

## Default shortcuts

| Action | Shortcut |
| --- | --- |
| Open or focus the question window | `⌥ + Space` (customizable) |
| Trigger the selection assistant | `⌥ + ⇧ + Space` |
| Focus the input | `⌘ + L` |
| Regenerate or retry | `⌘ + R` |
| Copy the latest answer | `⌘ + ⇧ + C` |
| Open Settings | `⌘ + ,` |
| New conversation | `⌘ + N` |
| Zoom in | `⌘ + =` |
| Zoom out | `⌘ + -` |
| Run the first enabled prompts | `⌘ + 1` through `⌘ + 9` |
| Send the question | `↩` |
| Add a line break | `⇧ + ↩` |
| Stop generating | `⎋` |

Prompt shortcuts depend on prompt order and which prompts are enabled. In-app shortcuts can be reassigned or cleared in Settings.

## Supported attachment types

| Type | Examples |
| --- | --- |
| Images | PNG, JPEG, WebP, HEIC, HEIF, TIFF, GIF |
| Code | Swift, Python, JavaScript, TypeScript, TSX, JSX, Rust, Go, Java, C, C++, shell |
| Text | TXT, Markdown, JSON, YAML, XML, CSV, TSV, log |

Up to 8 attachments are supported per message. Very large images are normalized before they are sent, and large text files are truncated after the first 60,000 characters.

## Conversation behavior

- Switching a model in the chat window changes only the current conversation.
- **New Conversation** returns to the Settings default model and clears the current draft.
- If conversation retention is enabled, SpotAsk asks whether to continue a conversation after it has been idle for a while.
- Escape behavior can be set in General: it stops a response or starts a new conversation.
