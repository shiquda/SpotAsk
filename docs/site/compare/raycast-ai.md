---
title: "SpotAsk vs Raycast AI: A Free, Open-Source Ask Box for Mac"
titleTemplate: false
description: "Raycast is a launcher with AI built in; SpotAsk is only the ask box. Compare price, where your API key's requests go, local models and hotkeys."
outline: [2, 3]
faq:
  - question: "Is Raycast AI free?"
    answer: "No. Raycast's billing page says AI features are not included in Raycast Free. Pro is $10 a month or $96 a year for 500 credits, as of November 2, 2026. Bring Your Own Key is marked Pro Exclusive."
  - question: "Does Raycast BYOK send my key through Raycast's servers?"
    answer: "For Anthropic, Google, and OpenAI, Raycast says the requests are processed through its servers. It does not say the key is stored on those servers. OpenRouter requests go directly to OpenRouter. Custom Provider requests go from your Mac to the endpoint you configured, and those keys stay in providers.yaml."
  - question: "Can SpotAsk replace Raycast?"
    answer: "No. SpotAsk does not replace the launcher, the clipboard, window management, or the extension store. It only covers the quick-ask part."
  - question: "Can I run SpotAsk and Raycast together?"
    answer: "Yes. Use Raycast as the launcher and SpotAsk as the ask box. Give Option+Space to only one of them."
---

# SpotAsk vs Raycast AI

**A launcher with AI, or just the ask box?**

## The short answer

Raycast and SpotAsk both open AI from a hotkey, but they solve different problems. Raycast is a full launcher. Its AI needs a paid plan, Pro from $10 a month as of November 2, 2026. With your own Anthropic, Google, or OpenAI key, those requests still pass through Raycast's servers. OpenRouter, Custom Providers, and local models are the exceptions. SpotAsk is a free, open-source ask box: your key goes to your provider, or one shortcut sends the question to a website or a CLI.

The wider table is the [comparison hub](/compare/). Shortcut collisions are on the [Option+Space page](/guides/chatgpt-option-space).

- Pick Raycast if you want the launcher, the store, and AI in one subscription.
- Pick SpotAsk if you only want the ask box, no account, and a key that goes to your provider.
- Use both if you want the launcher and a separate ask box. Give Option+Space to one of them.

SpotAsk is our app. We checked Raycast's own manual on November 2, 2026. Tell us if anything changed.

## What each app is for

