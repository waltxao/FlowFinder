# FlowFinder 第二轮整改 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（本会话内联执行）。
> Steps use checkbox (`- [ ]`) syntax for tracking.
> 用户未授权提交/推送，因此本计划不包含 commit 步骤。

**Goal:** 顶栏降至 36/30/18 并让红绿灯同线；工具入口回到品牌旁并以侧栏工具页呈现 5 个可用工具；第二行删除新建文件夹与齿轮，合并为唯一“显示设置”。

**Architecture:** 顶栏几何仍由 `FFTopBarMetrics`/`FFInteractionPolicy` 单点驱动；红绿灯由 MainWindowController 在布局后按内容坐标重新居中。工具页是 SidebarView 内的第二内容页，与收藏滚动容器互斥显示；工具清单由纯 `FFToolPageCatalog` 过滤/分组，便于测试。第二行只改 `PaneToolbar` 与 `FFToolbarRow2Item`，不触碰文件操作实现。

**Tech Stack:** Swift/AppKit、XCTest、FF_SELFTEST。

**Spec:** `docs/SPEC-2026-10-21-UI-ROUND2.md`

> **执行状态（2026-10-22）：** Task 1–4 全部完成。真机截图已补齐（顶栏/红绿灯 17.5pt=17.5pt、
> 合并菜单、工具页、窄侧栏胶囊换行）；桌面副本已覆盖为 0.8.0-26102202 并在最终产物上重跑自检。
> 当轮实测：XCTest 349 条 0 失败；自检 163 项 + 20 轮布局压力 0 失败。

## Global Constraints

- 顶栏 36 / 标签 30 / 非活动 26 / 空条 6 / 中线 18 / 命中 28 / 图标 16。
- 红绿灯中心距窗口内容顶 18pt；全屏隐藏红绿灯。
- 工具页不得显示当前路径或选中数量；只列 5 个可用工具。
- 新建文件夹仍可通过文件菜单、右键菜单、⇧⌘N 创建。
- 不提交、不推送；每轮同步台账与交接文档。

---

### Task 1: 顶栏几何与红绿灯对齐

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFVisualTokens.swift`
- Modify: `FlowFinder/FlowFinder/UI/FFInteractionPolicy.swift`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift`
- Modify: `FlowFinder/FlowFinder/UI/PaneTabs.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/InteractionRegressionTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFVisualTokensTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFShellLayoutTests.swift`

**Interfaces:**
- Produces: `FFTopBarMetrics.height = 36`, `.tabHeight = 30`, `.centerline = 18`.
- Produces: `MainWindowController.alignTrafficLightsToTopBar()` (internal, test-callable).
- Produces: `FFGlobalTopBar` without `toolButton`; order starts at `sidebarButton`.

- [x] **Step 1: 写失败测试（metrics / 中线 / 红绿灯）**

`InteractionRegressionTests.swift` 更新 `FFTopBarLayoutTests`：

```swift
func testTitleBandAndTabMetrics() {
    XCTAssertEqual(FFInteractionPolicy.titleBandHeight, 36)
    XCTAssertEqual(FFInteractionPolicy.activeTabHeight, 30)
    XCTAssertEqual(FFInteractionPolicy.inactiveTabHeight, 26)
    XCTAssertEqual(FFInteractionPolicy.tabTopGap, 6)
    XCTAssertEqual(FFInteractionPolicy.tabSeamFillet, 10)
    XCTAssertEqual(FFInteractionPolicy.tabInsetFromPanel, 26)
    XCTAssertEqual(FFInteractionPolicy.topBarHitSize, 28)
    XCTAssertEqual(FFInteractionPolicy.addButtonBottomInset, 4)
    XCTAssertEqual(FFInteractionPolicy.plusGlyphSize, 14)
}

func testTopBarContentSharesEighteenPointCenterline() {
    XCTAssertEqual(FFTopBarMetrics.centerline, 18, accuracy: 0.001)
    let tabCenter = FFTabStripLayout.centerFromTop(
        bandHeight: FFTopBarMetrics.height,
        itemHeight: FFTopBarMetrics.tabHeight,
        bottomInset: 0)
    XCTAssertEqual(tabCenter, 21, accuracy: 0.001)
    XCTAssertEqual(tabCenter - FFTopBarMetrics.tabContentOffset, 18, accuracy: 0.001)
    let plus = FFTabStripLayout.centerFromTop(
        bandHeight: FFTopBarMetrics.height,
        itemHeight: FFInteractionPolicy.topBarHitSize,
        bottomInset: FFInteractionPolicy.addButtonBottomInset)
    XCTAssertEqual(plus, 18, accuracy: 0.001)
}
```

