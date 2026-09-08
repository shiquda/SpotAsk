---
title: Spotlight, Siri & Shortcuts
description: Use SpotAsk from Spotlight, Siri, Shortcuts, or a spotask:// URL.
---

# Spotlight, Siri & Shortcuts

The official SpotAsk release registers app actions that macOS can expose to Spotlight, Siri, and Shortcuts. It also registers the `spotask://` URL scheme for Alfred, Raycast, terminal scripts, and Shortcuts.

## Available actions

- **Open SpotAsk** opens the question window.
- **Ask AI** asks a question.
- **Translate**, **Explain**, **Summarize**, and **Polish** run the matching built-in prompt on content you provide.
- **New Conversation** clears the current conversation and opens SpotAsk.

## Spotlight

Search for SpotAsk in Spotlight and choose an action such as **Ask SpotAsk a question**, then enter your content or question.

## Siri

Ask Siri to use a SpotAsk action, for example "Ask SpotAsk to translate [text]".

## Shortcuts

Open the Shortcuts app and search for SpotAsk actions. Add an action with its required content, or build a larger shortcut that passes text, a question, or another shortcut's output to SpotAsk.

## URL scheme

Open these links from another app, a shortcut, or Terminal. Spaces and other special characters in a question must be percent-encoded.

| URL | What it does |
| --- | --- |
| `spotask://open` | Opens the question window |
| `spotask://ask?q=Your%20question` | Fills in the question and sends it |
| `spotask://ask?q=Your%20question&submit=false` | Fills in the question without sending |
| `spotask://toggle` | Shows or hides the question window |
| `spotask://settings` | Opens Settings |

From Terminal:

```sh
open "spotask://ask?q=What%20is%20Swift%20concurrency"
```

If SpotAsk is not running, the URL launches it and then runs the command. If it is already in the menu bar, the command runs immediately.

## Custom builds

System integrations work in the official release. If you build SpotAsk yourself, the app must be signed with an Apple development team, and you should run it once from Xcode before using its actions in Shortcuts. Personal Team builds are for personal use and may need to be rebuilt periodically.

Related: [Prompts](/guides/prompts), [Getting Started](/getting-started)
