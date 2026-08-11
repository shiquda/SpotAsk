---
title: Connect an OpenAI-Compatible Service
description: Add an OpenAI-compatible provider, choose an address mode, save the access key, and add a model.
---

# Connect an OpenAI-Compatible Service

Use **OpenAI Compatible** for OpenAI and for any provider that exposes an OpenAI-compatible chat API.

## Add the service

1. Open Settings and go to **Services**.
2. Add a new service or edit an existing one.
3. Set **API Format** to **OpenAI Compatible**.
4. Enter a **Name** you will recognize.
5. Enter the **Service Address** from your provider.
6. Choose **Address Type**.
7. Enter and save the **Access Key**.
8. Add the **Model ID** your provider expects.
9. Click **Test Connection**.

## Address examples

Use **Service Root** when the provider gives you a base address:

```text
https://api.openai.com/v1
```

Use **Full Request Address** when the provider gives you the complete chat endpoint:

```text
https://api.openai.com/v1/chat/completions
```

Other providers may use different paths. Copy the exact base address or full endpoint from your provider's documentation.

## Add the model

The model list can be refreshed when the service uses **Service Root** and exposes a models endpoint. If discovery is not available, add the model manually:

1. Under the service, select **Add Model**.
2. Enter a **Display Name** for the model picker.
3. Enter the exact **Model ID** the API expects.
4. Choose whether answers should stream into the window.
5. Select **Use for Chat** when ready.

## After setup

Close Settings, press `⌥ + Space`, and ask a question. If the connection test passes but a question fails, see [Troubleshooting](/troubleshooting).

Related: [Service Root vs Full Request Address](/guides/service-addresses), [Providers & Models](/guides/providers-and-models)
