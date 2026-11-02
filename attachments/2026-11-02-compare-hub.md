# SpotAsk：/compare 精简对比总页 brief（2026-11-02，北京时间）

> 英文页；中文备注给 Jim。**不是成品文章**，Writer（Dev / Mika）按本 brief 写稿。
> slug：`/compare/`（源文件建议 `docs/site/compare/index.md`）。Jim 2026-11-02 已同意做 /compare 并点名 Raycast。
> 导航：主页 / 顶栏不动。侧栏：放 Guides ▸ More 组（与 Reference / Philosophy / Privacy 同组），显示名 **Compare apps**；等对比页 ≥3 篇再考虑独立 Compare 组（10-27 既定建议）。← 这一条 PR 出来给 Jim 看一眼。
> 参考：WhyFirst `/blog/website-blocker-comparison`（WF-28 hub）结构；Lenny L10（中漏斗"选谁"）、L13（开头把对手定在它擅长的事 + own your alternatives）、L7/L15（事实总表给 AI 引用）。

## 1. 搜索意图与读者
- 人群：Mac 用户，想"按一个键就问 AI"，正在 Raycast AI / BoltAI / MindMac / ChatGPT 自带快捷键 / 开源小工具之间挑。
- 查询（Google 补全 2026-11-02，hl=en gl=us；不报搜索量）：`raycast ai alternative`、`open source raycast alternative`、`raycast open source alternative reddit`、`raycast ai byok`、`bolt ai alternative`、`boltai free alternative`、`mindmac alternative`。`best ai menu bar app mac` 补全为空，但 SERP 前排是 felloai.com、thinkdifferent.blog、timingapp 的榜单 → 这是榜单型查询，hub 只当"事实总表"，不硬抢。
- 读者此刻要的：一张能直接对比的表 + "我这种情况该选谁"。

## 2. Title ×2 / meta ×2
- Title A（66）：`Mac AI Quick-Ask Apps Compared: SpotAsk, Raycast AI, BoltAI & More`
- Title B（65）：`Which Mac AI Menu Bar App? SpotAsk vs Raycast AI, BoltAI, ChatGPT`
- Meta 1（约 148）：`An honest table of Mac apps that open AI from a hotkey: SpotAsk, Raycast AI, BoltAI, MindMac, ChatGPT. Price, BYOK, privacy, and when to pick each.`
- Meta 2（145）：`Raycast, BoltAI, MindMac, ChatGPT or SpotAsk? Compare price, open source, where your key's requests go and who each app is for. Checked Nov 2026.`
- 站点后缀：VitePress 默认加 ` | SpotAsk – Ask Any AI on Mac` 会超长 → 本页关掉 titleTemplate（同 ⌥Space 页做法）。
- H1：`Mac AI quick-ask apps compared`（或与 title 同步）

## 3. Answer-ready 引用段（页首，60–90 词，给 AI Overviews / ChatGPT 引用）
> "If you want one hotkey on your Mac to ask AI a quick question, there are four kinds of app. **Raycast** is a launcher that also has AI (AI needs a paid plan as of Nov 2026). **BoltAI** and **MindMac** are paid AI chat workspaces that use your own API keys. **ChatGPT's desktop app** has its own shortcut but only talks to OpenAI. **SpotAsk** is a free, open-source menu bar app that does only the ask box: your own key, sent straight to your provider, or a one-key hand-off to ChatGPT, Perplexity or a CLI agent."
（括号内事实以发布当天复核为准；字数 80 左右。）

## 4. 结构（H2 大纲）
1. **Quick answer**（上面那段）+ "Last checked: <date>" + 作者声明：`SpotAsk is our app. We list where others are the better choice.`
2. **The comparison table**（核心，见 §5）
3. **Which one should you pick?** 决策树（§6）
4. **When Raycast is the better choice**（3–4 条，诚实；链 `/compare/raycast-ai`）
5. **When BoltAI or MindMac is the better choice**（项目、长对话、MCP、多端 → 选它们；一句话链到官网，不做贬低）
6. **When ChatGPT's own shortcut is enough**（只用 ChatGPT、快捷键正常 → 不用装任何东西；坏了 → 链 ⌥Space 页）
7. **Where SpotAsk fits**（3 句：快问、BYOK 直连、External Ask；不是启动器、不是工作台）
8. **How we checked**（日期、来源链接列表、"prices change, check vendor pages"）
9. FAQ（3–4 条，FAQPage 可选）：`Is there a free Raycast AI alternative?` / `Which Mac AI apps let me use my own API key?` / `Do any of these send my key through their servers?` / `Can I use ChatGPT Plus in these apps?`
字数：**900–1,300 词**（hub 要精简，长内容放单篇对比页）。

## 5. 对比表（列与已核事实；⚠ = 发布前 Dev 必须复核并写日期）

