---
title: 外部提问
description: 在 SpotAsk 统一敲下问题，一键或由决策模型自动分流至 ChatGPT、Perplexity、本地应用或终端 CLI。
---

# 外部提问

在统一的快捷小窗中随时捕捉灵感与疑问，然后一键交由最适合的工具解答。SpotAsk 负责全局即时唤起与分流，网页 AI、本地应用或终端 Agent 负责深入解答。

外部提问直接调用目标平台，**不消耗 SpotAsk 的模型 API 额度，提问内容也不会记录在本地历史中**。

## 快速分流

在提问窗口中，你可以随时把问题分发至外部平台：

- **即写即发**：输入问题后，直接点击底部的渠道按钮，或按下对应快捷键（如 <kbd>⌘ + 5</kbd>），立即唤起目标平台并关闭提问窗口。
- **预选渠道**：在输入框为空时点击渠道按钮或按下快捷键，输入框上方会挂载该目标标签；输入完毕按 <kbd>↩</kbd> 发送，按 <kbd>Esc</kbd> 或清空内容可取消。
- **对话中切换**：在已有对话中，点击输入框左下角预设菜单，或在回答底部的模型选单中选择外部渠道，即可带着当前问题快速前往其他平台对照解答。

---

## 动作类型

外部提问支持三种去向，通过 `{query}` 占位符自动填入你的提问内容：

### 1. 网页提问

在默认浏览器中打开目标链接并自动填入问题：

| 平台 | 预设链接 | 说明 |
| :--- | :--- | :--- |
| **问 ChatGPT** | `https://chatgpt.com/?q={query}` | 预填问题至输入框 |
| **问 Perplexity** | `https://www.perplexity.ai/search?q={query}` | 直接发起联网搜索 |
| **问 Grok** | `https://grok.com/?q={query}` | 预填问题并生成解答 |

::: tip 搭配脚本实现 ChatGPT 自动发送
ChatGPT 官方网页默认仅预填问题。若希望跳转后**自动点击发送**，可安装油猴脚本：[ChatGPT URL Prompt Auto Submit](https://greasyfork.org/zh-CN/scripts/592577-chatgpt-url-prompt-auto-submit)。
:::

### 2. 桌面应用

通过 macOS 协议链接（URL Scheme）将问题发往其他本地应用。例如笔记软件的快速记录协议：`quicknote://new?text={query}`。

### 3. 终端命令

将问题传递给终端中运行的命令行工具或本地 Agent，例如：

```text
omp {query}
```

![SpotAsk 一键唤起本地终端 CLI Agent](/images/spotask-external.gif)

---

## 自定义与管理渠道

进入 **设置 > 外部提问**，你可以自由添加、排序或停用渠道：

1. 点击 **添加渠道**（`+`），可直接选用主流服务预设模板（ChatGPT、Claude、Perplexity 等）或创建自定义渠道；
2. 自定义渠道需输入名称，并在链接或命令中用 `{query}` 标记问题填充位置；
3. 保存即可。系统会根据名称自动匹配官方品牌图标。

内置与自定义渠道均支持编辑或删除。停用的条目会保留在列表中，但不会出现在提问主窗口。

<SpotAskSettingsLink section="external-ask" />

---

## 智能路由 {#decision-routing}

除了手动点击渠道或按快捷键发送外，SpotAsk 还支持**智能路由**：

在提问输入框中敲下回车时，由轻量决策模型（分类器）研判意图，判断应当留在应用内直接作答，还是自动分发至最合适的外部平台。

<video poster="/images/spotask-smart-routing-preview.gif" src="/videos/SpotAsk-smart-routing-v5.mp4" controls muted playsinline width="720"></video>

*视频：一个问题，三种去向——智能路由实机演示（28 秒）。[下载 / 观看高清视频 (1080p MP4)](/videos/SpotAsk-smart-routing-v5.mp4)*

- **内联交互确认**：敲下回车后在输入框上方显示推荐去向与置信度，按 <kbd>↩</kbd> 放行，按 <kbd>Tab</kbd> 或方向键快速切换目标，按 <kbd>Esc</kbd> 取消。
- **双决策引擎支持**：支持配置 **System One (jev-1.13.0)** 官方/OpenRouter 端点或 **OpenAI Decisions (gpt-6-luna)**，各引擎参数独立存储。
- **阈值自动放行与临时暂停**：支持设定置信度阈值自动流转，并可通过标题栏图标（快捷键 <kbd>⌘ + ⇧ + R</kbd>）随时针对当前对话暂停路由。

::: tip 详细配置与进阶指南
有关 TypeSafe、OpenRouter 与 OpenAI Decisions 的完整接口参数、API Key 配置、渠道语义提示与安全边界，请参阅专门的使用指南：  
👉 **[智能路由完整配置指南](/zh-CN/guides/decision-routing)**
:::

<SpotAskSettingsLink section="external-ask" />
## 快捷键与停用

- **快捷键**：外部提问渠道按启用顺序排列，前两个渠道默认快捷键为 <kbd>⌘ + 5</kbd> 与 <kbd>⌘ + 6</kbd>。可在 **设置 > 快捷键** 中自定义。
- **功能总开关**：在 **设置 > 外部提问** 顶部关闭总开关，即可完整隐藏所有外部提问按钮与快捷键，已配置的条目仍会妥善保存在本地。

---

## 常见问题

**为什么没有默认内置 Claude 和 Gemini？**  
只有支持通过链接预填并直接作答的平台才会默认内置。Claude 目前仅支持预填需手动点击发送，Gemini 的 Web 链接暂不支持传参。你仍可随时将其添加为自定义网页条目使用。

**我的问题文本会被发送到哪里？**  
手动点击渠道时，问题仅会发送给你指定的网页或本地程序。使用智能路由时，问题文本与候选渠道名称会发送给你当前选择的决策服务进行分类研判，不包含任何账户凭据或历史对话。

---

相关内容：[智能路由](/zh-CN/guides/decision-routing) · [提示词预设](/zh-CN/guides/prompts) · [隐私与本地数据](/zh-CN/privacy) · [快捷键一览](/zh-CN/reference)
