# FlowFinder UI/UX 全界面精修 Implementation Plan

> **实施状态：** Task 1–7 已完成（2026-10-21）；P-01 面板圆角回归修复已追加。XCTest 282 条 0 失败；自检 135 项 0 失败；浅/深色真机走查通过。全部改动留在工作区，未提交、未推送。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把全应用收敛到同一套连续曲率、层级半径和卡片语言：主窗口 12/12/8/6，详情栏紧凑自适应，工具/搜索/查重/辅助窗口统一，修复冲突默认与命中尺寸。

**Architecture:** 在现有双面板、区内详情、工具协议和任务服务上做视觉/布局精修；不改 Rust、不改双栏/标签拖拽。先落圆角 token 与连续曲率，再修详情栏，随后逐个窗口收敛；每个任务独立可构建、可测试。

**Tech Stack:** Swift / AppKit / Combine / UserDefaults / XCTest；macOS 12+。

**Spec:** `docs/SPEC-2026-10-21-UIUX-POLISH.md`

## Global Constraints

- 圆角：窗口 12、操作面板 12、详情 8、控件 6；全部 `.continuous`。
- 间距：4/8/12/16/24；窗口内容边距 16，面板内边距 8。
- 双操作区、两行工具栏、区内 54pt 详情栏保留；不恢复旧版粉色发光。
- 冲突弹窗默认“跳过”；替换是危险色且放最后。
- 标签关闭视觉 20、命中 24；侧栏最小 180。
- 状态：空/加载/错误必须有明确下一步；颜色不是唯一信号。
- **不 commit、不 push、不发版**；所有改动留在工作区。

---

## File Structure

| 文件 | 职责 | 任务 |
|---|---|---|
| `UI/FFVisualTokens.swift` | 半径/间距/字号 token；`details` 半径 | 1 |
| `UI/SquircleView.swift` | 面板连续曲率圆角 | 1 |
| `UI/FFGlassView.swift` | 浮层连续曲率圆角 | 1 |
| `UI/FFComponents.swift` | `FFPaneGlow` 使用 12 半径阴影 | 1 |
| `UI/FFDetailsLayout.swift`（新建） | 详情列数、最大高度、图标尺寸策略 | 2 |
| `UI/ExpandableDetailsBar.swift` | 紧凑底部 inspector、图标可变、信息自适应 | 2 |
| `UI/SettingsWindowController.swift` | 详情预览大小滑块 | 2 |
| `UI/FFToolProtocol.swift` / `FFToolRegistry.swift` / `FFToolPopoverController.swift` | 工具分组、标题不写左右面板 | 3 |
| `UI/SearchPanelController.swift` | 中心空态 + 构建索引 CTA | 4 |
| `UI/DuplicateScanWindowController.swift` | 条件/结果/预览/动作四段 | 5 |
| `UI/ConflictResolver.swift` | 跳过默认、危险色、按钮顺序 | 6 |
| `UI/PaneTabs.swift` | 关闭命中 24 | 6 |
| `UI/MainWindowController.swift` | 侧栏最小 180、窗口/面板圆角 | 1/6 |
| `UI/BatchRenameWindowController.swift` | token 统一（不重排） | 6 |
| `Tests/FlowFinderTests/*` | 策略/结构/集成测试 | 1–7 |
| `docs/` | 规格、计划、台账、CHANGELOG、HANDOVER | 7 |

---

### Task 1: 圆角 token 与连续曲率

**Files:**
- Modify: `FlowFinder/UI/FFVisualTokens.swift`
- Modify: `FlowFinder/UI/SquircleView.swift`
- Modify: `FlowFinder/UI/FFGlassView.swift`
- Modify: `FlowFinder/UI/FFComponents.swift`
- Modify: `FlowFinder/UI/MainWindowController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFRadiusTokensTests.swift`

