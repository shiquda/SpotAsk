# Changelog

All notable changes to SpotAsk are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Turning thinking off for a generic OpenAI-compatible model no longer sends `reasoning_effort: none`, which New API-style gateways reject with HTTP 400. DeepSeek's off setting now also sends `reasoning_effort: off`, so thinking actually stops.
- Scrolling a long conversation no longer jumps the message on screen.

## [0.2.7] - 2026-10-08

**Gemini services, pre-filled official addresses, smoother model discovery**

### Added

- **Gemini** joins OpenAI Compatible and Anthropic as an API Format in Settings > Services, using Google Gemini keys directly without a compatibility gateway.
- A new Service pre-fills official addresses for the selected format and type, and the docs now link to provider key consoles and API references.
- The model selection sheet in Settings > Services uses a native macOS tri-state checkbox that stays synchronized with individual model toggles.

## [0.2.6] - 2026-10-05

**Live action bar preview, quieter update prompts**

### Added

- Settings > Selection Assistant previews the action bar live in a 1:1 view as you toggle display switches; the preview is view-only, and an empty configuration shows an explanation.
- Checking for updates when already up to date shows a lightweight in-app toast instead of a modal dialog.

### Fixed

- Sending a question from the composer to another app closes the window once the target opens, even when pinned, so it no longer covers the target window.
- Clearing local data now purges session history too, and failed configuration backup imports roll back atomically to prevent corrupted settings.

## [0.2.5] - 2026-09-20

**Direct settings links, guide links, live diagrams**

### Added

- `spotask://settings/<page>` links open a specific Settings page directly, with unknown pages falling back to the Settings window.
- Behavior-heavy Settings groups link to their guide in the current interface language.
- The documentation site adds theme-adaptive diagrams for address types and the Selection Assistant, plus an "Open Settings in SpotAsk" button.
- The "retry with another model" picker on answers lists enabled External Ask targets, opening the platform with the original question while keeping the session unchanged.
- An optional, off-by-default clipboard-assisted selection mode in Settings > Selection Assistant for apps you choose, restoring the clipboard afterwards.

### Changed

- The header model picker is centered in the title bar, keeping the loading animation grouped with it.
- The header quick switcher lists models only again, moving External Ask targets to the retry picker.
- Adding selected text to chat prefixes each line with Markdown `>`, and the selection action uses a quote bubble icon.
- The documentation home page renders the flow diagram between the hero actions and feature cards.
- The documentation home page hero keeps only the SpotAsk wordmark, dropping the secondary Docs heading.

### Fixed

- The Open Documentation link no longer sits under the Settings scrollbar and lines up with the card below it.
- Running the test suite no longer overwrites your macOS clipboard.

## [0.2.4] - 2026-09-16

**In-app updates, multiple download sources, composer @ filtering**

### Added

- Check for Updates now downloads and installs in-app, with options to skip versions and restore alerts in About.
- Configurable update download sources (Automatic, Official GitHub, Accelerated Mirror) in Settings > About > Updates with automatic timeout and mirror fallback.
- Type `@` in the composer to filter prompt presets and External Ask targets, preserving drafts or launching immediately with text.
- Dedicated chat icon in the selection action bar to populate the chat input with selected text for follow-ups, with a toggle in Settings.
- Preset popover menu in existing conversations lists External Ask targets alongside prompt presets, opening upward from the bottom bar.

### Changed

- Selected prompt and External Ask badges sit above the composer field on the left with compact content-adaptive width.
- Empty-state External Ask chips and shortcuts select a pending target instead of launching immediately; click again, Esc, or clear to cancel.

### Fixed

- Pressing an External Ask shortcut or selecting from the popover sends immediately when composer text is present.

## [0.2.3] - 2026-09-11

**Refreshed settings sidebar, compact layouts, clearable global shortcut**

### Changed

- Settings uses a compact grouped sidebar with bilingual search, keyboard navigation, and visible-control jump targets.
- Refreshed Settings experience with tighter spacing, gradient icon tiles, and compact provider layouts.

### Fixed

- Global shortcuts can be cleared in Settings so SpotAsk no longer occupies a system hotkey.

## [0.2.2] - 2026-09-10

**Reasoning timer optimization, localized directory scan fix**

### Fixed

- Completed and collapsed reasoning conversations no longer keep a live thinking-time clock refreshing.
- Localization no longer re-scans language directories on every thinking header refresh.

## [0.2.1] - 2026-09-08

**External Ask on selection, URL scheme support, Homebrew Cask**

### Added

- The selection action bar can show External Ask targets beside prompt presets, with up to eight actions supported.
- Open SpotAsk via `spotask://` URLs (`open`, `ask?q=`, `toggle`, `settings`) from Alfred, Raycast, Shortcuts, or Terminal.
- Homebrew Cask distribution: install and update SpotAsk directly via `brew install --cask spotask`.

### Changed

- Ask Grok quick action is now disabled by default on fresh installations.

### Fixed

- Input field text is properly cleared after triggering an External Ask quick action.
- Preserve composed IME input and multiline text during keyboard navigation and submission.
- The ask window no longer jumps in front during Space switching when Keep window on top is off.
- Settings switch labels use available row width so longer copy is no longer truncated.
- The Selection Assistant settings page scrolls when controls exceed window height.
- Labeled selection action bar prompts truncate gracefully inside the 400pt panel while keeping full names in tooltips.
- Clearing or failing a selection, or disabling the assistant, dismisses the action bar and drops the captured snapshot.

## [0.2.0] - 2026-08-19

