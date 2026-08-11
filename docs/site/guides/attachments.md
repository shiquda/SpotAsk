---
title: Images & Files
description: Attach images, screenshots, text, and code files to a SpotAsk conversation.
---

# Images & Files

Attachments let you ask about the content of an image, screenshot, text file, or code file.

## Add an attachment

- Drag and drop a file into the question window.
- Use the attach button and choose a file.
- Paste a screenshot from the clipboard.

Images are normalized before they are sent. Text and code files are read as UTF-8 text.

## What is supported

| Type | Examples |
| --- | --- |
| Images | PNG, JPEG, WebP, HEIC, HEIF, TIFF, GIF |
| Code | Swift, Python, JavaScript, TypeScript, JSX, Rust, Go, Java, C, C++, shell |
| Text | TXT, Markdown, JSON, YAML, XML, CSV, TSV, log |

Up to 8 attachments are allowed per message. Folders cannot be attached.

## Limits

- Images are downscaled if their longest side is above 4096 pixels.
- Very large text files are truncated after the first 60,000 characters.
- Unsupported file types show a clear error instead of being silently ignored.

## Context behavior

Attachments stay with the current conversation for follow-up questions. When conversation retention is enabled, the text conversation is retained locally, but attached files are not carried across a restart.

Related: [Getting Started](/getting-started), [Reference](/reference)
