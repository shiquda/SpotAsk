---
title: 在 Mac 菜单栏应用中使用自己的 AI API 密钥 | SpotAsk
titleTemplate: false
description: 添加 OpenAI、Anthropic 或 Gemini API 密钥，测试连接，并通过 Mac 全局快捷键快速提问。免费开源，直连服务商，凭据仅存本机。
---

# BYOK Mac 菜单栏 AI 助手：连接自备模型与 API 密钥

SpotAsk 是专为桌面快问设计的免费开源 Mac 菜单栏 AI 助手，基于 Bring-Your-Own-Key（BYOK，自带密钥）架构打造。按下全局快捷键 <kbd>⌥ Space</kbd> 即可在任意屏幕即时呼出，完成极速问答、划词就近解释与提示词分流。你的 API 访问密钥保存在本机权限受限的凭据文件（`0600` 权限，仅当前系统用户可读写）中，不写入 macOS Keychain，也绝不同步至任何云端。网络请求从你的 Mac 直接发往所配置的服务商端点，无 SpotAsk 中转服务器、用户账号或后台遥测。软件本身完全免费，你只需向模型服务商按实际消耗的 Token 付费。

## 为什么在 Mac 菜单栏选择 BYOK？

多数商业 AI 桌面客户端按月收取固定订阅费（通常为每月 $20），或将请求经由专属代理转发，这不仅带来了服务溢价，还可能记录你的提示词。如果你已经在 OpenAI、OpenRouter、Anthropic、Google 或 DeepSeek 拥有开发者 API 密钥，或者在本地运行 Ollama 模型，仅为了在写代码或查资料时问一两句话而额外购买一套打包的聊天订阅往往是冗余的。

SpotAsk 将原生的 macOS 快捷交互界面与底层模型服务商解耦：
- **无订阅溢价与中转加价**：Token 费用严格按照模型服务商官方的开发者账单结算，按需付费。
- **端到端直接请求**：网络请求直接发送至目标服务商 API；若使用 Ollama 等本地大模型，请求完全留在本地回环接口（Loopback），不经过外网。
- **模型灵活切换**：在浮动提问窗口顶部的选择器中，即可在不同服务商（如 OpenAI、Anthropic、Gemini）与本地模型之间随心切换。

## 一分钟内验证你的首次回答

完成服务配置后，你可以在几十秒内验证连通性并获得首次模型回复。

以下时间线以保存服务并点击**测试连接**成功后为起点：按快捷键 <kbd>⌥ Space</kbd> 呼出窗口、选择模型、输入提示词到接收首个流式 Token。这一测算不包含注册服务商账号、充值账单或下载几十 GB 本地模型权重的一次性前置时间。

![SpotAsk 首次提问与流式回复演示](/images/spotask-byok-first-answer.gif)
*图 1：使用 deepseek-v4-flash 的完整快速提问流程：选择已配置模型、输入测试问题并接收流式回复。*

### 实测验证提示词与回复结果

为了保证可复现性与结果一致性，我们在已实测的配置中使用了一条输出结构简短、确定性强的测试提示词：

```text
Give me three concise names for a menu bar app that answers quick questions. Return one per line.
```

在连接 OpenAI 兼容服务端点使用 `deepseek-v4-flash` 时，SpotAsk 实测返回：

```text
QuickAsk QBar AnswerBar
```

- **实测首 Token 延迟**：点击发送后约 700 毫秒显示首字。
- **实测完整流式输出耗时**：约 2.5 秒。
- **返回原应用**：按 <kbd>Esc</kbd> 即可立刻关闭提问窗口，无缝回到原本的桌面工作流程中。

## 运行前提与环境要求

- **操作系统**：macOS 15.0（Sequoia）或更高版本。支持 Apple Silicon（`arm64`）与 Intel（`x86_64`）原生通用二进制架构。
- **服务商凭据或本地服务**：
  - 拥有已充值且额度充足的 API Key（支持 OpenAI 兼容端点、Anthropic 或 Google Gemini）；或者
  - Mac 本地已运行并下载好模型的模型运行器，如 Ollama（默认接口 `http://localhost:11434/v1`）或 LM Studio（`http://localhost:1234/v1`）。
- **网络连接**：能够直连所配置服务商 API 端点的外网出站权限；本地模型则需允许回环访问。如处在代理网络下，可在 **设置 > 通用** 中配置 HTTP 或 SOCKS5 代理。

## 复现配置：完整操作步骤

按照以下步骤即可配置一个 OpenAI 兼容服务（官方推荐的主线路径）并验证连接：

