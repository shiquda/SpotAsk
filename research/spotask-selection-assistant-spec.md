# SpotAsk 跨应用划词助手实现规格

状态：H0 待确认

目标读者：SpotAsk 开发者与产品验收人员

基线：`origin/main` at `ab32fcb919b77abb1ae22234472c0cd1fe06ae57`
日期：2026-08-05

## 1. 结论

首版新增一个独立的“划词助手”全局快捷键。用户在任意支持 macOS 辅助功能文本接口的应用中选中文字后，按下该快捷键；SpotAsk 根据设置执行以下一种模式：

1. **直接执行**：不显示快捷操作条，使用用户指定的默认提示词打开 SpotAsk 主窗口并立即提问。
2. **显示快捷操作**：在选区附近显示不抢占当前应用焦点的操作条；用户点击翻译、解释、总结、润色或自定义提示词后，SpotAsk 打开主窗口并立即提问。

两种模式共用同一套权限、选区读取、错误处理和任务路由。首版不做“选中即自动弹出”，也不轮询或持续监听用户选区；两种模式都由明确的快捷键动作触发。这是当前推荐的最小充分方案：它满足免复制粘贴和快速执行，同时避免把跨应用监听可靠性、误触控制和额外隐私负担带入第一版。

## 2. 目标与非目标

### 2.1 目标

- 用户无需复制粘贴即可把当前选中文本交给 SpotAsk。
- 主入口在 SpotAsk 窗口之外可用，并与现有“打开 SpotAsk”快捷键并存。
- 内置提示词和已启用的自定义提示词都可作为划词动作。
- 权限未授予、没有选区、来源应用不支持和读取超时都有明确且可行动的反馈。
- 选区文本只在用户触发时读取，不写入日志，不额外持久化，不把来源应用信息发送给模型。
- 核心流程可以通过协议替身做单元测试；真实跨应用行为有明确的人工验收矩阵。

### 2.2 非目标

- 首版不做选中文字后自动弹出操作条。
- 不使用 OCR、截图识别或屏幕录制权限读取文本。
- 不以模拟 `Command-C`、读取剪贴板再恢复为主路径或默认降级路径。
- 不读取密码框、安全输入控件、图片、文件对象或富媒体选区。
- 不在首版增加按应用白名单/黑名单、站点规则、自动语言识别规则或多步工作流。
- 不承诺所有应用都能读取选区；能力边界由来源应用的辅助功能实现决定。

## 3. 用户流程

### 3.1 首次启用

1. 用户进入设置中的“划词助手”。
2. 打开“启用划词助手”。
3. SpotAsk 请求“辅助功能”访问权限。
4. 设置页显示当前状态：未授权、已授权或需要重新检查。
5. 用户选择触发模式、快捷键；直接执行模式还需选择默认动作。
6. 权限授权后，应用在重新获得前台状态时自动刷新状态，不要求用户重启。

设置页只使用结果导向文案，例如“允许 SpotAsk 读取你主动选中的文字”和“打开系统设置”；不向普通用户展示 AX、TCC、进程或沙盒等实现术语。

### 3.2 直接执行模式

```text
选中文字
  -> 按划词快捷键
  -> 检查权限并读取当前选区
  -> 解析默认提示词
  -> 打开 SpotAsk 主窗口
  -> 立即发送“提示词 + 选中文字”
```

- 默认建议动作：内置“翻译”。用户可改为任意已启用提示词。
- 如果默认提示词后来被停用或自定义提示词被删除，设置层解析为第一个已启用提示词。
- 如果当前没有任何已启用提示词，不发送含义不明确的裸文本；打开主窗口，把选区填入输入框并聚焦，等待用户选择动作或补充问题。
- 如果当前正在生成回答，沿用现有 `ChatView.receiveQuestion` 行为：保留文本到输入框，不并发启动第二个请求。

### 3.3 显示快捷操作模式

```text
选中文字
  -> 按划词快捷键
  -> 检查权限并读取当前选区
  -> 在选区附近显示操作条，来源应用保持焦点
  -> 点击一个动作
  -> 关闭操作条
  -> 打开 SpotAsk 主窗口并立即发送
```

