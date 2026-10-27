---
title: Troubleshooting
description: Common SpotAsk connection, model, selection, permission, and shortcut problems and their fixes.
---

# Troubleshooting

## Connection test failed

Check these in Settings > **Services**:

1. **Address Type** matches what you entered. Use **Service Root** for a base URL such as `https://api.openai.com/v1`, or **Full Request Address** for the complete chat endpoint.
2. The address uses `https` for remote services. Plain `http` is accepted only for local services such as `http://localhost` or `http://127.0.0.1`.
3. The access key is saved and current.
4. The model ID is one your service accepts.
5. The response timeout is long enough for the service.
6. If you enabled a proxy, **Test Proxy** succeeds and the proxy address is correct.

<SpotAskSettingsLink section="provider" />

## Models cannot be discovered

Model discovery is available when the service uses **Service Root** and exposes a models list. It is not available for **Full Request Address** mode.

If refresh fails, verify the service address and access key first. If your provider does not expose a models endpoint, add the model manually with its exact Model ID.

## Selection Assistant does not appear

1. Enable **Selection Assistant** in Settings > **Selection Assistant**.
2. Allow the **Cross-app text access** permission when requested, and check its status in Settings.
3. If **Trigger mode** is **Show quick actions**, enable **Show quick actions after selecting text**.
4. Check **Auto-show apps**. In whitelist mode, only selected apps show the actions; in blacklist mode, excluded apps do not.
5. Try the selection shortcut manually: the default is `⌥ + ⇧ + Space`.
6. Remember that SpotAsk cannot read empty selections, secure input fields, or text in apps that do not expose selected text.

## Global shortcut conflicts

If another app uses the same global hotkey, record a different shortcut in Settings > **Shortcuts** > **Global Shortcut**, or clear **Global Shortcut** if you open SpotAsk from the menu bar or a URL. In-app shortcuts are separate from the global hotkey.

SpotAsk can only detect conflicts between its own shortcuts. It does not know when ChatGPT, Raycast, or another app already owns a key, so a shortcut that SpotAsk accepts may still be taken at the system level. Using the ChatGPT Mac app? See [ChatGPT ⌥Space conflicts](/guides/chatgpt-option-space).

## SpotAsk says it cannot read saved service settings

Settings > General > **Clear All Local Data** resets corrupted local service data. You will need to add your services and keys again.

<SpotAskSettingsLink section="general" />

## Decision routing does not recommend a channel

Check Settings > **External Ask** > **Decision Routing**:

1. **Enable External Ask** and **Enable automatic routing** are on, the toolbar switch for this conversation is on, and at least one external channel is enabled.
2. The selected engine matches the address. System One uses a System One base address, not a chat-completions URL. TypeSafe official is `https://api.typesafe.ai`. OpenRouter is `https://openrouter.ai/api`. OpenAI Decisions uses `https://api.openai.com` (SpotAsk adds `/v1/decisions`); do not paste a chat-completions URL.
3. The decision model matches that engine: `jev-1.13.0` for TypeSafe official, `typesafe/jev-1.13` for OpenRouter, `gpt-6-luna` for OpenAI Decisions. OpenAI does not serve `jev`.
4. The access key belongs to that same engine. TypeSafe official and `api.openai.com` will not send a request without a key. A custom OpenAI address can omit the key. OpenRouter rejects a missing or TypeSafe key at its own endpoint.
5. **Timeout** is long enough for that service. The default is 2 seconds, and the maximum is 5 seconds. A timeout falls back to manual channel selection unless you chose **Answer in SpotAsk**.
6. Use **Test question** in Settings. It shows the recommended destination without opening an external app.

A message with attachments, or a channel you already picked, skips the decision model on purpose.

Remote decision addresses require HTTPS; plain HTTP works only on loopback hosts, not LAN servers. A custom service's model cannot be blank. Cross-origin redirects and HTTPS downgrades are blocked: configure the final trusted endpoint directly.

The settings test reports missing credentials, invalid addresses/models, 401/403 authentication or permission failures, 404 endpoint errors, 429 rate limits, other HTTP statuses, network failures, timeout, and invalid/unrecognized answers separately. No evaluation time is shown when prerequisites or configuration prevent a request. After correcting the named cause, test again; SpotAsk does not automatically retry or send to another external channel.

If Settings reports that a saved access key could not be read, that is not the same as a missing key. SpotAsk keeps the previous key preference when that key cannot be read and does not migrate an empty value. After access to the saved local data is restored, reopen External Ask settings to read it again. The old preference is cleared only when the old key is confirmed absent or a migration saves successfully.

## Need more detail

Settings > General > **Diagnostics** can record recent request and selection details locally, then **Export Log** creates a file you can share. Credentials are never included.
