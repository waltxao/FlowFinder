---
name: macos-appkit-ui-testing
description: "macOS AppKit 布局回归与实机 UI 验收的测试编排：先锁定显示前初始布局，用 arrangedSubviews、alignment rect、flipped 方向和持久化默认值隔离编写稳定 XCTest，再用 20 轮侧栏/单双栏/活动面板交替压力循环和只读帧诊断捕捉空白、悬空、面板数异常；实机阶段用独立 Bundle ID 副本、按 PID 驱动 AX、按窗口区域截图并复核。用于 NSWindow/NSSplitView/NSStackView/NSButton/SF Symbol 的首帧 50/50、空白面板、对齐 0.5pt、测试间默认值污染、同名进程/多副本冲突、TCC 弹窗与坐标点击失效。纯 SwiftUI/Web、只做像素测量或纯几何 TDD 时转用相邻 Skill。"
---

# macOS AppKit UI Testing

把“看起来不对”变成两层证据：可重复的布局测试，以及隔离实例上的实机截图/AX 证据。这个 Skill 负责测试编排、状态隔离和取证顺序；纯几何细节见 [appkit-layout-tdd](../appkit-layout-tdd/SKILL.md)，截图/像素测量/TCC 细节见 [macos-app-ui-verification](../macos-app-ui-verification/SKILL.md)。

## 何时使用

- 修改 `NSWindow`、`NSSplitView`、`NSStackView`、`NSButton`、SF Symbol 图标布局后，需要补回归测试或验证修复。
- 出现首帧空白、首帧 50/50、面板数变成 3、详情栏悬空、对齐差 0.5pt、切换侧栏/单双栏后布局塌陷。
- 测试单独跑绿、全量跑红，怀疑 `UserDefaults` 中的布局状态污染。
- 需要隔离运行副本、按 PID 驱动 AX、按窗口区域截图，避免命中用户正在用的实例或同名副本。
- 需要把一次偶发的真机问题固化成压力循环、只读帧诊断和可复核证据。

## 不适用

- 只计算几何、不运行应用：用 `appkit-layout-tdd`。
- 只做像素测量、Computer Use 点击或 TCC 排障：用 `macos-app-ui-verification`。
- 只需要隔离副本、按 PID 验证，不涉及布局测试：优先用 `macos-isolated-app-ui-verification`。
- 纯 SwiftUI/UIKit、Web 页面、iOS 模拟器，或没有 AppKit 布局维度的改动。

## 铁律

1. **先隔离，再测试**：不杀、不覆盖用户正在用的实例；只操作自己启动的 PID。需要退出、改默认值或删临时副本时先取得同意。
2. **先快照，后改状态**：测试和实机验证前记录布局默认值，结束用 `defer` 恢复；不要用 `defaults delete` 清整个域。
3. **0 tests 不是通过**：确认 scheme、target、`-only-testing` 真的选中了测试；执行数必须大于 0。
4. **同祖先坐标**：比较 frame 前先转换到同一祖先；视觉中心用 `alignmentRect`，不要直接比 `NSButton` 的原始 `frame`。
5. **不猜 flipped 方向**：读 `isFlipped` 或对两个方向都做断言；正 `centerY` 常量在 flipped 视图里可能向下。
6. **单测不等于实机**：布局测试、应用内自检、真机截图/AX 证据分开报告；没有执行证据的项标“未验”。

## 工作流

### 1. 侦察与基线

1. 读取项目结构、scheme、测试 target 和现有布局测试，记录测试前基线数量。
2. 搜索测试入口是否包含 `pkill`、`killall`：命中时不要直接跑该 make 目标，改用定向 `xcodebuild test` 和独立 DerivedData。
3. 记录当前运行实例：路径、Bundle ID、版本、PID、窗口 bounds。确认要验证的是桌面副本、构建缓存副本，还是自己启动的临时副本。
4. 快照布局默认值。常见键包括 `sidebar_hidden`、`sidebar_width`、`single_pane_mode`、`pane_left_width`；再检查项目自己的详情栏宽度、窗口 frame、列宽等持久化键。记录“键不存在”的状态，恢复时删除而不是写回默认值。
5. 记录基线：目标测试、全量 XCTest、应用内自检的精确执行数。

