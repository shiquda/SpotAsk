---
title: Connect Anthropic
description: Add Anthropic as a SpotAsk service and verify the connection.
---

# Connect Anthropic

Use the **Anthropic** API format when your service speaks the Anthropic Messages API.

## Add the service

1. Open Settings and go to **Services**.
2. Add a new service or edit an existing one.
3. Set **API Format** to **Anthropic**.
4. Enter a recognizable **Name**.
5. Enter the service address.
6. Enter and save the Anthropic **Access Key**.
7. Add the **Model ID** from your Anthropic console or provider documentation.
8. Click **Test Connection**.

## Address examples

Use **Service Root** for a base address:

```text
https://api.anthropic.com/v1
```

Use **Full Request Address** for the complete Messages endpoint:

```text
https://api.anthropic.com/v1/messages
```

## Notes

Model discovery works with **Service Root** mode when Anthropic exposes a model list. With **Full Request Address**, add the model manually.

The service must support the Anthropic API request format. Anthropic-compatible proxies and gateways can be used the same way.

Related: [Service Root vs Full Request Address](/guides/service-addresses), [Providers & Models](/guides/providers-and-models)