- 操作条按 `AppSettings.enabledPromptPresets` 的顺序展示动作。
- 最多直接显示前 4 个动作；更多动作放入尾部“更多”菜单，避免操作条随提示词数量无限变宽。
- 每个动作使用现有 `PromptPreset.symbolName` 和标题，图标按钮提供 tooltip 和可访问性名称。
- 操作条不显示原文预览，避免在屏幕上重复暴露敏感内容。
- 再次按划词快捷键、点击操作条之外、来源应用切换或成功选择动作都会关闭操作条。首版不承诺用 `Escape` 关闭非激活浮层，避免为此引入全局键盘监听或改变来源应用的按键行为。
- 点击动作前重新读取一次选区。只有来源 PID、文本和选区 range 与初始快照一致时才发送；任何一项变化都关闭操作条并提示“选区已改变，请重新触发”，避免用户基于 A 选区做决定却发送 B 选区。

### 3.4 失败反馈

| 状态 | 用户反馈 | 后续动作 |
| --- | --- | --- |
| 未授权 | “需要允许 SpotAsk 读取你主动选中的文字。” | 提供“打开系统设置” |
| 没有选中文字 | “请先选中文字，再试一次。” | 仅显示短提示，不打开主窗口 |
| 当前应用不支持 | “无法读取这个应用中的选中文字。” | 建议在其他文本区域重试；不提复制粘贴降级 |
| 来源应用暂时无响应 | “暂时无法读取选中的文字，请重试。” | 允许再次触发 |
| 安全输入区域 | “无法处理安全输入区域中的内容。” | 不读取 range、不定位、不发送 |
| 选区已改变 | “选区已改变，请重新触发。” | 关闭旧操作条 |
| 没有可用动作 | 主窗口带入选区但不发送 | 用户选择提示词或输入问题 |
| 快捷键冲突 | 设置页保留旧值并提示冲突 | 用户选择另一组快捷键 |

失败提示由划词浮层控制器显示为短时消息；除权限配置和“没有可用动作”外，不为错误强行激活 SpotAsk 主窗口。

## 4. 默认产品决策

以下默认值需要在 H0 确认：

| 决策 | 推荐默认值 | 理由与代价 |
| --- | --- | --- |
| 首版触发方式 | 选中文字后按快捷键 | 行为明确、低误触、不做后台选区监听；代价是比自动弹出多一次按键 |
| 初始模式 | 显示快捷操作 | 首次使用不必提前猜测用户要翻译还是总结；代价是多一次点击 |
| 划词快捷键 | `Option + Shift + Space` | 与现有 `Option + Space` 有连续心智模型且不冲突 |
| 直接执行默认动作 | 翻译 | 对选中文本有明确输出语义；用户可改为任意已启用提示词 |
| 功能初始状态 | 关闭 | 避免应用启动即请求高敏感权限；用户启用时再解释收益并请求权限 |
| 操作条可见动作 | 前 4 个 + 更多菜单 | 保持稳定宽度并复用用户的提示词排序 |

## 5. 技术边界

### 5.1 macOS 接口

主读取路径使用公开的 macOS Accessibility API：

1. `AXIsProcessTrustedWithOptions` 检查并按用户动作请求权限。
2. `AXUIElementCreateSystemWide()` 获取系统级元素。
3. 从 `kAXFocusedUIElementAttribute` 获取当前聚焦元素。
4. 在聚焦元素及有限父级链上读取 `kAXSelectedTextAttribute`。
5. 读取 `kAXSelectedTextRangeAttribute`，再通过 `kAXBoundsForRangeParameterizedAttribute` 尝试得到选区矩形。
6. 对系统级 AX 元素设置较短的 messaging timeout，避免来源应用无响应时阻塞 SpotAsk 主线程。

Apple 将 `kAXSelectedTextAttribute` 描述为可编辑文本元素的选中文本，因此网页正文、自定义渲染控件和只读文本的实际支持度必须通过真实应用验收，不能仅凭 API 存在宣称“任意应用均支持”。

参考：

- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)
- [kAXSelectedTextAttribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)
- [kAXSelectedTextRangeAttribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute)
- [kAXBoundsForRangeParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute)
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

