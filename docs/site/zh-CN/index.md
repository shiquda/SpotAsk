---
layout: home

title: SpotAsk
titleTemplate: "原生 macOS AI 助手与查询路由器"
description: "SpotAsk 是一款免费开源的 macOS 菜单栏 AI 助手与查询路由器。快捷键秒级呼出、随时提问——支持应用内 BYOK 极速回答，或一键将问题发给 ChatGPT、本地终端 Agent 等外部工具。"

hero:
  name: SpotAsk
  text: 文档
  tagline: "先提问，去向随心。原生 macOS 菜单栏 AI 助手与查询路由器。"
  actions:
    - theme: brand
      text: 快速开始
      link: /zh-CN/getting-started/
    - theme: alt
      text: 探索 SpotAsk
      link: /zh-CN/explore/

features:
  - title: "先提问，随心分流"
    details: "按快捷键秒级呼出窗口，写下问题并自由选择：直接应用内 BYOK 流式回答，或一键分发至网页端、桌面端应用及终端 Agent。"
  - title: "选中文本即刻处理"
    details: "在任意应用中选中文字，在就近操作条中一键翻译、解释、总结、润色，或执行自定义提示词。"
  - title: "自带密钥 (BYOK)，隐私留在本机"
    details: "直连 OpenAI 兼容或 Anthropic 服务。密钥保存在本机系统钥匙串中，无中间服务器，无遥测。"
  - title: "原生轻量，无 Electron"
    details: "安装包约 10 MB，纯 Swift 与 AppKit 构建，无 Electron 运行时，全键盘驱动（Esc 一键关闭），毫秒级冷启动。"
---

![SpotAsk 浅色与深色模式下的提问窗口，含提示词和外部提问入口](/images/spotask-chat.png)

## SpotAsk 是什么

SpotAsk 是一款免费开源的 macOS 菜单栏 AI 助手与查询路由器，建立在一个极简的前提之上：**“先提问，去向随心（Ask first. Decide where it goes after.）”**。

按一个快捷键——默认 `Option + Space`——一个专注的提问窗口就会浮现在当前屏幕之上。在灵感或疑问闪现的当下立刻捕获它，然后自由决定如何处理：

1. **应用内极速回答**：使用你配置的 AI 模型（BYOK）直接在当前小窗内获取快速流式解答。
2. **一键分流三大出口 (External Ask)**：一键将问题无损派发给网页端平台（ChatGPT、Perplexity、Grok）、桌面端应用（URI 协议）或终端中的本地 CLI Agent，不消耗 API Token，不残留多余对话历史。

没有账号体系，没有遥测，你和你的模型服务商之间没有任何中间商。按 `Esc` 关闭窗口即彻底结束——“问完就走”，零心智负担。

三个最常用的核心流程可以直接看下面的动图：快捷键流程从任意应用中快速呼出对话窗口；划词流程在选中文本就近显示操作条；外部提问（External Ask）支持一键唤起本地 CLI Agent 或外部工具。

![默认快捷键快速对话](/images/spotask-hotkey.gif)

![选中文字后显示快捷操作](/images/spotask-selection.gif)

![一键分流至终端 CLI Agent 与外部工具](/images/spotask-external.gif)

## 下一步

- [快速开始](/zh-CN/getting-started)介绍安装和第一次提问。
- [探索 SpotAsk](/zh-CN/explore)是应用能力地图。
- [故障排查](/zh-CN/troubleshooting)处理连接、模型、权限和快捷键问题。