| | SpotAsk | Raycast AI | BoltAI | MindMac | ChatGPT desktop (Chat Bar / Mini) |
|---|---|---|---|---|---|
| What it is | Menu bar ask box + selected-text actions + hand-off | Launcher (apps, clipboard, windows, extensions) with AI | AI chat workspace | AI chat client | OpenAI's own app |
| Price | Free | AI not in Free; Pro $10/mo or $96/yr (500 credits), Pro+ $20/mo（Raycast Billing 手册，2026-11-02 读） | 一次性买断，⚠ 价格（felloai 10-10 称 $79/$99/$199，以 boltai.com 为准） | ⚠ 价格与是否仍在维护 | App free; Plus etc. for more |
| Open source | Yes, AGPL-3.0 | No | No | No ⚠ | No |
| Your own API key (BYOK) | OpenAI-compatible, Anthropic, Gemini | Anthropic, Google, OpenAI, OpenRouter + Custom Providers（OpenAI 兼容）；⚠ Free 账号能否用 BYOK | Yes（OpenAI, Anthropic, Gemini, Mistral, Azure, Bedrock…） | Yes ⚠ | No（用 ChatGPT 账号） |
| Where BYOK requests go | Straight to your provider（无 SpotAsk 服务器） | Anthropic/Google/OpenAI key：经 Raycast 服务器；OpenRouter、Custom Providers：设备直连（Raycast BYOK / Custom Providers 手册 2026-11-02）；注意 Custom Providers 的图片附件仍会上传（Privacy 页） | Direct to provider（官网自述） ⚠ | ⚠ | OpenAI |
| Local models | Via OpenAI-compatible endpoint（如 Ollama）⚠ 以文档为准 | Local Models（Ollama） | Ollama, LM Studio | ⚠ | No |
| Send to ChatGPT / Perplexity web or CLI agent | Yes（External Ask，一键或决策模型） | ⚠（扩展可实现，非内置同等功能） | ⚠（可用 Codex CLI / Claude Code 集成） | ⚠ | — |
| Selected-text actions | Yes（Selection Assistant） | Yes（AI Commands） | Yes（inline） | ⚠ | Partial（Work with Apps）⚠ |
| Launcher / clipboard / window mgmt | No | Yes | No | No | No |
| Account required | No | Yes for AI（Raycast 账号） | No（官网） | ⚠ | Yes |
| Default hotkey | ⌥Space | ⌥Space（launcher）⚠ / Quick AI 另设 | ⚠ | ⚠ | ⌥Space → Mini（新版）；Chat Bar 在 ChatGPT Classic（10-27 brief，⚠ 发布日复核） |
| macOS | 15+, Apple silicon & Intel | ⚠ Raycast 2：macOS Tahoe + Apple silicon（第三方 Ferrocast 表格称，须查 Raycast 官方） | 13+, Intel & Apple silicon（官网） | ⚠ | ⚠ |

写作规则：每个 ⚠ 要么复核后写实，要么从表里删掉那格（写 "—" 并在 How we checked 里说明没核到），**不许猜**。价格写 "as of <date>"。

## 6. 决策树（文字版，可做成列表）
- 你还想要启动器、剪贴板、窗口管理、扩展 → **Raycast**（有预算上 Pro 用 AI）
- 你要项目、长对话、MCP、多端同步的 AI 工作台，愿意一次性付费 → **BoltAI**（或 MindMac ⚠）
- 你只用 ChatGPT，且它的快捷键正常 → **ChatGPT 自带**；快捷键坏了 → 链 `/guides/chatgpt-option-space`
- 你只想一个键随手问一句、自己的 key 直连、免费开源，或想把问题一键甩给 ChatGPT / Perplexity / CLI agent → **SpotAsk**
- 已经在用 Raycast 又想要 SpotAsk 的直连快问 → 可共存，注意两者默认都是 ⌥Space（链 `/compare/raycast-ai#using-both`）

## 7. 内链
- 出：`/compare/raycast-ai`（表头 + When Raycast）、`/guides/chatgpt-option-space`（ChatGPT 行 + 决策树）、`/use-cases/byok-macos-ai`（BYOK 行）、`/guides/external-ask`（hand-off 行）、`/use-cases/privacy-architecture`（Where requests go 行）、`/getting-started`（结尾 CTA）
- 入：⌥Space 页 Related（见内链 brief）、`/compare/raycast-ai` 顶部面包屑/首段、`use-cases/mac-ai-launcher.md`（"compare with Raycast and others"）、`use-cases/byok-macos-ai.md`（"other BYOK apps compared"）、README "Documentation" 行后可加一条（可选，Jim 定）
- 主页 / 顶栏：不加。

## 8. Schema / 技术
- 自指 canonical；进 sitemap；可选 FAQPage；表格用真实 `<table>`（Markdown 表即可），别做成图片。
- llms.txt：生成脚本把 /compare 收进去（随 N3 同步）。

## 9. 不要写
- ❌ "best"、"#1"、"Raycast alternative that does everything"
- ❌ 未复核的价格 / 系统要求
- ❌ "Raycast sends all your data to its servers"（不实：OpenRouter、Custom Providers、Local Models 不经过 Raycast）
- ❌ 贬低竞品功能；任何搜索量数字