### 5.2 沙盒与分发关口

当前发布配置在 `Config/SpotAsk.entitlements` 和 Xcode target 中启用了 App Sandbox。跨进程 Accessibility API 在当前签名、沙盒和 macOS 版本组合下的行为必须先做一个最小真实构建验证，不能只验证 `swift test` 或未签名命令行进程。

实施批次 1 的第一项是“分发形态技术验证”：

- 固定记录构建命令、签名身份类别、macOS 15.x 具体版本和测试账户类型；以目标 GitHub 分发形态的 app bundle 为通过对象。
- 用 `codesign` 校验最终 bundle 的 designated requirement 和实际 entitlements，避免只检查源文件。
- 在授权前后分别记录 `AXIsProcessTrustedWithOptions` 状态，并在 Safari、Chrome 和 Notes 中记录各读取步骤的 AX 错误码；任何记录都不包含选区正文。
- 若当前沙盒构建可用，保持现有 entitlements，不扩大权限变化。
- 若当前沙盒构建不可用，触发 H1：由用户决定是否为 GitHub 直发版本移除 App Sandbox。未经该决策，不自行改变发布安全边界。

Mac App Store 分发不在本次范围内；若未来进入商店，需要单独评估审核与沙盒约束。

## 6. 架构

### 6.1 数据模型

```swift
struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let source: SelectionSourceApplication
    let selectedRange: SelectionCharacterRange?
    let anchor: SelectionAnchor
}

struct SelectionCharacterRange: Equatable, Sendable {
    let location: Int
    let length: Int
}

struct SelectionSourceApplication: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
}

enum SelectionAnchor: Equatable, Sendable {
    case selectionRect(CGRect)
    case elementRect(CGRect)
    case pointer(CGPoint)
}
```

- `text` 保留内部换行和格式字符，只用首尾空白裁剪结果判断是否为空。
- `source` 和 `selectedRange` 与内存中的原文一起用于点击动作时确认选区未变化；这些字段不发送给模型。
- `anchor` 使用 AppKit 全局屏幕坐标。AX 坐标转换集中在一个纯函数中，并覆盖多显示器和负坐标测试。

### 6.2 协议与组件

```swift
protocol SelectedTextReading: Sendable {
    func readSelection(promptForPermission: Bool) async throws -> SelectedTextSnapshot
}

protocol AccessibilityElementReading: Sendable {
    func copyAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> AccessibilityValue
    func copyParameterizedAttribute(
        _ attribute: String,
        parameter: AccessibilityValue,
        from element: AccessibilityElementID
    ) throws -> AccessibilityValue
}

@MainActor
protocol SelectionOverlayControlling: AnyObject {
    func showActions(snapshot: SelectedTextSnapshot, presets: [PromptPreset])
    func showMessage(_ message: SelectionFeedback, anchor: SelectionAnchor?)
    func hide()
}
```

| 组件 | 职责 |
| --- | --- |
| `AccessibilitySelectedTextReader` | 权限检查、聚焦元素查找、有限父级回溯、选中文本和矩形读取、AX 错误映射 |
| `AccessibilityElementReading` adapter | 隔离 CF/AX 对象与错误码，使父级回溯、属性缺失、超时和安全字段可用替身测试 |
| `SelectionAssistantCoordinator` | 处理快捷键、模式分支、快照刷新、提示词解析、错误反馈和命令路由 |
| `SelectionOverlayController` | 管理非激活 `NSPanel`，展示动作或短消息，处理定位和关闭 |
| `SelectionActionBarView` | 渲染前 4 个提示词、更多菜单和可访问性信息 |
| `GlobalHotKey` / 注册协调 | 支持两个不同 ID 的全局热键并检测注册冲突 |
| `AppSettings` | 保存启用状态、模式、快捷键和默认提示词 ID |

### 6.3 线程与生命周期

- Accessibility 调用不在主线程执行；读取器在专用串行执行上下文中完成同步 AX 调用，只把 `Sendable` 快照或领域错误返回主线程。
- `SelectionAssistantCoordinator` 为 `@MainActor`，是快捷键回调、浮层和 `SpotAskCommandCenter` 之间的唯一编排入口。
- 每次触发生成一个递增 token。较早读取若晚于新触发返回，其结果被丢弃，避免旧选区覆盖新选区。
- App 退出时注销两组全局快捷键、关闭浮层并移除事件监视器。
- 不创建长期持有来源应用 `AXUIElement` 的缓存；每次用户触发都重新解析。

