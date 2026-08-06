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

### Fixed

- The selection assistant could not read selected text in some builds; reads now work reliably with Accessibility permission.
- Selections made with text markers now resolve correctly.
- The composer draft is preserved after closing the window, and the panel fade animation is restored.
- The app icon no longer shows white corners in dark mode.
- Provider cards can be expanded and collapsed reliably.
- Thinking expansion behavior: when enabled, thinking stays expanded during reasoning and collapses for the final answer; when disabled, it stays collapsed.

[Unreleased]: https://github.com/shiquda/SpotAsk/compare/v0.1.3...HEAD
