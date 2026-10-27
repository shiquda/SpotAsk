---
title: 本地优先与零遥测隐私架构
description: "SpotAsk 采用本地优先架构。无用户账号体系，无中转代理服务器，零商业遥测，凭据保存在本机文件中。"
---

# 本地优先与零遥测：数据去向与隐私设计

SpotAsk 从项目立项的第一天起，就采用本地优先（Local-First）与零遥测（Zero-Telemetry）设计。

整个客户端没有用户注册、登录或商业许可激活机制；完全没有搭建任何形式的私有云端中间代理服务器；二进制代码中不包含第三方商业分析追踪 SDK。

代码 100% 遵循 GNU AGPL-3.0 许可协议在 GitHub 公开源代码，随时接受全球开发者的独立安全与隐私审计。

## 数据去向明细

| 数据类型 | 保存位置与网络去向 | 访问机制与控制方式 |
| :--- | :--- | :--- |
| **API 访问密钥** | 本机凭据文件 (`credentials.json`) | 文件访问权限限制为当前用户（`0600`；当前实现不使用 Keychain）；在设置中可随时修改或删除 |
| **提问文本与附件** | 直连你配置的服务商官方端点（或本地回环） | 仅在主动提问时建立 HTTPS 连接；远程服务商的数据处理方式以其自身政策为准；使用本地 Ollama 时数据留在本机 |
| **智能路由问题文本** | 你配置的外部决策服务端点（默认关闭） | 仅在启用智能路由并发送问题时请求建议；含附件的问题自动绕过决策路由，改由对话模型处理 |
| **本地偏好与对话缓存** | 本机沙盒目录 (`~/Library/Application Support/SpotAsk/`) | 仅供本地界面展示与历史回溯，不向任何云端服务同步；可在设置中随时一键清空 |
| **版本更新检查** | 官方 GitHub Releases API（可彻底关闭） | 启动时单次请求对比版本号；不包含任何提问正文、设备指纹或访问密钥；可在“关于”中随时关闭 |

## 3 步快速上手与自主验证

1. **流量抓包审计**：安装 SpotAsk 后，打开任意网络流量监测工具（如 Little Snitch 或 Proxyman）。你会观察到应用在未发起提问时没有任何后台上报连接。
2. **配置直连密钥或离线本地模型**：在 **设置 > 服务** 中输入你自己的 API 密钥，或填入本地 Ollama 地址实现断网环境下的完全本地运行。
3. **一键清除本地数据**：在 **设置 > 通用** 中点击“清除所有本地数据”，可清除本机存储的凭据文件、设置与本地对话缓存。

## 必要边界与使用说明

- **第三方服务商政策**：虽然 SpotAsk 本身不收集、不中转任何数据，但你配置的外部服务商（如 OpenAI、Anthropic 或 Google）会根据其各自的开发者数据协议处理你的请求。如需实现物理级数据隔离，建议配合本地运行的 Ollama 模型使用。
- **智能路由决策端点边界**：当在外部提问中启用决策模型自动路由时，问题文本与已启用的渠道名称会通过 HTTPS 发送至你配置的决策端点（如 TypeSafe 或 OpenRouter）进行分类。决策请求强制采用 HTTPS 连接。
- **开源代码与独立审计**：SpotAsk 代码完全公开于 GitHub，使用标准 Swift 与 AppKit 开发，任何人均可自由审查其网络请求与本地文件读写逻辑。

## 立即下载 SpotAsk

体验自主可控、零遥测的原生 macOS AI 助手。

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) 下载最新 DMG（支持 Apple Silicon 与 Intel），或使用 Homebrew 安装：

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### 相关指南

- [隐私与本地数据官方说明](/zh-CN/privacy) — 本地存储路径、数据清理与日志诊断详尽拆解。
- [BYOK 原生 macOS AI 客户端](/zh-CN/use-cases/byok-macos-ai) — 自带 API 密钥与按需用量计费。
- [macOS 全局 AI 启动器](/zh-CN/use-cases/mac-ai-launcher) — 快捷键极速呼出与全键盘交互。
- [能力地图](/zh-CN/explore) — 全面掌握 SpotAsk 的系统级能力。
