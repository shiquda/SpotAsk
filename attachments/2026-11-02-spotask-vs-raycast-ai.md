# SpotAsk vs Raycast AI — writer-ready brief（2026-11-02，北京时间）

> 英文页，中文备注给 Jim。**不是成品文章。** Jim 2026-11-02 已同意点名 Raycast。
> slug：`/compare/raycast-ai`（源文件 `docs/site/compare/raycast-ai.md`），挂在 /compare hub 下；侧栏同 hub（Guides ▸ More ▸ Compare apps 下一级，或同组第二项）。
> 模板：WhyFirst 对比页（`/workspace/seo/whyfirst/comparison-post-design-2026-10-23.md`）——开头一句把对方定在它最擅长的事（Lenny L13），先承认对方强项，"When Raycast is the better choice" 必须有，事实表带日期，作者声明。
> **先实测再写**：§7 的事实清单 Dev 必须先核完写回 issue，再动笔。

## 1. 意图与读者
- 查询（Google 补全 2026-11-02 hl=en gl=us，不报量）：`raycast ai alternative`（补全还带出 `free ai alternative`）、`open source raycast alternative`、`raycast open source alternative reddit`、`raycast ai byok`（补全只回原词，需求窄但意图精确）。
- SERP 现状（2026-11-02，box 搜索索引，非 Google 实时排名）：`raycast ai alternative` 前排全是**启动器**——Tinycast、Floe、SuperCmd、Ainto、Ferrocast 自家的 "Raycast alternative" 页；`open source raycast alternative` 前排是 openappscout / repolode 榜单 + Vicinae、Sol、Wox。**没有一个结果是"只要 Raycast 的 AI 快问、不要启动器"的角度** → 这是 SpotAsk 能诚实占的缝。
- 人群：①用 Raycast 但只为了 Quick AI，不想付 Pro；②在意 BYOK 请求经不经过第三方服务器；③想要开源、无账号。**不是**：想换掉整个启动器的人（他们该看 Tinycast/Sol 等，正文要说清并给出去的路）。

## 2. Title ×2 / meta ×2
- Title A（58）：`SpotAsk vs Raycast AI: A Free, Open-Source Ask Box for Mac`
- Title B（63）：`Raycast AI Alternative for Mac: SpotAsk vs Raycast (Free, BYOK)`
- Meta 1（143）：`Raycast is a launcher with AI built in; SpotAsk is only the ask box. Compare price, where your API key's requests go, local models and hotkeys.`
- Meta 2（140）：`Looking for a Raycast AI alternative? SpotAsk is a free, open-source Mac menu bar app that sends your own API key straight to your provider.`
- 推荐 A + 1（诚实、对得上"vs"查询，不夸）。B 更贴 `raycast ai alternative`，但"Free"放 title 容易被读成"Raycast 免费替代启动器"。**Jim 选。** 关闭站点后缀。
- H1：`SpotAsk vs Raycast AI`（副标题一行：`A launcher with AI, or just the ask box?`）

## 3. 开头（定住对方擅长的事）
- 第一句方向：`Raycast is a launcher that also has AI. SpotAsk is only the ask box.`
- 第二、三句：Raycast 的强项（启动器、剪贴板、窗口、扩展商店、AI Commands、Pro 里多模型）→ 如果你要这些，Raycast 更好；SpotAsk 只做"按 ⌥Space 问一句、自己的 key 直连、一键交给 ChatGPT/Perplexity/CLI"。
- 作者声明：`SpotAsk is our app. We checked Raycast's own manual on <date>; tell us if anything changed.`

## 4. Answer-ready 引用段（页首，70–90 词）
> "Raycast and SpotAsk both open AI from a hotkey on a Mac, but they solve different problems. Raycast is a full launcher; its AI needs a paid plan (Pro from $10 a month as of Nov 2026), and with your own Anthropic, Google or OpenAI key, requests still pass through Raycast's servers — OpenRouter, Custom Providers and local models are the exceptions. SpotAsk is a free, open-source menu bar app that does only quick questions: your own key goes straight to your provider, or one key sends the question to ChatGPT or Perplexity."
（每个事实以 §7 复核结果为准，改了就同步改。）

