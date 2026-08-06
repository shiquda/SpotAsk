# Changelog

All notable changes to SpotAsk are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Cross-app selection assistant: select text in Safari, Notes, or other apps to translate, explain, summarize, polish, or run a custom prompt.
- Quick action bar that appears next to selected text, with text labels shown by default.
- Direct-run mode and optional automatic invocation for the selection assistant.
- Anthropic provider support in addition to OpenAI-compatible services, with model discovery and refresh.
- HTTP and SOCKS5 proxy support with optional credentials and a connection test.
- Customizable global hotkey for opening the chat window.
- Thinking display with elapsed time, plus an option to keep thinking expanded by default.
- Per-message answer toolbar with copy and retry actions.
- Configurable interface language: English, 简体中文, Español, Deutsch, 日本語, Français, Português, Русский.
- Configuration export/import and diagnostics export for troubleshooting.
- Compact in-app notification toasts for feedback.

### Changed

- The summarize quick action uses a clearer icon.
- Selection assistant settings collapse when the feature is off; Accessibility permission is requested only when enabling it.
- Conversation roles are labeled with icons, the assistant's model name, and 你 for your own messages.
- Streaming answer updates are isolated to the active message instead of rewriting the whole conversation array.
- The conversation keeps the recent active tail non-lazy while older history remains lazily loaded.
- Streaming answers render Markdown while generating; parsing happens off the main actor and is rate-limited instead of showing raw markup or re-laying out Textual blocks per token.
- Scroll geometry callbacks only update follow state when the near-bottom value actually changes, and size-change anchoring is disabled while the user is scrolling.

### Fixed

- Long answers streamed in the current window stay expanded after completion, and expanded assistant messages survive later conversation updates.
- Chat and reasoning scrolling now coalesces rapid updates instead of queuing one scroll command per token flush.
- The composer skips full TextKit measurement while it is already at its maximum height.
- The selection assistant could not read selected text in some builds; reads now work reliably with Accessibility permission.
- Selections made with text markers now resolve correctly.
- The composer draft is preserved after closing the window, and the panel fade animation is restored.
- The app icon no longer shows white corners in dark mode.
- Provider cards can be expanded and collapsed reliably.
- Thinking expansion behavior: when enabled, thinking stays expanded during reasoning and collapses for the final answer; when disabled, it stays collapsed.

[Unreleased]: https://github.com/shiquda/SpotAsk/compare/v0.1.3...HEAD