`FFShellLayoutTests.swift` 更新全局顶栏顺序并新增红绿灯测试：

```swift
func testGlobalTopBarOrderAndSharedCenterline() {
    // ...创建 controller...
    let ordered: [NSView] = [bar.sidebarButton, bar.leftTabStrip,
                             bar.rightTabStrip, bar.themeButton, bar.paneModeButton]
    let minXs = ordered.map { $0.convert($0.bounds, to: bar).minX }
    XCTAssertEqual(minXs, minXs.sorted())
    for view in ordered {
        let rect = view.convert(view.bounds, to: bar)
        XCTAssertEqual(bar.bounds.height - rect.midY, 18, accuracy: 1)
    }
}

func testTrafficLightsAlignToTopBarCenterline() {
    let controller = MainWindowController(startsWithSinglePane: false,
                                          showImmediately: false,
                                          runsSelfTests: false)
    defer { controller.close() }
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    controller.alignTrafficLightsToTopBar()
    guard let window = controller.window, let content = window.contentView else { return XCTFail() }
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        guard let button = window.standardWindowButton(type) else { return XCTFail() }
        let center = button.superview!.convert(
            NSPoint(x: button.frame.midX, y: button.frame.midY), to: content)
        XCTAssertEqual(content.bounds.height - center.y, 18, accuracy: 1.5)
    }
}
```

`FFVisualTokensTests.swift`：

```swift
XCTAssertEqual(FFTopBarMetrics.height, 36)
XCTAssertEqual(FFTopBarMetrics.tabHeight, 30)
XCTAssertEqual(FFTopBarMetrics.topStrip, 6)
XCTAssertEqual(FFTopBarMetrics.centerline, 18)
```

- [x] **Step 2: 运行聚焦测试确认失败**

```bash
cd /Volumes/Iris-Data/文件管理系统/flowfinder-native/FlowFinder
xcodebuild test -project FlowFinder.xcodeproj -scheme FlowFinderTests \
  -derivedDataPath /tmp/flowfinder-xctest-derived \
  -only-testing:FlowFinderTests/FFTopBarLayoutTests \
  -only-testing:FlowFinderTests/FFShellLayoutTests/testGlobalTopBarOrderAndSharedCenterline \
  -only-testing:FlowFinderTests/FFShellLayoutTests/testTrafficLightsAlignToTopBarCenterline
```
Expected: 数值断言失败；`alignTrafficLightsToTopBar` 不存在导致编译失败。

- [x] **Step 3: 实现 metrics 与红绿灯对齐**

```swift
// FFVisualTokens.swift
static let height: CGFloat = 36
static let tabHeight: CGFloat = 30
static let topStrip: CGFloat = 6
static let centerline: CGFloat = 18

// FFInteractionPolicy.swift
static let titleBandHeight: CGFloat = 36
static let activeTabHeight: CGFloat = 30
static let inactiveTabHeight: CGFloat = 26
static let addButtonBottomInset: CGFloat = 4

// MainWindowController.swift
func alignTrafficLightsToTopBar() {
    guard let window, !window.styleMask.contains(.fullScreen),
          let content = window.contentView else { return }
    let contentTop = content.convert(NSPoint(x: 0, y: content.bounds.height), to: nil).y
    let targetCenterY = contentTop - FFTopBarMetrics.centerline
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        guard let button = window.standardWindowButton(type),
              let superview = button.superview else { continue }
        var frame = button.frame
        let centerInSuper = superview.convert(
            NSPoint(x: frame.midX, y: targetCenterY), from: nil)
        let newY = centerInSuper.y - frame.height / 2
        if abs(frame.origin.y - newY) > 0.5 {
            frame.origin.y = newY
            button.frame = frame
        }
    }
}
```

