---
title: 图片与文件
description: 在 SpotAsk 对话中附加图片、截图、文本和代码文件。
---

# 图片与文件

附件让你可以针对图片、截图、文本文件或代码文件的内容提问。

## 添加附件

- 将文件拖入提问窗口。
- 使用添加附件按钮选择文件。
- 从剪贴板粘贴截图。

图片会先做规范化处理，文本和代码文件会按 UTF-8 读取。

## 支持的类型

| 类型 | 示例 |
| --- | --- |
| 图片 | PNG、JPEG、WebP、HEIC、HEIF、TIFF、GIF |
| 代码 | Swift、Python、JavaScript、TypeScript、JSX、Rust、Go、Java、C、C++、Shell |
| 文本 | TXT、Markdown、JSON、YAML、XML、CSV、TSV、LOG |

每条消息最多 8 个附件，不能附加文件夹。

## 限制

- 图片最长边超过 4096 像素时会自动缩小。
- 超大文本文件会截取前 60,000 个字符。
- 不支持的文件类型会显示明确错误，而不是静默忽略。

## 上下文行为

附件会保留在当前对话中，供后续追问使用。启用对话保留时，文字对话会保存在本地，但附件不会在重启后恢复。

相关：[快速开始](/zh-CN/getting-started)、[参考](/zh-CN/reference)
