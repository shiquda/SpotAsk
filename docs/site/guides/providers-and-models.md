---
title: Providers & Models
description: Manage AI services and models, refresh model lists, and switch models for the current conversation.
---

# Providers & Models

Settings > **Services** is where you keep your AI services and models.

<SpotAskSettingsLink section="provider" />

## Services

Each service has:

- A **Name** you choose.
- An **API Format**: **OpenAI**, **Anthropic**, or **Gemini**.
- A **Service Address** and **Address Type**.
- A **Response Timeout**.
- Its own **Access Key**.

You can add, edit, or delete services. Deleting a service removes its models. At least one service and model must remain.

## Official addresses and API keys

A new service starts with the official address of the selected **API Format** and **Address Type** already filled in — for example `https://api.openai.com/v1` in **Service Root** mode. Keep it to use the official service, or replace it with your gateway's address. Until you type an address of your own, the two pickers keep the field in step, so switching between formats shows what each one expects ([Service Root vs Full Request Address](/guides/service-addresses)).

To use an official service, create an API key first, paste it into **Access Key**, and click **Test Connection**:

| API Format | Create an API key | API documentation |
| --- | --- | --- |
| **OpenAI** | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | [platform.openai.com/docs/api-reference](https://platform.openai.com/docs/api-reference) |
| **Anthropic** | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) | [Messages API](https://docs.claude.com/en/api/messages) |
| **Gemini** | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | [Gemini API docs](https://ai.google.dev/gemini-api/docs) |

## Models

Each model has a **Display Name**, an exact **Model ID**, a streaming setting, and a thinking setting. The **Active** model is the Settings default used for new conversations.

SpotAsk infers **API Compatibility** automatically from the provider and model name, and preserves a profile you choose manually. **Provider default** sends no extra thinking fields and keeps the provider's own behavior. **Off** disables thinking where the provider supports it, while the level options map to the provider's reasoning effort or thinking budget. If a service needs a less common field, enter it as a **Custom Request Parameter**; custom thinking fields replace the selected thinking setting for that model.

To add a model, use **Add Model**. To pull models from a service that supports discovery, use **Refresh Models**; this requires **Service Root** address mode and a saved access key.

Models discovered from the service are marked **From service**. Saving changes to a discovered model keeps it as a custom model.

## Switch models in chat

The model picker in the chat window changes the model for the current conversation only. The Settings default is not changed.

- Choose a different model before or after a completed answer to retry with that model.
- **Use Default Model** returns the conversation to the Settings default.
- **New Conversation** clears the override and returns to the default model.

## If a request fails

When a request fails, SpotAsk offers **Retry** and, where appropriate, **Retry with another model**. Select another model to regenerate the latest answer without losing the conversation.

Related: [Connect an OpenAI-Compatible Service](/guides/connect-openai-compatible), [Connect Anthropic](/guides/connect-anthropic)