**External Ask routing, custom target commands, backup support**

### Added

- External Ask: send questions from the quick-ask panel to outside targets like ChatGPT and Grok in one click.
- Add custom External Ask targets using web URLs, app schemes, or terminal commands such as `omp {query}`.
- Master toggle for External Ask in Settings, enabled by default.
- Brand icons for External Ask targets and custom prompt presets.
- Configuration backups now include External Ask targets while maintaining backwards compatibility.

### Fixed

- After a local reinstall, the selection assistant prompts to re-authorize Accessibility permissions for reading selected text.
- The quick-ask panel starts a fresh conversation after a period of inactivity.

## [0.1.6] - 2026-08-12

**Per-model reasoning effort, startup update checks, automatic compatibility**

### Added

- Per-model thinking control: disable reasoning or select effort levels, with custom JSON request parameters.
- Optional automatic update check at launch with in-app notifications and release page links.
- Compatibility settings are inferred automatically from provider and model names while preserving manual selections.

### Fixed

- Code block copy buttons receive clicks reliably while Markdown text selection stays enabled.

## [0.1.5] - 2026-08-11

**Provider icons, bubble chat layout, math rendering, multi-line selection**

### Added

- Provider brand icons for supported services in the model picker, chat header, and settings.
- Optional IM-style bubble layout (assistant on left, user on right) configurable in Appearance settings.
- Switch to another model directly from the answer header and regenerate the latest response.
- Copying selected message text preserves Markdown formatting across headings, lists, quotes, code blocks, and tables.
- LaTeX math formula rendering inside answers, configurable in Appearance settings.
- Bilingual online documentation site accessible directly from About settings.

### Changed

- Automatic selection assistant skips empty or whitespace-only text selections.
- Completed code blocks wrap text automatically so drag-selection passes through continuously.

### Fixed

- Message text can be selected continuously across multiple lines and copied cleanly.
- Selection highlighting stays continuous across Markdown blocks without visual fragmentation.
- Press ⌘+L to instantly refocus the question composer when focus has moved away.
- Settings sidebar supports Up/Down arrow navigation between sections when focused.
- Smoother animation and interaction when expanding reasoning steps during long thinking responses.
- Ordinary clicks or canceled selections no longer trigger the selection assistant unexpectedly.

## [0.1.4] - 2026-08-07

**Initial release: quick asking, selection assistant, multi-model byok, reasoning**

### Added

- Quick model switch: choose any provider's model from the header for the current chat; new chats return to the default model.
- Temporary attachments: paste screenshots, drag in images or code files, with images sent as visual input and text as context.
- Attachment context follows the chat: subsequent follow-up questions and retries retain all previous attachments.
- Model picker features search, provider grouping, keyboard navigation, and a shortcut to restore the default model.
- Cross-app selection assistant: select text anywhere on macOS to translate, explain, summarize, polish, or run custom prompts.
- Quick action bar appears alongside selected text, showing text labels by default.
- Selection assistant supports direct-run execution and optional automatic invocation.
- Automatic invocation includes blacklist and whitelist app filtering with a searchable app picker.
- Anthropic native provider support with model discovery, alongside OpenAI-compatible services.
- HTTP and SOCKS5 proxy support with optional credentials and connection testing.
- Customizable global shortcut for bringing up the ask window.
- Collapsible reasoning process display with elapsed time tracking and default-expansion setting.
- Per-answer action bar with quick copy and retry actions.
- Interface localization supporting 8 languages: English, 简体中文, Español, Deutsch, 日本語, Français, Português, and Русский.
- Configuration export/import and diagnostic logging with lightweight in-app feedback toasts.

### Changed

- The summarize quick action uses a clearer, more recognizable icon.
- Selection assistant settings collapse when disabled, requesting Accessibility permissions only on enable.
- Conversation participants are labeled with icons, model names for assistants, and 你 for user messages.
- Streaming updates are isolated to active messages instead of rewriting the entire conversation array.
- Conversations keep recent active messages eagerly rendered while loading older history lazily.
- Streaming responses render as stable Markdown blocks, sealing the tail upon completion without rebuilding the tree.
- Scroll callbacks update follow state only on genuine threshold crossings, disabling size anchoring during manual scrolling.

### Fixed

- Streaming Markdown preserves paragraph, soft wrap, list, and code block formatting while generating.
- Long streaming answers stay expanded after completion and survive subsequent conversation updates.
- Chat and reasoning scrolling coalesces rapid updates, eliminating per-token queue lag.
- The composer skips full TextKit measurement once reaching maximum height.
- Selection assistant reads selected text reliably once granted Accessibility permissions.
- Selections created with text markers resolve accurately.
- Closing the window preserves composer drafts and restores smooth panel fade animations.
- App icon corners render cleanly in Dark Mode without white artifact borders.
- Service provider cards expand and collapse reliably.
- Thinking expansion behavior: expands during reasoning and collapses for final answers when enabled; stays collapsed when disabled.

[Unreleased]: https://github.com/shiquda/SpotAsk/compare/v0.2.7...HEAD
[0.2.7]: https://github.com/shiquda/SpotAsk/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/shiquda/SpotAsk/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/shiquda/SpotAsk/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/shiquda/SpotAsk/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/shiquda/SpotAsk/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/shiquda/SpotAsk/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/shiquda/SpotAsk/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/shiquda/SpotAsk/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/shiquda/SpotAsk/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/shiquda/SpotAsk/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/shiquda/SpotAsk/compare/v0.1.3...v0.1.4