## 7. 选区读取算法

1. 检查功能是否启用。
2. 获取当前前台应用；如果前台应用是 SpotAsk，则返回“没有外部选区”。
3. 检查辅助功能权限。只有用户在设置页启用或明确触发划词功能时才允许系统弹出权限提示。
4. 创建 system-wide element，并设置短超时。
5. 读取 focused UI element。
6. 从 focused element 开始，先收集最多 6 层候选元素，只读取父级关系、`kAXRoleAttribute` 和 `kAXSubroleAttribute`，不读取任何 selected text。
7. 对完整候选链做安全预检；任一层具有 `kAXSecureTextFieldSubrole` 都立即返回 `sensitiveField`，不得读取正文、range、bounds 或元素 frame。
8. 安全预检通过后，再按由近到远的顺序读取候选元素：
   - 若支持 `kAXSelectedTextAttribute` 且文本非空，记录该最终命中元素并停止。
   - 若属性无值或不支持，继续父级。
   - 若 API 被禁用、目标进程未实现或通信失败，映射为对应领域错误。
9. 在最终命中 selected text 的同一个元素上读取 `kAXSelectedTextRangeAttribute`；确认值为 `AXValue` 的 `.cfRange` 且长度大于 0，再把同一个 range `AXValue` 传给 `kAXBoundsForRangeParameterizedAttribute`。
10. 若无法得到选区矩形，尝试元素的 position + size；仍失败则使用 `NSEvent.mouseLocation`。
11. 返回快照。原始文本不进入 `SafeLogger`，日志只允许错误类别、来源 bundle ID 和耗时。

父级回溯是兼容不同控件暴露方式的有限降级，不做无界辅助功能树遍历，避免性能不可控。

坐标契约：读取器内部保留 AX 返回的全局屏幕矩形，坐标转换器以包含矩形中心点的 `CGDisplayBounds` / `NSScreen` 配对为输入，输出 AppKit 全局坐标。转换不得使用主屏高度统一翻转所有屏幕；表驱动测试至少覆盖主屏、副屏位于左侧或上方、负坐标、Retina scale 和无 bounds 降级。多行选区以 AX 返回的联合 bounds 为锚点；若来源只返回单行或插入点矩形，则按实际矩形定位，不自行遍历每一行。

## 8. 浮层行为

### 8.1 窗口属性

- 使用独立、无标题、非激活 `NSPanel`，不复用主聊天面板。
- 操作条出现时不调用 `NSApp.activate`，来源应用和文字选区保持不变。
- 窗口层级高于普通窗口，可加入所有 Space，并支持全屏辅助显示。
- 点击动作后先关闭浮层，再调用 `SpotAskCommandCenter`；主聊天面板随后按现有逻辑激活应用。
- 浮层适配当前 `AppSettings.appearance`，语言变化时重建内容。

### 8.2 定位

定位优先级：

1. 选区矩形下方居中，间距 8 pt。
2. 下方空间不足时放在选区上方。
3. 没有选区矩形时放在聚焦元素附近。
4. 仍无定位信息时放在鼠标右下方。

最终 frame 必须限制在对应屏幕 `visibleFrame` 内，四边至少保留 8 pt。多显示器转换使用选区中心点对应的显示器，不假设主屏幕原点为 `(0, 0)`。

### 8.3 焦点与关闭

- 浮层可接受鼠标点击，但不成为主窗口，不把键盘焦点从来源应用永久移走。
- 安装局部与全局鼠标事件监视器用于点击外部关闭；监视器只判断事件位置，不读取按键内容。
- 操作条可见时再次按划词快捷键等价于关闭。
- 切换前台应用时关闭，避免浮层悬留在错误上下文。

## 9. 设置与持久化

新增设置分区 `SettingsSection.selectionAssistant`，位于“提示词”和“快捷键”之间。

