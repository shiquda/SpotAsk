---
title: 连接 Anthropic
description: 将 Anthropic 添加为 SpotAsk 服务并验证连接。
---

# 连接 Anthropic

服务使用 Anthropic Messages API 时，选择 **Anthropic** 接口格式。

## 添加服务

1. 打开设置，进入“服务”。
2. 新建服务或编辑已有服务。
3. 将“接口格式”设为 **Anthropic**。
4. 输入便于识别的名称。
5. 使用已预填的 Anthropic **服务地址**，或替换为你的服务商地址。
6. 输入并保存 Anthropic 访问密钥。
7. 添加 Anthropic 控制台或服务商文档中的模型 ID。
8. 点击“测试连接”。

<SpotAskSettingsLink section="provider" />

## 地址示例

使用**服务根地址**：

```text
https://api.anthropic.com/v1
```

使用**完整请求地址**：

```text
https://api.anthropic.com/v1/messages
```

## 获取 Anthropic 密钥

SpotAsk 会预填 `https://api.anthropic.com/v1`。到 [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) 创建密钥，填入“访问密钥”，再点击“测试连接”。Messages API 文档见 [docs.claude.com/en/api/messages](https://docs.claude.com/en/api/messages)。

## 说明

服务使用**服务根地址**且 Anthropic 提供模型列表时，可以自动发现模型。使用**完整请求地址**时，请手动添加模型。

服务必须支持 Anthropic API 请求格式。Anthropic 兼容代理或网关也可以按同样方式配置。

相关：[服务根地址与完整请求地址](/zh-CN/guides/service-addresses)、[服务与模型](/zh-CN/guides/providers-and-models)