## 5. H2 大纲 + 每节要点
1. **The short answer**（引用段 + 三行"pick Raycast if / pick SpotAsk if / use both if"）
2. **What each app is for**（两段，各 3–4 句；Raycast 先写）
3. **Side-by-side**（事实表，见 §6）
4. **Where your API key's requests go**（本页核心差异，写准确）
   - Raycast：Anthropic/Google/OpenAI BYOK 经 Raycast 服务器（"to unify model APIs, fallback, prompt management"，引用手册原话并链接）；OpenRouter 直连；Custom Providers（`~/.config/raycast/ai/providers.yaml`，OpenAI 兼容）直连、key 留本机；Local Models（Ollama）本机；部分工具（图片生成、`raycast` web search）仍走 Raycast 并耗 credits；Custom Providers 的图片附件仍会上传（Privacy 页）。
   - SpotAsk：OpenAI 兼容 / Anthropic / Gemini 都从本机直连 provider；无 SpotAsk 服务器、无账号、无遥测；key 存本机仅当前用户可读的文件（**按 N3 修正后的说法写，不写 Keychain**）。
   - 结论句要诚实：`If you configure Raycast with Custom Providers or OpenRouter, the routing gap mostly closes; the remaining differences are price, account, open source and scope.`
5. **Price**（Raycast：Free 无 AI；Pro / Pro+ / Max 价格与 credits，as of 日期；BYOK 是否需要付费计划 → §7 实测结论；SpotAsk 免费，只付你自己 provider 的 API 费用）
6. **Sending a question somewhere else**（SpotAsk External Ask：ChatGPT/Perplexity/Grok 网页预填、CLI agent、URI；不填 key 也能用 → 以复测为准；Raycast 侧如何实现写实，可能靠扩展/Quicklinks ⚠）
7. **Using both**（两者默认都是 ⌥Space ⚠ 复核 Raycast 默认热键 → 给出改键建议；ChatGPT Mini 也会抢 ⌥Space → 链 ⌥Space 页）
8. **When Raycast is the better choice**（≥4 条：要启动器/剪贴板/窗口/扩展；要 Raycast 统一管理多模型和 credits；要 AI Commands 生态与团队共享；Windows/iOS 也要用）
9. **When SpotAsk is the better choice**（3–4 条：只要快问；不想要账号/订阅；要直连不想配 YAML；要开源可审计；要一键 hand-off 到网页 AI 或 CLI agent）
10. **If you want a full open-source launcher instead**（1 段，诚实给出去的路：Tinycast、Sol、Vicinae 等，链到它们官网或 openappscout 榜单；SpotAsk 不是启动器）
11. **How we checked**（日期、Raycast 手册 4 个链接、SpotAsk 源码/文档链接、测试机 macOS 版本）
12. **FAQ**（4 条）：`Is Raycast AI free?` / `Does Raycast BYOK send my key through Raycast's servers?` / `Can SpotAsk replace Raycast?`（答：不能替代启动器，只替代 AI 快问那部分）/ `Can I run SpotAsk and Raycast together?`

字数：**1,400–1,900 词**。

## 6. 事实表（行；⚠ = 发布前复核）
| | Raycast AI | SpotAsk |
|---|---|---|
| Product type | Launcher + AI | Menu bar ask box + selection actions + hand-off |
| AI price | Not in Free; Pro $10/mo or $96/yr, 500 credits; Pro+ $20/mo; Max $50/mo（Billing，2026-11-02） | Free; you pay your provider |
| Account | Required for AI ⚠ | None |
| Open source | No | AGPL-3.0 |
| BYOK providers | Anthropic, Google, OpenAI, OpenRouter（one key each）+ Custom Providers | OpenAI-compatible, Anthropic, Gemini |
| BYOK model list | Anthropic/Google/OpenAI：only models Raycast offers；OpenRouter：full catalog | Any model ID your provider accepts ⚠（以 providers-and-models 文档为准） |
| BYOK routing | Via Raycast servers for Anthropic/Google/OpenAI; direct for OpenRouter & Custom Providers | Direct to provider |
| Local models | Local Models（Ollama, auto-detect） | Loopback OpenAI-compatible（Ollama, LM Studio） |
| Hand-off to web AI / CLI | ⚠ | Built in（External Ask） |
| Selected text | AI Commands | Selection Assistant（⌥⇧Space） |
| Platforms | macOS, Windows, iOS ⚠ 系统版本要求 | macOS 15+, Apple silicon & Intel |
| Default hotkey | ⚠ | ⌥Space |

