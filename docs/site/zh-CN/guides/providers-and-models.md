---
title: 服务与模型
description: 管理 AI 服务和模型、刷新模型列表，以及切换当前对话使用的模型。
---

# 服务与模型

设置 > **服务**用于维护你的 AI 服务和模型。

<SpotAskSettingsLink section="provider" />

## 服务

每个服务包含：

- 自定义名称。
- **接口格式**：**OpenAI**、**Anthropic** 或 **Gemini**。
- 服务地址和地址类型。
- 响应等待时间。
- 独立的访问密钥。

你可以添加、编辑或删除服务。删除服务会同时删除其模型，并且至少需要保留一个服务和模型。

## 官方地址与 API Key

新建服务时，SpotAsk 会按所选的**接口格式**和**地址类型**预填官方地址，例如**服务根地址**模式下的 `https://api.openai.com/v1`。使用官方服务就保留它，使用网关或代理则改成自己的地址。在你手动输入地址之前，切换这两个选项会同步更新该字段，便于对照各格式分别需要什么地址（见[服务根地址与完整请求地址](/zh-CN/guides/service-addresses)）。

调用官方服务前，先创建 API Key，填入“访问密钥”，再点击“测试连接”：

| 接口格式 | 创建 API Key | 接口文档 |
| --- | --- | --- |
| **OpenAI** | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | [platform.openai.com/docs/api-reference](https://platform.openai.com/docs/api-reference) |
| **Anthropic** | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) | [Messages API](https://docs.claude.com/en/api/messages) |
| **Gemini** | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | [Gemini API 文档](https://ai.google.dev/gemini-api/docs) |

## 模型

每个模型包含“显示名称”、准确的“模型 ID”、实时显示设置和思考设置。“当前”模型是设置中的默认模型，新对话会使用它。

SpotAsk 会根据服务商和模型名称自动推断“接口兼容类型”，并保留你手动选择的兼容类型。**由服务决定**不会发送额外思考字段，保持服务商默认行为；**关闭**会在服务商支持时禁用思考；低、中、高等选项会映射为对应服务商的思考强度或预算。遇到较少见的专属参数，可填写在“自定义请求参数”中；自定义思考字段会替换该模型的思考等级设置。

使用“添加模型”手动添加。服务支持发现且使用**服务根地址**、已保存访问密钥时，可点击“更新模型”拉取列表。

从服务发现的模型会标记为“来自服务”。对发现的模型保存修改后，它会作为自定义模型保留。

## 在对话中切换模型

对话窗口的模型选择器只改变当前对话使用的模型，不会修改设置中的默认模型。

- 可以在回答完成前选择其他模型，或用于重试最近一次失败请求。
- “使用默认模型”会让当前对话回到设置默认值。
- “开始新对话”会清除当前对话的模型覆盖，回到默认模型。

## 请求失败时

请求失败时，SpotAsk 会提供“重试”，以及合适场景下的“用其他模型重试”。选择另一个模型可以在不丢失对话的情况下重新生成回答。

相关：[连接 OpenAI 兼容服务](/zh-CN/guides/connect-openai-compatible)、[连接 Anthropic](/zh-CN/guides/connect-anthropic)