**Interfaces:**
- Produces: `FFVisualTokens.Radius.details = 8`, `panel = 12`, `window = 12`, `card = 8`, `control = 6`.
- Produces: `FFGlassView.cornerCurve: CALayerCornerCurve`（默认 `.continuous`）。

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFRadiusTokensTests: XCTestCase {
    func testHierarchyRadii() {
        XCTAssertEqual(FFVisualTokens.Radius.window, 12)
        XCTAssertEqual(FFVisualTokens.Radius.panel, 12)
        XCTAssertEqual(FFVisualTokens.Radius.details, 8)
        XCTAssertEqual(FFVisualTokens.Radius.card, 8)
        XCTAssertEqual(FFVisualTokens.Radius.control, 6)
    }

    func testPaneUsesPanelRadius() {
        let pane = SquircleView(cornerRadius: FFVisualTokens.Radius.panel)
        pane.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        pane.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.layer?.cornerRadius, 12)
        XCTAssertEqual(pane.layer?.cornerCurve, .continuous)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，`Radius.details` 不存在/`cornerCurve` 为 `.circular`。

- [ ] **Step 3: 实现**

1. `FFVisualTokens.Radius` 改为：

```swift
static let control: CGFloat = 6
static let card: CGFloat = 8
static let details: CGFloat = 8
static let panel: CGFloat = 12
static let window: CGFloat = 12
```

2. `SquircleView.applySquircleMask()` 在设置 `layer?.cornerRadius` 后加：

```swift
layer?.cornerCurve = .continuous
```

3. `FFGlassView` 增加：

```swift
var cornerCurve: CALayerCornerCurve = .continuous
```

并在所有设置 `layer?.cornerRadius` / `glassView.cornerRadius` / `visualEffect.layer?.cornerRadius` 的位置同步设置 `cornerCurve`。

4. `MainWindowController` 面板容器：

```swift
let container = SquircleView(cornerRadius: FFVisualTokens.Radius.panel,
                             squircleFactor: 5.0,
                             autoUpdateMask: true)
```

5. `ExpandableDetailsBar` 外层/玻璃背景使用 `FFVisualTokens.Radius.details`，并设置 `.continuous`。

6. `FFPaneGlow.updateShadowPath` 的圆角从 16 改为 `FFVisualTokens.Radius.panel`；`inset` 仍为 8。

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS。

- [ ] **Step 5: 构建/截图检查**

Run `make -C flowfinder-native build`；截图确认窗口/面板/详情三层圆角连续、无内层大于外层。**不 commit。**

---

### Task 2: 详情栏紧凑布局、图标滑块与自适应信息

**Files:**
- Create: `FlowFinder/UI/FFDetailsLayout.swift`
- Modify: `FlowFinder/UI/ExpandableDetailsBar.swift`
- Modify: `FlowFinder/UI/SettingsWindowController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFDetailsLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum FFDetailsLayoutPolicy { static func columns(forWidth:) -> Int; static func maxExpandedHeight(forPaneHeight:) -> CGFloat; static func clampedIconSize(_:) -> CGFloat }`
  - `FFUserDefaultsKeys.detailsPreviewSize`（Double，48–96）
  - `ExpandableDetailsBar.previewIconSize: CGFloat`
  - `ExpandableDetailsBar.applyPreviewIconSize(_:)`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import FlowFinder

final class FFDetailsLayoutTests: XCTestCase {
    func testColumnsSwitchAt480() {
        XCTAssertEqual(FFDetailsLayoutPolicy.columns(forWidth: 479), 1)
        XCTAssertEqual(FFDetailsLayoutPolicy.columns(forWidth: 480), 2)
        XCTAssertEqual(FFDetailsLayoutPolicy.columns(forWidth: 800), 2)
    }

    func testExpandedHeightClamp() {
        XCTAssertEqual(FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight: 200), 120)
        XCTAssertEqual(FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight: 800), 260)
    }

    func testIconSizeClamp() {
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(40), 48)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(64), 64)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(120), 96)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，类型不存在。

- [ ] **Step 3: 实现布局策略**

```swift
enum FFDetailsLayoutPolicy {
    static func columns(forWidth width: CGFloat) -> Int {
        width < 480 ? 1 : 2
    }

    static func maxExpandedHeight(forPaneHeight height: CGFloat) -> CGFloat {
        min(260, max(120, height * 0.45))
    }

    static func clampedIconSize(_ value: CGFloat) -> CGFloat {
        min(96, max(48, value))
    }
}
```

