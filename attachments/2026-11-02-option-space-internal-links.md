# SpotAsk：⌥Space 页内链 brief（2026-11-02，北京时间）

> 目标页：https://shiquda.github.io/SpotAsk/guides/chatgpt-option-space （源文件 `docs/site/guides/chatgpt-option-space.md`）
> 依据：Lenny L4（Ethan Smith, internal linking：从已有曝光的 crawl point 出发，每页 5–10 条描述性锚文本的上下文链接）；GSC 2026-10-05~11-01 本页 159 曝光 / 5 点击 / 均排 6.6，是全站唯一 crawl point。
> **约束：主页 / 顶栏 IA 不动（Jim 2026-10-27 决定）。只加正文里的上下文链接 + 本页底部 Related 小节。不改本页 title / meta / H1 / slug。**

## 现状（repo main @ 59b0f63）
- 正文上下文入链只有 2 处：`troubleshooting.md:40`、`use-cases/mac-ai-launcher.md:32`（另有侧栏 Help）。
- 本页出链：getting-started、external-ask ×3、macos-integration、reference ×2、troubleshooting、byok-macos-ai、mac-ai-launcher。没有 Related 小节，没有对比页（还不存在）。

## A. 入链（加到这些页，英文页；锚文本用查询原话，别都一样）

| # | 来源页（源文件:大致行） | 放在哪 | 锚文本（原样） | 目标 |
|---|---|---|---|---|
| 1 | `getting-started.md:10`（"Press ⌥ + Space…"） | 该步骤后加一句提示 | `ChatGPT took ⌥Space on your Mac?` | `/guides/chatgpt-option-space` |
| 2 | `reference.md:39`（全局快捷键行） | 表格行末或表下注释 | `ChatGPT Option+Space conflicts` | `/guides/chatgpt-option-space#set-up-spotask-on-space-without-fighting-chatgpt` |
| 3 | `guides/macos-integration.md:35`（Summon via Global Hotkey） | 该条末尾 | `if ChatGPT's Option+Space is not working or opens Mini` | `/guides/chatgpt-option-space` |
| 4 | `guides/external-ask.md`（讲 Ask ChatGPT 内置项的段落） | 段尾一句 | `Coming from ChatGPT's ⌥Space chat bar? Get a one-hotkey quick ask back` | `/guides/chatgpt-option-space#if-you-just-want-one-hotkey-to-ask-anything-spotask` |
| 5 | `use-cases/external-ask-routing.md:52` 起的 Related 列表 | 列表新增一行 | `ChatGPT chat bar not working on Mac` — fixes and a one-hotkey alternative | `/guides/chatgpt-option-space` |
| 6 | `use-cases/byok-macos-ai.md`（讲需要 API key 的段落） | 一句话 | `use your ChatGPT subscription through Ask ChatGPT instead` | `/guides/chatgpt-option-space#faq` |
| 7 | `explore.md:28`（"default ⌥ + Space"） | 括号补一句 | `shortcut clash with ChatGPT?` | `/guides/chatgpt-option-space` |
| 8 | 新 `/compare/` hub（见 compare brief） | ChatGPT Chat Bar 行 + 决策树 "ChatGPT's shortcut stopped working" 分支 | `ChatGPT ⌥Space not working` | `/guides/chatgpt-option-space` |
| 9 | 新 `/compare/raycast-ai` | "Using both" 一节 | `ChatGPT Mini can also take ⌥Space from Raycast` | `/guides/chatgpt-option-space#mini-took-space-from-another-app` |

锚点 id 以 VitePress 实际生成的为准（Dev 构建后核对，坏锚点改成页面级链接）。zh-CN 页不加（该页是 englishOnlyPages）。

## B. 本页出链：在 FAQ 之前加 `## Related problems and comparisons`（3–5 条，每条一句说明）
1. `[Global shortcut conflicts in SpotAsk](/troubleshooting#global-shortcut-conflicts)` — other apps that grab a key
2. `[Open SpotAsk from Spotlight, Siri or a URL](/guides/macos-integration)` — if you'd rather not use any global hotkey
3. `[SpotAsk vs Raycast AI](/compare/raycast-ai)` — if you use Raycast and are deciding where AI should live（**对比页上线后再加**，同 PR 则一起）
4. `[Compare Mac AI quick-ask apps](/compare/)` — SpotAsk, Raycast AI, BoltAI, MindMac, ChatGPT（同上）
5. `[Route a question to ChatGPT, Perplexity or a CLI agent](/guides/external-ask)`

## C. 可选（同 PR，Dev 判断篇幅）：补两条 FAQ 覆盖补全里的变体
- `Is the ChatGPT chat bar gone on Mac?` → 2–3 句：新 app 不再用 ⌥Space 开旧 Chat Bar，Chat Bar 在 ChatGPT Classic；链到本页 "Go back to ChatGPT Classic"。**发布当天复核 ChatGPT 现状，标 As of 日期。**
- `Why is my ChatGPT Mac keyboard shortcut not working?` → 指向 Quick answer 判定表。
- 依据：Google 补全 2026-11-02（hl=en gl=us）出现 `chatgpt mac shortcut not working`、`chatgpt macos shortcut not working`、`macbook chatgpt shortcut not working`、`chatgpt mac keyboard shortcut not working`；`chatgpt option space` 有 10 条补全。不报搜索量。
- 不改 title/meta（CTR 基线：28 天约 3%，均排 6.6；改 title 另走 ScreenZen 式基线流程）。

## 验收
- [ ] 7 处现有页入链 + Related 小节（对比页链接随对比页一起上线）
- [ ] 锚文本不重复、都是描述性；无"click here"
- [ ] 主页、顶栏、侧栏结构未改
- [ ] 构建后无坏链（docs:verify）；预览链接贴 issue
