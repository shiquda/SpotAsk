# SpotAsk N3：定位句统一 + 事实自洽检查（2026-11-02，北京时间）

> As of 2026-11-02。来源：`shiquda/SpotAsk` main @ 59b0f63（2026-10-29 00:50 北京时间提交，v0.3.3 已发布 2026-10-28 11:49 北京时间）、线上文档 https://shiquda.github.io/SpotAsk/ （首页 JSON-LD、/llms.txt）、`gh repo view` About。
> 证据：`briefs/evidence/2026-11-02/spotask-repo-head.txt`；源码行号见下表。
> 结论一句话：**最大的问题是 Key 存储说法**。README、首页、Philosophy、Providers 页、llms.txt 都说 key 放在（加密的）macOS Keychain；源码和 BYOK / Privacy Architecture 页说的是本地 `credentials.json`（权限 0600，**不用 Keychain、不加密**）。这正是 WhyFirst DEV-638 那类"对外说法和实际不符"，而且 llms.txt 会被 AI 直接引用。

## 1. 不一致清单（已核实）

| # | 说法（出处） | 实际（证据） | 建议改成 | 严重度 |
|---|---|---|---|---|
| F1 | "Access keys are stored securely in macOS Keychain"（README.md:115）；"访问密钥加密保存在 macOS 本地钥匙串中"（README.zh-CN.md:115） | `Sources/SpotAsk/Persistence/LocalAPIKeyStore.swift:20-21` "Stores API keys in Application Support while a stable Keychain signing identity is unavailable"；L122 `JSONEncoder().encode(...).write`，L123 `0o600` → 明文 JSON，仅当前用户可读 | "Access keys are stored only on this Mac, in a local credentials file readable only by your macOS user (not in Keychain), and are sent only to the provider you configured." 中文同义 | **高**（隐私说法） |
| F2 | 首页 feature "Access keys stay encrypted in your Keychain"（docs/site/index.md:33；zh-CN/index.md:34） | 同上 | "Access keys stay on this Mac and go only to your provider — no middle server, no telemetry." | 高 |
| F3 | "stored only on this Mac, in the system Keychain"（philosophy.md:50；zh-CN/philosophy.md:50） | 同上 | "stored only on this Mac" + 链到 Privacy Architecture | 高 |
| F4 | "Stored locally in encrypted macOS Keychain"（guides/providers-and-models.md:29；zh 版同页如有同句一起改） | 同上 | "Stored locally in a user-only credentials file (0600)" | 高 |
| F5 | llms.txt Product facts："access keys are stored in the macOS Keychain"（生成源 `Scripts/generate-docs-metadata.mjs`） | 同上；llms.txt 是给 AI 看的事实页 | 改生成脚本里那句，重新生成 llms.txt / llms-full.txt | **高**（AEO 直接受影响） |
| F6 | llms.txt "App size is under 10 MB"（同脚本 L212）；philosophy "~10 MB" | v0.3.3 DMG：arm64 10,078,283 B、x86_64 10,490,049 B（>10 MB 十进制） | "about 10 MB" | 低 |
| F7 | 更新检查 "checks the official release page once at launch"（privacy.md:33）；"Official GitHub Releases API … Single check at launch"（use-cases/privacy-architecture.md:22） | Sparkle 2.9.6，`Info.plist` `SUEnableAutomaticChecks=true`、未设 `SUScheduledCheckInterval` → Sparkle 默认约每 24 小时后台检查，不止启动一次；读的是 GitHub Releases 上的 `appcast-*.xml`，不是 Releases API；下载源 "Automatic / Accelerated Mirror" 会用 `https://ghproxy.net/` 前缀（`AppVersion.swift:45`，reference.md:81 提到镜像但 privacy 页没提） | Dev 按源码确认后写清：检查频率、读 appcast、"Accelerated/Automatic 可能经 ghproxy.net 镜像"；仍不含问题/密钥/选中文字 | 中（**needs-verify**：Automatic 模式何时回落镜像） |
| F8 | privacy-architecture.md:26 "You will observe zero background telemetry connections when idle" | 有周期更新检查（F7） | "no telemetry; the only background request is the update check (can be turned off)" | 中 |
| F9 | GitHub About 列 "OpenAI, Claude, any OpenAI-compatible"，漏 Gemini；Homebrew cask desc "Ask an AI assistant from your menu bar"（太泛，没有 hotkey / BYOK） | getting-started.md:17/40 支持 OpenAI / Anthropic / Gemini 三种 API Format | 见 §2 统一句 | 低 |
| F10 | README 首句是 "menu-bar AI assistant & query router … decision model"；首页 title 是 "One Hotkey to Ask Any AI"；cask 是 "Ask an AI assistant" —— 三种说法 | — | 统一成 §2 的一句话，README 首句可保留 router 作第二句 | 低（定位一致性） |
| F11 | JSON-LD `applicationCategory: DeveloperApplication` | 产品是通用效率工具 | `UtilitiesApplication`（或 `ProductivityApplication`），可选 | 低 |

