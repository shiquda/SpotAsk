<p align="center">
  <img src="images/spotask-icon.png" width="104" alt="SpotAsk 应用图标">
</p>

<h1 align="center">SpotAsk</h1>

<p align="center">
  一款原生 macOS 菜单栏 AI 助手。按快捷键快速呼出、随时提问；也可以在 Safari、备忘录等应用中选中文字，一键翻译、解释、总结或润色——使用你自己的 AI 服务（BYOK）。
</p>

<p align="center">
  <a href="https://github.com/shiquda/SpotAsk/releases/latest"><img alt="最新发布" src="https://img.shields.io/github/v/release/shiquda/SpotAsk?display_name=tag&sort=semver"></a>
  <a href="https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml"><img alt="CI 状态" src="https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="许可证：AGPL-3.0" src="https://img.shields.io/github/license/shiquda/SpotAsk"></a>
</p>

<p align="center">
  原生 macOS 应用 · 隐私优先 · macOS 15+ · 支持 Apple silicon 和 Intel · AGPL-3.0
</p>

<p align="center">
  <a href="#下载">下载</a> · <a href="#快速开始">从源码构建</a> · <a href="#开发">开发</a> · <a href="README.md">English</a>
</p>

<p align="center">
  <img src="images/spotask-chat.png" width="640" alt="SpotAsk 英文界面在浅色与深色模式下的问答主界面">
</p>

## 主要功能

- **随时随地提问** — 按 Option + Space（可自定义）呼出专注的对话窗口，即开即用。
- **选中文字即问** — 在 Safari、备忘录或其他 macOS 应用中选中文字，操作条会出现在选中内容旁边，一键翻译、解释、总结、润色或执行自定义提示词。
- **使用自己的服务（BYOK）** — 自带密钥接入任意 OpenAI 兼容或 Anthropic 服务，自动发现可用模型；可选 HTTP 或 SOCKS5 代理并填写账号密码。
- **实时显示回答** — 回答逐步显示，附带思考过程与耗时；可以停止、重试或重新生成。
- **按需复制内容** — 一键复制完整回答，也可以单独复制代码块。
- **常用任务一键完成** — 内置翻译、解释、总结、润色四组提示词，也可以创建自己的提示词用于重复工作。
- **自定义快捷键** — 全局热键可选预设，也可以录制自己的快捷键，用于对话、划词助手和常用操作。
- **8 种界面语言** — 简体中文、English、Español、Deutsch、日本語、Français、Português、Русский。
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
- 一个提供 OpenAI 兼容或 Anthropic 聊天 API 的服务账户

**构建和运行**

```sh
./Scripts/make-app-bundle.sh
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

1. **服务商** — 选择要使用的服务（OpenAI 兼容或 Anthropic），也可以新增一个。
2. **服务地址** — 服务商提供的完整聊天接口地址。
3. **模型** — 服务商要求的模型名称（例如 `gpt-5-mini`）。
4. **访问密钥** — 你的服务凭证，仅保存在这台 Mac 上。

点击**测试连接**确认配置正确后，关闭设置即可开始提问。

## 日常使用

| 操作 | 方式 |
|---|---|
| 打开对话窗口 | 点击菜单栏图标，或按你配置的快捷键（默认 Option + Space） |
| 发送问题 | 输入问题后按 Return |
| 换行 | Shift + Return |
| 停止生成 | 按 Escape，或点击停止按钮 |
| 复制回答 | 右键点击回答，或使用复制按钮 |
| 复制代码块 | 点击代码块上的复制图标 |
| 对选中文字执行提示词 | 在其他应用中选中文字，然后点击操作条里的动作 |
| 开始新对话 | 在菜单栏中选择"新对话" |
| 使用提示词 | 输入框中已有内容时，选择提示词会直接发送；输入框为空时，选择后输入问题，再按 Return 发送 |
| 打开设置 | 点击菜单栏图标并选择设置，或按 Cmd + , |

窗口的大小和位置会在下次启动时自动恢复。

## 隐私

默认隐私优先：SpotAsk 是原生 macOS 应用，访问密钥仅保存在这台 Mac 上，选中的文字只发送给你配置的服务商。

你发送的问题、自定义指令和生成的回答会交由你配置的服务商处理。处理敏感信息前，请先确认服务商的隐私和数据保留政策。

访问密钥和设置仅存储在这台 Mac 上。启用对话保留后，最近的对话也会保存在本地。

划词助手会通过 macOS 辅助功能读取你选中的文字；权限只在你开启该功能时申请，选中的文字仅发送给你配置的服务商。

## 开发

构建、测试、打包、本地化与发布说明见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 许可证

SpotAsk 使用 [GNU AGPL v3](LICENSE) 许可证。
