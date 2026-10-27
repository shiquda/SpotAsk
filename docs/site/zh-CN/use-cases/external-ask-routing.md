---
title: External Ask 与智能路由
description: "在 SpotAsk 中写下问题，一键或通过智能路由分流至已配置的网页服务、本地终端工具或桌面应用。"
---

# External Ask 与智能路由：在统一窗口中分流至不同工具

SpotAsk 让提问流程更加自然：在统一的快捷悬浮窗口中写下问题，再发送到最适合解答的外部环境。

你可以手动点击目标渠道或使用快捷键快速发送；也可以配置并启用智能路由服务，在发送时由决策服务提供去向建议。

## 核心能力

- **支持多种外部去向**：支持携带问题直达网页搜索（如 Perplexity、ChatGPT）、执行终端命令（如本地 CLI Agent），或通过 URL 协议唤起 macOS 桌面应用。
- **提问窗口内快捷分发**：输入问题后，点击窗口内的渠道按钮或按下对应快捷键即可直接发送；输入框为空时，点击或按下快捷键可先预选目标渠道。
- **可选的智能路由建议**：可以配置并启用智能路由功能。发送问题时，SpotAsk 会向你配置的决策服务请求去向建议，默认由你确认后发送，也可设置为置信度高于阈值时自动放行。

## 3 步快速上手

1. **配置外部渠道**：打开 **设置 > 外部提问**，查看内置渠道或点击“新建”添加自定义网页链接、应用协议或终端命令。
2. **（可选）配置智能路由**：若希望获得去向建议，在下方“智能路由”中填写决策服务地址、模型与访问密钥，并开启总开关。
3. **呼出窗口并发送**：按全局快捷键呼出 SpotAsk，输入问题后点击渠道或按快捷键发送；若启用了智能路由，发送时确认推荐去向即可放行。

## 视觉演示

<video poster="/images/spotask-smart-routing-preview.gif" src="/videos/SpotAsk-smart-routing-v5.mp4" controls muted playsinline width="720"></video>

*视频：一个问题，三种去向——智能路由实机演示（28 秒）。[下载 / 观看高清视频 (1080p MP4)](/videos/SpotAsk-smart-routing-v5.mp4)*

![SpotAsk 一键唤起本地终端 CLI Agent](/images/spotask-external.gif)
*图 1：SpotAsk 将问题分流并注入终端本地运行的 CLI 工具。*

## 必要边界与使用说明

- **决策服务与响应时间**：智能路由功能内置于应用中，但决策模型需通过你配置的外部决策服务调用，并非随 App 内置或本机离线运行。请求耗时受网络和服务影响，系统提供可配置超时限制（默认 2 秒）。
- **数据传输与附件机制**：启用智能路由后，发送问题时会将问题正文发送至决策服务进行研判；含附件（如图片、文档）的问题不进入自动决策路由，改由当前配置的对话模型处理（若配置了远程对话模型，请求仍会发往对应服务商）。
- **外部环境依赖**：网页型渠道依赖目标网站在默认浏览器中的登录有效态；终端命令运行在当前用户的登录 Shell 环境中，目标命令需预先配置于系统的环境变量路径中。

## 立即下载 SpotAsk

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) 下载最新 DMG（支持 Apple Silicon 与 Intel），或使用 Homebrew 安装：

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### 相关指南

- [External Ask 外部提问指南](/zh-CN/guides/external-ask) — 自定义渠道语法、智能路由配置与常见问题。
- [macOS 全局 AI 启动器](/zh-CN/use-cases/mac-ai-launcher) — 快捷键呼出与全键盘交互。
- [BYOK 原生 macOS AI 客户端](/zh-CN/use-cases/byok-macos-ai) — 自带 API 密钥与按需用量计费。
- [全局划词 AI 助手](/zh-CN/use-cases/selection-assistant) — 跨软件划词就地处理。