- [ ] **Step 4: 详情栏改为紧凑 inspector**

1. 收起态保持 54pt；展开高度取 `FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight:)`，内容超出时放入可滚动容器，不再无限增高。
2. 图标区宽度由 `previewIconSize` 驱动，默认 64；`bigIconView` 约束改为可更新常量，不再固定 110。
3. 信息区改为自适应网格：
   - `columns(forWidth:) == 1`：单列，路径一行省略，标签最多两行；
   - `== 2`：两列，字段按“名称/类型/大小/日期/位置/标签/说明”顺序排布。
4. 路径使用 `lineBreakMode = .byTruncatingMiddle` + `toolTip` 完整路径；不再按单词硬折行。
5. 展开/收起、窗口宽度、面板宽度变化时重新计算列数与高度；不重建 metadata provider。
6. 设置 > 外观新增“详情预览大小”滑块 48–96，默认 64，写入 `FFUserDefaultsKeys.detailsPreviewSize`；左右详情栏监听变化并 `applyPreviewIconSize`。

- [ ] **Step 5: 测试/构建**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS（新增 3 条）。
Run `make -C flowfinder-native build`；选中长文件名/长路径、视频、文件夹，确认图标随滑块变化、路径省略、内容不溢出。**不 commit。**

---

### Task 3: 工具浮层分组与上下文

**Files:**
- Modify: `FlowFinder/UI/FFToolProtocol.swift`
- Modify: `FlowFinder/UI/FFToolRegistry.swift`
- Modify: `FlowFinder/UI/FFToolPopoverController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFToolRegistryTests.swift`

**Interfaces:**
- Produces:
  - `enum FFToolGroup: Int, CaseIterable { case organize, task, system }`
  - `protocol FFTool` 增加 `var group: FFToolGroup { get }`
  - `FFToolPopoverController.titleForTesting: String`

- [ ] **Step 1: 写失败测试**