在 `handleWindowLayout()`、`windowDidBecomeKey`、`windowDidEnterFullScreen`、`windowDidExitFullScreen` 末尾调用；显示后下一拍再调用一次，避免 AppKit 重置。

- [x] **Step 4: 删除顶栏工具按钮**

`FFGlobalTopBar` 删除 `toolButton`、`onTool`、configure/action 与 layout frame；`contentStart` 基于 `sidebarButton.frame.maxX + 12`。`MainWindowController.setupUI` 删除 `topBar.onTool` 绑定。

- [x] **Step 5: 更新 WELD/AVOID/POLICY 自检常量**

`MainWindowController+Tabs.swift`：
- POLICY：36/30/26/6/28/10。
- WELD：顶栏 36、活动 30、非活动 26、空条 6、内容中线 18；活动标签内容中心断言改为 18。
- AVOID：活动标签高度 30。

- [x] **Step 6: 运行聚焦 + 全量测试**

```bash
xcodebuild test -project FlowFinder.xcodeproj -scheme FlowFinderTests \
  -derivedDataPath /tmp/flowfinder-xctest-derived
```
Expected: 全绿。

---

### Task 2: 第二行收口（删新建文件夹 + 合并显示设置）

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFToolbarPreferences.swift`
- Modify: `FlowFinder/FlowFinder/UI/PaneToolbar.swift`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFToolbarPreferencesTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFShellLayoutTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFAccessibilityTests.swift`

**Interfaces:**
- Produces: `FFToolbarRow2Item` cases `search/sort/group/viewMode` only.
- Produces: `PaneToolbar.displaySettingsButton` (the eye), label/tooltip “显示设置”.
- Removes: `PaneToolbar.viewOptionsButton`, `newFolderButton`, `paneToolbarDidClickNewFolder`.

- [x] **Step 1: 写失败测试**

```swift
// FFToolbarPreferencesTests
func testNewFolderIsNoLongerConfigurable() {
    XCTAssertFalse(FFToolbarRow2Item.allCases.map(\.rawValue).contains("newFolder"))
}

// FFShellLayoutTests
func testToolbarHasSingleDisplaySettingsEntry() {
    let toolbar = PaneToolbar(frame: .zero)
    toolbar.side = .left
    XCTAssertEqual(toolbar.displaySettingsButton.accessibilityLabel(), "显示设置")
    XCTAssertFalse(toolbar.displaySettingsButton.isHidden)
    XCTAssertNil(toolbar.viewOptionsButton, "齿轮按钮应已移除")
}

// FFAccessibilityTests 更新原断言
XCTAssertEqual(toolbar.displaySettingsButton.accessibilityLabel(), "显示设置")
```

- [x] **Step 2: 运行确认失败**

```bash
xcodebuild test ... -only-testing:FlowFinderTests/FFToolbarPreferencesTests \
  -only-testing:FlowFinderTests/FFShellLayoutTests/testToolbarHasSingleDisplaySettingsEntry
```

- [x] **Step 3: 实现**

- `FFToolbarRow2Item` 删除 `.newFolder`。
- `PaneToolbar` 删除 `newFolderButton`、`viewOptionsButton`、`newFolderClicked`、`setFolderSelectionCount`、hover hint 全段；row2 数组改为 `searchContainer, sortPopup, groupPopup, listViewButton, gridViewButton, toolsSeparator, toolsButton`。
- `toolsButton` 的 label/tooltip 改为“显示设置”；新增 `var displaySettingsButton: NSButton { toolsButton }`，删除 `viewOptionsButton` 或将其改为 alias 返回 nil（测试要求 nil）。
- `showFolderOptionsMenu` 增加第二行显示复选框：遍历 `FFToolbarRow2Item.allCases`，标题映射 搜索/排序/分组/列表 / 图标，action `toggleRow2Item`。
- 删除 `showRow2ConfigMenu`；`toggleRow2Item` 保留并用于新菜单。
- `MainWindowController.updatePaneUI` 删除 `toolbar?.setFolderSelectionCount(files.count)`；协议与实现删除 `paneToolbarDidClickNewFolder`。