### 2. 锁定显示前布局

1. 对 `showImmediately: false` 的窗口，先完成 setup、内容装载和初始分隔线，再 `makeKeyAndOrderFront` / `showWindow`。
2. 添加或恢复 `arrangedSubviews` 后，先 `adjustSubviews()` + `layoutSubtreeIfNeeded()`，再 `setPosition` 恢复记忆宽度，最后再布局一次。
3. 不要把初始 `setPosition` 放进 `DispatchQueue.main.async`。异步执行会让首帧先显示 50/50，下一拍才跳回记忆宽度；新窗口和启动首帧都踩过这个坑。
4. 在窗口显示前读取布局并断言：窗口仍不可见、面板数正确、可见面板填满分栏、内容高度不是 0、详情栏贴视觉底部。
5. 如果窗口必须在显示后才能拿到非零 bounds，先禁用首帧动画/隐藏过渡，并单独测试 pre-show 状态；不要把“显示后再修”当成初始布局。

### 3. 写稳定布局测试

1. 一次只覆盖一个可观察行为，例如“单栏切换活动面板后仍只有一块 arranged subview”或“详情栏距视觉底部小于 80pt”。
2. 优先把布局计算抽成纯几何函数；需要真实层级时再创建最小窗口或视图。
3. 面板数用 `split.arrangedSubviews.count`，不要用 `split.subviews.count`。宽度浮标、拖拽标签、分隔线装饰挂在分栏的父容器，不要 `split.addSubview`，否则 `NSSplitView` 会把它当成第三个 pane。
4. 视觉中心用：

   ```swift
   let rect = button.alignmentRect(forFrame: button.frame)
   let inAncestor = ancestor.convert(rect, from: button.superview)
   ```

   `alignmentRect(forFrame:)` 接收与 `frame` 同坐标系的矩形，传 `frame`，不要传 `bounds`；返回矩形仍按传入坐标系解释，再从 `superview` 转到目标祖先。
5. 明确处理 flipped：

   ```swift
   let dy = host.isFlipped ? -offset : offset
   ```

   不要因为“AppKit 默认非 flipped”就硬编码符号；`NSStackView` 及其子视图可能给出相反方向。把 `isFlipped`、`frame`、`alignmentRect`、`isHidden`、`superview` 链一起写进失败信息。
6. 默认值隔离优先用可注入的 `UserDefaults(suiteName:)`；只能使用 `.standard` 时按 key 保存/恢复。详见 [references/layout-test-harness.md](references/layout-test-harness.md)。
7. 先运行定向测试，确认它因预期原因失败；若失败来自测试自己的坐标假设，先修测试，不要为了迎合错误断言改生产布局。

### 4. 交替压力回归

1. 用 20 轮循环交替：隐藏/显示侧栏、单栏/双栏、左/右活动面板；每轮触发布局后再读取。
2. 每轮断言：`arrangedSubviews.count` 与模式一致；可见面板填满 split；内容 clip/列表高度大于阈值；详情栏距视觉底部在允许范围内；面板没有被标记 hidden 却仍参与排列。
3. 快照必须只读：诊断函数不调用 `layoutSubtreeIfNeeded`、不改 frame、不重绘。测试可以先触发布局，再调用只读快照；两者分开。
4. 用 `defer` 恢复所有默认值、窗口尺寸和分栏位置。测试结束前再读一次，确认恢复成功。
5. 如果 20 轮没有复现，不要宣称“已修复偶发 bug”；增加轮数或交替同步/异步路径可以继续排查，但报告要写“未复现”和已覆盖的状态。
6. 需要记录每一轮的帧值时，输出精简摘要而不是整棵视图树，避免日志淹没证据。

### 5. 隔离实机验证