| 设置 | 类型 | 默认值 |
| --- | --- | --- |
| `selectionAssistantEnabled` | `Bool` | `false` |
| `selectionAssistantMode` | `direct` / `actionBar` | `actionBar` |
| `selectionHotKeyPreset` | 独立全局快捷键枚举 | `optionShiftSpace` |
| `selectionDefaultPromptID` | `UUID?` | 内置翻译提示词 ID |

设置页结构：

- 功能开关与一句话说明。
- 权限状态和“打开系统设置”按钮。
- 模式 segmented control：“直接执行” / “显示快捷操作”。
- 划词快捷键 picker。
- 仅在直接执行模式显示“默认动作”picker。
- 说明操作条使用“提示词”页面中已启用的项目和顺序。

现有主窗口全局快捷键保持不变。两组快捷键不能相同；快捷键 picker 不直接绑定并持久化最终设置，而是先产生候选配置，交给注册协调器验证和切换。只有两组候选均注册成功后才写入 `AppSettings`；失败时显式恢复两组旧注册和旧设置，并向设置页返回可显示错误。

`SpotAskConfigBackup` 升级为 schema v2，general schema 同步加入上述 4 项设置。`General` 自定义解码对 v1 缺失字段使用本节默认值，导入路径接受 v1 并规范化为 v2 内存模型；导出只写 v2。导入新旧备份时都必须经过同一个快捷键候选提交流程，不能绕过冲突验证。

## 10. 与现有代码的集成

### 10.1 命令路由

现有 `SpotAskCommandCenter.ask(_:promptPreset:)` 继续负责成功动作的主窗口唤醒和自动发送。新增一个仅用于无可用提示词降级的命令：

```swift
case compose(String, PromptPreset?)
```

`ChatView` 处理 `.compose` 时写入 `viewModel.input`、应用仍有效的提示词并聚焦输入框，但不调用 `send()`。

### 10.2 全局快捷键

现有 `GlobalHotKey` 把 Carbon ID 固定为 `1`，无法安全注册第二个实例。修改为由初始化参数提供稳定 ID，或引入一个很小的注册表统一分配 ID；不引入第三方快捷键库。

建议 ID：

- `1`：现有主窗口快捷键。
- `2`：划词助手快捷键。

新增 `GlobalHotKeyRegistrationCoordinator` 管理两组活动注册。它先校验候选组合互不相同，再对需要变化的注册按固定顺序执行“注销旧值 -> 注册候选值”；所有步骤成功后才通知 `AppSettings` 持久化。由于同一 Carbon 组合不能在旧注册仍存在时预注册候选实例，不能把“原子切换”理解为同时保留两套注册。任一步失败都按旧配置反向恢复；若恢复也失败，进入可见的降级错误状态、注销不确定注册并禁止持久化候选值。不得让 `@Bindable` 在注册成功前直接写 `UserDefaults`。

### 10.3 提示词目录

- 操作条每次显示时读取 `settings.enabledPromptPresets`，不复制维护另一份提示词数组。
- 划词路径新增严格 resolver，只接受目录中仍存在且已启用的 preset ID；停用或删除返回 `nil`。现有 `promptPresetAllowedForUse` 保留给历史缓冲动作兼容，不能用于划词点击的失效检查。
- 自定义提示词正文沿用现有存储与发送路径，不新增“划词专用提示词”模型。

## 11. 预期文件范围