Raycast opens a command bar. From that bar you launch apps, search files, run extensions, and use AI. Clipboard history, window management, snippets, and the [Raycast Store](https://www.raycast.com/store) are part of the product. A subscription also includes Windows and iOS. The current Mac app requires macOS Tahoe and Apple silicon.

SpotAsk does not launch apps or search files. You press a shortcut, ask, and leave. [Selection Assistant](/guides/selection-assistant) can act on text you selected in another app. [External Ask](/guides/external-ask) can open that question in a browser, another app, or a terminal command. That is the product. It is not a Raycast replacement.

## Side-by-side

Checked November 2, 2026. Raycast was not installed on this Mac.

| | Raycast AI | SpotAsk |
| --- | --- | --- |
| Product type | Launcher plus AI | Menu bar ask box, selection actions, and hand-off |
| AI price | Not in Free. Pro $10/month or $96/year, 500 credits. Pro+ $20/month. Max $50/month. | Free. You pay your provider. |
| Account | Yes | None |
| Open source | No | AGPL-3.0 |
| BYOK providers | Anthropic, Google, OpenAI, OpenRouter, plus Custom Providers. Pro Exclusive. | OpenAI-compatible, Anthropic, Gemini |
| BYOK model list | Anthropic, Google, and OpenAI: models Raycast offers. OpenRouter: that catalog. | The model ID you enter |
| BYOK routing | Through Raycast servers for Anthropic, Google, and OpenAI. Direct for OpenRouter and Custom Providers. | To the endpoint you configure |
| Local models | Ollama, on this Mac. Pro Exclusive. | Loopback OpenAI-compatible server, such as Ollama or LM Studio |
| Hand-off to a website or CLI | Quicklinks can open a search URL. Store extensions were not inventoried. | Built in. External Ask. |
| Selected text | AI Commands | Selection Assistant. Default Option+Shift+Space. |
| Platforms | macOS, Windows, and iOS. Current Mac app: Tahoe and Apple silicon. | macOS 15 or later. Apple silicon and Intel. |
| Default hotkey | Command+Space and Option+Space, customizable | Option+Space |

## Where your API key's requests go

The path depends on which Raycast AI feature you turn on.

Raycast's [Bring Your Own Key](https://manual.raycast.com/ai/bring-your-own-key) page says: if you use BYOK with Anthropic, Google, or OpenAI, requests are processed through Raycast servers "in order to unify the model APIs, integrate fallback behaviors, and do some final prompt management." OpenRouter is the exception: those requests go directly to OpenRouter. The same page says a few tools Raycast runs on its own servers, such as image generation, still use a Raycast AI model and count against your AI credits. BYOK is marked Pro Exclusive. You can store one key per provider.

[Custom Providers](https://manual.raycast.com/ai/custom-providers) are also Pro Exclusive. Requests go directly from your device to the endpoint you configured. They are not processed through Raycast servers. Keys stay in `providers.yaml` on the device. The manual tells you to open that file from Settings → AI → Models & Providers → Reveal Providers Config. It does not print the absolute path, so this page does not invent one. Image attachments are a separate case: the [privacy page](https://manual.raycast.com/ai/raycast-ai-privacy-security) says images sent to Custom Providers are still uploaded to Raycast.

[Local Models](https://manual.raycast.com/ai/local-models) are Pro Exclusive and use Ollama. Prompts and conversations stay on the machine. The same page says some image-generation tools still use a Raycast AI model, which needs a network connection and credits.

SpotAsk sends a configured provider's request to the endpoint you set. There is no SpotAsk account in that path. Provider credentials are stored in a local file with mode `0600`, not in the Keychain. You can point the endpoint at OpenAI-compatible, Anthropic, or Gemini APIs, or at a local server. The model ID is the ID you enter. Sources: [BYOK on macOS](/use-cases/byok-macos-ai), [Privacy Architecture](/use-cases/privacy-architecture), and [Providers & Models](/guides/providers-and-models).

If you configure Raycast with Custom Providers or OpenRouter, the routing gap mostly closes. The remaining differences are price, account, open source, and scope.

## Price

Raycast Free does not include AI features. That sentence is on the [billing page](https://manual.raycast.com/billing). Bring Your Own Key does not remove the plan requirement. Pro is $10 a month or $96 a year for 500 credits. Pro+ is $20 a month or $192 a year for 3,000 credits. Max is $50 a month or $480 a year for 7,500 credits. Those figures matched the [pricing page](https://www.raycast.com/pricing) on November 2, 2026. A free Pro trial is offered to eligible new accounts. Windows and iOS are included with the subscription.

SpotAsk has no subscription. You pay the provider for tokens, or you pay nothing extra if the model is running on your own machine. That does not make SpotAsk a free Raycast. You do not get the launcher, the store, clipboard history, or window management.

## Sending a question somewhere else

SpotAsk [External Ask](/guides/external-ask) is a built-in hand-off. A saved target can be a website URL, an app URI scheme, or a Bash command. The web hand-off opens the browser with the question pre-filled. The guide says that web hand-off does not use a provider key. A live click-through with no key was not repeated for this page. Until that check is published, treat the no-key claim as the current guide, not as a new test.

Raycast can open a search URL through [Quicklinks](https://manual.raycast.com/quicklinks). A Quicklink can take a query argument, and you can give it a hotkey. That is a shortcut you create. It is not the same as a built-in ask box that already knows how to pre-fill a web AI chat. Extensions may add more. This page did not inventory the store, so it does not claim those commands exist or do not exist.

## Using both

You can install both. Use Raycast as the launcher. Use SpotAsk when you want the small question window, or when you want External Ask to open a website or a CLI without putting that question through Raycast AI.

Do not give both apps Option+Space. SpotAsk defaults to Option+Space. Raycast's keyboard-shortcut manual lists Command+Space and Alt+Space as the default shortcut to open or close Raycast, and says it can be customized. On a Mac, Alt is Option. The ChatGPT desktop app's current docs also use Option+Space. One shortcut, one owner. Change the others in that app's settings. The ChatGPT collision is covered in [Mini took Option+Space from another app](/guides/chatgpt-option-space#mini-took-space-from-another-app). SpotAsk's own note is [Global shortcut conflicts](/troubleshooting#global-shortcut-conflicts).

We did not run that collision. Raycast and ChatGPT were not installed.

## When Raycast is the better choice

Choose Raycast if the launcher is the thing you wanted:

- You want to launch apps, search files, manage windows, and keep clipboard history in the same bar as AI.
- You want the extension store, snippets, and team-shared commands or Quicklinks.
- You want one account to manage several models and a monthly credit pool, including AI without bringing a key.
- You want AI Commands on text you pick, inside the launcher you already use.
- You also want Raycast on Windows or iOS. The current Mac app still requires macOS Tahoe and Apple silicon.

SpotAsk will not grow into those features. If that list is the job, Raycast is the better app.

## When SpotAsk is the better choice

Choose SpotAsk if you do not want a launcher:

- You want a question window and nothing else in that app.
- You do not want an account or a monthly AI plan.
- You want provider requests to go to the endpoint you configured, without a Pro plan and without a `providers.yaml` file.
- You want the app to be open source, so you can read the AGPL-3.0 code.
- You want a built-in hand-off to a website or a CLI, separate from the in-app answer.

An Intel Mac, or a Mac that is not on macOS Tahoe, cannot install Raycast's current Mac app. SpotAsk still runs on Intel and Apple silicon with macOS 15 or later. That is a reason to pick SpotAsk only if the ask box is the job you wanted.

## If you want a full open-source launcher instead

SpotAsk is not that project. People who want an open-source replacement for Raycast's launcher look elsewhere. These sites resolved on November 2, 2026. We did not install or review them: [Tinycast](https://tinycast.app), [Sol](https://sol.ospfranco.com), and [Vicinae](https://www.vicinae.com/). If the job is "replace Raycast," start there. If the job is "I only need the ask box," [Getting Started](/getting-started) is the install path.

## How we checked

Checked on November 2, 2026, on a Mac running macOS 26.7.1. SpotAsk 0.3.3 (build 29) was installed. Raycast was not installed. No dual-app shortcut test was run. The conclusion for a shared shortcut is "pick one owner," not a winner.

Raycast manual pages read that day: [Bring Your Own Key](https://manual.raycast.com/ai/bring-your-own-key), [Custom Providers](https://manual.raycast.com/ai/custom-providers), [privacy](https://manual.raycast.com/ai/raycast-ai-privacy-security), [billing](https://manual.raycast.com/billing), plus [Local Models](https://manual.raycast.com/ai/local-models), [keyboard shortcuts](https://manual.raycast.com/keyboard-shortcuts), [Quicklinks](https://manual.raycast.com/quicklinks), [pricing](https://www.raycast.com/pricing), and [raycast.com/new](https://www.raycast.com/new). The download query on that last page was version 2.9.0.0.

SpotAsk sources: [Getting Started](/getting-started), [Providers & Models](/guides/providers-and-models), [External Ask](/guides/external-ask), [BYOK on macOS](/use-cases/byok-macos-ai), and [Privacy Architecture](/use-cases/privacy-architecture). Back to the [comparison hub](/compare/).

## FAQ

### Is Raycast AI free?

No. Raycast's billing page says AI features are not included in Raycast Free. Pro is $10 a month or $96 a year for 500 credits, as of November 2, 2026. Bring Your Own Key is marked Pro Exclusive.

### Does Raycast BYOK send my key through Raycast's servers?

For Anthropic, Google, and OpenAI, Raycast says the requests are processed through its servers. It does not say the key is stored on those servers. OpenRouter requests go directly to OpenRouter. Custom Provider requests go from your Mac to the endpoint you configured, and those keys stay in providers.yaml.

### Can SpotAsk replace Raycast?

No. SpotAsk does not replace the launcher, the clipboard, window management, or the extension store. It only covers the quick-ask part.

### Can I run SpotAsk and Raycast together?

Yes. Use Raycast as the launcher and SpotAsk as the ask box. Give Option+Space to only one of them.
