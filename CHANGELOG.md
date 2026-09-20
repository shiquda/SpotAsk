# Changelog

All notable changes to SpotAsk are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `spotask://settings/<page>` links open one Settings page directly (Provider, Prompts, External Ask, Selection Assistant, Shortcuts, General, Appearance, About), so documentation, shortcuts, and terminal scripts can send users to the exact page. Plain `spotask://settings` still opens Settings, and an unknown page falls back to it.
- Settings groups that configure behavior worth explaining now link to their guide (service addresses, models, prompts, External Ask, Selection Assistant, shortcuts reference, proxy, local data, appearance). Links follow the interface language, opening the English or Simplified Chinese page.
- The documentation site draws flow diagrams for service setup, address types, model selection, External Ask, and the Selection Assistant, and adds an **Open Settings in SpotAsk** button to the English and Simplified Chinese pages that jump to the matching settings page. Each button also states the manual path, so it still works without the app installed.
- The **retry with another model** picker on an answer now lists your enabled External Ask targets under an "External Ask" section. Picking one opens that platform with the question this answer was generated for, and the conversation, the session model, and the composer draft all stay exactly as they are.
- An optional, off-by-default clipboard-assisted selection mode in Settings > Selection Assistant for apps you choose. Selections in those apps are detected as usual, and the app's own Copy command runs only when you use an action, so accurate text reaches the action while the clipboard is restored afterwards.

### Changed

- The header model picker is centered in the title bar, instead of sitting next to the SpotAsk brand. The generating spinner stays grouped with the picker.
- The header's quick model switcher lists models only again. It switches the model of the current window, so offering External Ask targets there promised a model change that picking one never performed; that entry now lives in the retry picker, where the question to ask elsewhere is already at hand.
- Adding selected text to chat now prefixes each line with Markdown `>`, and the selection action uses a quote bubble icon.
- The documentation home page renders the hero flow diagram between the hero actions and the feature cards, in both languages, instead of below them.
- The documentation home page hero keeps only the SpotAsk wordmark; the `Docs` / `文档` second line is gone.

### Fixed

- The **Open Documentation** link no longer sits under the Settings window's scrollbar. It keeps a 16pt trailing inset, so it lines up with the card below it on every settings page that shows the link.
- Running the test suite no longer overwrites your macOS clipboard. Code block copy buttons write to an injectable pasteboard, so tests copy into a private one while the app still copies real code blocks to the system clipboard.

## [0.2.4] - 2026-09-16

### Added

- Check for Updates now downloads and installs inside the app. You can skip a version from the update window and restore alerts in About. GitHub Releases remains available if the in-app updater cannot run.
- Configurable update download sources (Automatic, Official GitHub, Accelerated Mirror) in Settings > About > Updates with automatic timeout detection and mirror fallback for reliable downloads across regions.
- Type `@` in the composer to filter prompt presets and External Ask targets. Selecting a preset keeps the draft; a nonempty query launches External Ask immediately.
- Dedicated chat icon in the selection assistant action bar to quickly populate the chat input with selected text for follow-up questions, with a configurable setting in Settings (enabled by default).
- In existing conversations, the preset popover menu now lists enabled External Ask targets alongside prompt presets, opens upward from the bottom composer bar, and External Ask shortcuts attach a pending badge that launches on send.

### Changed

- The selected prompt or External Ask badge now sits above the composer field on the left with a compact content-adaptive width, outside the input, so the extra bottom row and its leftover space are gone.
- Empty-state External Ask chips and their shortcuts now select a pending target instead of launching immediately; Return sends the draft, and clicking again, Esc, or clearing the input cancels the selection.

### Fixed

- When composer input is present, pressing an External Ask shortcut or selecting from the popover menu sends immediately rather than requiring an extra Return keypress.

## [0.2.3] - 2026-09-11

### Changed

- Settings now uses a compact grouped sidebar with bilingual content search, keyboard navigation, and search results that jump only to visible controls.
- The Settings experience has been refreshed with tighter spacing, gradient icon tiles, and more compact page and provider layouts.
### Fixed

- Global Shortcut can be cleared in Settings so SpotAsk no longer occupies a system hotkey. Existing installs keep their current shortcut, including the default Option+Space.

## [0.2.2] - 2026-09-10

### Fixed

- Completed and hidden reasoning conversations no longer keep a live thinking-time clock refreshing.
- Localization no longer re-scans language directories on every thinking-header refresh.

## [0.2.1] - 2026-09-08

### Added

- The selection action bar can show External Ask targets beside prompt presets. Separate toggles hide prompts or External Ask (both on by default). Up to eight actions share the bar.
- Open SpotAsk from Alfred, Raycast, Shortcuts, or the terminal with `spotask://` URLs: `open`, `ask?q=`, `toggle`, and `settings`.
- Homebrew Cask distribution: install and update SpotAsk directly via `brew install --cask spotask`.

### Changed

- Ask Grok quick action is now disabled by default on fresh installations.

### Fixed

