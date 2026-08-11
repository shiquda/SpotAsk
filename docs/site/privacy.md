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

## Selection permission

The selection assistant reads text you select through macOS Accessibility. Permission is requested only when you enable the feature, and SpotAsk does not keep selected text after the action completes unless conversation retention stores that conversation.

## Configuration backup

Configuration backup exports your services, models, prompts, shortcuts, and general settings. Access keys are excluded by default. If you choose to include them in the export, keep the file private.

## Clear local data

Settings > General > **Clear All Local Data** removes access keys, settings, and saved recent conversations.

## Diagnostics

Settings > General > **Diagnostics** can record recent request and selection details locally to help troubleshoot issues. Credentials are never recorded. Use **Export Log** to share the log with someone helping you.
