# SpotAsk

SpotAsk 是一款轻量级 macOS 快速对话工具。它常驻菜单栏，让你随时打开一个专注的提问窗口。

## 使用 SpotAsk

### 开始使用

1. 从菜单栏打开 SpotAsk，或按 `Option + Space`。
2. 打开“设置”，填写服务地址、模型名称和访问密钥。
3. 返回提问窗口，输入问题后按 `Return` 发送；按 `Shift + Return` 换行。

你可以在设置中调整快捷键、是否开机启动、窗口置顶、对话保留方式和阅读外观。关闭窗口不会发送内容。

### 日常功能

- 回答会在当前对话中逐步显示，可随时停止或重试。
- 支持复制完整回答和单独复制代码。
- 可从 Spotlight、Siri 或快捷指令中打开 SpotAsk、开始新对话或直接提问。

### 隐私

你发送的问题、自定义指令和生成的回答会交由所选服务处理。处理敏感信息前，请确认服务商的隐私和数据保留政策。访问密钥和应用设置仅保存在这台 Mac 上。

## 开发者说明

本节面向需要构建、测试或修改项目的开发者。

### 要求

- macOS 15 或更高版本
- Xcode 16 或更高版本
- 一个兼容 OpenAI Chat Completions 的服务账户

项目通过 [Textual](https://github.com/gonzalezreal/textual) 呈现富文本回答；其他依赖和版本以 `Package.swift` 为准。

### 构建与测试

在 Xcode 中打开 `Package.swift`，选择 `SpotAsk` scheme 后运行。

```sh
swift test
swift build -c release
./Scripts/make-app-bundle.sh
open build/SpotAsk.app
```

发布应用时，请根据目标分发方式配置所需的签名、权限和网络访问能力。
