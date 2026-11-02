---
layout: home

title: "SpotAsk｜Mac 菜单栏快问 · ⌥Space"
titleTemplate: false
description: "免费开源的 Mac 菜单栏快问工具：按 ⌥Space，用你自己的 API Key 得到回答，或处理选中文字，或一键交给 ChatGPT、本地 AI Agent。"

hero:
  name: SpotAsk
  text: 先提问，再决定去向
  tagline: '<span class="nowrap">一次提问，三个去向。</span><br class="hidden sm:inline"><span class="nowrap">随时唤起，随问随走。</span>'
  actions:
    - theme: brand
      text: 下载 Apple Silicon 版
      link: https://github.com/shiquda/SpotAsk/releases/latest
    - theme: alt
      text: 下载 Intel 版
      link: https://github.com/shiquda/SpotAsk/releases/latest
    - theme: alt
      text: 快速开始
      link: /zh-CN/getting-started

# Left info rendered by SpotAskHeroCompat; right terminal card rendered by
# SpotAskHeroInstall in #home-hero-image (see docs/site/.vitepress/theme/Layout.vue).
heroInstall:
  compat: "macOS 15+ · Apple Silicon / Intel · Native Swift"

features:
  - title: "先提问，随心分流"
    details: "随时按快捷键唤出窗口，敲下问题：支持应用内 BYOK 流式解答，也可一键或由决策模型自动分流至网页端、桌面端与终端 Agent。"
  - title: "选中文本就近处理"
    details: "在任意应用中选中文字，通过就近浮动操作栏直接翻译、解释、总结、润色，或带入对话继续追问。"
  - title: "自带密钥 (BYOK)，数据留在本机"
    details: "密钥只留在这台 Mac 上，只发给你的服务商——没有中间服务器，也没有遥测。"
  - title: "纯原生轻量，无 Electron"
    details: "纯 Swift 与 AppKit 构建，零 Electron 运行时；全键盘驱动，按 <kbd>Esc</kbd> 随问随走，极致克制。"

# Rendered below the hero install block by SpotAskHeroShowcase.
heroShowcase:
  src: /images/spotask-hero-zh.png
  alt: "SpotAsk — 一次提问，分流至应用内回答、网页 AI 或本地 Agent"
---

## SpotAsk 是什么

<span class="nowrap">SpotAsk</span> 是一款免费开源的 macOS 菜单栏 AI 助手与分流工具，建立在一个极简的前提之上：**“先提问，再决定去向（Ask first. Decide where it goes after.）”**。

随时按快捷键（默认 <kbd>⌥ + Space</kbd>），专注的提问小窗即刻浮现。先写下当下的问题，再决定如何处理：

- **应用内流式回答（BYOK）**：用你配置的 AI 模型直接在小窗内作答。
- **外部提问智能分流 (<span class="nowrap">External Ask</span>)**：把问题交给网页平台（ChatGPT、Perplexity、Grok）、桌面应用或本地终端 CLI Agent——一键直达，或由决策模型自动选路。

没有账号系统，没有遥测监控。按 <kbd>Esc</kbd> 随问随走。

## 下一步

- [快速开始](/zh-CN/getting-started)：安装 SpotAsk、连接 AI 服务并完成第一次提问。
- [探索 SpotAsk](/zh-CN/explore)：提问、划词、分流、模型、附件、提示词与快捷键的能力地图。
- [指南](/zh-CN/guides/connect-openai-compatible)：先配置服务，再按功能查阅使用指南与场景专题。
- [故障排查](/zh-CN/troubleshooting)：处理连接、模型、权限和快捷键问题。
