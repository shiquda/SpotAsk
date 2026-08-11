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

## Models cannot be discovered

Model discovery is available when the service uses **Service Root** and exposes a models list. It is not available for **Full Request Address** mode.

If refresh fails, verify the service address and access key first. If your provider does not expose a models endpoint, add the model manually with its exact Model ID.

## Selection Assistant does not appear

1. Enable **Selection Assistant** in Settings > **Selection Assistant**.
2. Allow the **Cross-app text access** permission when requested, and check its status in Settings.
3. If **Trigger mode** is **Show quick actions**, enable **Show quick actions after selecting text**.
4. Check **Auto-show apps**. In whitelist mode, only selected apps show the actions; in blacklist mode, excluded apps do not.
5. Try the selection shortcut manually: the default is `Option + Shift + Space`.
6. Remember that SpotAsk cannot read empty selections, secure input fields, or text in apps that do not expose selected text.

## Global shortcut conflicts

If another app uses the same global hotkey, choose a different preset or record a different shortcut in Settings > **Shortcuts**. The in-app shortcuts are separate from the global hotkey.

## SpotAsk says it cannot read saved service settings

Settings > General > **Clear All Local Data** resets corrupted local service data. You will need to add your services and keys again.

## Need more detail

Settings > General > **Diagnostics** can record recent request and selection details locally, then **Export Log** creates a file you can share. Credentials are never included.
