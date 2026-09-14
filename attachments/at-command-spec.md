# SpotAsk `@` 命令交互与视觉规范

**版本**：v1.0  
**对应任务**：DEV-86  
**作者**：Designer  
**目标**：为 Stage 2（DEV-87）提供可直接落地的 `@` 命令唤起浮层设计规范，覆盖触发状态机、IME 兼容、浮层布局、键盘流与动作分发。

---

## 1. 设计目标与原则

| 原则 | 说明 |
|------|------|
| **零打断** | `@` 唤起不打断输入流；用户可继续键入过滤或随时取消，光标始终留在输入框。 |
| **原生感** | 严格遵循 macOS Human Interface Guidelines，使用既有 `Brand` 色系与 `NSPopover` / SwiftUI Popover 体系，避免自定义窗口。 |
| **一致性** | 与现有 `PresetPopoverTrigger`、`QuickActionStripView` 的交互模型（hover 高亮、圆角、阴影、字体）保持像素级一致。 |
| **IME 安全** | 中文/日文 Marked Text 状态下，浮层不拦截输入法按键，不吞字，不与候选窗竞争焦点。 |

---

## 2. 输入状态机（Trigger & Input State Machine）

### 2.1 状态定义

```
[Idle] --输入 `@` 且满足触发条件--> [TriggerActive]
[TriggerActive] --键入过滤字符--> [Filtering]
[TriggerActive] --Esc / 退格删除 @ / 光标移出范围--> [Idle]
[Filtering] --Esc / 退格删除 @ / 光标移出范围--> [Idle]
[Filtering] --Enter / Tab / 点击选中--> [ActionExecuting]
[ActionExecuting] --动作完成--> [Idle]
```

### 2.2 触发条件（Trigger Conditions）

| 场景 | 是否触发 | 说明 |
|------|----------|------|
| 输入框为空，键入 `@` | ✅ | 句首触发，光标后无字符。 |
| 光标位于空白字符后（空格、换行、Tab），键入 `@` | ✅ | 与 LobeHub 行为一致。 |
| 光标位于英文单词中间（如 `email@` 或 `user@domain`），键入 `@` | ❌ | 避免与邮箱、URL、英文习惯写法冲突。 |
| 光标位于中文文字中间，键入 `@` | ❌ | 同上，避免误触。 |
| 已处于 Marked Text（输入法组合态），键入 `@` | ❌ | IME 组合期间不触发，避免与拼音候选窗冲突。 |
| 输入框已有文本且光标在文本中间，前方紧邻非空白字符 | ❌ | 仅在「词边界」触发。 |

**判定逻辑（供 Dev 参考）**：
- 获取 `NSTextView` 的 `selectedRange()` 与 `textStorage`。
- 检查 `@` 字符前一位（`location - 1`）：
  - 若 `location == 0` → 触发；
  - 若前一位是 `.whitespaceAndNewline` → 触发；
  - 否则不触发。
- 同时检查 `hasMarkedText()`，为 `true` 时抑制触发。

### 2.3 关键字捕获（Keyword Capture）

- `@` 触发后，后续连续键入的字符（含中文、英文、数字、连字符、下划线）进入 `keyword` 缓冲区。
- 允许范围：`a-z A-Z 0-9 _ - 一-鿿 ぀-ヿ`（覆盖 CJK 与假名）。
- 不允许：空格、标点、`@` 本身（视为重新触发或取消）。
- 退格键删除 `keyword` 最后一个字符；删除至 `@` 本身时，浮层收起并回到 `Idle`。

### 2.4 取消与收起（Dismissal）

| 触发方式 | 行为 |
|----------|------|
| 按 `Esc` | 浮层淡出收起，输入框内容保持 `@keyword` 不变，光标不动。 |
| 退格删除 `@` 字符 | 浮层立即收起，`keyword` 同步清空。 |
| 光标移出 `@keyword` 编辑范围（点击他处、方向键移出词边界） | 浮层收起，`@keyword` 保留为普通文本。 |
| 点击输入框外部 / 面板失去焦点 | 浮层收起，输入框保持现有文本。 |
| 选中某项并执行 | 浮层收起，执行对应动作（见 §5）。 |

---

## 3. IME 与 Marked Text 兼容规范