| 文件或模块 | 变更 |
| --- | --- |
| `Sources/SpotAsk/Selection/SelectedTextSnapshot.swift` | 快照、来源应用、定位和领域错误模型 |
| `Sources/SpotAsk/Selection/AccessibilitySelectedTextReader.swift` | AX 权限、读取、回溯、矩形和错误映射 |
| `Sources/SpotAsk/Selection/SelectionAssistantCoordinator.swift` | 两种模式的状态机和命令路由 |
| `Sources/SpotAsk/Selection/SelectionOverlayController.swift` | 非激活面板、定位、事件监视和生命周期 |
| `Sources/SpotAsk/Selection/SelectionActionBarView.swift` | 动作条和短消息 SwiftUI 内容 |
| `Sources/SpotAsk/HotKey/GlobalHotKey.swift` | 支持多个稳定 Carbon hot key ID |
| `Sources/SpotAsk/HotKey/GlobalHotKeyRegistrationCoordinator.swift` | 候选注册、两组切换、回滚和错误返回 |
| `Sources/SpotAsk/App/SpotAskApp.swift` | 构造协调器、注册第二快捷键、清理资源 |
| `Sources/SpotAsk/App/SpotAskCommandCenter.swift` | 增加 compose 路由 |
| `Sources/SpotAsk/Rendering/ChatView.swift` | 处理 compose，不自动发送 |
| `Sources/SpotAsk/Settings/AppSettings.swift` | 新设置、默认值、解析和持久化 |
| `Sources/SpotAsk/Settings/ConfigBackup.swift` | 配置备份 schema 与旧版本默认值 |
| `Sources/SpotAsk/Settings/SettingsView.swift` | 新设置分区和权限状态 UI |
| `Sources/SpotAsk/Resources/*/Localizable.strings` | 中英文用户文案和可访问性名称 |
| `Tests/SpotAskTests/Selection*.swift` | 读取器边界、协调器、定位和设置测试 |
| `Tests/SpotAskTests/SpotAskIntentTests.swift` | compose 与 ask 路由回归测试 |
| `Tests/SpotAskTests/AppSettingsTests.swift` | 新设置默认值和持久化测试 |
| `Tests/SpotAskTests/ConfigBackupTests.swift` | 新旧备份导入与快捷键冲突验证 |
| `Config/SpotAsk.entitlements` | 默认不改；仅在 H1 明确批准后调整 |

## 12. 实施批次与干扰

### 批次 1：平台验证与核心读取

- P1A：当前沙盒 app bundle 的真实 AX 验证。
- P1B：纯模型、错误类型、权限客户端、底层 AX adapter 和读取协议测试。
- P1C：`AccessibilitySelectedTextReader` 与坐标转换测试。

P1A 是后续发布边界的阻塞依赖；P1B 可与其并行。P1C 依赖错误模型稳定。

### 批次 2：直接执行模式

- P2A：多全局快捷键注册与冲突处理。
- P2B：`SelectionAssistantCoordinator`、`compose` 路由和设置持久化。
- P2C：设置页基础开关、权限状态、模式和默认动作。

P2A 与 P2B 会共同影响 `SpotAskApp.swift`，实现时分开文件所有权并由主代理串行集成该文件；其他新增文件可并行。

### 批次 3：快捷操作条

- P3A：非激活面板、定位与关闭状态机。
- P3B：操作条 SwiftUI 内容、更多菜单、可访问性和本地化。
- P3C：协调器的点击前刷新与过期结果保护。

P3A/P3B 可在协议稳定后并行；`SelectionOverlayController.swift` 由 P3A 独占。

### 批次 4：综合验证与独立审查

- 全量 `swift test` 和 release build。
- 使用签名 app bundle 做真实应用矩阵。
- 独立代码审查聚焦隐私、焦点、竞态、权限恢复和主快捷键回归。
- 用户执行 H2 体验验收。

## 13. 测试规格

### 13.1 自动化测试

- 未授权时不调用 AX 读取并返回权限错误。
- 聚焦元素直接提供选区时返回文本。
- 聚焦元素不支持、父级支持时有限回溯成功。
- 空字符串、零长度 range 和 unsupported attribute 映射为正确状态。
- `cannotComplete`、`notImplemented`、API disabled 分别映射，不泄漏原文到描述或日志。
- bounds -> element frame -> pointer 三层定位降级。
- 多屏幕、上方/下方空间不足和负坐标下 frame 仍位于 visible frame。
- 直接模式调用 `ask`；没有可用提示词时调用 `compose`。
- 操作条模式第一次读取只显示动作，点击时第二次读取后才发送。
- 快速连续触发时旧 token 结果被丢弃。
- 候选链中即使子元素未标记安全、父级标记 `kAXSecureTextFieldSubrole`，也会在读取任何正文前被拒绝，且不会继续读取 range、bounds 或触发发送。
- 点击时来源 PID、文本或 range 任一变化都会关闭旧操作条，不发送新旧文本。
- 提示词在操作条显示后被停用/删除时，严格 resolver 返回 `nil`，不沿用历史兼容 resolver。
- 两组全局快捷键 ID 不冲突，设置组合相同会被拒绝。
- 第二组注册失败会恢复两组旧快捷键，并且失败候选不会写入 `UserDefaults`。
- 新设置默认值、持久化、损坏值回退和清除本地数据行为正确。
- 配置备份可导出新设置，旧备份导入使用默认值，新备份导入不绕过快捷键冲突验证。
- 现有 Option+Space、Spotlight/Siri/Shortcuts、外部 `ask` 路由测试继续通过。

