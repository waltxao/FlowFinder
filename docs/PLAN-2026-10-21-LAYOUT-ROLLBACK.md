# FlowFinder 双操作区结构回归与三边微光 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 恢复“每侧两行工具栏 + 操作区内 54pt 详情栏 + 无全局底栏”的双操作区结构，同时保留无发光视觉、单一强调色与现有性能/任务/工具改造，并加入三边下亮上隐的微光。

**Architecture:** 外科式重接，不用 `git checkout` 整体回退。以 HEAD `732a5f4` 为视觉参考，在当前 `PaneStore`/`MetadataService`/`TaskService`/`ToolRegistry` 架构上恢复旧布局；旧的同步媒体读取不恢复，统一走异步元数据。强调色收敛到 `FFAccent` 单一来源，微光用单层渐变/形状实现，不恢复 14 层绘制。

**Tech Stack:** Swift / AppKit / Combine / UserDefaults / XCTest；Rust core 与 FFI 协议不动。

**Spec:** `docs/SPEC-2026-10-21-LAYOUT-ROLLBACK.md`

## Global Constraints

- 部署目标 macOS 12.0；不引入第三方 UI 框架。
- 双操作区：每侧 72pt 两行工具栏 + 54pt 操作区内详情栏；移除全局 28px 底栏。
- 活动面板微光：只左/右/下，顶部不发光；blur 9px、opacity 0.50、fadeStart 0.42；颜色 `FFAccent.current`。
- 强调色唯一来源：`FFAccent.current`；旧 `accent_color` 只迁移清理一次，之后仍可在设置中改。
- 详情栏元数据全部异步；禁止主线程同步 PDF/AV/SMB/目录读取。
- 保留原生标签、标签拖拽、工具上下文浮层、任务中心、安全默认与现有性能改造。
- **不提交 commit、不推送、不发版**；所有改动留在工作区，由用户决定提交。
- TDD：每个任务先写失败测试，再实现，再跑 `make swift-test`；最后跑 `make build` 与 `FF_SELFTEST=1`。

---

## File Structure

| 文件 | 职责 | 任务 |
|---|---|---|
| `FlowFinder/UI/FFCommon.swift` | `FFAccent` 单一来源、迁移、hex 解析 | 1 |
| `FlowFinder/UI/FFToolbarPreferences.swift`（新建） | 第二行显示项、持久化、纯策略 | 2 |
| `FlowFinder/UI/FFGlowSpec.swift`（新建） | 三边微光参数与 alpha 曲线 | 2 |
| `FlowFinder/UI/PaneToolbar.swift` | 恢复 72pt 两行；搜索回 row2；配置齿轮 | 3 |
| `FlowFinder/UI/MainWindowController.swift` | 移除全局底栏；显示区内详情；⌘I 展开；底部约束 | 4/5 |
| `FlowFinder/UI/ExpandableDetailsBar.swift` | 恢复 54pt 浮层；异步元数据；取消同步媒体 | 4/5 |
| `FlowFinder/UI/FFDetailsPopoverController.swift` | 退役（删除） | 5/8 |
| `FlowFinder/UI/FFStatusBarView.swift` / `FFStatusBarText.swift` | 退役（删除） | 8 |
| `FlowFinder/UI/FFComponents.swift` | 活动面板顶边 + 三边微光接入 | 6 |
| `FlowFinder/UI/FileListView.swift` / `FileGridView.swift` | 选中色统一到 FFAccent | 7 |
| `FlowFinder/UI/PaneTabs.swift` / `BreadcrumbBar.swift` / `FFDragOverlay.swift` | 强调色统一 | 7 |
| `FlowFinder/Tests/FlowFinderTests/*` | 新增/改写测试 | 1–8 |
| `FlowFinder/FlowFinder.xcodeproj/project.pbxproj` | 新文件/退役文件登记 | 2/8 |
| `docs/` | 规格、计划、台账、CHANGELOG、HANDOVER | 8 |

---

### Task 1: 强调色单一来源与一次性迁移

**Files:**
- Modify: `FlowFinder/UI/FFCommon.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFAccentSourceTests.swift`（新建）

**Interfaces:**
- Produces:
  - `FFAccent.unifiedMigrationKey: String`
  - `FFAccent.systemHex: String`
  - `FFAccent.color(forStoredHex:) -> NSColor`
  - `FFAccent.resolvedHex(forStoredHex:) -> String`
  - `FFAccent.migrateToUnifiedAccent(defaults: UserDefaults = .standard)`
