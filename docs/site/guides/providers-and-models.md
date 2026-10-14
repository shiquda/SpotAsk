---
title: Providers & Models
description: Manage AI services and models, refresh model lists, and switch models for the current conversation.
---

# Providers & Models

Settings > **Services** is where you keep your AI services and models.

<SpotAskSettingsLink section="provider" />

## Quick Summary

SpotAsk provides a local-first, Bring-Your-Own-Key (BYOK) multi-provider architecture supporting official OpenAI, Anthropic, Gemini, and any OpenAI-compatible API gateway (DeepSeek, Groq, OpenRouter, Ollama, SiliconCloud). It manages multiple upstream services, automated model discovery, per-model reasoning/thinking parameter mapping, and in-chat model switching without vendor lock-in.

## Applicable Scenarios

- **Cost-Effective Daily Workflow**: Use fast, cost-effective models (such as DeepSeek V3, Claude 3.5 Haiku, or GPT-4o-mini) as your active default for routine lookups and text polishing.
- **Complex Reasoning & Architecture**: Switch on the fly in the chat window to frontier reasoning models (such as OpenAI o1/o3, DeepSeek R1, or Claude 3.7 Sonnet) with custom reasoning budgets when solving difficult technical problems.
- **Local & Offline Privacy Workflows**: Connect to a local Ollama or vLLM instance running on your Mac (`http://localhost:11434/v1`) with zero telemetry, zero data transmission over the internet, and complete offline privacy.

## Prerequisites & Compatibility

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Operating System** | macOS 15.0 (Sequoia) or later | Apple Silicon (`arm64`) and Intel (`x86_64`) |
| **Application Version** | SpotAsk `v0.1.0+` | Gemini format supported in `v0.2.7+`; thinking parameters in `v0.2.9+` |
| **API Formats** | OpenAI, Anthropic, Gemini | Compatible with any OpenAI-compliant proxy gateway |
| **API Credentials** | Provider API key or local endpoint | Stored locally in encrypted macOS Keychain; never sent to SpotAsk servers |
| **Network Requirements** | Direct HTTPS or local HTTP (`localhost`) | Custom proxies and gateways fully supported with configurable timeouts |

## Step-by-Step Instructions

1. **Open Services Settings**: Press `⌘ + ,` and select **Services** in the sidebar, or run `open "spotask://settings/provider"`.
2. **Add a Service**: Click **Add Service** (`+`) at the bottom of the service list.
3. **Configure Endpoint & API Format**:
   - Choose **API Format**: **OpenAI**, **Anthropic**, or **Gemini**.
   - Fill in **Service Address** (e.g. `https://api.openai.com/v1`, `https://api.deepseek.com`, or `http://localhost:11434/v1`).
   - Select **Address Type**: **Service Root** (recommended for auto-discovery) or **Full Request Address**.
4. **Enter API Key & Test Connection**: Paste your provider key into **Access Key** and click **Test Connection** to verify network connectivity and credentials.
5. **Add or Discover Models**:
   - Click **Refresh Models** to automatically fetch available models from the provider endpoint.
   - Or click **Add Model** to specify a custom **Model ID**, **Display Name**, and **Thinking Setting** (reasoning effort / budget).
6. **Switch Models During Chat**: Open the chat window (`⌥ + Space`) and click the model picker dropdown in the title bar to switch models for the current conversation.

## Visual Proof

![SpotAsk conversation window showing model selector with deepseek-v4-flash and prompt presets](/images/spotask-chat.png)
*Figure 1: The SpotAsk conversation window provides a top model picker to switch active LLMs on the fly across light and dark system themes.*

## Known Limitations & Boundaries

- **Minimum Service Invariant**: At least one service and one model must remain configured at all times; SpotAsk disables deleting the last remaining provider.
- **Protocol Endpoint Semantics**: Anthropic native endpoints expect `/v1/messages`; OpenAI endpoints expect `/v1/chat/completions`; Gemini endpoints expect Google Generative Language format. Mismatched format selections cause HTTP 400 or 404 errors.
- **Model Discovery Dependencies**: **Refresh Models** requires the service address to be in **Service Root** mode and requires the upstream gateway to implement a standard GET `/v1/models` endpoint.
- **Thinking / Reasoning Budget Support**: Extended reasoning effort and thinking budget parameters require upstream model support (such as Claude 3.7 or OpenAI o1/o3); unsupported models will return an API error unless thinking is set to **Off** or custom request parameters are adjusted.
- **Local Key Storage**: API keys are saved exclusively on your local machine; SpotAsk does not run user accounts or cloud synchronization, so keys must be configured on each Mac independently.

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
