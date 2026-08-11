---
title: 快速开始
description: 安装 SpotAsk、连接 AI 服务并完成第一次提问。
---

# 快速开始

SpotAsk 是原生 macOS 菜单栏应用。连接 AI 服务后，最短使用流程是：

1. 按 `⌥ + Space`（或你配置的快捷键）打开提问窗口。
2. 输入问题。
3. 复制回答，或按 `⎋` 关闭窗口，回到原来的任务。

## 环境要求

- macOS 15 或更高版本
- 一个提供 OpenAI 兼容或 Anthropic 聊天 API 的服务账户和访问密钥

## 安装 SpotAsk

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases) 下载匹配的软件包：

- Apple silicon Mac 使用名称带 `arm64` 的 DMG。
- Intel Mac 使用名称带 `x86_64` 的 DMG。

打开 DMG 并将 SpotAsk 移到“应用程序”。官方发布版本已使用 Apple Developer ID 签名并通过公证。启动后 SpotAsk 只显示在菜单栏。

## 连接你的 AI 服务

从菜单栏打开设置（或按 `⌘ + ,`），进入“服务”。

1. 添加或选择一个服务。
2. 选择“接口格式”：**OpenAI 兼容**或 **Anthropic**。
3. 输入服务地址。
4. 选择“地址类型”：**服务根地址**或**完整请求地址**。
5. 输入并保存访问密钥。
6. 添加或选择服务商要求的模型 ID。
7. 点击“测试连接”。

测试成功后，关闭设置并开始提问。连接失败大多是地址、密钥或模型 ID 配置问题；请参考[故障排查](/zh-CN/troubleshooting)。

## 第一次提问

点击菜单栏图标或按 `⌥ + Space`，输入问题后按 `↩`。

服务支持时，回答会实时显示。你可以：

- 点击回答或代码块上的“复制”。
- 按 `⎋` 停止生成。
- 按 `⌘ + N` 开始新对话。

## 继续探索

- [探索 SpotAsk](/zh-CN/explore)展示应用还能做什么。
- [连接 OpenAI 兼容服务](/zh-CN/guides/connect-openai-compatible)详细介绍服务配置。
- [隐私与本地数据](/zh-CN/privacy)说明密钥、对话和选中文字的保存方式。
