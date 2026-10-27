---
title: 智能路由
description: 了解 SpotAsk 智能路由机制，配置 TypeSafe、OpenRouter 与 OpenAI Decisions 决策引擎，实现按提问意图自动分流。
---

# 智能路由

开启智能路由后，无需手动挑选外部渠道或在多个 AI 工具之间来回切换。

在提问小窗中敲下回车时，SpotAsk 会将问题交由轻量决策模型（分类器）即时研判意图，判断应当留在应用内由当前模型直接作答，还是分发至最合适的外部平台（如 ChatGPT、Perplexity、本地终端 Agent 等）。

智能路由仅负责去向决策，**不改变应用内对话的生成模型，也不会将对话历史记录在本地日志中**。

<SpotAskSettingsLink section="external-ask" />

---

## 视频演示

<video poster="/images/spotask-smart-routing-preview.gif" src="/videos/SpotAsk-smart-routing-v5.mp4" controls muted playsinline width="720"></video>

*视频：一个问题，三种去向——智能路由实机演示（28 秒）：应用内回答、网页自动跳转提示与本地 Agent 确认卡片。[下载 / 观看高清视频 (1080p MP4)](/videos/SpotAsk-smart-routing-v5.mp4)*

---

## 快速配置

进入 **设置 > 外部提问 > 智能路由**，开启总开关，并选择决策引擎。SpotAsk 支持 **System One (jev)** 与 **OpenAI Decisions** 两套决策协议，并各自独立保存服务地址、模型与 API 密钥，切换引擎不会互相覆盖。

填写连接参数后，点击下方 **测试提问** 即可直接在设置中验证连通性与推荐效果。

### 方案 A：TypeSafe 官方（推荐）

地址与模型已默认预填，填入 TypeSafe API 密钥即可开箱即用：

| 配置项 | 推荐值 | 说明 |
| :--- | :--- | :--- |
| **服务地址** | `https://api.typesafe.ai` | 官方决策接口地址 |
| **决策模型** | `jev-1.13.0` | 专为意图分类优化的 System One 决策模型 |
| **访问密钥** | 你的 TypeSafe API Key | 必填，未填时不发起远程请求 |

### 方案 B：OpenRouter

使用 OpenRouter 托管的 System One 分类模型：

| 配置项 | 推荐值 | 说明 |
| :--- | :--- | :--- |
| **服务地址** | `https://openrouter.ai/api` | SpotAsk 会自动补全 `/v1/systemone` 接口路径 |
| **决策模型** | `typesafe/jev-1.13` | 可填 `typesafe/jev-1.13`（固定版本）或 `~typesafe/jev-latest` |
| **访问密钥** | 你的 OpenRouter API Key | 使用 OpenRouter 平台密钥，按用量计费 |

::: tip OpenRouter 地址说明
只需填入基准地址 `https://openrouter.ai/api`，不要粘贴完整或聊天补全接口（`/chat/completions`）。
:::

### 方案 C：OpenAI Decisions

