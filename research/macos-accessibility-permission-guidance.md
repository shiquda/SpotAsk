# macOS 辅助功能权限引导调研

> 读者：SpotAsk 开发者。调研日期：2026-08-06。范围：跨应用划词助手读取选中文本所需的 macOS 辅助功能权限。

## 结论

不要把权限处理设计成单一的设置页面，也不要只依赖第一次系统弹窗。较成熟的 macOS 应用采用三层分工：

| 场景 | 应承担的职责 | SpotAsk 建议 |
| --- | --- | --- |
| 设置 > 划词助手 | 持续展示授权状态、解释用途、提供恢复入口 | 在既有“划词助手”页增加“辅助功能权限”状态区，而非新建通用权限页 |
| 用户开启功能或首次主动触发 | 在用户意图明确时请求系统提示，并说明下一步 | 开启开关时静默检查；用户点击“授权”或首次按划词快捷键时才请求系统提示 |
| 快捷键读取失败 | 不打断地说明当前功能不可用，并给出一次可行动作 | 现有浮层消息升级为“未允许跨应用读取”加“打开系统设置”，避免反复触发系统弹窗 |

macOS 的辅助功能权限必须由用户在“系统设置 > 隐私与安全性 > 辅助功能”中手动开启；应用不能自行完成授权。Apple 明确说明第三方应用尝试通过辅助功能控制 Mac 时会显示系统提示，用户可选择“打开系统设置”或拒绝，之后仍可在同一页面修改授权状态。[Apple Support](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)

## 推荐流程

1. 用户打开“划词助手”设置页时，使用无提示的 `AXIsProcessTrusted()` 或 `AXIsProcessTrustedWithOptions(... false)` 刷新状态。
2. 未授权时展示：状态“未允许”；说明“用于读取你主动选中的文字”；两个动作“授权并打开系统设置”和“刷新状态”。
3. 用户点击“授权并打开系统设置”时，调用 `AXIsProcessTrustedWithOptions` 的提示选项，请求系统原生提醒；应用同时可以打开 Accessibility 设置页。系统提示是异步的，调用返回 `false` 不等于用户永久拒绝，因此不要据此锁死流程。[Apple API](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
4. 当应用重新获得焦点时自动刷新；用户点击“刷新状态”时立即刷新。可再监听 `com.apple.accessibility.api` 作为加速路径，但该通知未见 Apple 正式公开文档，不能作为唯一真相来源。
5. 权限变为已允许时，更新状态并启用划词快捷键；权限被撤销时，禁用跨应用读取但保留 SpotAsk 的其他能力。
6. 同一运行会话内，如果用户已经看过系统提示，不要因每一次快捷键失败重复请求系统提示；改为显示“打开系统设置”入口。

## 同类实践

### Raycast：按功能请求，缺失时提供修复动作

Raycast 的 Window Management 和部分 AI 能力要求辅助功能权限。其官方文档把权限需求绑定到具体功能，并在缺失时提供授权入口。这支持“在用户实际要使用该能力时请求”，而不是启动即打扰用户。

- [Window Management](https://manual.raycast.com/window-management)
- [AI Commands](https://manual.raycast.com/ai/ai-commands)

### AltTab：权限状态窗口加持续检查

AltTab 用 `AXIsProcessTrustedWithOptions` 的无提示模式维护授权状态；代码中还同时使用分布式通知和低频轮询，应对授权撤销或通知未到达的情况。其源码明确标注 `com.apple.accessibility.api` 为未文档化行为，因此这个通知只适合作为优化而非平台依赖。

- [状态检查与通知/轮询](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/SystemPermissions.swift)
- [权限窗口](https://github.com/lwouis/alt-tab-macos/blob/master/src/secondary-windows/permission-window/PermissionsWindow.swift)

### Rectangle：专门授权窗口，授权后立即继续

Rectangle 在缺失辅助功能权限时显示专门的授权窗口，并周期性重新检查 `AXIsProcessTrusted()`；一旦授权成立便关闭窗口、继续功能。这是“显式等待用户完成系统步骤后即时恢复”的清晰实现。

- [授权检查与轮询](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityAuthorization/AccessibilityAuthorization.swift)
- [授权窗口](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityAuthorization/AccessibilityWindowController.swift)

### Hammerspoon：偏好设置页显示长期状态

Hammerspoon 在偏好设置中常驻展示辅助功能是否启用，同时在需要时调用系统请求接口。这验证了“设置页可恢复、操作时才请求”的组合模式。

- [辅助功能工具](https://github.com/Hammerspoon/hammerspoon/blob/master/Hammerspoon/MJAccessibilityUtils.m)
- [偏好设置状态](https://github.com/Hammerspoon/hammerspoon/blob/master/Hammerspoon/MJPreferencesWindowController.m)

### Maccy：按需授权与能力降级

Maccy 将辅助功能权限绑定在自动粘贴这一动作上：未授权时并不阻断剪贴板管理本身。SpotAsk 也应遵循这个边界，未授权时只关闭跨应用划词，不影响普通聊天。

- [FAQ](https://github.com/p0deje/Maccy/blob/master/README.md)
- [维护者关于首次尝试粘贴时请求权限的说明](https://github.com/p0deje/Maccy/discussions/980)

## 对 SpotAsk 当前实现的影响

当前实现已经在快捷键触发读取时调用带提示的权限检查，并在失败后显示短消息；但设置页没有状态、恢复入口或返回应用后的刷新机制。因此下一次实现应优先补齐一个 `AccessibilityPermissionCoordinator`，由它统一提供：无提示状态检查、用户主动请求、打开系统设置、应用激活时刷新、以及“本次会话已经请求过”的防打扰策略。

不建议首版加入后台高频轮询。对 SpotAsk 而言，应用重新激活、用户手动刷新和每次真正使用划词前的轻量检查足以覆盖主要路径；只有实测发现 macOS 特定版本存在状态滞后时，再增加低频兜底。

## 证据与限制

- Apple Support 和 Apple API 文档是平台行为的一手来源。
- Raycast 文档是产品自身的一手说明；AltTab、Rectangle、Hammerspoon、Maccy 是可审计的开源实现或维护者说明。
- `x-apple.systempreferences:` 深链与 `com.apple.accessibility.api` 通知均被多款应用采用，但前者/后者不是此处能够确认的稳定公开 API。上线前必须在 SpotAsk 的签名、沙盒配置和支持的 macOS 版本上实测。
- Apple 的系统授权弹窗和实际读取能力需区分：即使授权完成，具体来源应用是否暴露可读取的选中文本仍取决于该应用的辅助功能实现。