- Input field text is properly cleared after triggering an External Ask quick action.
- Preserve composed and multiline input during keyboard navigation and submission.
- The ask window no longer jumps in front during Space switching when Keep window on top is off.
- Settings switch labels use the available row width instead of the 134pt control column, so longer copy is no longer truncated.
- The Selection Assistant settings page scrolls when its controls no longer fit the window.
- Labeled selection action bar prompts stay inside the 400pt panel: long titles truncate instead of rendering off-canvas. Full names remain on the tooltip.
- Clearing or failing a selection, or turning the assistant off, dismisses the action bar and drops the captured snapshot.

## [0.2.0] - 2026-08-19

### Added

- External Ask: send your question to an outside target from the quick-ask panel, then the panel closes and the target opens. Built in are Ask ChatGPT and Ask Grok, which open in your browser and start answering right away.
- Add your own External Ask targets: open a web link, open an app's link, or run a command such as `omp {query}` in Terminal. Choose an icon, reorder, and toggle each target.
- A master switch for External Ask in settings, on by default.
- Brand icons for external targets and custom prompt presets you create.
- Config backups now include your External Ask targets and stay compatible with older backups.

### Fixed

- After a local reinstall, the selection assistant asks you to allow the current install to read selected text again.
- The quick-ask panel starts a fresh conversation after a period of inactivity.

## [0.1.6] - 2026-08-12

### Added

- Per-model thinking control: disable thinking or choose a level, with provider-specific request compatibility and custom JSON request parameters.
- Optional automatic update check at launch, with an in-app notice that opens the release page when a new version is available.
- Compatibility settings are inferred automatically from provider and model names, while manually selected profiles are preserved.

### Fixed

- Code block copy buttons receive clicks again while Markdown text selection stays enabled.

## [0.1.5] - 2026-08-11

### Added

- Provider brand icons for supported services in the model picker, chat header, and settings.
- Optional IM-style conversation layout: model messages on the left and your messages on the right in bubbles, available from Appearance settings.
- Choose another model from the assistant message header and regenerate the latest answer with it.
- Copied message selections restore Markdown markers across headings, lists, quotes, code blocks, and tables.
- Math formulas render inside answers, with a toggle in Appearance settings.
- A bilingual online user guide, reachable from About settings.

### Changed

- Automatic selection assistant skips empty or whitespace-only selections before waking.
- Completed message code blocks wrap instead of opening a separate scrollable selection surface, so a drag can pass through them continuously.

### Fixed

- Message text can be selected continuously across multiple lines and copied.
- Selection highlighting stays continuous across Markdown blocks instead of showing separate highlighted fragments.
- ⌘+L restores focus to the question input when focus has moved elsewhere.
- The Settings sidebar supports Up/Down arrow navigation between sections while a sidebar item is focused.
- Expanding the thinking process is smoother during long deep-thinking answers.
- Automatic selection assistant no longer opens after an ordinary click or a selection that was already cleared.

## [0.1.4] - 2026-08-07

### Added

- Quick model switch: pick any provider's model for the current conversation from the header without touching Settings; New Conversation returns to the default model.
- Temporary attachments: paste a screenshot, drag in images or text/code files, or pick them from a file chooser; images are sent as image content and text files are attached as text context.
- Attachment context follows the conversation: later questions resend earlier screenshots and files, and retry keeps the original attachments.
- Model picker search with provider grouping, keyboard navigation, and a Use Default Model shortcut for returning to the Settings default.

- Cross-app selection assistant: select text in Safari, Notes, or other apps to translate, explain, summarize, polish, or run a custom prompt.
- Quick action bar that appears next to selected text, with text labels shown by default.
- Direct-run mode and optional automatic invocation for the selection assistant.
- Blacklist and whitelist app filtering for the selection assistant's automatic invocation, with a searchable app picker.
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
- Streaming answers are rendered as stable Markdown blocks; only the active tail reparses, and completion seals the tail without replacing the renderer tree.
- Scroll geometry callbacks only update follow state when the near-bottom value actually changes, and size-change anchoring is disabled while the user is scrolling.

### Fixed

- Streaming Markdown now preserves paragraph, soft line, list, and code-block line breaks while the answer is still generating.
- Long answers streamed in the current window stay expanded after completion, and expanded assistant messages survive later conversation updates.
- Chat and reasoning scrolling now coalesces rapid updates instead of queuing one scroll command per token flush.
- The composer skips full TextKit measurement while it is already at its maximum height.
- The selection assistant could not read selected text in some builds; reads now work reliably with Accessibility permission.
- Selections made with text markers now resolve correctly.
- The composer draft is preserved after closing the window, and the panel fade animation is restored.
- The app icon no longer shows white corners in dark mode.
- Provider cards can be expanded and collapsed reliably.
- Thinking expansion behavior: when enabled, thinking stays expanded during reasoning and collapses for the final answer; when disabled, it stays collapsed.

[Unreleased]: https://github.com/shiquda/SpotAsk/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/shiquda/SpotAsk/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/shiquda/SpotAsk/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/shiquda/SpotAsk/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/shiquda/SpotAsk/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/shiquda/SpotAsk/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/shiquda/SpotAsk/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/shiquda/SpotAsk/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/shiquda/SpotAsk/compare/v0.1.3...v0.1.4