1. **打开服务设置**：启动 SpotAsk，按快捷键 <kbd>⌘ ,</kbd> 打开设置面板，在左侧导航选择 **服务**（或在浏览器/终端输入深层链接 `spotask://settings/provider` 直达）。
2. **添加服务**：点击列表下方的“添加服务”，将 **接口格式** 设为 **OpenAI**，并输入易于辨识的名称（如 `OpenRouter` 或 `OpenAI`）。
3. **填写服务地址与地址模式**：
   - **服务根地址（推荐）**：填入服务商的基础 API 根路径（例如 `https://openrouter.ai/api/v1` 或 `https://api.openai.com/v1`）。在此模式下，SpotAsk 会自动在对话时追加 `/chat/completions`，并在发现模型时请求 `/models`。
   - **完整请求地址**：填入完整的会话请求路径（例如 `https://openrouter.ai/api/v1/chat/completions`）。若服务商使用了非标路径时选择此项，该模式下无法自动拉取模型列表，需手动添加模型 ID。
4. **填入并保存访问密钥**：在 **访问密钥** 栏中粘贴 API Key，点击“保存”。密钥在界面中呈掩码显示，并在本地以 `0600` 权限保存于 `~/Library/Application Support/SpotAsk/credentials.json`。SpotAsk 不使用 Keychain，杜绝了自编译或未签名二进制因签名变更引发的系统弹窗卡顿。
5. **获取或填写模型 ID**：在服务根地址模式下，点击 **刷新模型** 即可发起 `GET /models` 请求自动列出模型，点选所需模型（如 `openai/gpt-4o-mini`）；若使用完整地址，则点击“添加模型”手动输入准确的上游 Model ID。
6. **测试连接**：关闭设置前，点击“测试连接”。SpotAsk 会发起一次轻量的非流式验证请求（ping）。界面显示绿色对勾即表示服务地址有效、网络通畅且密钥认证成功。若失败，通常原因包括：401/403（密钥错误或已失效）、404（地址拼接错误，如在根地址模式多填了 completions 路径，或模型名不存在）、429（服务商账户额度不足或达到频率上限）或网络超时。
7. **快捷呼出提问**：按全局快捷键 <kbd>⌥ Space</kbd>，在浮动窗口顶部确认选中所配置的模型，输入问题敲击回车，即可看到实时流式回答。按 <kbd>⌘ C</kbd> 拷贝回答，按 <kbd>Esc</kbd> 快速隐藏。

## 本地与兼容端点：支持矩阵

SpotAsk 原生内置了对 OpenAI 兼容格式、Anthropic Messages API 与 Google Gemini REST API 的支持。由于各第三方服务商与本地运行时对规范的实现程度不一，我们将支持情况明确区分为**已实测**、**文档支持**与**不支持**：

| 服务商 / 本地运行器 | 接口格式 | 默认地址规范 | 支持状态 | 实测特性与运行边界 |
| :--- | :--- | :--- | :--- | :--- |
| **OpenRouter** | OpenAI 兼容 | 根地址：`https://openrouter.ai/api/v1` | **已实测** | 完整验证流式 SSE 回复、模型自动发现（`GET /models`）、连接测试与跨模型路由。使用 `openai/gpt-4o-mini` 实测通过。 |
| **Google Gemini** | Gemini REST | 根地址：`https://generativelanguage.googleapis.com/v1beta` | **已实测** | 原生 `generateContent` 协议与 `x-goog-api-key` 头认证。实测模型发现支持 Gemini 2.5 Flash 与 Pro。 |
| **OpenAI 官方** | OpenAI 兼容 | 根地址：`https://api.openai.com/v1` | **文档支持** | 官方标准参考实现。需在 OpenAI 开发者后台预充值 API 余额。 |
| **Anthropic** | Anthropic Messages | 根地址：`https://api.anthropic.com/v1` | **文档支持** | 原生 Messages API，使用 `x-api-key` 与 `anthropic-version: 2023-06-01` 请求头。需账号额度正常。 |
| **Ollama** | OpenAI 兼容 | 根地址：`http://localhost:11434/v1` | **文档支持** | 仅允许本地回环地址（`localhost`、`127.0.0.1`）。SpotAsk 不代下载或分发模型权重，需提前在本地启动 Ollama 并拉取模型。会话不离机。 |
| **LM Studio** | OpenAI 兼容 | 根地址：`http://localhost:1234/v1` | **文档支持** | 需在本地开启服务并允许跨域与端点。密钥字段可填任意占位符。 |
| **非回环明文 HTTP 端点** | 任意格式 | `http://...`（远程明文） | **不支持** | SpotAsk 地址校验器主动拦截远程明文 HTTP 请求，防止凭据和提示词在公网明文泄漏。远程服务必须使用 HTTPS。 |