```swift
func testToolsAreGroupedAndTitleOmitsPaneSide() {
    let context = FFToolContext(activePane: .right, currentPath: "/tmp", selection: [], window: nil)
    let controller = FFToolPopoverController(context: context)
    controller.loadViewIfNeeded()
    XCTAssertEqual(controller.titleForTesting, "工具")
    XCTAssertFalse(controller.titleForTesting.contains("右面板"))
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，`group`/`titleForTesting` 不存在。

- [ ] **Step 3: 实现**

1. `FFToolProtocol` 增加：

```swift
enum FFToolGroup: Int, CaseIterable {
    case organize, task, system
}
protocol FFTool {
    // existing...
    var group: FFToolGroup { get }
}
extension FFTool {
    var group: FFToolGroup { .organize }
}
```

2. 内置工具分组：重复/批量 `.organize`，任务中心 `.task`，AI/设置/关于 `.system`。
3. `FFToolPopoverController` 标题固定“工具”，副标题只显示路径 + 选择摘要；按 `FFToolGroup` 分区，行高 32、图标 16、禁用原因右侧。
4. 工具行内提示上下文：例如批量重命名显示“作用于当前选择”，未选中显示“先选择文件”；不写“左面板/右面板”。

- [ ] **Step 4: 跑测试/构建**

Run `make -C flowfinder-native swift-test 2>&1 | tail -20`；Expected PASS。
Run `make -C flowfinder-native build`；真机打开浮层确认分组/上下文/禁用项。**不 commit。**

---

### Task 4: 搜索中心空态

**Files:**
- Modify: `FlowFinder/UI/SearchPanelController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFSearchEmptyStateTests.swift`

**Interfaces:**
- Produces:
  - `SearchPanelController.isEmptyStateForTesting: Bool`
  - `SearchPanelController.emptyStatePrimaryTitleForTesting: String`

- [ ] **Step 1: 写失败测试**

```swift
func testSearchWithoutResultsShowsCenteredEmptyState() {
    let controller = SearchPanelController.shared
    controller.showPanel(initialQuery: "", searchPath: "/tmp")
    XCTAssertTrue(controller.isEmptyStateForTesting)
    XCTAssertEqual(controller.emptyStatePrimaryTitleForTesting, "构建内容索引")
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，属性不存在。

- [ ] **Step 3: 实现**

1. 新建/内嵌 `FFSearchEmptyStateView`：图标、标题“搜索这台 Mac”、说明、主按钮“构建内容索引”、次按钮“只搜索文件名”。
2. 当 `currentQuery` 为空且无结果时显示在结果区中央；隐藏原右上角“构建索引”按钮。
3. 左侧筛选合并为一张卡片；顶部保留 28pt 搜索框与范围 chip。
4. 主按钮调用现有 `buildContentIndex` 路径；次按钮保持当前目录搜索。
5. 结果出现后隐藏空态，恢复表格。

- [ ] **Step 4: 跑测试/构建**

Run `make -C flowfinder-native swift-test 2>&1 | tail -20`；Expected PASS。
Run `make -C flowfinder-native build`；截图搜索空态/有结果两态。**不 commit。**

---

### Task 5: 查重四段式

**Files:**
- Modify: `FlowFinder/UI/DuplicateScanWindowController.swift`
- Modify: `FlowFinder/UI/DuplicateGroupView.swift`（如需）
- Test: `FlowFinder/Tests/FlowFinderTests/FFDuplicateLayoutTests.swift`

**Interfaces:**
- Produces:
  - `DuplicateScanWindowController.isEmptyStateForTesting: Bool`
  - `DuplicateScanWindowController.primaryActionTitleForTesting: String`

- [ ] **Step 1: 写失败测试**

```swift
func testDuplicateWindowShowsFourSectionEmptyState() {
    let controller = DuplicateScanWindowController.shared
    controller.showWindow(scanPath: "/tmp")
    XCTAssertTrue(controller.isEmptyStateForTesting)
    XCTAssertEqual(controller.primaryActionTitleForTesting, "开始扫描")
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，属性不存在。

- [ ] **Step 3: 实现四段**

1. 顶部条件卡片：路径 + 浏览、扫描方式、文件类型、最小大小；开始/停止按钮放同一行。
2. 结果区：空态图标 + “还没有扫描结果” + 主按钮“开始扫描”；扫描后显示分组列表。
3. 右侧预览卡片：空态说明；选中组后显示文件/大小/保留项。
4. 底部动作栏：组数/文件数、可释放空间、“选择重复项”“取消选择”“确认删除”（危险色；零选中禁用）。
5. 保持安全默认：扫描结果零勾选；永久删除二次确认文案不变。

- [ ] **Step 4: 跑测试/构建**

Run `make -C flowfinder-native swift-test 2>&1 | tail -20`；Expected PASS。
Run `make -C flowfinder-native build`；用含重复文件的临时目录截图空态/结果/选中态。**不 commit。**

---

### Task 6: 辅助窗口、冲突默认、标签命中与侧栏

**Files:**
- Modify: `FlowFinder/UI/ConflictResolver.swift`
- Modify: `FlowFinder/UI/PaneTabs.swift`
- Modify: `FlowFinder/UI/MainWindowController.swift`
- Modify: `FlowFinder/UI/BatchRenameWindowController.swift`
- Modify: `FlowFinder/UI/SettingsWindowController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFConflictPolicyTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFShellLayoutTests.swift`

**Interfaces:**
- Produces:
  - `FFConflictPolicy.buttonOrder: [ConflictResolution] = [.skip, .keepBoth, .replace]`
  - `FFTabMetrics.closeHitSize: CGFloat = 24`
  - `MainWindowController.sidebarMinWidth` 180

- [ ] **Step 1: 写失败测试**

```swift
func testConflictDefaultIsSkipAndReplaceIsLast() {
    XCTAssertEqual(FFConflictPolicy.buttonOrder.first, .skip)
    XCTAssertEqual(FFConflictPolicy.buttonOrder.last, .replace)
}
func testTabCloseHitTargetIs24() {
    XCTAssertGreaterThanOrEqual(FFTabMetrics.closeHitSize, 24)
}
func testSidebarMinimumIs180() {
    XCTAssertGreaterThanOrEqual(MainWindowController.sidebarMinWidth, 180)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，顺序/常量不存在或值不符。

- [ ] **Step 3: 实现**

1. `ConflictResolver` 按钮顺序改为 跳过 / 保留两者 / 替换…；`alert.buttons[0]` 映射 `.skip`；替换按钮 `hasDestructiveAction = true`（或红色 bezel）。`FFConflictPolicy.buttonOrder` 与映射共用。
2. `PaneTabs` 关闭按钮视觉 20×20，外层命中 24×24（透明容器或 `hitTest` 扩展），保持可聚焦/可访问标签。
3. `MainWindowController.sidebarMinWidth = 180`；默认宽度仍 220；恢复记忆值时低于 180 回退默认。
4. 批量重命名/设置只替换为 `FFVisualTokens` 的 12/8/6、16pt 内边距和系统字号；不改结构。

- [ ] **Step 4: 跑测试/构建**

Run `make -C flowfinder-native swift-test 2>&1 | tail -20`；Expected PASS。
Run `make -C flowfinder-native build`；截图冲突弹窗、标签关闭、160/180 侧栏。**不 commit。**

---

### Task 7: 深色/高对比/可访问性与文档

**Files:**
- Modify: `FlowFinder/UI/FFVisualTokens.swift`（如需对比度修正）
- Modify: `docs/HANDOVER.md`
- Modify: `docs/REQUIREMENTS-LEDGER.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/SPEC-2026-10-21-UIUX-POLISH.md`

- [ ] **Step 1: 深色/高对比验收**

启动应用，切换浅色/深色、高对比、Reduce Motion；逐屏截图主窗口、详情、工具、搜索、查重、设置、冲突弹窗：
- 正文对比度 ≥4.5:1；分隔线/选中态可见；
- 无布局跳动；详情展开/收起不遮关键内容；
- Reduce Motion 下无长动画/弹跳。

- [ ] **Step 2: 可访问性**

- 图标按钮 accessibilityLabel 非空；
- 标签关闭、工具行、详情按钮可键盘到达；
- 焦点顺序=视觉顺序；焦点环 2px；
- 目标 ≥24pt（桌面）。

- [ ] **Step 3: 全量测试**

```bash
make -C flowfinder-native swift-test 2>&1 | tail -20
make -C flowfinder-native build
pkill -f "MacOS/FlowFinder" || true
FF_SELFTEST=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" &
sleep 12
pkill -f "MacOS/FlowFinder" || true
grep -c "FAIL" /tmp/ff-debug.log
```

Expected: XCTest 0 失败；BUILD SUCCEEDED；自检 0 FAIL。

- [ ] **Step 4: 文档（不提交）**

- `HANDOVER.md` 新增“2026-10-21 UI/UX 精修”章节；
- `REQUIREMENTS-LEDGER.md` 新增 R-17，逐条引用 U-01..U-13；
- `CHANGELOG.md` 未发版段记录圆角/详情/工具/搜索/查重/冲突默认；
- 规格状态改为“已实现/已验证（未提交）”。
- **不 commit、不 push。**

---

## Self-Review

**Spec coverage:**
- U-01/U-02 → Task 1。
- U-03/U-04 → Task 2。
- U-05 → Task 3。
- U-06 → Task 4。
- U-07 → Task 5。
- U-08 → Task 6/7。
- U-09 → Task 6。
- U-10/U-11 → Task 6。
- U-12 → Task 1（阴影半径/颜色）。
- U-13 → Task 7。

**Placeholder scan:** 无 TBD/TODO；每个任务有测试、实现、命令、预期。

**Type consistency:**
- `FFDetailsLayoutPolicy` Task 2 定义并使用。
- `FFToolGroup` Task 3 定义并用于内置工具。
- `FFConflictPolicy.buttonOrder` Task 6 定义并用于 `ConflictResolver`。
- `FFTabMetrics.closeHitSize` Task 6 定义并用于 `PaneTabs`。
- `MainWindowController.sidebarMinWidth` 在 Task 6 修改，现有引用自动跟随。