SpotAsk 的 `ChatInputTextView` 已依赖 `NSTextView` 的 `hasMarkedText()` 来防止输入法组合期误发送（见 `ChatInputTextView.swift:299`）。`@` 命令浮层必须复用同一防护策略。

| 场景 | 行为 |
|------|------|
| 中文拼音输入「@」后进入 Marked Text 选词 | 浮层已展示，但 `↑`/`↓`/`Enter`/`Tab`/`Esc` 全部让渡给 IME，不拦截。 |
| 用户通过 IME 上屏一个中文字符 | 该字符追加到 `keyword`，浮层实时过滤；Marked Text 结束后恢复键盘导航。 |
| 用户想取消 `@` 但处于 Marked Text | `Esc` 优先由 IME 消费（取消选词）；IME 无 Marked Text 时才关闭浮层。 |
| 浮层展示期间，IME 候选窗弹出 | 浮层位置避让：若 IME 候选窗出现在输入框上方，浮层自动下移至输入框下方；避免重叠。 |

**实现提示**：
- 在 `ComposerTextView.keyDown(with:)` 中，先判断 `hasMarkedText()`；为 `true` 时直接 `super.keyDown(with:)`，不进入 `@` 命令处理分支。
- 浮层定位使用 `NSTextView.layoutManager.boundingRect(forGlyphRange:)` 计算光标位置，转换为屏幕坐标后避开 `NSMenu` / IME 候选窗区域。

---

## 4. 浮层布局与视觉规范

### 4.1 定位与容器

- **锚点**：以输入框当前光标行为锚点，浮层下边缘与光标所在行上边缘对齐（`offset.y = -4`），水平居中对齐光标。
- **越界自适应**：当输入框位于屏幕下半部时，浮层翻转到光标下方展示；当输入框位于屏幕上半部时，保持上方展示。
- **容器**：使用 SwiftUI `.popover(attachmentAnchor: .point(.bottom), arrowEdge: .top)`（或 AppKit `NSPopover` 等价配置），与 `AssistantMessageRow` / `ModelPickerView` 的现有 Popover 模式一致。
- **尺寸**：
  - 宽度：`min(320, 输入框宽度)`，最大不超过 `400`；
  - 高度：自适应内容，最大 `320`（约 8 条候选），超出后内部滚动；
  - 圆角：`10`；
  - 背景：`Brand.surface`（浅色模式）/ `Brand.surface.opacity(0.95)` + `ultraThinMaterial`（深色模式，与系统 Popover 一致）；
  - 阴影：`shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)`；
  - 边框：`strokeBorder(Brand.muted.opacity(0.2), lineWidth: 0.5)`。

### 4.2 双类别分栏

浮层内部采用垂直分段，顶部为搜索状态栏，下方为分类列表。

```
┌─────────────────────────────┐
│ 🔍  "@keyword" 正在过滤…    │  ← 状态栏（小字，Brand.muted）
├─────────────────────────────┤
│ ▼ 提示词预设 (Prompts)      │  ← 分组标题（11pt, Brand.muted, uppercase）
│   🌐 翻译 / Translate       │
│   📝 解释 / Explain         │
│   📋 总结 / Summarize       │
│   ✨ 润色 / Polish          │
│   ➕ 自定义 Prompt…         │
├─────────────────────────────┤
│ ▼ 外部提问 (External Ask)   │  ← 分组标题
│   🤖 ChatGPT               │
│   🚀 Grok                  │
│   💻 终端命令               │
│   🔗 自定义 URL Scheme…     │
└─────────────────────────────┘
```

#### 4.2.1 提示词预设（Prompt Presets）

| 元素 | 规范 |
|------|------|
| 图标 | 使用 `PromptPreset.symbolName` 对应的 SF Symbol，尺寸 `13pt`，颜色 `Brand.muted`（hover/选中时 `Brand.fg`）。 |
| 标题 | `13pt`, `weight: .medium`, `Brand.fg`。 |
| 副标题 | 若存在，显示预设描述前 20 字，`11pt`, `Brand.muted`。 |
| 快捷键提示 | 若 `showsShortcutHints` 为 true，右侧展示 `ShortcutKeycap`，与 `PresetPopoverContent` 一致。 |
| 选中态 | 右侧 `checkmark`（`12pt`, `weight: .semibold`, `Brand.accent`）。 |
| Hover 态 | 背景 `Brand.surface`（圆角 `8`），图标与文字颜色加深，`animation: .easeOut(duration: 0.1)`。 |

