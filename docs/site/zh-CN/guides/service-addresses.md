---
title: 服务根地址与完整请求地址
description: 理解 SpotAsk 的两种地址类型，以及什么时候使用哪一种。
---

# 服务根地址与完整请求地址

每个服务都有“地址类型”设置。

## 服务根地址

输入服务商的基础地址时使用**服务根地址**，SpotAsk 会自动拼接聊天接口路径：

```text
https://api.openai.com/v1
```

OpenAI 兼容服务会自动补上 `/chat/completions`；Anthropic 会在需要时补上 Messages 路径。

该模式还支持模型发现，因为 SpotAsk 可以请求服务商的模型列表。

## 完整请求地址

服务商给出精确的聊天接口，并且你希望请求直接发送到该路径时，使用**完整请求地址**：

```text
https://api.openai.com/v1/chat/completions
```

完整地址必须指向所选接口格式对应的正确聊天接口。该模式不支持模型发现，需要手动添加模型。

## 应该选择哪一种

除非服务商文档明确要求填写完整接口，否则优先使用**服务根地址**。

## 本地服务

SpotAsk 只允许 `http://localhost`、`http://127.0.0.1` 等本地服务使用明文 HTTP，远程地址必须使用 `https`。

相关：[连接 OpenAI 兼容服务](/zh-CN/guides/connect-openai-compatible)、[连接 Anthropic](/zh-CN/guides/connect-anthropic)