- Consumes: existing `NSColor.ffHexString`、`NSColor(hex:)`。

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFAccentSourceTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "FFAccentSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testMigrationClearsLegacyAccentOnce() {
        let defaults = suite()
        defaults.set("#ff375f", forKey: FFAccent.storageKey)

        FFAccent.migrateToUnifiedAccent(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: FFAccent.storageKey))
        XCTAssertTrue(defaults.bool(forKey: FFAccent.unifiedMigrationKey))

        defaults.set("#bf5af2", forKey: FFAccent.storageKey)
        FFAccent.migrateToUnifiedAccent(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: FFAccent.storageKey), "#bf5af2")
    }

    func testResolvedHexFallsBackToSystemAccent() {
        let hex = FFAccent.resolvedHex(forStoredHex: nil)
        XCTAssertEqual(hex, FFAccent.systemHex)
        XCTAssertEqual(FFAccent.resolvedHex(forStoredHex: "#bf5af2"), "#bf5af2")
    }

    func testCustomColorIsParsed() {
        let color = FFAccent.color(forStoredHex: "#ff375f")
        XCTAssertEqual(color.ffHexString, "ff375f")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，`FFAccent.unifiedMigrationKey`/`systemHex`/`migrateToUnifiedAccent` 不存在。

- [ ] **Step 3: 实现最小代码**

在 `FFAccent` 中加入：

```swift
static let unifiedMigrationKey = "accent_unified_migration_v1"

static var systemHex: String {
    "#" + NSColor.controlAccentColor.ffHexString
}

static func color(forStoredHex hex: String?) -> NSColor {
    guard let hex, let color = NSColor(hex: hex) else {
        return .controlAccentColor
    }
    return color
}

static func resolvedHex(forStoredHex hex: String?) -> String {
    hex ?? systemHex
}

static func migrateToUnifiedAccent(defaults: UserDefaults = .standard) {
    guard !defaults.bool(forKey: unifiedMigrationKey) else { return }
    defaults.removeObject(forKey: storageKey)
    defaults.set(true, forKey: unifiedMigrationKey)
}
```

把 `current` / `currentHex` 改为调用上述函数；保留 `defaultHex`（标签色板仍引用）但不再作为当前强调色来源。

在 `AppDelegate.applicationDidFinishLaunching` 最早处调用：

```swift
FFAccent.migrateToUnifiedAccent()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS。

- [ ] **Step 5: 构建与记录**

Run: `make -C flowfinder-native build`
Expected: BUILD SUCCEEDED。**不要 commit。**

---

### Task 2: 第二行显示策略与微光参数（纯函数）

**Files:**
- Create: `FlowFinder/UI/FFToolbarPreferences.swift`
- Create: `FlowFinder/UI/FFGlowSpec.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFToolbarPreferencesTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFGlowSpecTests.swift`
- Modify: `FlowFinder/FlowFinder.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  - `enum FFToolbarRow2Item: String, CaseIterable { case search, sort, group, viewMode, newFolder }`
  - `enum FFToolbarRow2Preferences { static let storageKey; static let defaultItems; static func visibleItems(from:) -> Set<FFToolbarRow2Item>; static func encode(_:) -> String; static func toggled(_:in:) -> Set<...> }`
  - `struct FFGlowSpec { let blurRadius; let opacity; let fadeStart; static let standard; func alpha(atNormalizedY:) -> CGFloat }`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import FlowFinder

final class FFToolbarPreferencesTests: XCTestCase {
    func testDefaultIsEveryItem() {
        XCTAssertEqual(FFToolbarRow2Preferences.visibleItems(from: nil),
                       Set(FFToolbarRow2Item.allCases))
    }

    func testUnknownAndDuplicatesAreIgnored() {
        let items = FFToolbarRow2Preferences.visibleItems(from: "search,sort,unknown,search")
        XCTAssertEqual(items, [.search, .sort])
    }

    func testRoundTripAndToggle() {
        var items = FFToolbarRow2Preferences.defaultItems
        items = FFToolbarRow2Preferences.toggled(.search, in: items)
        XCTAssertFalse(items.contains(.search))
        XCTAssertEqual(FFToolbarRow2Preferences.visibleItems(
            from: FFToolbarRow2Preferences.encode(items)), items)
    }
}
```

```swift
import XCTest
@testable import FlowFinder

final class FFGlowSpecTests: XCTestCase {
    func testStandardValues() {
        XCTAssertEqual(FFGlowSpec.standard.blurRadius, 9)
        XCTAssertEqual(FFGlowSpec.standard.opacity, 0.50)
        XCTAssertEqual(FFGlowSpec.standard.fadeStart, 0.42)
    }

    func testBottomIsOpaqueAndTopIsInvisible() {
        XCTAssertEqual(FFGlowSpec.standard.alpha(atNormalizedY: 0), 0.50, accuracy: 0.001)
        XCTAssertEqual(FFGlowSpec.standard.alpha(atNormalizedY: 0.42), 0.50, accuracy: 0.001)
        XCTAssertEqual(FFGlowSpec.standard.alpha(atNormalizedY: 1), 0, accuracy: 0.001)
    }

    func testMidFadeIsBetween() {
        let alpha = FFGlowSpec.standard.alpha(atNormalizedY: 0.71)
        XCTAssertGreaterThan(alpha, 0)
        XCTAssertLessThan(alpha, 0.50)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，类型不存在。

- [ ] **Step 3: 实现**

```swift
enum FFToolbarRow2Item: String, CaseIterable, Hashable {
    case search, sort, group, viewMode, newFolder
}

enum FFToolbarRow2Preferences {
    static let storageKey = "toolbar_row2_items"
    static let defaultItems = Set(FFToolbarRow2Item.allCases)

    static func visibleItems(from raw: String?) -> Set<FFToolbarRow2Item> {
        guard let raw else { return defaultItems }
        return Set(raw.split(separator: ",").compactMap {
            FFToolbarRow2Item(rawValue: String($0))
        })
    }

    static func encode(_ items: Set<FFToolbarRow2Item>) -> String {
        items.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func toggled(_ item: FFToolbarRow2Item,
                        in items: Set<FFToolbarRow2Item>) -> Set<FFToolbarRow2Item> {
        items.contains(item) ? items.subtracting([item]) : items.union([item])
    }
}
```

```swift
struct FFGlowSpec: Equatable {
    let blurRadius: CGFloat
    let opacity: CGFloat
    let fadeStart: CGFloat

    static let standard = FFGlowSpec(blurRadius: 9, opacity: 0.50, fadeStart: 0.42)

    /// y=0 底部，y=1 顶部。
    func alpha(atNormalizedY y: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, y))
        guard clamped > fadeStart else { return opacity }
        let t = (clamped - fadeStart) / (1 - fadeStart)
        return opacity * (1 - t)
    }
}
```

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS（新增 6 条）。

- [ ] **Step 5: 登记文件并构建**

把两个新源文件与两个测试文件加入 `project.pbxproj`（UI group / Tests group / Sources phase）。Run `make -C flowfinder-native build`；Expected BUILD SUCCEEDED。**不要 commit。**

---

### Task 3: 恢复每侧 72pt 两行工具栏 + 应用级配置

**Files:**
- Modify: `FlowFinder/UI/PaneToolbar.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFShellLayoutTests.swift`

**Interfaces:**
- Consumes: `FFToolbarRow2Preferences`、`FFToolbarRow2Item`。
- Produces:
  - `PaneToolbar.showsSecondaryRow: Bool` 恒为 true
  - `PaneToolbar.visibleRow2ItemsForTesting: Set<FFToolbarRow2Item>`
  - `PaneToolbar.applyRow2Visibility()`
  - 通知 `.toolbarRow2PreferencesChanged`

- [ ] **Step 1: 写失败测试**

```swift
func testToolbarRestoresTwoVisibleRows() {
    let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 600, height: 72))
    toolbar.side = .left
    XCTAssertTrue(toolbar.showsSecondaryRow)
    XCTAssertEqual(toolbar.visibleRow2ItemsForTesting,
                   Set(FFToolbarRow2Item.allCases))
}

func testToolbarCanHideSearchButKeepsGear() {
    let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 600, height: 72))
    toolbar.side = .left
    toolbar.setRow2Item(.search, visible: false)
    XCTAssertFalse(toolbar.visibleRow2ItemsForTesting.contains(.search))
    XCTAssertNotNil(toolbar.viewOptionsButton)
    XCTAssertFalse(toolbar.viewOptionsButton.isHidden)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，`showsSecondaryRow` 为 false / `visibleRow2ItemsForTesting` 不存在。

- [ ] **Step 3: 恢复两行布局**

参考 HEAD 实现（`git show HEAD:FlowFinder/FlowFinder/UI/PaneToolbar.swift`）：

1. 删除 `viewOptionsButton` 的显隐第二行逻辑；把它移到 row2 末尾。
2. row1 只保留导航按钮、刷新、面包屑；删除 row1 里的 `searchContainer`。
3. row2 恢复：搜索容器、排序 popup、分组 popup、列表/网格按钮、新建文件夹按钮、齿轮。固定高度：

```swift
heightAnchor.constraint(equalToConstant: 72).isActive = true
row1Height = 32
row2Height = 32
row1.top = top + 4
row2.top = row1.bottom + 4
```

4. 新增：

```swift
var showsSecondaryRow: Bool { true }
private(set) var visibleRow2Items: Set<FFToolbarRow2Item> = FFToolbarRow2Preferences.defaultItems

func applyRow2Visibility() {
    searchContainer.isHidden = !visibleRow2Items.contains(.search)
    sortPopup.isHidden = !visibleRow2Items.contains(.sort)
    groupPopup.isHidden = !visibleRow2Items.contains(.group)
    listViewButton.isHidden = !visibleRow2Items.contains(.viewMode)
    gridViewButton.isHidden = !visibleRow2Items.contains(.viewMode)
    newFolderButton.isHidden = !visibleRow2Items.contains(.newFolder)
    viewOptionsButton.isHidden = false
}

func setRow2Item(_ item: FFToolbarRow2Item, visible: Bool) {
    visibleRow2Items = visible
        ? visibleRow2Items.union([item])
        : visibleRow2Items.subtracting([item])
    UserDefaults.standard.set(FFToolbarRow2Preferences.encode(visibleRow2Items),
                              forKey: FFToolbarRow2Preferences.storageKey)
    applyRow2Visibility()
    NotificationCenter.default.post(name: .toolbarRow2PreferencesChanged, object: nil)
}

var visibleRow2ItemsForTesting: Set<FFToolbarRow2Item> { visibleRow2Items }
```

5. 齿轮 action 改为打开 `NSPopover`：标题“第二行显示”，逐项复选框（搜索/排序/分组/列表与图标/新建文件夹），点击调用 `setRow2Item`。
6. 初始化从 `UserDefaults.standard.string(forKey: storageKey)` 读取；两个面板监听 `.toolbarRow2PreferencesChanged` 并同步 `applyRow2Visibility()`。
7. `row2.detachesHiddenViews = false`，隐藏单项不改变 row2 高度。

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS；新增 2 条。

- [ ] **Step 5: 真机检查与构建**

Run `make -C flowfinder-native build`，启动后确认：每侧两行、搜索在第二行、齿轮打开五项开关、隐藏搜索后布局不跳动、左右同步。**不要 commit。**

---

### Task 4: 恢复操作区内详情栏，移除全局底栏

**Files:**
- Modify: `FlowFinder/UI/MainWindowController.swift`
- Modify: `FlowFinder/UI/ExpandableDetailsBar.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFShellLayoutTests.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFDetailsIntegrationTests.swift`（改写）

**Interfaces:**
- Produces:
  - `MainWindowController.detailsBar(for: PaneSide) -> ExpandableDetailsBar?`
  - `ExpandableDetailsBar.expand()`
  - `ExpandableDetailsBar.collapse()`
  - `MainWindowController.showDetailsForActiveSelection()` 改为展开详情栏
- Consumes: existing `handleSelectionChanged`、`updateStatus`、`onHeightChanged`。

- [ ] **Step 1: 写失败测试**

```swift
private func containsStatusBar(_ view: NSView) -> Bool {
    if view is FFStatusBarView { return true }
    return view.subviews.contains(where: containsStatusBar)
}

func testMainWindowHasNoGlobalStatusBarAndShowsDetailsBars() {
    let c = MainWindowController(startsWithSinglePane: false,
                                 showImmediately: false,
                                 runsSelfTests: false)
    defer { c.close() }
    let root = c.window?.contentView
    XCTAssertFalse(root.map(containsStatusBar) ?? false)
    XCTAssertNotNil(c.detailsBar(for: .left))
    XCTAssertFalse(c.detailsBar(for: .left)!.isHidden)
    XCTAssertFalse(c.detailsBar(for: .right)!.isHidden)
}

func testCmdIExpandsActivePaneDetailsBar() {
    let c = MainWindowController(startsWithSinglePane: false,
                                 showImmediately: false,
                                 runsSelfTests: false)
    defer { c.close() }
    c.focus.activate(.right)
    c.rightPaneViewModel.state.selectedFiles = [
        FileEntry(path: "/tmp/right.txt", name: "right.txt", isDirectory: false, size: 1)
    ]
    c.showDetailsForActiveSelection()
    XCTAssertTrue(c.detailsBar(for: .right)!.isExpandedForTesting)
    XCTAssertFalse(c.detailsBar(for: .left)!.isExpandedForTesting)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，状态栏存在/详情栏隐藏/`isExpandedForTesting` 不存在。

- [ ] **Step 3: 恢复布局**

在 `MainWindowController`：

1. 删除 `mainStatusBar` 属性、创建、`addSubview`、`onDetailsRequested` 与所有约束。
2. 把 `mainSplitView.bottomAnchor` 改回 `taskProgressBar.topAnchor`。
3. 删除 `detailsBar.isHidden = true`（两个面板）。
4. 保留现有 `leftDetailsBar/rightDetailsBar` 引用；`handleSelectionChanged` 与 `updatePaneUI` 已写 `detailsBar.update(with:)` / `updateStatus(...)`，无需重建调用链。
5. `refreshStatusBar()` 只保留给已退役状态栏的调用则删除；所有调用点一并删除。
6. `detailsBar.onHeightChanged` 已同步列表/网格底部 inset；确认两个面板都保留。

在 `ExpandableDetailsBar`：

```swift
var isExpandedForTesting: Bool { isExpanded }

func expand() {
    guard !isExpanded else { return }
    isExpanded = true
}

func collapse() {
    guard isExpanded else { return }
    isExpanded = false
}
```

把 `showDetailsForActiveSelection()` 改为：

```swift
func showDetailsForActiveSelection() {
    let side = activePane
    guard let bar = detailsBar(for: side) else { return }
    bar.expand()
    bar.update(with: side == .left
        ? leftPaneViewModel.selectedFiles
        : rightPaneViewModel.selectedFiles)
}
```

删除 `detailsPopover` 属性与 `FFDetailsPopoverController` 调用；`menuGetInfo` 继续调用 `showDetailsForActiveSelection()`。

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS；详情/窗口测试通过。

- [ ] **Step 5: 构建与真机检查**

Run `make -C flowfinder-native build`；确认无全局底栏、每侧详情栏可见、⌘I 展开当前侧、列表底部有浮层留白。**不要 commit。**

---

### Task 5: 详情栏异步元数据，移除同步媒体读取

**Files:**
- Modify: `FlowFinder/UI/ExpandableDetailsBar.swift`
- Modify: `FlowFinder/UI/MainWindowController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFDetailsIntegrationTests.swift`

**Interfaces:**
- Produces:
  - `ExpandableDetailsBar.metadataProvider: FFMetadataProviding?`
  - `ExpandableDetailsBar.cancelMetadataRequest()`
- Consumes: `FFMetadataService`、`FFFileMetadata`。

- [ ] **Step 1: 写失败测试（用 spy provider）**

```swift
private final class DetailsSpyProvider: FFMetadataProviding {
    var paths: [String] = []
    func load(path: String,
              completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID {
        paths.append(path)
        return UUID()
    }
    func cancel(_ token: UUID) {}
}

func testDetailsBarUsesInjectedMetadataProvider() {
    let bar = ExpandableDetailsBar()
    let spy = DetailsSpyProvider()
    bar.metadataProvider = spy
    let file = FileEntry(path: "/tmp/a.txt", name: "a.txt", isDirectory: false, size: 1)
    bar.update(with: [file])
    XCTAssertEqual(spy.paths, ["/tmp/a.txt"])
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，`metadataProvider` 不存在。

- [ ] **Step 3: 实现异步详情**

1. 在 `ExpandableDetailsBar` 增加：

```swift
var metadataProvider: FFMetadataProviding? {
    didSet { cancelMetadataRequest() }
}
private var metadataToken: UUID?
private var currentMetadataPath: String?

private func cancelMetadataRequest() {
    if let metadataToken { metadataProvider?.cancel(metadataToken) }
    metadataToken = nil
    currentMetadataPath = nil
}

private func requestMetadata(for path: String) {
    guard currentMetadataPath != path else { return }
    cancelMetadataRequest()
    currentMetadataPath = path
    metadataToken = metadataProvider?.load(path: path) { [weak self] result in
        guard let self, self.currentMetadataPath == path else { return }
        if case .success(let metadata) = result {
            self.apply(metadata: metadata)
        }
    }
}
```

2. 在 `update(with files:)` 中：
   - 保留现有的名称/类型/大小即时显示；
   - 单选时调用 `requestMetadata(for: file.path)`；
   - **删除** `PDFDocument(url:)`、`AVAsset`、`contentsOfDirectory` 等同步媒体/目录读取调用；
   - 展开状态下的 PDF 页数/视频时长字段在没有异步 provider 数据时显示“—”，不得同步补读。
3. `cancelMetadataRequest()` 在 `update(with:)` 切换选择、收起、`deinit` 时调用。
4. 在 `MainWindowController.createPaneContainer` 注入：

```swift
detailsBar.metadataProvider = FFMetadataService()
```

左右各一个实例，互不干扰。

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS；spy 断言通过。

- [ ] **Step 5: 构建/性能检查**

Run `make -C flowfinder-native build`；选中视频/PDF/大目录，确认主线程无 PDF/AV/目录同步读取（用 sample/signpost）。**不要 commit。**

---

### Task 6: 三边微光视图

> **实施记录（2026-10-21）：** 第一版两层渐变描边在真机仍呈硬边，已删除 `FFActivePaneGlowView`，
> 改为 `FFPaneGlow` 原生 `CALayer` 阴影（无描边、向下偏移）。本任务代码以 `FFPaneGlow` 为准。

**Files:**
- Create: `FlowFinder/UI/FFActivePaneGlowView.swift`
- Modify: `FlowFinder/UI/FFComponents.swift`
- Modify: `FlowFinder/UI/MainWindowController.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFGlowViewTests.swift`
- Modify: `FlowFinder/FlowFinder.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `FFGlowSpec`、`FFAccent.current`
- Produces:
  - `final class FFActivePaneGlowView: NSView`
  - `var spec: FFGlowSpec`
  - `var accentColor: NSColor`
  - `func refreshAppearance()`
  - `isOpaque == false`、`hitTest == nil`

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFGlowViewTests: XCTestCase {
    func testGlowIsNonInteractive() {
        let view = FFActivePaneGlowView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertFalse(view.isOpaque)
    }

    func testGlowUsesStandardSpec() {
        let view = FFActivePaneGlowView(frame: .zero)
        XCTAssertEqual(view.spec, .standard)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，类型不存在。

- [ ] **Step 3: 实现两层渐变三边微光**

`FFActivePaneGlowView` 用两层 `CAGradientLayer` 模拟柔光（宽层 12px、低透明度；核心层 5px），两层都用同一个“只描左/右/下”的 `CAShapeLayer` 作为 mask；顶部路径停在 `bounds.height - 2`，因此顶部不发光。渐变从底部 `accentColor` 到顶部透明，透明度按 `FFGlowSpec.alpha(atNormalizedY:)` 生成 8 个 stop。

```swift
final class FFActivePaneGlowView: NSView {
    var spec: FFGlowSpec = .standard { didSet { rebuildLayers() } }
    var accentColor: NSColor = FFAccent.current { didSet { rebuildLayers() } }

    private let wideLayer = CAGradientLayer()
    private let coreLayer = CAGradientLayer()
    private let wideMask = CAShapeLayer()
    private let coreMask = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        [wideLayer, coreLayer].forEach { layer?.addSublayer($0) }
        [wideMask, coreMask].forEach {
            $0.fillColor = NSColor.clear.cgColor
            $0.strokeColor = NSColor.white.cgColor
            $0.lineJoin = .round
        }
        wideLayer.mask = wideMask
        coreLayer.mask = coreMask
        rebuildLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        [wideLayer, coreLayer].forEach { $0.frame = bounds }
        [wideMask, coreMask].forEach {
            $0.frame = bounds
            $0.path = threeEdgePath(in: bounds)
        }
    }

    private func rebuildLayers() {
        let stops = (0...8).map { CGFloat($0) / 8 }
        let coreColors = stops.map {
            accentColor.withAlphaComponent(spec.alpha(atNormalizedY: $0)).cgColor
        }
        let wideColors = stops.map {
            accentColor.withAlphaComponent(spec.alpha(atNormalizedY: $0) * 0.35).cgColor
        }
        wideLayer.colors = wideColors
        coreLayer.colors = coreColors
        [wideLayer, coreLayer].forEach {
            $0.locations = stops.map { NSNumber(value: Double($0)) }
            $0.startPoint = CGPoint(x: 0.5, y: 0)   // 底部
            $0.endPoint = CGPoint(x: 0.5, y: 1)     // 顶部
        }
        wideMask.lineWidth = 12
        coreMask.lineWidth = 5
        needsLayout = true
    }

    /// 只描左、下、右；顶部留 2pt 不发光。
    private func threeEdgePath(in rect: NSRect) -> CGPath {
        let inset: CGFloat = 3
        let r: CGFloat = 15
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let bottom = rect.minY + inset
        let top = rect.maxY - inset - 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addArc(center: CGPoint(x: left + r, y: bottom + r),
                    radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addArc(center: CGPoint(x: right - r, y: bottom + r),
                    radius: r, startAngle: .pi * 1.5, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: right, y: top))
        return path
    }
}
```

集成：

- 在 `MainWindowController.makeCardWrapper` 中，把 `FFActivePaneBorderView` 的 glow 子视图改为 `FFActivePaneGlowView`，放在内容之下、卡片背景之上。
- 活动面板切换时只改 `isHidden`/alpha；`FFActivePaneBorderView` 仍保留顶部 2px 强调边。
- `viewDidChangeEffectiveAppearance` 里刷新 `accentColor = FFAccent.current` 与 `needsDisplay`。

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS；新增 2 条。

- [ ] **Step 5: 构建/视觉检查**

Run `make -C flowfinder-native build`；截图确认顶部无光、左/右/下渐隐、与标签区不重叠；浅/深色各一次。**不要 commit。**

---

### Task 7: 强调色统一到列表/面包屑/标签/拖拽

**Files:**
- Modify: `FlowFinder/UI/FileListView.swift`
- Modify: `FlowFinder/UI/FileGridView.swift`
- Modify: `FlowFinder/UI/PaneTabs.swift`
- Modify: `FlowFinder/UI/BreadcrumbBar.swift`
- Modify: `FlowFinder/UI/FFDragOverlay.swift`
- Modify: `FlowFinder/UI/FFComponents.swift`
- Test: `FlowFinder/Tests/FlowFinderTests/FFAccentSelectionTests.swift`

**Interfaces:**
- Produces: `FFAccentSelection.fillColor`、`FFTableRowView` 使用 FFAccent。
- Consumes: `FFAccent.current`.

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFAccentSelectionTests: XCTestCase {
    func testTabUnderlineUsesApplicationAccent() {
        XCTAssertEqual(FFVisualTokens.tabUnderlineColor.ffHexString,
                       FFAccent.current.ffHexString)
    }

    func testSelectionFillUsesApplicationAccent() {
        XCTAssertEqual(FFAccentSelection.fillColor.ffHexString,
                       FFAccent.current.ffHexString)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: FAIL，`tabUnderlineColor` / `FFAccentSelection` 不存在。

- [ ] **Step 3: 实现统一**

1. `FFVisualTokens` 增加：

```swift
static var tabUnderlineColor: NSColor { FFAccent.current }
```

2. `PaneTabs` 的下划线改用 `FFVisualTokens.tabUnderlineColor`。
3. `FFAccentSelection`：

```swift
enum FFAccentSelection {
    static var fillColor: NSColor { FFAccent.current }
    static let fillAlpha: CGFloat = 0.16
}
```

4. `FileListView` 自定义 `FFTableRowView` 的 `drawSelection(in:)`：

```swift
FFAccentSelection.fillColor.withAlphaComponent(FFAccentSelection.fillAlpha).setFill()
NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
```

保留当前文字颜色（label），不随选中改白；在深色模式用同一 alpha。

5. `BreadcrumbBar`、`FFDragOverlay`、`FFActivePaneBorderView` 中所有 `NSColor.controlAccentColor` / `FFVisualTokens.accent` 改为 `FFAccent.current`（系统控件如 `NSButton` 默认高亮不强制改）。
6. `FileGridView` 已有 `FFAccent.current` 的选中填充，复核 alpha 与文字对比。

- [ ] **Step 4: 跑测试**

Run: `make -C flowfinder-native swift-test 2>&1 | tail -20`
Expected: PASS；新增 2 条。

- [ ] **Step 5: 构建/视觉检查**

Run `make -C flowfinder-native build`；确认面包屑、选中行、标签下划线、拖拽浮层颜色一致；浅/深色对比度可读。**不要 commit。**

---

### Task 8: 退役旧入口、全量验收与文档

**Files:**
- Delete: `FlowFinder/UI/FFStatusBarView.swift`
- Delete: `FlowFinder/UI/FFStatusBarText.swift`
- Delete: `FlowFinder/UI/FFDetailsPopoverController.swift`
- Delete test: `FFStatusBarTextTests.swift`、`FFDetailsIntegrationTests.swift` 中 popover 用例（改写为详情栏）
- Modify: `FlowFinder/FlowFinder.xcodeproj/project.pbxproj`
- Modify: `docs/HANDOVER.md`、`docs/REQUIREMENTS-LEDGER.md`、`CHANGELOG.md`、`docs/SPEC-2026-10-21-LAYOUT-ROLLBACK.md`

- [ ] **Step 1: 检索并移除旧引用**

Run:

```bash
grep -rn "FFStatusBarView\|FFStatusBarText\|FFDetailsPopoverController\|mainStatusBar\|detailsPopover" FlowFinder/FlowFinder FlowFinder/Tests
```

Expected: 只允许历史文档/本任务清单命中；代码命中全部删除或改为详情栏。

- [ ] **Step 2: 更新测试**

- 删除 `FFStatusBarTextTests` 或改为 `FFDetailsBarSummaryTests`（验证无选择/单选/多选文案）。
- 删除 Task 4 中 `containsStatusBar`/`FFStatusBarView` 的断言（类型已不存在），改为只断言两个详情栏存在且可见；全局底栏缺失由布局截图验收。
- `FFDetailsIntegrationTests` 只保留：
  - `testCmdIExpandsActivePaneDetailsBar`
  - `testCmdIDoesNotExpandInactivePane`
  - `testDetailsBarShowsDirectorySummaryWithoutSelection`（断言收起摘要可见、不强制展开）
- 新增 `FFLayoutRestoreTests`（Task 3/4 的断言合并到 `FFShellLayoutTests`）。
- 全量测试：

```bash
make -C flowfinder-native swift-test 2>&1 | tail -20
```

Expected: PASS（数量按实际新增增减，不得有失败）。

- [ ] **Step 3: 构建与自检**

```bash
make -C flowfinder-native build
pkill -f "MacOS/FlowFinder" || true
FF_SELFTEST=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" &
sleep 12
pkill -f "MacOS/FlowFinder" || true
grep -c "FAIL" /tmp/ff-debug.log
```

Expected: BUILD SUCCEEDED；自检 0 FAIL。

- [ ] **Step 4: 视觉与性能验收**

- 1400×900、1060×700，浅色/深色：无全局底栏；两行工具栏；两侧 54pt 详情栏；顶部无光；三边微光仅活动面板；第二行配置生效。
- 选中 100 次、滚动 500 项、⌘I 展开：无整表 reload、无同步 PDF/AV、sample 无长主线程栈。
- 截图归档 `docs/images/2026-10-21-layout-*`。

- [ ] **Step 5: 文档更新（不提交）**

- `HANDOVER.md`：新增“2026-10-21 结构回归”章节，标注与 UIUX-REDO 的取代关系。
- `REQUIREMENTS-LEDGER.md`：新增 R-16，逐条引用 D-01..D-15，记录测试/自检数字。
- `CHANGELOG.md`：未发版段新增“双操作区结构回归 / 三边微光 / 单一强调色”。
- 本规格状态改为“已实现/已验证（未提交）”。
- **不要 commit、不要 push。**

---

## Self-Review

**Spec coverage:**
- D-01/D-02/D-03 → Task 3/4。
- D-04/D-10/D-11/D-15 → Task 2/6。
- D-05 → Global Constraints + File Structure。
- D-06/D-09 → Task 4/5。
- D-07/D-08 → Task 2/3。
- D-12 → Task 1/7。
- D-13 → 保留现状，Task 3/8 不改工具入口。
- D-14 → 保留 `PaneStore`/`MetadataService`/`TaskService`，Task 5 只改详情读取方式。

**Placeholder scan:** 无 TBD/TODO；每个任务有测试、实现、运行命令与预期结果。

**Type consistency:**
- `FFToolbarRow2Item`/`FFToolbarRow2Preferences` 在 Task 2 定义，Task 3 使用。
- `FFGlowSpec` 在 Task 2 定义，Task 6 使用。
- `FFAccentSelection` 在 Task 7 定义，任务内使用。
- `ExpandableDetailsBar.metadataProvider` 在 Task 5 定义，Task 4 的 `expand()` 已先存在。
- `detailsBar(for:)` 在 Task 4 定义，Task 8 验收使用。

**Known sequencing:** Task 4 先恢复布局（可能暂时使用旧详情刷新路径），Task 5 再切断同步媒体；每个任务结束都可构建，不把性能回归留到后续分支。
