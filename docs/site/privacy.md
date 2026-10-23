---
title: Privacy & Local Data
description: Where SpotAsk stores access keys, conversations, settings, and diagnostics data.
---

# Privacy & Local Data

SpotAsk is a bring-your-own-key app. It does not provide its own AI account, and your AI service is the provider you configure.

## What stays on this Mac

- **Access keys** are stored on this Mac and are sent to the AI service you configure when SpotAsk makes a request.
- **Settings**, saved services, models, prompts, and shortcuts are stored locally.
- **Recent conversations** are stored locally only when conversation retention is enabled.
- **Diagnostics** are saved locally only when recording is enabled. Keys and proxy passwords are not recorded.

Selected text and attached files are sent to the service when you ask a question about them. Before handling sensitive information, review the privacy and data-retention policies of the service you use.

When automatic routing is on and you have not picked a channel, SpotAsk also sends the question text and the candidate channel names and descriptions to the decision address in Settings > External Ask. That can be TypeSafe (`https://api.typesafe.ai`), another System One address you enter such as OpenRouter (`https://openrouter.ai/api`), or the OpenAI Decisions API (`https://api.openai.com`, address editable). The decision access key for the selected engine is stored on this Mac and is sent only to that address. Routing does not run for a manually chosen channel, a message with attachments, or a conversation whose toolbar routing switch is off.

Decision requests require HTTPS outside loopback debugging. SpotAsk rejects redirects to another origin before forwarding the request body; same-origin redirects remain allowed. Routing sends the current question and candidate descriptions, not full conversation history or attachments. Routing error messages expose only a failure category and, where relevant, an HTTP status—not question text, access keys, proxy passwords, or authentication headers. Cancelling a recommendation cannot retract a decision request already sent to its configured service, but prevents the pending destination handoff.

## Selection permission

The selection assistant reads text you select through macOS Accessibility. Permission is requested only when you enable the feature, and SpotAsk does not keep selected text after the action completes unless conversation retention stores that conversation.

## Configuration backup

Configuration backup exports your services, models, prompts, shortcuts, and general settings. Access keys are excluded by default. If you choose to include them in the export, keep the file private.

## Update checks

Automatic update checking is enabled by default and checks the official release page once at launch. You can turn it off or check manually in About > Updates. The check does not send questions, access keys, or selected text.

## Clear local data

Settings > General > **Clear All Local Data** removes access keys, settings, and saved recent conversations.

<SpotAskSettingsLink section="general" />

## Diagnostics

Settings > General > **Diagnostics** can record recent request and selection details locally to help troubleshoot issues. Credentials are never recorded. Use **Export Log** to share the log with someone helping you.