- [x] **Step 4: 运行测试**

```bash
xcodebuild test ... -only-testing:FlowFinderTests/FFToolbarPreferencesTests \
  -only-testing:FlowFinderTests/FFAccessibilityTests \
  -only-testing:FlowFinderTests/FFShellLayoutTests
```

---

### Task 3: 品牌旁工具胶囊与侧栏工具页

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFIcon.swift`（wrench）
- Modify: `FlowFinder/FlowFinder/UI/FFPillButton.swift`（active/height）
- Modify: `FlowFinder/FlowFinder/UI/FFToolProtocol.swift`（`FFToolPageCatalog`）
- Modify: `FlowFinder/FlowFinder/UI/SidebarView.swift`（品牌胶囊 + 工具页）
- Reuse: `FlowFinder/FlowFinder/UI/FFToolPopoverController.swift`（`FFToolRowView`）
- Test: `FlowFinder/Tests/FlowFinderTests/InteractionRegressionTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFShellLayoutTests.swift`

**Interfaces:**
- Produces: `FFToolPageCatalog.tools(for:) -> [(FFTool, FFToolAvailability)]`，过滤 AI 后固定 5 个。
- Produces: `SidebarView.showToolsPage()`, `hideToolsPage()`, `isToolPageVisible`, `toolPageToolCountForTesting`, `toolPillForTesting`.
- Produces: `FFPillButton.isSelected` 与 `init(title:icon:height:)`.

- [x] **Step 1: 写失败测试**

```swift
final class FFToolPageCatalogTests: XCTestCase {
    private func context(path: String, selection: [FileEntry]) -> FFToolContext {
        FFToolContext(activePane: .left, currentPath: path,
                      selection: selection, window: nil)
    }
    func testCatalogHasFiveToolsAndNoAI() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        let tools = FFToolPageCatalog.tools(for: context(path: "/tmp", selection: []))
        XCTAssertEqual(tools.map { $0.0.title },
                       ["重复文件扫描", "批量重命名", "任务中心", "设置", "关于"])
        XCTAssertFalse(tools.contains { ["ai-tag", "ai-organize"].contains($0.0.id) })
    }
    func testAvailabilityFollowsContext() {
        let tools = FFToolPageCatalog.tools(for: context(path: "", selection: []))
        XCTAssertEqual(tools.first { $0.0.id == "duplicate-scan" }?.1, .needsFolder)
        XCTAssertEqual(tools.first { $0.0.id == "batch-rename" }?.1, .needsSelection)
    }
}
```

`FFShellLayoutTests`：

```swift
func testSidebarToolPageShowsFiveToolsAndTogglesBack() {
    let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 220, height: 600))
    sidebar.toolContextProvider = {
        FFToolContext(activePane: .left, currentPath: "/tmp", selection: [], window: nil)
    }
    sidebar.layoutSubtreeIfNeeded()
    sidebar.showToolsPage()
    XCTAssertTrue(sidebar.isToolPageVisible)
    XCTAssertEqual(sidebar.toolPageToolCountForTesting, 5)
    XCTAssertEqual(sidebar.toolPillForTesting?.isSelected, true)
    sidebar.hideToolsPage()
    XCTAssertFalse(sidebar.isToolPageVisible)
}
```

- [x] **Step 2: 运行确认失败**

```bash
xcodebuild test ... -only-testing:FlowFinderTests/FFToolPageCatalogTests \
  -only-testing:FlowFinderTests/FFShellLayoutTests/testSidebarToolPageShowsFiveToolsAndTogglesBack