## 7. Dev 先实测 / 复核清单（写回 issue，带日期和截图或手册链接）
1. **Raycast Free 账号**能否使用 BYOK、Custom Providers、Local Models？（Billing 手册写 "AI features aren't included in Raycast Free"，但 BYOK/Custom/Local 是否也锁在 Pro 需实测或找手册原句）
2. Raycast BYOK 路由原句 + Custom Providers 直连原句（2026-11-02 已读，见 `briefs/evidence/2026-11-02/raycast_*.html`）在发布日是否仍一致。
3. Raycast 当前 macOS 要求（第三方称 Raycast 2 需 macOS Tahoe + Apple silicon，**以 Raycast 官方为准**）与默认热键。
4. SpotAsk 与 Raycast 同时设 ⌥Space 时的表现（同 DEV-684 双 App 测法；测不了就写 "pick one owner"）。
5. SpotAsk v0.3.3 **不配任何 key** 时 External Ask → ChatGPT / Perplexity 是否打开并预填（与 N3 单共用结论）。
6. **ChatGPT 与 Claude 桌面版当前快捷键事实**（hub 表的 ChatGPT 行 + 本页 Using both 一节用）：新版 ChatGPT ⌥Space → Mini？Chat Bar 是否仍只在 Classic？Claude 桌面版默认快捷键（第三方 felloai 称"双击 Option"，需实测）。记 app 版本号 + 日期。
7. Raycast 侧把问题"甩给"ChatGPT 网页 / CLI 的现成方式（Quicklinks / 扩展），写实或写 "—"。

## 8. 内链
- 出：`/compare/`（面包屑 + 结尾）、`/guides/chatgpt-option-space#mini-took-space-from-another-app`（Using both）、`/use-cases/byok-macos-ai`（routing 节）、`/use-cases/privacy-architecture`（key 存储）、`/guides/external-ask`（hand-off 节）、`/troubleshooting#global-shortcut-conflicts`（Using both）、`/getting-started`（CTA）
- 入：`/compare/` hub（表头 + When Raycast）、⌥Space 页 Related、`use-cases/mac-ai-launcher.md`（一句 "How SpotAsk compares to Raycast AI"）、`use-cases/byok-macos-ai.md`（"BYOK in Raycast vs SpotAsk"）
- 外链：Raycast 手册 4 页（BYOK、Custom Providers、Privacy & Security、Billing），`rel` 正常（不 nofollow 官方来源）。

## 9. 不要写
- ❌ "Raycast sends everything through its servers"、"Raycast is not private"
- ❌ "SpotAsk replaces Raycast"
- ❌ "keys stored in Keychain"（N3 已证伪）
- ❌ 未复核的价格/系统要求/热键；任何搜索量数字
- ❌ 小号口吻或"we tested every app"之类夸张

## 10. 中文备注（给 Jim）
- 原来 board 里"Raycast BYOK 走它的服务器、SpotAsk 直连"这条差异**比我们以为的窄**：今天读 Raycast 手册，OpenRouter、Custom Providers（OpenAI 兼容 YAML）、本地 Ollama 都是直连。所以这页的卖点不能只押"隐私"，要押"只要快问 + 免费开源无账号 + 一键甩给网页 AI/CLI"，路由差异如实写成"默认三家走 Raycast，配置后可直连"。
- 要你定的只有：Title A 还是 B、Meta 1 还是 2；发布前看稿。