**已一致 / 已修过（不用动）：**
- troubleshooting 全局快捷键路径已是 Settings > **Shortcuts** > Global Shortcut（DEV-684 已修）；剩下两处 Settings > General 是 Clear All Local Data / Diagnostics，正确。
- "只能检测 SpotAsk 自身快捷键冲突"：troubleshooting、mac-ai-launcher、⌥Space 页三处一致。
- macOS 15+ / Apple Silicon + Intel：README、cask（`depends_on macos: :sequoia`，on_arm/on_intel）、JSON-LD、llms.txt 一致。
- 免费 / AGPL-3.0 / 无账号：一致。
- Plus ≠ API key、Ask ChatGPT 只预填不自动发送、打开网页版：⌥Space 页已写清。

**不填 API key 时 External Ask：** ⌥Space 页（DEV-684，阶段 0 由 Dev 实测，2026-10-27）写的是 "add an API key for in-app answers, or leave it empty and use Ask ChatGPT"。源码只在需要模型时抛 `missingAPIKey`（`ProviderTargetResolver.swift:68`），未见 External Ask 依赖 key。→ 可以写，但**本单请 Dev 在 v0.3.3 上复测一次**再把这句放进 About/llms.txt。

## 2. 统一推荐定位句（As of 2026-11-02）

**EN（一句，README 首句 / 首页 description 基调 / llms.txt 第一条）**
> SpotAsk is a free, open-source Mac menu bar app for quick questions: press ⌥Space to get an answer from your own API key (OpenAI-compatible, Anthropic or Gemini, sent straight to that provider), act on selected text, or hand the question to ChatGPT, Perplexity or a local CLI agent — it is not a launcher or a full AI workspace.

**ZH**
> SpotAsk 是免费开源的 Mac 菜单栏快问工具：按 ⌥Space，用你自己的 API Key（OpenAI 兼容、Anthropic 或 Gemini，直连服务商）得到回答，或处理选中文字，或一键交给 ChatGPT、Perplexity、本地 CLI Agent；它不是启动器，也不是完整的 AI 工作台。

**做什么 / 何时用 / 何时不用（给 llms.txt、FAQ、对比页复用）**
- 何时用：想一个键随手问一句；想自己选模型/服务商（BYOK 直连）；想同一个键把问题甩给 ChatGPT / Perplexity / CLI agent；想要开源、无账号、无遥测。
- 何时不用：要启动器、剪贴板、窗口管理、扩展商店（选 Raycast / Alfred）；要项目、长对话管理、MCP、多端同步的 AI 工作台（选 BoltAI 等）；只用 ChatGPT 且它的快捷键正常（直接用 ChatGPT 桌面版）。
- 不填 key：仍可用 External Ask 在浏览器打开 ChatGPT / Perplexity 并预填问题（待 v0.3.3 复测确认）。

**按渠道的短版**
- GitHub About（≤350 字符）：`Free, open-source Mac menu bar app for quick AI questions. Press ⌥Space to ask with your own API key (OpenAI-compatible, Anthropic, Gemini — sent straight to your provider), act on selected text, or hand off to ChatGPT, Perplexity or a local CLI agent. Native Swift, no account, no telemetry.`（约 300 字符）
- Homebrew cask `desc`（brew 规则：不以 "A"/产品名开头，≤80 字符）：`Menu bar AI quick-ask with one hotkey and your own API key`（58 字符）
- 首页 meta description：现有一句已接近，可保持；只要 Jim 不想动就不改（title/meta 改动走 CTR 流程）。

## 3. Checklist（给 Dev，docs + 元数据，不改产品功能）
- [ ] F1–F5：所有 Keychain / encrypted 说法改为真实存储方式（EN + zh-CN 成对改；README 两份；生成脚本改后重新生成 llms.txt / llms-full.txt）
- [ ] F6：10 MB 改 "about 10 MB"
- [ ] F7/F8：按源码确认更新检查频率、appcast、镜像（ghproxy.net）行为后改 privacy.md / privacy-architecture.md（EN+ZH）；结果贴 issue
- [ ] F9/F10：GitHub About（`gh repo edit --description`，**等 Jim 点头再执行**，这是对外可见改动）、cask desc、README 首句、llms.txt 第一条用 §2 统一句
- [ ] F11（可选）：JSON-LD applicationCategory
- [ ] 复测：v0.3.3、不配任何 key，⌥Space → Ask ChatGPT / Perplexity 是否正常打开并预填
- [ ] `rg -i "keychain|钥匙串|encrypted"` 在 README*、docs/site、Scripts 里结果只剩准确描述
- [ ] PR 开好停，不 merge；预览链接贴 issue

## 4. 给 Jim 的备注
- F1–F5 属于"隐私说法写错了"（说得比实际更安全），建议按事实改，不需要你挑措辞；但改 GitHub About 和 README 首句是对外可见的定位变化，PR 出来后给你看一眼。
- 如果你更想**改产品**（真的把 key 放进 Keychain），那是另一个功能单；本单只让文档说实话。