```

- [x] **Step 3: 实现 catalog**

```swift
enum FFToolPageCatalog {
    static let hiddenToolIDs: Set<String> = ["ai-tag", "ai-organize"]
    static func tools(for context: FFToolContext) -> [(FFTool, FFToolAvailability)] {
        FFToolRegistry.shared.availableTools(for: context)
            .filter { !hiddenToolIDs.contains($0.0.id) }
    }
    static func grouped(for context: FFToolContext)
        -> [(FFToolGroup, [(FFTool, FFToolAvailability)])] {
        FFToolGroup.allCases.compactMap { group in
            let rows = tools(for: context).filter { $0.0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }
}
```

- [x] **Step 4: 实现品牌胶囊与工具页**

`FFPillButton` 增加：
```swift
var isSelected = false { didSet { needsDisplay = true } }
init(title: String, icon: FFIconName, height: CGFloat = 20) { ... heightAnchor = height ... }
// draw(): isSelected ? accent 0.18 + accent text : existing
```

`SidebarView`：
- Brand 增加 `toolPill = FFPillButton(title:"工具", icon:.wrench, height:24)`，constrained trailing；宽/窄两套约束在 `layout()` 切换（≥200：名称行；<200：版本行）。
- brandView 高度改为 44，避免窄模式胶囊溢出。
- 新增 `SidebarToolPageView`（同文件私有类）：标题“工具”+“返回收藏”，`NSScrollView` 内纵向 stack；用 `FFToolPageCatalog.grouped(for:)` 生成组标题和 `FFToolRowView`；点击可用行 `tool.run(in:context)`，然后 `onRun?()`。
- `showToolsPage()`：`toolPage.reload(context:)`；隐藏 `sidebarScrollView`；显示工具页；`toolPill.isSelected = true`。
- `hideToolsPage()`：反向；`onBack/onRun` 调用。
- 工具页 constraints 与 sidebarScrollView 相同（brand.bottom+4、左右 0、bottom -8）。
- 顶栏工具删除后，`presentToolsPopover(from:)` 可保留但不调用；不再创建 popover。

- [x] **Step 5: 更新测试与自检**

- `FFGlobalTopBar` 顺序测试移除 toolButton。
- 新增 `testWrenchIconResolves`（FFIconFoundationTests）。
- 侧栏工具页 catalog/UI 测试全绿。
- 自检不新增计数；如新增检查，更新台账/HANDOVER 的 164。

- [x] **Step 6: 运行聚焦 + 全量测试**

```bash
xcodebuild test ... -only-testing:FlowFinderTests/FFToolPageCatalogTests \
  -only-testing:FlowFinderTests/FFShellLayoutTests \
  -only-testing:FlowFinderTests/FFIconFoundationTests
```

---

### Task 4: 构建、真机验证与文档收口

**Files:**
- Modify: `docs/REQUIREMENTS-LEDGER.md`
- Modify: `docs/HANDOVER.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/SPEC-2026-10-21-UI-ROUND2.md`（状态/验证）
- Modify: `docs/PLAN-2026-10-21-UI-ROUND2.md`（完成记录）

- [x] **Step 1: 全量构建与测试**

```bash
cd /Volumes/Iris-Data/文件管理系统/flowfinder-native
make build
cd FlowFinder
xcodebuild test -project FlowFinder.xcodeproj -scheme FlowFinderTests \
  -derivedDataPath /tmp/flowfinder-xctest-derived
```

- [x] **Step 2: 应用内自检**

```bash
rm -f /tmp/ff-debug.log
APP="$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder"
FF_SELFTEST=1 "$APP" &
sleep 9
pkill -f "$APP"   # 仅杀本进程路径
grep -E "FAIL|自检.*通过|布局压力" /tmp/ff-debug.log
```

- [x] **Step 3: 真机截图**

- 1400 双栏：红绿灯/侧栏开关/标签同线，工具按钮已从顶栏消失。
- 隐藏侧栏：标签组从侧栏开关后开始，面板顶边比旧版高 8pt。
- 点品牌旁“工具”：侧栏切工具页，5 行；返回收藏。
- 第二行：无新建文件夹、无齿轮；显示设置菜单包含显示项/第二行/列。
- 1060 单栏、全屏、浅/深色至少各一张。

- [x] **Step 4: 同步文档并报告未验项**

- 台账 R-19 追加本轮；HANDOVER §1.10；CHANGELOG 未发版。
- 记录：XCTest 数量、自检数量、截图路径、未复现/未验项。
- 不提交、不推送。桌面副本是否覆盖由用户确认。