1. 同 Bundle ID 多副本或已有实例在运行时，复制 `.app` 到临时目录，改独立 `CFBundleIdentifier` / `CFBundleName`，ad-hoc 重签后再启动。不要用 `open -a` 猜目标，也不要用同名进程名定位。
2. 通过 PID 或独立 Bundle ID 驱动 AX。用 `every application process whose unix id is <PID>` 并先判断 `count`，再取 `item 1`；`first process whose unix id is <PID>` 在进程尚未注册到 System Events 时可能返回 `-1719`。
3. 用 `tell application id "<bundle-id>" to activate` 置前，再读取 `AXPosition` / `AXSize`。按窗口区域执行 `screencapture -x -R x,y,w,h`；区域截图可能输出 1x，窗口截图可能是 2x，必须用 `sips -g pixelWidth -g pixelHeight` 核对，不能假设 Retina 一定是 2x。
4. `screencapture -l<window-id>` 依赖屏幕录制权限；全黑、只有壁纸或空白时先检查 TCC、最小化和当前 Space，不要循环重试。
5. 点击顺序：AX 元素操作 → CUA 元素操作 → CUA 坐标点击（同一次执行内重新截图）→ 人机配合。CGEvent 的 y 以屏幕顶部为原点，TCC 弹窗和重叠窗口会让点击打到别的 App；点击未报错不等于成功，必须复核截图或 AX 状态。
6. 需要构造窄侧栏等难拖拽状态时，先退出自己启动的实例，再写默认值、启动、截图、恢复。用户实例的默认值不要动。
7. 结束只 `kill` 自己的 PID，删除自己创建的临时副本，恢复默认值并再次确认。

### 6. 收口与报告

1. 先定向测试，再全量 XCTest，再应用内自检（若存在）；记录 exact 执行数与失败数。
2. 真机证据至少包含：PID、Bundle ID、版本、窗口 bounds、截图路径、关键测量值或 AX 输出。
3. 报告分开写“自动化证据”“实机证据”“未验项”。没有截图的视觉项不写成已通过。
4. 恢复默认值、窗口尺寸和分栏位置；确认没有遗留进程和临时副本。
5. 如果项目有台账、交接文档或 CHANGELOG 规范，按项目规范在同一轮同步；不要只在对话里说“已修”。

## 症状 → 检查

| 症状 | 优先检查 |
|---|---|
| 首帧 50/50，随后跳到记忆宽度 | 初始 `setPosition` 是否异步；是否在显示前完成布局 |
| 面板空白、详情栏跑到顶部 | 显示前布局是否为零；坐标是否 flipped；容器高度是否塌陷 |
| 面板数变成 3 | 是否把浮标/装饰 `addSubview` 进了 `NSSplitView`；断言是否用了 `arrangedSubviews` |
| 视觉中心差 0.5–2pt | `alignmentRect` 是否传了 `bounds`；是否从错误的 superview 转换 |
| 正常量把内容推向反方向 | `NSStackView`/祖先是否 flipped；是否硬编码了符号 |
| 单测单独绿、全量红 | `sidebar_hidden`、`sidebar_width`、`single_pane_mode`、`pane_left_width` 等默认值污染 |
| AppleScript 命中错误窗口 | 同 Bundle ID/同名进程；改用 PID 或独立 Bundle ID，先 `count` 再取 `item 1` |
| 截图空白或只有壁纸 | 屏幕录制权限、窗口最小化、其他 Space、窗口被遮挡 |
| 点击无效或打到别的 App | TCC 弹窗、重叠窗口、CGEvent 顶部原点、复用了旧截图坐标 |
| 0 tests 却显示成功 | scheme/target/`-only-testing` 不匹配；先修测试选择器 |

## 资源

- [references/layout-test-harness.md](references/layout-test-harness.md)：默认值快照/恢复、同祖先坐标、alignment rect、flipped、pre-show 测试、20 轮压力循环和只读诊断的代码骨架。
- [references/isolated-device-verification.md](references/isolated-device-verification.md)：独立 Bundle ID 副本、按 PID 取 AX、窗口区域截图、默认值改写/恢复、点击与清理命令。
- 纯几何与坐标陷阱：[appkit-layout-tdd](../appkit-layout-tdd/SKILL.md)。
- 截图、像素测量、TCC 与 Computer Use：[macos-app-ui-verification](../macos-app-ui-verification/SKILL.md)。
- 隔离副本、PID AX、`-R` 取证的完整清单：[macos-isolated-app-ui-verification](../macos-isolated-app-ui-verification/SKILL.md)。
