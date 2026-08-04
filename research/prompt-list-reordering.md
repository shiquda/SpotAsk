# 提示词列表重排：macOS 交互方案

调研日期：2026-08-04

范围：针对 `db0a55a` 的提示词设置页，选择能同时满足扁平卡片排布、拖过明确阈值才交换、拖动时不出现脱离列表的代理虚影，以及 macOS 可访问性的最小实现。本文只讨论列表重排；不改变提示词启用、快捷键或历史图标的产品规则。

## 结论

推荐在现有 SwiftUI `SettingsGroup` 内实现一个小型的内部重排组件（例如 `ReorderablePromptPresetList`）：仅给排序把手附加 `DragGesture`，让**正在拖动的原卡片**以 `offset` 跟随指针；指针越过相邻卡片中线加少量回滞后，调用既有的 `AppSettings.movePromptPreset(id:before:)` 交换顺序，并以短动画让其他卡片让位。不要继续使用 `.onDrag` / `.onDrop`，也不要为这一处列表引入 `NSTableView`。

这是一个基于需求的设计判断：Apple 将 `DragGesture` 定义为在拖动事件序列变化时触发的拖动手势，且它的 `translation` 是从起点到当前事件的总位移，因此它正好提供内部排序所需的连续指针位移，而不会开启系统拖放会话。[`DragGesture`](https://developer.apple.com/documentation/swiftui/draggesture)；[`DragGesture.Value.translation`](https://developer.apple.com/documentation/swiftui/draggesture/value/translation)

现状中，`PromptPresetsSettingsPage` 对每个条目调用 `.onDrag` 并用 `PromptPresetDropDelegate.dropEntered` 立即调用 `movePromptPreset(id:before:)`。这意味着一进入目标行就移动，没有“穿过半行”的阈值；同时它使用的是 SwiftUI 的拖放通道而不是内部位置手势。[`SettingsView.swift` at `db0a55a`](../../Sources/SpotAsk/Settings/SettingsView.swift)；[`View.onDrop(of:delegate:)`](https://developer.apple.com/documentation/swiftui/view/ondrop(of:delegate:))；[`DropDelegate`](https://developer.apple.com/documentation/swiftui/dropdelegate)

## 方案比较

| 方案 | 能否满足卡片跟手和阈值交换 | 可访问性 | 结论 |
| --- | --- | --- | --- |
| 保留 `.onDrag` + `DropDelegate` | 否。`DropDelegate` 是“接受 drop 的视图”回调；它的自然边界是进入目标视图，不是卡片中线。拖放仍是系统拖放会话。 | 需要自行补足；目前排序把手被 `accessibilityHidden(true)`。 | 排除。 |
| `List` / `ForEach.onMove` | 系统提供的是动态视图的“move action”，适合标准列表重排，但不提供本需求所需的可调阈值和原卡片跟手外观。 | 最低风险，系统列表语义最完整。 | 仅当接受标准 macOS 列表样式与交互时采用。 |
| `NSTableView` | AppKit 的表格是行列记录控件，能做原生排序；但引入 `NSViewRepresentable`、数据源/代理及与 SwiftUI 行内容的桥接，不能以最小成本保持现在的卡片布局。 | 原生表格语义较成熟。 | 对此只有一组提示词的设置页过重。 |
| 内部 `DragGesture` + 几何阈值 | 是。拖动的是原卡片；用相邻行中线决定一次交换，能完全控制回滞和动画。 | 必须显式提供非指针的排序动作。 | 推荐。 |

Apple 的 `DynamicViewContent.onMove(perform:)` 明确只设置动态视图的移动回调，且可用于 macOS；它没有承诺阈值或拖拽视觉的定制能力，因此不能把它当作本需求的交互规格。[`onMove(perform:)`](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove(perform:))

`.draggable` 和 `.dropDestination` 是较新的 SwiftUI 拖放 API，但仍分别将视图设为拖放源和目的地；替换 API 不会把跨视图拖放改成内部手势排序。`NSDraggingItem` 也被 Apple 定义为一个 dragging session 中的单个 dragged item，故 AppKit 拖放同样不是消除拖拽表示层的最小路径。[`View.draggable(_:preview:)`](https://developer.apple.com/documentation/swiftui/view/draggable(_:preview:))；[`View.dropDestination(for:action:isTargeted:)`](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:))；[`NSDraggingItem`](https://developer.apple.com/documentation/appkit/nsdraggingitem)

## 最小实现建议

### 交互和状态

1. 继续使用 `settings.promptPresets` 作为唯一显示顺序，继续通过 `AppSettings.movePromptPreset(id:before:)` 持久化；不要在 View 中维护第二份数组。
2. 将每个 `PromptPresetRow` 置于 `LazyVStack` 或当前 `VStack` 的扁平行容器内，保留单一的浅色卡片背景和 1px 分隔边界。卡片不是嵌套在额外的视觉卡片里，已存在的开关、默认、编辑、删除按钮保持原位。
3. 用 `PreferenceKey` 收集每行在命名 coordinate space 中的 `midY` 和高度。只在行左侧的排序把手上附加 `DragGesture(minimumDistance: 2, coordinateSpace: .named(...))`，避免手势吞掉右侧开关和按钮。
4. 开始拖动时记录 `draggedPresetID`、初始中心点和行高；拖动期间让该行提高 `zIndex` 并按手势位移 `offset`。其他行只响应模型顺序变化的动画，因此用户看到的是原卡片在移动、相邻卡片让位，而不是一张脱离列表的副本。
5. 每次更新手势时，以指针所在的纵坐标与相邻行中线比较。越过中线后再加 `max(6pt, rowHeight * 0.15)` 的回滞才执行一次 `movePromptPreset`；交换后更新锚点或已处理目标，直到进入下一条边界。该数值是建议的交互常量，不是 Apple 的规定，目的是避免刚跨线时来回交换。
6. 结束或取消手势时清除拖动状态，移除 offset；不创建 `NSItemProvider`、不使用 `.onDrag`、`.onDrop`、`DropDelegate` 或 `.draggable`。这将从根上避免系统拖放代理预览。

手势 API 的事实边界来自 Apple：`DragGesture` 在拖动事件序列变化时调用，`translation` 给出起点到当前事件的总位移；上述“中线 + 回滞”的判断是基于该位移作出的本地交互设计。[`DragGesture`](https://developer.apple.com/documentation/swiftui/draggesture)；[`DragGesture.Value.translation`](https://developer.apple.com/documentation/swiftui/draggesture/value/translation)

### 可访问性和键盘等价操作

不能因为排序把手可拖动就把它标为 `accessibilityHidden(true)`。把手应具有本地化的 label（例如“重新排序：翻译”）和 hint；为它提供“上移”和“下移”两个 `accessibilityAction(named:_:)`，动作调用同一个 `movePromptPreset` 路径，并在首项/末项时禁用或不暴露不可能的动作。每次移动后以 `accessibilityValue` 说明当前位置，例如“第 2 项，共 5 项”。

Apple 说明 `accessibilityAction` 让 VoiceOver 等辅助技术调用视图操作，`accessibilityLabel` 描述内容，`accessibilityValue` 描述当前值，`accessibilityHint` 说明操作后果；这些 API 都可用于 macOS。将可访问操作放在排序把手上，不要合并整行的 accessibility children，以免遮蔽已有的启用开关和编辑/删除按钮。[`accessibilityAction(named:_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:))；[`accessibilityLabel(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:))；[`accessibilityValue(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:))；[`accessibilityHint(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:))

同时提供可发现的键盘等价路径：把手在 Full Keyboard Access 中可聚焦，VoiceOver Actions 菜单包含上移/下移；若验证发现自定义 action 不会被 Full Keyboard Access 聚焦，则在行的更多菜单中增加同名菜单项，而不添加永久可见的上/下箭头按钮。Apple 指出 `accessibilityRespondsToUserInteraction(_:)` 能明确描述一个元素是否可由 Switch Control、Voice Control 或 Full Keyboard Access 等交互；验证时应检查这一状态。[`accessibilityRespondsToUserInteraction(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityrespondstouserinteraction(_:))

## 预期文件范围

| 文件 | 变更 |
| --- | --- |
| `Sources/SpotAsk/Settings/SettingsView.swift` | 移除 `PromptPresetDropDelegate` 与行上的 `.onDrag` / `.onDrop`；新增私有的内部重排容器、行 frame 偏好和排序把手的 `DragGesture`、可访问性动作。 |
| `Sources/SpotAsk/Settings/AppSettings.swift` | 通常无需改动：既有 `movePromptPreset(id:before:)` 已是唯一顺序写入点。只有在实现需要一个按相邻索引移动的纯辅助函数时才补充，不能重复保存逻辑。 |
| `Tests/SpotAskTests/PromptPresetTests.swift` | 保留并扩展顺序持久化测试；覆盖向上、向下、首尾无操作和跨内置/自定义条目的 ID 稳定性。 |
| `Resources/*/Localizable.strings` | 仅新增“重新排序”“上移”“下移”“第 %@ 项，共 %@ 项”等可访问性字符串。 |

不建议新增第三方拖拽库，也不建议引入 `NSTableView` bridge。前者无法降低本需求的手势和无障碍复杂度；后者会扩大 SwiftUI/AppKit 边界。Apple 对 `NSTableView` 的定位是行表示记录、列表示属性的表格，与这里只有纵向排序的扁平设置卡片不匹配。[`NSTableView`](https://developer.apple.com/documentation/appkit/nstableview)

## 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 交换边界抖动、一次拖动反复换位 | 每个相邻目标只在越过中线加回滞后触发；交换后刷新锚点，并只对受影响行做动画。 |
| 长行高度不一导致固定阈值手感不一致 | 用实际行高的比例加最小 pt 值计算回滞，不以固定行数或数组下标猜测位置。 |
| 滚动容器内拖到边缘无法继续 | 第一版限定在可见列表重排；若用户需要长列表边缘自动滚动，再单独增加 timer 驱动的 scroll proxy，避免把这项复杂度混入当前修复。 |
| 无障碍回归 | 以 Accessibility Inspector、VoiceOver 和 Full Keyboard Access 验收上移/下移；保留行内原有控件的独立焦点。 |
| 持久化、快捷键或系统快捷指令被顺序改动影响 | 只调用现有 `movePromptPreset`，不改变 UUID、启用状态或快捷键解析逻辑；重启后核对顺序和已分配快捷键。 |

## 验收方法

1. 在至少五个提示词、且包含不同说明文本高度时，只从排序把手开始拖动。拖动卡片本体连续跟随指针，没有额外的半透明副本离开卡片列表。
2. 缓慢从一项拖到相邻项：未越过中线加回滞时不交换；越过后只交换一次；在边界附近来回移动不抖动。快速跨越多项时顺序正确。
3. 拖动时启用开关、默认、编辑和删除按钮仍可正常点击，且不会因行手势误触发。
4. 重启应用后顺序不变；已禁用的提示词、应用内快捷键和系统快捷指令仍按原 UUID 解析。
5. 用 Accessibility Inspector 检查把手有名称、提示、当前位置及“上移/下移”动作；用 VoiceOver 实际执行两种动作，确认顺序和位置播报更新；用 Full Keyboard Access 逐项到达行内的开关和操作按钮。
6. 对本次改动运行 `swift test`，并做一次人工 macOS 拖动验收。测试覆盖数据顺序；手感、无代理虚影和辅助技术暴露必须由真实 UI 验收，不能仅凭单元测试宣称通过。

## 官方来源

- [Apple Developer Documentation: DragGesture](https://developer.apple.com/documentation/swiftui/draggesture)
- [Apple Developer Documentation: DragGesture.Value.translation](https://developer.apple.com/documentation/swiftui/draggesture/value/translation)
- [Apple Developer Documentation: DynamicViewContent.onMove(perform:)](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove(perform:))
- [Apple Developer Documentation: View.onDrop(of:delegate:)](https://developer.apple.com/documentation/swiftui/view/ondrop(of:delegate:))
- [Apple Developer Documentation: DropDelegate](https://developer.apple.com/documentation/swiftui/dropdelegate)
- [Apple Developer Documentation: View.draggable(_:preview:)](https://developer.apple.com/documentation/swiftui/view/draggable(_:preview:))
- [Apple Developer Documentation: View.dropDestination(for:action:isTargeted:)](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:))
- [Apple Developer Documentation: NSDraggingItem](https://developer.apple.com/documentation/appkit/nsdraggingitem)
- [Apple Developer Documentation: NSTableView](https://developer.apple.com/documentation/appkit/nstableview)
- [Apple Developer Documentation: View.accessibilityAction(named:_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:))
- [Apple Developer Documentation: View.accessibilityLabel(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:))
- [Apple Developer Documentation: View.accessibilityValue(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:))
- [Apple Developer Documentation: View.accessibilityHint(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:))
- [Apple Developer Documentation: View.accessibilityRespondsToUserInteraction(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityrespondstouserinteraction(_:))