关于各接口协议的完整技术参数与配置细节，可参考 [服务商与模型指南](/zh-CN/guides/providers-and-models)。

## 费用边界与凭据去向

在使用自带密钥模式前，需要厘清以下三项核心事实：

- **软件免费不等于大模型调用免费**：SpotAsk 作为遵循 AGPL-3.0 协议的开源软件，本身不收取任何费用。但向 OpenAI、Anthropic、Google 等云端发起请求时，消耗的 Token 由服务商直接从你的开发者账户余额中扣除。日常快速提问每次消耗数百 Token，通常仅产生极微小的费用；若想完全免费推理，可连接本地运行的 Ollama。
- **网页版付费订阅不是 API 密钥**：每月 $20 的 ChatGPT Plus 或 Claude Pro 属于消费级网页产品会员，无法直接作为 API Key 填入。开发者 API 需要在对应平台（如 [OpenAI Platform](https://platform.openai.com) 或 [Anthropic Console](https://console.anthropic.com)）单独创建密钥与绑定支付方式。如果你希望免配置 Key 直接使用 ChatGPT 网页账号，可使用 SpotAsk 的 [External Ask 外部提问](/zh-CN/guides/external-ask) 一键带词跳转至浏览器。
- **凭据本地存储与网络去向**：API 密钥只保存在本地电脑的 `~/Library/Application Support/SpotAsk/credentials.json` 中，权限被严格锁死为 `0600`（仅限你的 macOS 用户账户读写）。当请求云端模型时，Key 随加密的 TLS 连接发往目标服务商认证；当连接本地模型时，请求和密钥全程留存在本地回环链路，完全不出机器。

如需查看本地文件存储结构与数据流向审计，请参阅 [本地优先与零遥测隐私设计](/zh-CN/use-cases/privacy-architecture)。

## 什么时候完整工作台更合适？

SpotAsk 的产品定位是快捷、低干扰的即时提问、划词处理与意图分流，而非包揽多轮重度项目管理的复杂工作台。

在以下场景中，官方的 ChatGPT / Claude 桌面客户端或网页端依然是更合适的工具：

- **持久的多轮长对话与历史检索**：需要在侧边栏分类管理复杂的历史项目、树状知识库或自定义 GPTs。
- **依赖官方云端专属功能**：需要使用服务商托管的云端记忆、Canvas 协作文档编辑，或原生实时语音模式（如 ChatGPT Advanced Voice Mode）。
- **更倾向于固定打包月费**：希望每月固定支付 $20 随心畅聊，不想关注 Token 消耗速率、余额预警与密钥轮换。
- **复杂的多窗口与多任务分屏**：需要全屏展示大型代码产物、复杂图表预览或并排多文档对照。

SpotAsk 与完整工作台属于互补关系：深度的方案推演留在独立工作台中，日常随时闪现的疑问、翻译与代码求证，则交给快捷键呼出的 SpotAsk 就地解决。你在“服务”中配置的模型同样无缝驱动 [全局划词翻译与改写助手](/zh-CN/use-cases/selection-assistant)，无需重复配置。你也可以参考 [SpotAsk 与 ChatGPT macOS 客户端对比（英文）](/compare/chatgpt-mac) 深入评估两种工作流。

## 立即下载 SpotAsk

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) 下载已签名的最新 DMG 安装包（支持 Apple Silicon 与 Intel），或通过 Homebrew 安装：

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### 相关指南

- [连接 OpenAI 兼容服务](/zh-CN/guides/connect-openai-compatible) — OpenAI、OpenRouter、DeepSeek 与 Groq 配置。
- [全局划词 AI 助手工作流](/zh-CN/use-cases/selection-assistant) — 使用自备模型就地翻译与改写选中文本。
- [连接 Anthropic](/zh-CN/guides/connect-anthropic) — Claude API 密钥与流式对话配置。
- [服务根地址与完整请求地址](/zh-CN/guides/service-addresses) — 掌握不同平台 URL 拼接规范。
- [本地优先与零遥测隐私设计](/zh-CN/use-cases/privacy-architecture) — 凭据存储与数据去向说明。
- [SpotAsk 与 ChatGPT Mac 客户端对比（英文）](/compare/chatgpt-mac) — 菜单栏 BYOK 工具与官方桌面客户端的区别。
- [External Ask 外部提问指南](/zh-CN/guides/external-ask) — 免 API Key 分流至浏览器 AI 或终端 Agent。
