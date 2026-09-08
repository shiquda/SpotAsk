---
title: Spotlight、Siri 与快捷指令
description: 通过 Spotlight、Siri、快捷指令或 spotask:// 链接使用 SpotAsk。
---

# Spotlight、Siri 与快捷指令

官方 SpotAsk 发布版本会注册 macOS 可以暴露给 Spotlight、Siri 和快捷指令的应用操作，并注册 `spotask://` URL scheme，供 Alfred、Raycast、终端脚本和快捷指令调用。

## 可用操作

- **打开 SpotAsk**：打开提问窗口。
- **问 AI**：提出一个问题。
- **翻译**、**解释**、**总结**、**润色**：对你提供的内容执行对应的内置提示词。
- **新对话**：清空当前对话并打开 SpotAsk。

## Spotlight

在 Spotlight 中搜索 SpotAsk，选择“使用 SpotAsk 提问”等操作，然后输入问题或内容。

## Siri

让 Siri 使用 SpotAsk 操作，例如“使用 SpotAsk 翻译 [内容]”。

## 快捷指令

打开“快捷指令”App，搜索 SpotAsk 操作。可以单独添加一个操作并填写内容，也可以构建更复杂的快捷指令，把文本、问题或其他快捷指令的输出传给 SpotAsk。

## URL scheme

可以从其他应用、快捷指令或终端打开这些链接。问题中的空格和其他特殊字符需要做百分号编码。

| URL | 作用 |
| --- | --- |
| `spotask://open` | 打开提问窗口 |
| `spotask://ask?q=Your%20question` | 填入问题并发送 |
| `spotask://ask?q=Your%20question&submit=false` | 只填入问题，不发送 |
| `spotask://toggle` | 显示或隐藏提问窗口 |
| `spotask://settings` | 打开设置 |

在终端中：

```sh
open "spotask://ask?q=What%20is%20Swift%20concurrency"
```

如果 SpotAsk 尚未运行，该链接会先启动应用再执行命令；如果已经在菜单栏运行，则立即执行。

## 自行构建

系统联动在官方发布版本中可用。如果自行构建，需要使用 Apple 开发团队签名，并先通过 Xcode 运行一次，再在快捷指令中使用相关操作。Personal Team 构建仅供个人使用，可能需要定期重新构建。

相关：[提示词](/zh-CN/guides/prompts)、[快速开始](/zh-CN/getting-started)