#### 4.2.2 外部提问（External Ask）

| 元素 | 规范 |
|------|------|
| 图标 | 优先使用 `QuickAction.brandIconSlug` 对应的 `ProviderBrandIcon`；无匹配时使用 `QuickAction.symbolName`（SF Symbol），尺寸 `13pt`。 |
| 标题 | `QuickAction.displayName`，`13pt`, `weight: .medium`, `Brand.fg`。 |
| 类型标签 | 右侧小字标签：`Web` / `终端` / `Scheme`，`11pt`, `Brand.muted`。 |
| Hover/选中态 | 与提示词预设完全一致。 |

### 4.3 空结果态（Empty State）

- 当 `keyword` 过滤后无匹配项时，浮层展示单条空状态：
  - 图标：`magnifyingglass`（`20pt`, `Brand.muted`）；
  - 文案：`未找到匹配 "@keyword" 的命令`（`13pt`, `Brand.muted`）；
  - 提示：`按 Esc 取消`（`11pt`, `Brand.muted`）。
- 空结果态高度固定 `72`，不展示分类标题。

### 4.4 深色/浅色模式

- 所有颜色引用 `Brand` 枚举，自动适配系统外观。
- Popover 背景在深色模式下使用 `ultraThinMaterial` + `Brand.surface.opacity(0.95)`，确保与系统菜单质感一致。

---

## 5. 键盘导航与动作分发

### 5.1 导航键映射

| 按键 | 条件 | 行为 |
|------|------|------|
| `↑` / `↓` | 浮层展示中，无 Marked Text | 在过滤后的候选列表中上下移动高亮；到达边界时循环（wrap-around）。 |
| `Enter` / `Tab` | 浮层展示中，无 Marked Text，存在高亮项 | 执行高亮项动作（见 §5.2）。 |
| `Esc` | 浮层展示中，无 Marked Text | 收起浮层，输入框保持 `@keyword` 文本。 |
| 退格 | 浮层展示中，无 Marked Text | 删除 `keyword` 末尾字符；若删除 `@` 则收起浮层。 |
| 其他可打印字符 | 浮层展示中 | 追加到 `keyword`，实时过滤；光标保持在输入框。 |
| 鼠标点击 | 任意时刻 | 与 `Enter` 等价，执行被点击项动作。 |
| 鼠标悬停 | 任意时刻 | 同步更新高亮项（与键盘高亮共享同一状态）。 |

### 5.2 选中后动作分发（Action Execution）

#### 5.2.1 选中「提示词预设」

1. 清除输入框中的 `@keyword` 字符串（含 `@`），保留光标前后其他文本；
2. 调用 `viewModel.selectedPromptPreset = preset`；
3. 输入框上方展示 `SelectedPresetBadge`（与现有 `PresetStripView` 选中后行为一致）；
4. 光标回到输入框原位置，等待用户继续键入具体问题；
5. 浮层收起。

#### 5.2.2 选中「外部提问」

1. 清除输入框中的 `@keyword` 字符串（含 `@`），保留光标前后其他文本；
2. 调用 `QuickActionTrigger.trigger(actionID:)`，传入 `currentInput: { viewModel.input }`；
3. 若输入框内已有用户问题（`@keyword` 之外的内容），直接作为查询参数触发外部提问；
4. 若输入框无其他内容，则清空输入框并触发外部提问（打开对应应用/URL/终端）；
5. 浮层收起，SpotAsk 面板根据 `QuickActionTrigger` 逻辑决定是否关闭。

### 5.3 与现有 `QuickActionTrigger` 的集成

- 复用 `QuickActionTrigger` 的 `isSessionEmpty` / `isGenerating` / `currentInput` / `clearInput` / `resolveAction` / `closePanel` 契约；
- `@` 命令浮层仅作为「选择器」，不改变 `QuickActionTrigger` 的执行语义；
- 外部提问执行后，`QuickActionTrigger` 内部的 `isExecutingQuickAction` 防重复触发逻辑继续生效。

---

## 6. 无障碍与辅助功能