在分段选择器中切换至 **OpenAI Decisions**。此方案调用 [OpenAI Decisions API](https://developers.openai.com/api/docs/guides/decisions)（`POST /v1/decisions`），由 OpenAI 托管的分类模型提供研判：

| 配置项 | 推荐值 | 说明 |
| :--- | :--- | :--- |
| **服务地址** | `https://api.openai.com` | 支持自定义兼容网关，路径始终走 `/v1/decisions` |
| **决策模型** | `gpt-6-luna` | OpenAI Decisions 专用轻量研判模型 |
| **访问密钥** | 你的 OpenAI API Key | 官方地址必填；第三方兼容地址可选 |

::: warning 接口类型区别
OpenAI Decisions 不是普通的聊天接口，OpenAI 官方也不提供 `jev` / System One 模型。请勿将普通 Chat 补全链接填入此处。
:::

---

## 交互体验与快捷操作

### 内联确认卡片

在提问输入框中敲下回车后，输入框上方会弹出内联推荐卡片，展示推荐去向与研判置信度：

- 按 <kbd>↩</kbd>：立即按照推荐去向放行发送；
- 按 <kbd>Tab</kbd> 或方向键：快速在候选渠道之间切换高亮；
- 按 <kbd>Esc</kbd>：取消当前路由并保留输入框中的草稿。

### 阈值自动放行

在设置中开启“高于阈值自动放行”并设定置信度阈值：

- **命中应用内**：置信度高于阈值时直接在 SpotAsk 内生成回答；
- **命中外部渠道**：展示 0.8 秒轻量提示倒计时（期间可按回车立即发送，或按 <kbd>Esc</kbd> 随时取消），倒计时结束后自动跳转外部平台。

### 当前对话一键暂停

窗口标题栏右侧提供智能路由快捷开关（默认快捷键 <kbd>⌘ + ⇧ + R</kbd>）。

当需要连续在应用内专注问答时，可临时暂停当前会话的自动路由；新建对话会自动恢复默认状态。如需隐藏标题栏图标，可在设置中关闭对应选项。

### 渠道语义微调

智能路由在研判时会将已启用的渠道名称提供给决策模型。你还可以在 **设置 > 外部提问** 中编辑具体渠道：

- **渠道用途与适用场景**：补充该渠道适合处理哪些问题（例如“擅长处理最新科技新闻搜索”或“本地代码生成与 Git 操作”），显著提升分类模型的匹配准确度；
- **始终先确认**：针对高危或需要人工把关的渠道（如执行特定终端脚本），开启后即使置信度高于阈值也会强行弹出卡片等待确认。

---

## 安全边界与容灾机制

- **强制 HTTPS 加密**：远程决策服务必须采用 HTTPS 协议（仅本地回环调试 `localhost` / `127.0.0.1` 允许 HTTP）。系统严禁跨域及 HTTPS 至 HTTP 的重定向，在发送问题文本前即刻拦截非法重定向。
- **附件自动降级**：当问题中包含图片、文档等附件时，系统会自动跳过外部智能路由，将问题留在应用内，绝不向第三方决策服务上传你的本地附件。
- **草稿变更静默撤销**：在等待决策或 0.8 秒倒计时期间，只要修改输入框文本、调整附件或切换预设，正在进行的推荐就会被静默撤销，绝不误触跳转。
- **超时保护与降级**：默认决策超时为 2 秒（可设置 0.5 ~ 5 秒）。当决策服务超时或网络异常时，系统自动降级为手动选择或保留在应用内，不会阻塞主窗口。

![智能路由设置与实时测试路由](/images/spotask-decision-routing-settings.png)

---

## 常见问题

**智能路由会额外消耗很多模型费用吗？**  
不会。决策模型（如 `jev-1.13.0` 或 `gpt-6-luna`）是专门用于分类研判的极轻量模型，每次研判通常仅消耗几十个 Token，费用与延迟远低于常规对话大模型。

**我的问题内容会被记录或训练吗？**  
SpotAsk 本身零遥测，不记录任何用户数据。开启智能路由后，仅在敲下回车时将单次问题的文本与候选渠道名称发送给指定的决策端点。官方推荐的 TypeSafe 与 OpenAI 商业 API 均遵循不将 API 数据用于模型训练的企业隐私条款。

**为什么测试提问提示失败？**  
请检查：
1. 外部提问总开关与智能路由总开关是否均已开启；
2. 是否至少启用了除“应用内作答”之外的一个有效外部渠道；
3. API Key 是否有效且账户有可用余额；
4. 服务地址格式是否正确，避免粘贴带有 `/chat/completions` 的链接。

---

相关指南：[外部提问](/zh-CN/guides/external-ask) · [External Ask 智能路由场景专题](/zh-CN/use-cases/external-ask-routing) · [设置与快捷键参考](/zh-CN/reference) · [隐私与本地数据](/zh-CN/privacy)
