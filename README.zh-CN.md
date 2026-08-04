# SpotAsk

一款专注的 AI 对话工具，常驻 macOS 菜单栏。接入兼容服务后，随时开始提问。

[English](README.md)

![SpotAsk 展示聊天输入区与内置快捷操作](images/spotask-chat.png)

## 主要功能

- **随时随地提问** — 按 Option + Space 呼出专注的对话窗口，即开即用。
- **接入自己的服务** — 连接兼容 OpenAI Chat Completions API 的服务。服务地址、模型和访问密钥由你掌控。
- **实时显示回答** — 回答会逐步显示；可以停止回答、重试失败的请求，或重新生成最近一次回答。
- **按需复制内容** — 一键复制完整回答，也可以单独复制代码块。
- **常用任务一键完成** — 内置翻译、解释、总结、润色四组提示词，也可以创建自己的提示词用于重复工作。
- **融入 macOS 系统** — 通过 Spotlight、Siri 和快捷指令直接提问、开始新对话或执行提示词。

## 下载

请从 [GitHub Releases](https://github.com/shiquda/SpotAsk/releases) 下载与你的 Mac 匹配的软件包：

- **Apple silicon** — M 系列芯片的 Mac 请选择名称带 `arm64` 的 DMG。
- **Intel** — Intel 芯片的 Mac 请选择名称带 `x86_64` 的 DMG。

软件包目前尚未获得 Apple Developer ID 验证，首次打开时需要在 macOS 中确认。若要通过 Spotlight、Siri 或快捷指令调用 SpotAsk，请按照下方的[启用系统联动](#启用系统联动)说明，使用自己的 Apple 开发团队从源码构建。

## 快速开始

也可以从源码构建 SpotAsk。

**环境要求**

- macOS 15 或更高版本
- Xcode 16 或更高版本
- 一个提供 OpenAI 兼容聊天接口的服务账户

**构建和运行**

```sh
./scripts/make-app-bundle.sh
open build/SpotAsk.app
```

启动后 SpotAsk 会出现在菜单栏中，不在程序坞显示图标。

### 启用系统联动

Spotlight、Siri 和快捷指令需要使用 Apple 开发团队签名的构建版本。个人构建使用免费的 Apple 账户即可：

1. 使用 Xcode 打开 `SpotAsk.xcodeproj`。
2. 选择 SpotAsk target，然后打开 **Signing & Capabilities**。
3. 在 **Team** 中选择你的 Personal Team，并保持 **Automatically manage signing** 开启。
4. 如果 Xcode 提示 Bundle Identifier 不可用，请将 **Bundle Identifier** 改为一个唯一值。
5. 先从 Xcode 运行一次 SpotAsk，再到快捷指令中使用相关操作。

Personal Team 构建仅适合个人使用，并且可能需要定期重新构建。

## 首次配置

从菜单栏打开设置（或按 Cmd + ,），填写以下信息：

1. **服务地址** — 你的服务商提供的完整聊天接口地址。
2. **模型** — 服务商要求的模型名称（例如 `gpt-5-mini`）。
3. **访问密钥** — 你的服务凭证，仅保存在这台 Mac 上。

点击**测试连接**确认配置正确后，关闭设置即可开始提问。

## 日常使用

| 操作 | 方式 |
|---|---|
| 打开对话窗口 | 点击菜单栏图标，或按 **Option + Space** |
| 发送问题 | 输入问题后按 Return |
| 换行 | Shift + Return |
| 停止生成 | 按 Escape，或点击停止按钮 |
| 复制回答 | 右键点击回答，或使用复制按钮 |
| 复制代码块 | 点击代码块上的复制图标 |
| 开始新对话 | 在菜单栏中选择"新对话" |
| 使用提示词 | 输入框中已有内容时，选择提示词会直接发送；输入框为空时，选择后输入问题，再按 Return 发送 |

窗口的大小和位置会在下次启动时自动恢复。

## 隐私

你发送的问题、自定义指令和生成的回答会交由你配置的服务商处理。处理敏感信息前，请先确认服务商的隐私和数据保留政策。

访问密钥和设置仅存储在这台 Mac 上。启用对话保留后，最近的对话也会保存在本地。

## 开发者说明

### 构建与测试

```sh
# 运行测试
swift test

# 构建 release 版本
swift build -c release

# 创建 app bundle
./scripts/make-app-bundle.sh
open build/SpotAsk.app

# 创建 Apple silicon 或 Intel 的 DMG
./scripts/make-release-dmg.sh --arch arm64
./scripts/make-release-dmg.sh --arch x86_64
```

### 项目概览

SpotAsk 是一个 SwiftUI 应用，目标平台为 macOS 15，以菜单栏辅助程序（`LSUIElement`）方式运行，并使用 [Textual](https://github.com/gonzalezreal/textual) 渲染富文本回答。

入口文件为 `Sources/SpotAsk/App/SpotAskApp.swift`，测试位于 `Tests/SpotAskTests/`。

### 分发

准备分发应用时，请根据你的分发方式配置所需的签名、权限和网络访问能力。

## 许可证

SpotAsk 使用 [GNU AGPL v3](LICENSE) 许可证。
