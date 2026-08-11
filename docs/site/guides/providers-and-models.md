---
title: Providers & Models
description: Manage AI services and models, refresh model lists, and switch models for the current conversation.
---

# Providers & Models

Settings > **Services** is where you keep your AI services and models.

## Services

Each service has:

- A **Name** you choose.
- An **API Format**: **OpenAI Compatible** or **Anthropic**.
- A **Service Address** and **Address Type**.
- A **Response Timeout**.
- Its own **Access Key**.

You can add, edit, or delete services. Deleting a service removes its models. At least one service and model must remain.

## Models

Each model has a **Display Name**, an exact **Model ID**, and a streaming setting. The **Active** model is the Settings default used for new conversations.

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
