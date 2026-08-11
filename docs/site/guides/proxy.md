---
title: Proxy
description: Configure an HTTP or SOCKS5 proxy for SpotAsk requests and model updates.
---

# Proxy

If your network requires a proxy, configure it in Settings > General > **Proxy**.

## Enable and test

1. Turn on **Use a proxy**.
2. Choose **HTTP** or **SOCKS5**.
3. Enter the **Server** and **Port**.
4. Add **Username** and **Password** only if the proxy requires them.
5. Click **Test Proxy**.

The proxy is used for chat requests and model updates. A successful proxy test confirms SpotAsk can connect through the proxy.

## If the test fails

- Check the server host and port with your network provider.
- Confirm the proxy supports HTTP or SOCKS5.
- Check whether authentication is required.
- If the proxy is only needed for one network, disable it when you switch networks.

Proxy credentials are stored locally and are never included in exported diagnostics.

Related: [Troubleshooting](/troubleshooting), [Privacy & Local Data](/privacy)
