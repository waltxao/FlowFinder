---
name: appkit-layout-tdd
description: "AppKit 原生 UI 布局改动的 TDD 与回归流程：先写失败测试，用只读帧快照和纯几何断言定位，再运行 xcodebuild 与应用内自检。用于修改或调试 NSWindow、NSView、NSSplitView、NStackView、NSButton/SF Symbol 对齐、分栏浮标、窗口尺寸、布局持久化，或建立 AppKit 布局回归测试时。"
---

# AppKit Layout TDD

把布局问题当作行为问题：先写会失败的几何测试，再用最小改动转绿，最后用运行中的应用核对视觉结果。

## 何时使用

- 修改 `NSWindow`、`contentView`、`NSSplitView`、`NStackView`、`NSButton` 等 AppKit 布局。
- 对齐、间距、分栏宽度、窗口缩放或布局持久化出现回归。
- 需要把“看起来不对”转成可重复的几何断言或帧快照。
- 准备运行 `xcodebuild`、XCTest 或应用内自检，并需要避免误杀用户正在运行的副本。

不用于纯 SwiftUI/UIKit、纯业务逻辑或没有布局维度的样式改动。

## 工作流

### 1. 先侦察，不先改代码

1. 读取项目测试入口、Makefile 和现有布局测试，记录可用的 scheme、测试 target 与当前基线总数。
2. 运行 `xcodebuild -list`（项目或 workspace）确认 scheme；不要凭文件名猜。
3. 搜索测试命令是否包含 `pkill`、`killall` 或类似进程清理。命中时不要直接运行该目标，改用定向 `xcodebuild test` 和独立 DerivedData 路径；需要杀进程时先取得用户明确同意。
4. 检查当前是否有用户正在运行的应用实例。不得为了跑测试关闭、覆盖或重启用户副本。
5. 记录测试前状态：默认值、窗口尺寸、分栏位置；测试结束必须恢复。

### 2. 先写失败测试

1. 一次只覆盖一个可观察行为，例如“内容中线与活动标签中线相差小于 0.5pt”或“辅助浮标不增加分栏面板数”。
2. 优先把布局计算抽成纯几何函数，用数值断言测试；需要真实视图层级时再创建最小窗口或视图。
3. 帧快照必须只读：诊断代码不调用 `layoutSubtreeIfNeeded`、不改 frame、不重绘。测试可以主动触发布局，但触发布局与读取快照要分开。
4. 对转换到同一祖先坐标系后的矩形做断言，不要直接比较不同坐标系里的 `frame`。
5. 运行测试并确认它因预期原因失败。若测试数为 0，先修 scheme、target 或 `-only-testing` 标识，不能把 0 tests 当作红。
6. 若失败来自测试自己的坐标假设，先修测试。不要为了迎合错误断言而改生产布局。

### 3. 用几何证据定位

| 症状 | 优先检查 |
|---|---|
| 视觉中心差 1–2pt | `NSButton`/控件 `frame` 是否包含 SF Symbol 内边距；改比较 `alignmentRect` |
| `y=8` 被当成“距顶部 8” | AppKit 默认左下原点；先确认视图是否 flipped，再转换坐标 |
| 分栏突然多出一个面板 | 是否把浮标、分隔线或辅助视图直接加进了 `NSSplitView` |
| 调整 `centerY` 后方向相反 | `NSStackView`/父视图是否 flipped；正值可能向下 |
| 单独跑绿、全量套件红 | `UserDefaults.standard` 是否被前一个测试或真实应用状态污染 |
| 只跑了 0 个测试 | scheme、测试 target、测试类/方法名或 `-only-testing` 不匹配 |
| 测试导致用户应用退出 | 测试入口里存在 `pkill`/`killall`，立即停止并改用安全命令 |

以 `alignmentRect` 作为视觉对齐依据时，传入与 `frame` 同坐标系的矩形，不要传 `bounds`；转换时从控件 `superview` 转到目标祖先。具体配方见 [references/appkit-layout-pitfalls.md](references/appkit-layout-pitfalls.md)。

### 4. 转绿并验证

1. 先运行定向测试，确认红转绿且执行数大于 0。
2. 再运行完整 XCTest 套件，记录 exact 执行数与失败数。
3. 运行项目已有的应用内自检或布局压力检查；没有该入口就明确说明未运行，不伪造。
4. 启动真实应用核对至少一个目标状态：截图、辅助功能树或界面操作均可；合成事件不可靠时改用人机配合。
5. 恢复测试修改的默认值、窗口尺寸和分栏位置。
6. 报告证据：测试命令、执行数、关键帧值、应用内自检结果，以及仍未完成的人工验证项。

## 验收标准

- 修改前存在因目标行为而失败的测试。
- 修改后定向测试与全量测试均通过，且测试执行数明确大于 0。
- 应用内自检（若存在）通过，真实应用已核对目标状态。
- 没有通过错坐标断言、截图错觉或 0 tests 宣布成功。
- 未遗留 `UserDefaults`、窗口或分栏状态污染。

## 资源

- [references/appkit-layout-pitfalls.md](references/appkit-layout-pitfalls.md)：坐标原点、`alignmentRect`、`NSSplitView` 浮标、`NStackView` 翻转、默认值隔离和安全测试命令的具体模式。
