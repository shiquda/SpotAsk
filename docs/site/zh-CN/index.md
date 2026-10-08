---
layout: home

title: SpotAsk
titleTemplate: "原生 macOS AI 助手与查询路由器"
description: "SpotAsk 是一款免费开源的 macOS 菜单栏 AI 助手与分流工具。快捷键随时呼出，即问即走——支持应用内 BYOK 快速流式解答，或一键将问题分发至 ChatGPT、本地终端 Agent 等外部工具。"

hero:
  name: SpotAsk
  text: 先提问，再决定去向
  tagline: '<span class="nowrap">一次提问，三个去向。</span><br class="hidden sm:inline"><span class="nowrap">随时唤起，随问随走。</span>'
  actions:
    - theme: brand
      text: 快速开始
      link: /zh-CN/getting-started/
    - theme: alt
      text: 探索 SpotAsk
      link: /zh-CN/explore/

features:
  - title: "先提问，随心分流"
    details: "随时按快捷键唤出窗口，敲下问题并自由选择：应用内流式解答，或一键分发至网页端、桌面端与终端 Agent。"
  - title: "选中文本就近处理"
    details: "在任意应用中选中文字，通过就近浮动操作栏直接翻译、解释、总结、润色，或带入对话继续追问。"
  - title: "自带密钥 (BYOK)，数据留在本机"
    details: "直连 OpenAI 兼容或 Anthropic 接口。密钥加密保存在本地钥匙串，无中间服务器，无隐私收集。"
  - title: "纯原生轻量，无 Electron"
    details: "纯 Swift 与 AppKit 构建，安装包仅约 10 MB；全键盘驱动，按 <kbd>Esc</kbd> 随问随走，极致克制。"

# Rendered between the hero actions and the feature cards by SpotAskHeroShowcase.
heroShowcase:
  src: /images/spotask-hero-zh.png
  alt: "SpotAsk — 一次提问，分流至应用内回答、网页 AI 或本地 Agent"
---

## SpotAsk 是什么

<span class="nowrap">SpotAsk</span> 是一款免费开源的 macOS 菜单栏 AI 助手与分流工具，建立在一个极简的前提之上：**“先提问，再决定去向（Ask first. Decide where it goes after.）”**。

随时按快捷键（默认 <kbd>⌥ + Space</kbd>），专注的提问小窗即刻浮现于屏幕之上。在灵感或疑问闪现的当下先写下问题，再决定如何处理：

- **应用内流式回答**：使用你配置的 AI 模型（BYOK）直接在小窗内快速作答。
- **外部提问一键分流 (<span class="nowrap">External Ask</span>)**：将问题直派给网页平台（ChatGPT、Perplexity、Grok）、本地终端 CLI Agent 或桌面应用，不消耗 API 额度，不留多余历史记录。

没有账号系统，没有多余中转，没有遥测监控。按 <kbd>Esc</kbd> 随问随走，彻底告别沉重的工作流。

### 核心工作流一览

#### 1. 快捷呼出，即问即走
![默认快捷键快速对话](/images/spotask-hotkey.gif)

#### 2. 全局划词，就近处理
![选中文字后显示快捷操作](/images/spotask-selection.gif)

#### 3. 外部路由，多向分流
![一键分流至终端 CLI Agent 与外部工具](/images/spotask-external.gif)
## 下一步

- [快速开始](/zh-CN/getting-started)介绍安装和第一次提问。
- [探索 SpotAsk](/zh-CN/explore) 是应用能力地图。
- [故障排查](/zh-CN/troubleshooting)处理连接、模型、权限和快捷键问题。
