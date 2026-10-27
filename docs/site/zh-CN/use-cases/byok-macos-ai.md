---
title: BYOK 原生 macOS AI 客户端
description: "SpotAsk 是原生 BYOK（自带 API Key）macOS AI 客户端。直连 OpenAI、Anthropic、Gemini、DeepSeek 及本地 Ollama，无中转后端，凭据保存在本机文件中。"
---

# BYOK 原生 macOS AI 客户端：连接你自备的模型与 API 密钥

SpotAsk 采用 Bring-Your-Own-Key（BYOK，自带密钥）模式，直接连接你自己的 API 密钥或本地运行的大模型。

网络请求直达服务商官方端点，中间没有代理服务器，不设用户账号体系，费用由所选服务商和实际用量决定。

## 核心能力

- **多服务商与主流协议兼容**：原生支持 OpenAI 兼容格式、Anthropic Messages API 与 Google Gemini REST API，可在会话中通过顶部模型选择器随心切换。
- **端到端直接通信与本地凭据存储**：网络请求直接发往服务商端点，无 SpotAsk 中间中转层。API 访问密钥保存在本机凭据文件中，文件访问权限限制为当前用户（0600）；当前实现不使用 Keychain。
- **本地离线大模型支持**：原生支持连接运行在本机的 Ollama 或 LM Studio 回环接口，离线状态下可在本地完成任务处理。

## 3 步快速上手

1. **打开服务设置**：启动 SpotAsk，按 <kbd>⌘ + ,</kbd> 打开设置面板，点击 **服务** 标签页。
2. **配置服务商与密钥**：点击“添加服务”选择接口格式，输入服务地址、API 访问密钥与模型 ID，点击“测试连接”验证通信。
3. **选择模型并提问**：按全局快捷键呼出 SpotAsk，在顶部模型选择器中选定所需服务后即可开始提问。

## 视觉演示

![SpotAsk 对话窗口与模型选择器](/images/spotask-chat.png)
*图 1：SpotAsk 浮动对话窗口支持在已配置的 BYOK 服务商与模型之间随时切换。*

## 必要边界与使用说明

- **需自行准备模型服务商账号**：SpotAsk 作为客户端不贩售也不代充 API 额度。你需要自行在 OpenAI、Anthropic、Google 申请 API Key，或在 Mac 本地安装 Ollama。
- **费用与服务商配额**：使用远程 API 产生的费用由你直接向模型服务商按实际 Token 用量结算；请求限频（RPM/TPM）由服务商账户等级决定，客户端不加设调用限制。
- **服务地址格式要求**：OpenAI 兼容服务区分为“服务根地址”（如 `https://api.openai.com/v1`）与“完整请求地址”（如 `https://api.openai.com/v1/chat/completions`），配置时需注意区分。

## 立即下载 SpotAsk

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) 下载最新 DMG（支持 Apple Silicon 与 Intel），或使用 Homebrew 安装：

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### 相关指南

- [连接 OpenAI 兼容服务](/zh-CN/guides/connect-openai-compatible) — OpenAI、DeepSeek 与 Groq 配置。
- [连接 Anthropic](/zh-CN/guides/connect-anthropic) — Claude API 密钥与流式对话配置。
- [服务根地址与完整请求地址](/zh-CN/guides/service-addresses) — 掌握不同平台 URL 拼接规范。
- [本地优先与零遥测隐私设计](/zh-CN/use-cases/privacy-architecture) — 凭据存储与数据去向说明。
