---
title: Service Root vs Full Request Address
description: Understand the two SpotAsk address modes and when to use each one.
---

# Service Root vs Full Request Address

Every service has an **Address Type** setting.

## Service Root

Use **Service Root** when you enter the base address of the provider. SpotAsk appends the chat path automatically:

```text
https://api.openai.com/v1
```

For an OpenAI-compatible service, SpotAsk appends `/chat/completions`. For Anthropic, it appends the Messages path when needed.

This mode also makes model discovery possible, because SpotAsk can request the provider's model list.

## Full Request Address

Use **Full Request Address** when the provider gives you the exact chat endpoint and you want to send requests directly to that path:

```text
https://api.openai.com/v1/chat/completions
```

The full address must point to the correct chat endpoint for the selected API format. Model discovery is not available in this mode; add models manually.

## Which one should I choose?

Choose **Service Root** unless the provider documentation explicitly gives you a full endpoint that should not be derived from a base address.

```mermaid Address type decision: what the provider documents decides Service Root or Full Request Address
flowchart TD
  A[What does your provider document?] --> B{Base address or complete chat endpoint?}
  B -->|Base address| C[Service Root]
  B -->|Complete chat endpoint| D[Full Request Address]
  C --> E[SpotAsk appends the chat path]
  C --> F[Refresh Models can list models]
  D --> G[Requests go to the exact path you entered]
  D --> H[Add models manually]
```

<SpotAskSettingsLink section="provider" />

## Local services

SpotAsk accepts `http` only for local services such as `http://localhost` or `http://127.0.0.1`. Remote addresses must use `https`.

Related: [Connect an OpenAI-Compatible Service](/guides/connect-openai-compatible), [Connect Anthropic](/guides/connect-anthropic)