### 13.2 真实应用矩阵

| 应用/场景 | 文本读取 | 选区定位 | 直接模式 | 操作条模式 |
| --- | --- | --- | --- | --- |
| Safari 网页正文 | 必测 | 必测 | 必测 | 必测 |
| Chrome 网页正文 | 必测 | 必测 | 必测 | 必测 |
| Notes 富文本 | 必测 | 必测 | 必测 | 必测 |
| TextEdit 纯文本 | 必测 | 必测 | 必测 | 必测 |
| Xcode 编辑器 | 必测 | 必测 | 必测 | 必测 |
| Terminal 文本 | 记录支持度 | 记录支持度 | 支持时验证 | 支持时验证 |
| PDF 文字层（Preview） | 记录支持度 | 记录支持度 | 支持时验证 | 支持时验证 |
| 密码字段 | 必须拒绝/无文本 | 不显示 | 不发送 | 不显示动作 |
| 多显示器与全屏应用 | 必测 | 必测 | 必测 | 必测 |
| 非激活操作条焦点 | 不适用 | 不适用 | 不适用 | 首次点击即触发；显示期间来源应用不被激活/失焦；外部点击可关闭 |

“必测”表示发布阻塞；“记录支持度”表示不作为首版发布阻塞，但 README/支持文档不得承诺兼容。

## 14. 验收标准

1. 在 Safari、Chrome、Notes、TextEdit 和 Xcode 中选中一段文字后，以“Carbon 热键回调进入协调器”为起点、“操作条或失败提示完成首帧显示”为终点，各运行 5 次并记录中位数、最大值和超时样本；正常样本的中位数目标不超过 500 ms，来源应用无响应时不会冻结 SpotAsk 主线程。
2. 直接模式不会先显示操作条；使用设置的默认提示词打开主窗口并自动发送。
3. 显示快捷操作模式保持来源应用焦点和选区；点击动作后才激活 SpotAsk 并发送。
4. 操作条始终位于当前显示器可见区域，不遮挡整个选区，不因提示词数量改变基础布局宽度。
5. 未授权、无选区、不支持和超时状态可区分，反馈简短且给出下一步。
6. 日志、崩溃信息、UserDefaults 和会话之外的文件中不出现原始选区文本；来源应用元数据不发送给模型。
7. 现有 Option+Space、菜单栏、Dock 模式、Spotlight/Siri/Shortcuts 和常规提问流程没有回归。
8. `swift test`、release build 和目标 GitHub 分发签名 app bundle 验证通过；验收记录包含实际 entitlements、designated requirement 和 macOS 版本。
9. 当前沙盒配置若无法满足真实读取，必须在改变 entitlements 前经过 H1 用户确认。

## 15. 后续版本候选

只有首版数据证明用户确实需要时，再评估：

- 选中即自动显示操作条。
- 应用白名单/黑名单和按应用记忆模式。
- 键盘选择变化监听。
- 不激活主窗口的原位轻量回答。
- OCR 或截图内容理解。

这些能力会显著增加监听、权限、误触、性能或隐私复杂度，不作为当前实现的隐含范围。

## 16. H0 需要确认

实现开始前需要用户确认以下边界：

1. 接受首版两种模式都由 `Option + Shift + Space` 触发，不做“选中即自动弹出”。
2. 接受默认启用状态为关闭、初始模式为“显示快捷操作”、直接执行默认动作为“翻译”。
3. 接受先验证当前沙盒构建；若失败，另行进入 H1 决定是否为 GitHub 直发版本移除 App Sandbox。

H0 通过后按第 12 节批次连续推进，不在常规里程碑重复询问是否继续。