| 特性 | 规范 |
|------|------|
| VoiceOver | 浮层打开时，焦点自动移至浮层第一项；每项朗读标题与类型；选中后朗读「已选择 [名称]」。 |
| 键盘焦点环 | 高亮项展示 `2pt` 圆角焦点环（`Brand.accent`），与 `PopoverRow` 的 `isFocused` 样式一致。 |
| 对比度 | 所有文字与背景对比度 ≥ 4.5:1（WCAG AA），依赖 `Brand` 色系已验证的配色。 |
| 减少动态效果 | 尊重 `NSWorkspace.accessibilityDisplayShouldReduceMotion`，关闭浮层淡入淡出动画。 |

---

## 7. 交付物与验收清单

### 7.1 交付物

- [x] 本设计规范文档（Markdown，挂载于 DEV-86 附件）；
- [ ] DEV-86 Issue 正文末尾交互式验收清单（见 §7.2）；
- [ ] 设计定稿后移交 Dev 的工程要点说明（见 §8）。

### 7.2 交互式验收清单（供 DEV-86 Issue 正文）

```markdown
## ✅ @ 命令设计验收清单

- [ ] 触发条件：句首/空格后 `@` 唤起浮层；英文单词中间、URL、Marked Text 期间不唤起
- [ ] 关键字过滤：`@keyword` 实时过滤候选列表；退格逐字删除；删除 `@` 收起浮层
- [ ] 取消方式：Esc、光标移出、点击外部均可平滑收起
- [ ] IME 兼容：Marked Text 期间不拦截按键，不吞字，候选窗弹出时浮层避让
- [ ] 浮层定位：锚定光标行，上方优先，越界自动翻转；宽度自适应，最大 400pt
- [ ] 双类别展示：提示词预设与外部提问分栏清晰，图标/标题/副标题/快捷键提示符合规范
- [ ] 视觉风格：macOS 原生毛玻璃质感，深色/浅色模式自适应，与现有 Popover 一致
- [ ] 键盘导航：↑/↓ 循环移动，Enter/Tab 选中，Esc 取消，与鼠标行为完全一致
- [ ] 提示词预设动作：清除 `@keyword`，激活预设，展示 SelectedPresetBadge，光标回输入框
- [ ] 外部提问动作：清除 `@keyword`，复用 QuickActionTrigger 触发外部服务
- [ ] 空结果态：展示搜索图标与提示文案，高度固定，不展示分类标题
- [ ] 无障碍：VoiceOver 朗读、焦点环、对比度、减少动态效果适配
```

---

## 8. 移交 Dev 的工程要点

> 以下内容为 Designer 对 Stage 2（DEV-87）实现的技术提示，非强制实现约束。

1. **触发检测**：在 `ComposerTextView.keyDown(with:)` 或 `textView(_:shouldChangeTextIn:replacementString:)` 中检测 `@`；优先使用后者，可在插入前判定上下文。
2. **关键字捕获**：使用 `NSTextView.textStorage` 与 `selectedRange()` 维护一个 `NSRange` 表示 `@keyword` 编辑区；每次文本变更时重新计算并同步到 SwiftUI 状态。
3. **浮层宿主**：建议在 `ChatView` 中新增 `@State private var atCommandState: AtCommandState?`，通过 `ChatInputTextView` 的 `onTextViewReady` 回调获取光标屏幕坐标，驱动 `.popover` 或自定义 `NSPanel`。
4. **IME 防护**：所有按键处理前必须检查 `hasMarkedText()`；为 `true` 时直接透传 `super.keyDown(with:)`。
5. **数据模型**：建议统一 `AtCommandItem` 枚举：
   ```swift
   enum AtCommandItem: Identifiable {
       case preset(PromptPreset)
       case quickAction(QuickAction)
   }
   ```
   过滤逻辑对两者使用同一套 `localizedCaseInsensitiveContains`。
6. **测试覆盖**：
   - 单元测试：`AtCommandState` 触发条件、过滤逻辑、动作分发；
   - UI 测试：IME 模拟（使用 `XCTest` 的 `XCUIElement` 键盘事件模拟中文输入流程）。

---

*设计定稿。如有交互细节调整，请在 DEV-86 评论区提出；Stage 2 实现问题请移交 [@Dev](mention://agent/eff4eec4-e00d-464c-bf87-482792b3afd8)。*
