---
title: 快速开始
description: 安装 SpotAsk、连接 AI 服务并完成第一次提问。
---

# 快速开始

SpotAsk 是原生 macOS 菜单栏应用。你可以**无需 API Key** 直接通过浏览器/CLI 外部提问上手，也可以接入自己的 API Key 或本地模型在弹窗内流式作答：

1. 按 <kbd>⌥ + Space</kbd>（或你配置的快捷键）打开提问窗口。
2. 输入问题。
3. 直接点击 **Ask ChatGPT**（或 Perplexity、Grok、本地 CLI Agent）在浏览器或终端中继续——无需配置 API Key；或者在配置好服务后按 <kbd>↩</kbd> 在弹窗内获取流式回答。
4. 按 <kbd>Esc</kbd> 关闭窗口，回到原来的任务。

## 环境要求

- macOS 15 或更高版本（支持 Apple silicon `arm64` 与 Intel `x86_64`）
- **以下任一方式即可开始**（不强制先准备 API Key）：
  - **无 API Key 直接上手（External Ask）**：浏览器中已有登录会话（如免费的 ChatGPT 或 ChatGPT Plus 网页登录）或本地 CLI 工具即可接收提问交接。*（注：ChatGPT Plus / Pro 等消费级订阅不包含开发者 API 额度，无法直接用于 SpotAsk 弹窗内流式 API 调用。）*
  - **弹窗内流式回答（可选 BYOK 或本地模型）**：提供 OpenAI 兼容、Anthropic 或 Gemini 聊天 API 的服务账户与访问密钥，或本机运行的 Ollama（`http://localhost:11434/v1`）等本地模型服务。

## 安装 SpotAsk

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) 下载对应架构的 `v0.3.4` 安装包：

- **Apple silicon**：[`SpotAsk-0.3.4-arm64.dmg`](https://github.com/shiquda/SpotAsk/releases/download/v0.3.4/SpotAsk-0.3.4-arm64.dmg)
- **Intel**：[`SpotAsk-0.3.4-x86_64.dmg`](https://github.com/shiquda/SpotAsk/releases/download/v0.3.4/SpotAsk-0.3.4-x86_64.dmg)

打开 DMG 并将 SpotAsk 移到“应用程序”。官方发布版本已使用 Apple Developer ID 签名并通过公证。启动后 SpotAsk 只显示在菜单栏。

也可以使用 Homebrew 安装：

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

## 方式一：无需 API Key 直接使用（External Ask 外部提问）

如果暂不想申请或充值开发者 API Key，可以直接使用浏览器或终端交接模式：

1. 点击菜单栏图标或按 <kbd>⌥ + Space</kbd>。
2. 输入你的问题。
3. 点击 **Ask ChatGPT**（或 **Ask Perplexity** / **Ask Grok**，或按 **设置 > 快捷键** 中分配的对应快捷键）。

SpotAsk 会用默认浏览器打开 `chatgpt.com` 并预填好问题，直接复用你当前浏览器已登录的网页会话，无需 API Key，也不消耗 API Token。更多自定义网页目标与本地 CLI Agent 用法见[外部提问](/zh-CN/guides/external-ask)。

## 方式二：连接你的 AI 服务获取弹窗内流式回答（BYOK）

如需在 SpotAsk 小窗内直接流式作答，从菜单栏打开设置（或按 <kbd>⌘ + ,</kbd>），进入“服务”：

1. 添加或选择一个服务。
2. 选择“接口格式”：**OpenAI**、**Anthropic** 或 **Gemini**。
3. 输入服务地址（连接本地 Ollama 可填 `http://localhost:11434/v1`）。
4. 选择“地址类型”：**服务根地址**或**完整请求地址**。
5. 输入并保存访问密钥（保存在本机 `~/Library/Application Support/SpotAsk/credentials.json`，文件权限为 `0600`；当前实现不使用钥匙串）。
6. 添加或选择服务商要求的模型 ID。
7. 点击“测试连接”。

测试成功后，关闭设置即可在提问窗口按 <kbd>↩</kbd> 获取流式回答。连接失败大多是地址、密钥或模型 ID 配置问题；请参考[故障排查](/zh-CN/troubleshooting)。

<SpotAskSettingsLink section="provider" />

## 第一次提问

点击菜单栏图标或按 <kbd>⌥ + Space</kbd>，输入问题后选择发送方式：

- **无 API Key**：点击 **Ask ChatGPT** 等外部提问按钮，在浏览器或终端中继续。
- **已配置 BYOK 或本地模型**：按 <kbd>↩</kbd> 在弹窗内实时查看流式回答。你可以：
  - 点击回答或代码块上的“复制”。
  - 按 <kbd>Esc</kbd> 停止生成或关闭窗口。
  - 按 <kbd>⌘ + N</kbd> 开始新对话。

## 继续探索

- [探索 SpotAsk](/zh-CN/explore) 展示应用还能做什么。
- [服务根地址与完整请求地址](/zh-CN/guides/service-addresses)说明该选哪种地址类型。
- [连接 OpenAI 兼容服务](/zh-CN/guides/connect-openai-compatible)详细介绍服务配置。
- [隐私与本地数据](/zh-CN/privacy)说明密钥、对话和选中文字的保存方式。
