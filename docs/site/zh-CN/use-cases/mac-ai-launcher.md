---
title: macOS 全局 AI 启动器
description: "SpotAsk 是基于原生 Swift 与 AppKit 构建的轻量 macOS AI 启动器。全局快捷键瞬时呼出，支持快捷键复制与灵活收起，不占 Dock 栏。"
---

# macOS 全局 AI 启动器：快捷呼出与用完即走

SpotAsk 是专为高频、轻量提问打造的原生 macOS AI 启动器。

按下全局快捷键即可在当前工作区上方呼出提问窗口，输入问题实时流式展示回答，完成后快捷收起，不打断手头工作。

## 核心能力

- **全局快捷键即时呼出**：默认全局快捷键 <kbd>⌥ + Space</kbd>，跨全屏应用、IDE 或浏览器浮现，无需桌面滑动切换。
- **菜单栏静默驻留**：作为 macOS 系统辅助应用运行，常驻菜单栏，不占用 Dock 栏空间。
- **快捷键盘交互与收起**：支持通过快捷键复制回答（默认专用快捷键为 <kbd>⌘ + ⇧ + C</kbd>）；完成后可收起窗口，<kbd>Esc</kbd> 的具体行为取决于当前状态与设置（例如停止流式生成、收起候选面板或关闭窗口）。

## 3 步快速上手

1. **确认快捷键**：启动 SpotAsk，在 **设置 > 快捷键** 中确认默认唤醒组合键（<kbd>⌥ + Space</kbd>），亦可点击录制框更换为你顺手的按键。
2. **配置模型服务**：进入 **设置 > 服务**，配置你的 API 服务商与模型信息，并通过“测试连接”验证。
3. **呼出并提问**：在任意界面按下唤醒快捷键，输入问题后按回车查看流式解答。

## 视觉演示

![默认快捷键快速对话](/images/spotask-hotkey.gif)
*图 1：使用全局快捷键在当前界面上方呼出浮动窗口提问。*

## 必要边界与使用说明

- **系统版本要求**：SpotAsk 基于现代 Swift 与 AppKit 构建，需要 macOS 15.0 (Sequoia) 或更高版本。
- **快捷键占用冲突**：若系统中有其他第三方工具占用了 <kbd>⌥ + Space</kbd>，SpotAsk 会给出提示，建议在设置中指定无冲突的组合键。
- **系统安全输入保护**：在 macOS 密码输入框或安全终端环境下，系统级安全机制（Secure Input）会自动保护键盘输入，全局快捷键捕获可能被临时挂起。

## 立即下载 SpotAsk

从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases/latest) 下载最新 DMG（支持 Apple Silicon 与 Intel），或使用 Homebrew 安装：

```sh
brew tap shiquda/spotask https://github.com/shiquda/SpotAsk
brew install --cask shiquda/spotask/spotask
```

### 相关指南

- [BYOK 原生 macOS AI 客户端](/zh-CN/use-cases/byok-macos-ai) — 自带 API 密钥与按需用量计费。
- [External Ask 智能路由](/zh-CN/use-cases/external-ask-routing) — 分流至网页服务或本地命令行工具。
- [全局划词 AI 助手](/zh-CN/use-cases/selection-assistant) — 划词就地翻译与润色。
- [快捷键一览与自定义](/zh-CN/reference) — 深入了解全局与窗口内按键配置。
