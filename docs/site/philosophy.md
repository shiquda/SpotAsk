---
title: Design Philosophy
description: Why SpotAsk stays small, keyboard-first, and local — the design ideas behind a fast macOS AI assistant for quick questions and selected text.
---

# Design Philosophy

SpotAsk is not a smaller ChatGPT. It is built on a different premise: **not every question is worth opening a full AI platform for**. Many everyday questions — understanding a term, translating a paragraph, summarizing an article, polishing a reply — are simple, yet the way we usually answer them is not: interrupt the task at hand, open a browser, load an AI site, wait for a flagship model to think, copy the result, and switch back.

SpotAsk exists to make lightweight questions genuinely lightweight. This page explains the ideas behind that goal and the tradeoffs they imply.

## Questions first, tools second

A common experience: you have a question, and before you can ask it you first decide *where* to ask it. By the time you have chosen a platform and clicked through to it, the original question is half forgotten.

SpotAsk flips the order. You write the question down first — in a window that is always one hotkey away — and only then decide who answers it:

- Ask the configured model directly with streaming answers (BYOK).
- Use **External Ask** to hand the question to 3 destinations: web platforms (ChatGPT, Perplexity, Grok), desktop apps via URI schemes, or local CLI agents in Terminal.
The question is captured at the moment it appears; the routing decision can wait.

## Lightweight by intention

SpotAsk deliberately does not try to be an all-in-one AI workspace. Tasks that need multi-step reasoning, long context, repeated debugging, or multi-turn retrieval are better served by dedicated tools — and External Ask is the bridge to them.

Staying narrow is what keeps the app fast:

- Pure Swift & AppKit — installer is ~10 MB with zero Electron or Chromium runtime.
- It lives quietly in the menu bar and stays out of the way until summoned.
- Closing the window (`Esc`) ends the interaction completely — no tabs, no inbox, nothing calling you back.

The goal is that after you close the window, it is as if SpotAsk never appeared: you are simply back in your original context with an answer.

## Keyboard-first, zero pointer travel

Most SpotAsk workflows never require touching the mouse: summon the window, ask with a preset prompt, copy the reply, clear the conversation, dismiss with `⎋`. A typical flow — for example, explaining a term a friend just mentioned in chat — is four keystroke steps from start to finish.

Every shortcut is configurable, so the app adapts to your hands rather than the other way around.

## Text in place

Good questions often start from text that is already on screen. Instead of copy-pasting into a separate app, SpotAsk works where the text is: select a paragraph in Safari, Notes, Mail, or any other app, and translate, explain, summarize, or polish it in place. The answer can replace the original selection, go to the clipboard, or open as a conversation for follow-up questions.

Custom prompts turn your own repeated text tasks into the same one-step operation.

## Your keys, your Mac

SpotAsk follows the BYOK model — bring your own key. It connects to OpenAI-compatible and Anthropic services that you choose, and:

- Service addresses and access keys are stored only on this Mac, in the system Keychain.
- Nothing is sent anywhere except the API provider you configured.
- There is no account system, no telemetry backend, and no SpotAsk server in the middle.

Details live in [Privacy & Local Data](/privacy).

## Native and small, like Spotlight

The name comes from Spotlight: the press-a-few-keys-and-done interaction model, applied to one specific job — asking questions. Where heavier tools feel oversized for such a small need, SpotAsk aims for a native, lighter, purer experience — a menu-bar utility that does one small thing quickly, and then gets out of the way.

## Keywords

quick questions · selection assistant · external ask · keyboard-first · BYOK · local-only privacy · lightweight and native · done and gone

## Where to go next

- [Getting Started](/getting-started) — install and ask your first question.
- [Explore SpotAsk](/explore) — the full capability map.
- [External Ask](/guides/external-ask) — route questions to other AI platforms.
- [Selection Assistant](/guides/selection-assistant) — work with text in other apps.
