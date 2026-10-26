# FlowFinder UI/UX 与结构整改 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 D-01..D-12 把 FlowFinder 重做成“优雅的现代化 Finder 进化版”：安静原生双栏 + 标准标签 + 智能工具组（入口暂留侧栏），同时把选中/详情/渲染/任务/工具的结构债一次收清。

**Architecture:** 原地绞杀。先落设计 tokens 与视觉外壳；再引入 `PaneStore`/`WindowFocusModel` 收编状态与活动面板；随后用 `RenderPipeline` 合并列表/网格重载、`MetadataService` 后台化详情、`TaskService` 统一进度、`ToolProtocol/Registry` 统一工具；最后拆 `MainWindowController` 并删除旧路径。每一步旧路径保留到验收通过。

**Tech Stack:** Swift / AppKit / Combine / XCTest；Rust core 与现有 C ABI 不动。

**Spec:** `docs/SPEC-2026-10-20-UIUX-REDO.md`

> **执行状态（2026-10-21）：** Task 1–8、10、11 自动化完成（245 XCTest / 135 自检全绿）；
> Task 9 完成 coordinator 接缝与状态所有权迁移，布局/拖拽/标签装配仍在 MainWindowController；
> Task 4 的独立 `RenderPipeline` 未抽出，以「选中不 reload + viewMode 守卫 + PaneStore 签名比较」落地。
> 视觉/性能/VoiceOver 人工验收因屏幕锁定未做，见 SPEC §13。

## Global Constraints

- 部署目标 macOS 12.0；不引入第三方 UI 框架；不重写 Rust core / Bridge 协议。
- **不要提交 commit**：用户未授权 git commit。每个任务结束只构建与测试，改动留在工作树。
- **TDD**：先写失败测试并亲眼确认失败，再写最小实现；禁止先写生产代码再补测试。
- 现有 **190 条 XCTest** 必须保持全绿；应用内 `FF_SELFTEST=1` 必须保持 0 失败。
- 性能门槛（D-11）：选中响应 <50ms；500 项目录首屏 <300ms；滚动 60fps；无主线程 >100ms 阻塞；热启动 <2s。
- 视觉硬约束（D-06）：系统强调色；SF Pro；1px hairline；2px 活动边；无粉红发光/玻璃白边/大面积半透明填充。
- 交互硬约束（D-05）：Finder 标准键为准；⌘1/⌘2 切面板；单一 `activePane`；F5/F6 仅可选加速键。
- 标签（D-08 + D-12）：标准原生标签；单标签保留轻量标签，不隐藏；最后标签仍可直接拖出。
- 工具（D-03）：入口暂留侧栏品牌区右侧；本轮不改结构，只改善文案/提示/上下文；内部 `ToolProtocol` 预留扩展。
- 迁移（D-10）：每片可构建、可运行、可回滚；旧路径在该片验收后删除；不长期维护双 UI。
- 测试命令：
  - 全量：`make swift-test`
  - 单类：`xcodebuild test -project FlowFinder/FlowFinder.xcodeproj -scheme FlowFinderTests -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -only-testing:FlowFinderTests/<ClassName>`
- 构建：`make build`；截图：`screencapture -x /tmp/<name>.png`（本机已可用）。

---

## File Structure

| 文件 | 职责 | 动作 |
|---|---|---|
| `FlowFinder/FlowFinder/UI/FFVisualTokens.swift` | 颜色/字体/间距/圆角/动效/图标尺寸令牌 | 新建 |
| `FlowFinder/FlowFinder/UI/FFContrast.swift` | WCAG 对比度纯函数 | 新建 |
| `FlowFinder/FlowFinder/UI/FFKeyboardContract.swift` | 快捷键唯一来源 + 冲突检测 | 新建 |
| `FlowFinder/FlowFinder/UI/FFStatusBarText.swift` | 状态栏文案纯函数 | 新建 |
| `FlowFinder/FlowFinder/UI/FFStatusBarView.swift` | 28px 统一状态栏 | 新建 |
| `FlowFinder/FlowFinder/UI/FFDetailsPopoverController.swift` | ⌘I 按需详情浮层 | 新建 |
| `FlowFinder/FlowFinder/UI/FFViewOptionsPopover.swift` | 排序/分组/列/密度 | 新建 |
| `FlowFinder/FlowFinder/UI/FFToolProtocol.swift` | 工具协议/上下文/可用性 | 新建 |
| `FlowFinder/FlowFinder/UI/FFToolRegistry.swift` | 工具注册表 | 新建 |
| `FlowFinder/FlowFinder/UI/FFToolPopoverController.swift` | 工具 popover | 新建 |
| `FlowFinder/FlowFinder/Model/PaneStore.swift` | 每面板单一真值 + 粒度变更集 | 新建 |
| `FlowFinder/FlowFinder/UI/WindowFocusModel.swift` | 唯一 activePane | 新建 |
| `FlowFinder/FlowFinder/UI/RenderPipeline.swift` | 合并渲染 + 选择差分 | 新建 |
| `FlowFinder/FlowFinder/Bridge/MetadataService.swift` | 后台元数据/媒体 | 新建 |
| `FlowFinder/FlowFinder/Bridge/TaskService.swift` | 任务/进度/取消/历史 | 新建 |
| `FlowFinder/FlowFinder/UI/WindowShellCoordinator.swift` | 窗口壳装配 | 新建 |
| `FlowFinder/FlowFinder/UI/PaneCoordinator.swift` | 单面板装配 | 新建 |
| `FlowFinder/FlowFinder/UI/SidebarCoordinator.swift` | 侧栏装配 | 新建 |
| `FlowFinder/FlowFinder/UI/ToolCoordinator.swift` | 工具装配 | 新建 |
| `FlowFinder/FlowFinder/UI/TaskCoordinator.swift` | 任务装配 | 新建 |
| `UI/MainWindowController.swift` | 逐步瘦身/转发 | 修改 |
| `UI/PaneToolbar.swift` | 单行工具栏 + 视图选项 | 修改 |
| `UI/PaneTabs.swift` | 标准原生标签 + 单标签轻量保留 | 修改 |
| `UI/FFComponents.swift` | 活动面板 2px 边；删除发光 | 修改 |
| `UI/SidebarView.swift` | 工具药丸文案/提示/状态 | 修改 |
| `UI/FFDiscoverPanel.swift` | 收编到 ToolRegistry/Popover | 修改/退役 |
| `UI/FileListView.swift` / `FileGridView.swift` | 接 RenderPipeline；选择不重载 | 修改 |
| `UI/ExpandableDetailsBar.swift` | 收编到详情 popover；删除常驻栏 | 修改/退役 |
| `Bridge/ThumbnailManager.swift` | hash key + 摊销清理 | 修改 |
| `UI/MainMenu.swift` | 菜单读 FFKeyboardContract | 修改 |
| `UI/SettingsWindowController.swift` | 快捷键/死开关/工具设置 | 修改 |
| `UI/SearchPanelController.swift` | 统一搜索框/范围/结果定位 | 修改 |
| `UI/DuplicateScanWindowController.swift` | 默认当前目录/不预勾选/永久删除 | 修改 |
| `UI/BatchRenameWindowController.swift` | 上下文/预览/冲突 | 修改 |
| `Tests/FlowFinderTests/FFVisualTokensTests.swift` | tokens/对比度 | 新建 |
| `Tests/FlowFinderTests/FFKeyboardContractTests.swift` | 快捷键/冲突 | 新建 |
| `Tests/FlowFinderTests/FFStatusBarTextTests.swift` | 状态文案 | 新建 |
| `Tests/FlowFinderTests/PaneStoreTests.swift` | 粒度变更/选择/筛选 | 新建 |
| `Tests/FlowFinderTests/RenderPipelineTests.swift` | 选择不重载/批量更新 | 新建 |
| `Tests/FlowFinderTests/FFToolRegistryTests.swift` | 注册/可用性/上下文 | 新建 |
| `Tests/FlowFinderTests/FFMetadataServiceTests.swift` | generation/取消 | 新建 |
| `Tests/FlowFinderTests/FFTaskServiceTests.swift` | 进度/取消/发布 | 新建 |
| `Tests/FlowFinderTests/FFActivePaneIntegrationTests.swift` | 点击/Tab/⌘1/⌘2/侧栏 | 新建 |
| `Tests/FlowFinderTests/FFDetailsIntegrationTests.swift` | ⌘I/按需/关闭取消 | 新建 |

---

## Task 1: 设计 tokens、对比度、快捷键与状态栏纯函数

**Files:**
- Create: `FlowFinder/FlowFinder/UI/FFVisualTokens.swift`
- Create: `FlowFinder/FlowFinder/UI/FFContrast.swift`
- Create: `FlowFinder/FlowFinder/UI/FFKeyboardContract.swift`
- Create: `FlowFinder/FlowFinder/UI/FFStatusBarText.swift`
- Create: `FlowFinder/Tests/FlowFinderTests/FFVisualTokensTests.swift`
- Create: `FlowFinder/Tests/FlowFinderTests/FFKeyboardContractTests.swift`
- Create: `FlowFinder/Tests/FlowFinderTests/FFStatusBarTextTests.swift`
- Modify: `project.pbxproj`（注册新源码/测试）

**Interfaces:**
- Produces:
  - `FFVisualTokens`：`accent`、`windowBackground`、`paneBackground`、`sidebarBackground`、`separator`、`label`、`secondaryLabel`、`spacing`、`radius`、`font`、`iconSize`、`motion`
  - `FFContrast.ratio(_:_:) -> CGFloat`
  - `FFShortcutAction` / `FFShortcut` / `FFKeyboardContract`
  - `FFStatusBarText.summary(...) -> String`

- [ ] **Step 1: 写 tokens/对比度失败测试**

Create `FFVisualTokensTests.swift`:

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFVisualTokensTests: XCTestCase {
    func testSpacingScaleIsFourBased() {
        XCTAssertEqual(FFVisualTokens.Spacing.xs, 4)
        XCTAssertEqual(FFVisualTokens.Spacing.s, 8)
        XCTAssertEqual(FFVisualTokens.Spacing.m, 12)
        XCTAssertEqual(FFVisualTokens.Spacing.l, 16)
        XCTAssertEqual(FFVisualTokens.Spacing.xl, 24)
    }

    func testRowAndControlMetrics() {
        XCTAssertEqual(FFVisualTokens.rowHeight, 28)
        XCTAssertEqual(FFVisualTokens.rowHeightCompact, 24)
        XCTAssertEqual(FFVisualTokens.toolbarHeight, 34)
        XCTAssertEqual(FFVisualTokens.statusBarHeight, 28)
        XCTAssertEqual(FFVisualTokens.iconSize, 16)
        XCTAssertEqual(FFVisualTokens.activePaneEdge, 2)
    }

    func testContrastHelperMatchesKnownRatios() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(FFContrast.ratio(white, black), 21, accuracy: 0.1)
        XCTAssertEqual(FFContrast.ratio(white, white), 1, accuracy: 0.01)
    }

    func testAccentIsSystemAccent() {
        XCTAssertEqual(FFVisualTokens.accent, NSColor.controlAccentColor)
    }
}
```

- [ ] **Step 2: 写快捷键失败测试**

Create `FFKeyboardContractTests.swift`:

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFKeyboardContractTests: XCTestCase {
    func testFinderCanonicalShortcuts() {
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .newWindow).display, "⌘N")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .newFolder).display, "⌘⇧N")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .moveToTrash).display, "⌘⌫")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .rename).display, "Return")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .closeTab).display, "⌘W")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .closeWindow).display, "⌘⇧W")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .focusLeft).display, "⌘1")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .focusRight).display, "⌘2")
    }

    func testOverridesDetectConflict() {
        var overrides: [FFShortcutAction: FFShortcut] = [:]
        overrides[.newWindow] = FFKeyboardContract.shortcut(for: .newFolder)
        let conflicts = FFKeyboardContract.conflicts(overrides: overrides)
        XCTAssertTrue(conflicts[.newWindow]?.contains(.newFolder) ?? false)
        XCTAssertTrue(conflicts[.newFolder]?.contains(.newWindow) ?? false)
    }
}
```

- [ ] **Step 3: 写状态栏文案失败测试**

Create `FFStatusBarTextTests.swift`:

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFStatusBarTextTests: XCTestCase {
    private func file(_ name: String, size: UInt64, isDirectory: Bool = false) -> FileEntry {
        FileEntry(path: "/tmp/\(name)", name: name, isDirectory: isDirectory, size: size)
    }

    func testEmptySelectionShowsActivePaneAndCounts() {
        XCTAssertEqual(
            FFStatusBarText.summary(activePaneName: "Desktop", selection: [], totalCount: 13,
                                    diskFree: "62.16 GB", isLoading: false),
            "Active: Desktop · 13 项 · 62.16 GB 可用"
        )
    }

    func testSingleSelectionShowsSizeAndType() {
        let f = file("a.png", size: 1_100_000)
        let text = FFStatusBarText.summary(activePaneName: "Desktop", selection: [f], totalCount: 13,
                                           diskFree: "62.16 GB", isLoading: false)
        XCTAssertTrue(text.contains("1 项已选"))
        XCTAssertTrue(text.contains("PNG"))
    }

    func testMultiSelectionAggregatesSize() {
        let a = file("a.txt", size: 100)
        let b = file("b.txt", size: 200)
        let text = FFStatusBarText.summary(activePaneName: "Desktop", selection: [a, b], totalCount: 13,
                                           diskFree: "62.16 GB", isLoading: false)
        XCTAssertTrue(text.contains("2 项已选"))
        XCTAssertTrue(text.contains("300"))
    }

    func testFolderSelectionShowsCounting() {
        let dir = file("docs", size: 0, isDirectory: true)
        let text = FFStatusBarText.summary(activePaneName: "Desktop", selection: [dir], totalCount: 13,
                                           diskFree: "62.16 GB", isLoading: false)
        XCTAssertTrue(text.contains("文件夹"))
        XCTAssertTrue(text.contains("计算中") || text.contains("项"))
    }
}
```

- [ ] **Step 4: 注册文件并确认测试失败**

在 `project.pbxproj` 注册 4 个源码 + 3 个测试文件（独立 ID 段，先 grep 候选 ID）。运行：

```bash
xcodebuild test -project FlowFinder/FlowFinder.xcodeproj -scheme FlowFinderTests \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:FlowFinderTests/FFVisualTokensTests \
  -only-testing:FlowFinderTests/FFKeyboardContractTests \
  -only-testing:FlowFinderTests/FFStatusBarTextTests
```

Expected: 编译错误 `cannot find 'FFVisualTokens'` 等；加最小桩后应看到断言失败（不是语法错误）。

- [ ] **Step 5: 实现 tokens/对比度**

Create `FFVisualTokens.swift`:

```swift
import AppKit

enum FFVisualTokens {
    static let accent = NSColor.controlAccentColor
    static let windowBackground = NSColor.windowBackgroundColor
    static let paneBackground = NSColor.controlBackgroundColor
    static let sidebarBackground = NSColor.underPageBackgroundColor
    static let separator = NSColor.separatorColor
    static let label = NSColor.labelColor
    static let secondaryLabel = NSColor.secondaryLabelColor
    static let tertiaryLabel = NSColor.tertiaryLabelColor

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 10
        static let window: CGFloat = 12
    }

    static let rowHeight: CGFloat = 28
    static let rowHeightCompact: CGFloat = 24
    static let toolbarHeight: CGFloat = 34
    static let statusBarHeight: CGFloat = 28
    static let iconSize: CGFloat = 16
    static let activePaneEdge: CGFloat = 2

    enum Font {
        static let caption = NSFont.systemFont(ofSize: 11)
        static let captionMedium = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let body = NSFont.systemFont(ofSize: 13)
        static let sectionTitle = NSFont.systemFont(ofSize: 15, weight: .medium)
        static let emptyTitle = NSFont.systemFont(ofSize: 17, weight: .semibold)
    }

    enum Motion {
        static let micro: TimeInterval = 0.16
        static let paneMode: TimeInterval = 0.22
    }
}
```

Create `FFContrast.swift`:

```swift
import AppKit

enum FFContrast {
    static func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = luminance(a)
        let lb = luminance(b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent)
            + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }
}
```

- [ ] **Step 6: 实现快捷键契约**

Create `FFKeyboardContract.swift`:

```swift
import AppKit

enum FFShortcutAction: String, CaseIterable, Hashable {
    case newWindow, newFolder, newTab, closeTab, closeWindow
    case moveToTrash, rename, quickLook, duplicate, getInfo
    case back, forward, up, focusLeft, focusRight
    case nextTab, previousTab, search, globalSearch, duplicateScan
    case copyToOther, moveToOther, settings
}

struct FFShortcut: Equatable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let display: String
}

enum FFKeyboardContract {
    static func shortcut(for action: FFShortcutAction) -> FFShortcut {
        switch action {
        case .newWindow: return .init(key: "n", modifiers: [.command], display: "⌘N")
        case .newFolder: return .init(key: "n", modifiers: [.command, .shift], display: "⌘⇧N")
        case .newTab: return .init(key: "t", modifiers: [.command], display: "⌘T")
        case .closeTab: return .init(key: "w", modifiers: [.command], display: "⌘W")
        case .closeWindow: return .init(key: "w", modifiers: [.command, .shift], display: "⌘⇧W")
        case .moveToTrash: return .init(key: String(UnicodeScalar(0x08)!), modifiers: [.command], display: "⌘⌫")
        case .rename: return .init(key: String(UnicodeScalar(0x0D)!), modifiers: [], display: "Return")
        case .quickLook: return .init(key: " ", modifiers: [], display: "Space")
        case .duplicate: return .init(key: "d", modifiers: [.command], display: "⌘D")
        case .getInfo: return .init(key: "i", modifiers: [.command], display: "⌘I")
        case .back: return .init(key: "[", modifiers: [.command], display: "⌘[")
        case .forward: return .init(key: "]", modifiers: [.command], display: "⌘]")
        case .up: return .init(key: String(UnicodeScalar(0xF700)!), modifiers: [.command], display: "⌘↑")
        case .focusLeft: return .init(key: "1", modifiers: [.command], display: "⌘1")
        case .focusRight: return .init(key: "2", modifiers: [.command], display: "⌘2")
        case .nextTab: return .init(key: String(UnicodeScalar(0x09)!), modifiers: [.control], display: "⌃Tab")
        case .previousTab: return .init(key: String(UnicodeScalar(0x09)!), modifiers: [.control, .shift], display: "⌃⇧Tab")
        case .search: return .init(key: "f", modifiers: [.command], display: "⌘F")
        case .globalSearch: return .init(key: "f", modifiers: [.command, .shift], display: "⌘⇧F")
        case .duplicateScan: return .init(key: "d", modifiers: [.command, .shift], display: "⌘⇧D")
        case .copyToOther: return .init(key: "c", modifiers: [.command, .shift], display: "⌘⇧C")
        case .moveToOther: return .init(key: "x", modifiers: [.command, .shift], display: "⌘⇧X")
        case .settings: return .init(key: ",", modifiers: [.command], display: "⌘,")
        }
    }

    static func conflicts(overrides: [FFShortcutAction: FFShortcut] = [:]) -> [FFShortcutAction: [FFShortcutAction]] {
        var effective: [FFShortcutAction: FFShortcut] = [:]
        for action in FFShortcutAction.allCases {
            effective[action] = overrides[action] ?? shortcut(for: action)
        }
        var result: [FFShortcutAction: [FFShortcutAction]] = [:]
        for (a, sa) in effective {
            for (b, sb) in effective where a != b {
                if sa.key == sb.key && sa.modifiers == sb.modifiers {
                    result[a, default: []].append(b)
                }
            }
        }
        return result
    }
}
```

- [ ] **Step 7: 实现状态栏文案**

Create `FFStatusBarText.swift`:

```swift
import AppKit

enum FFStatusBarText {
    static func summary(activePaneName: String,
                        selection: [FileEntry],
                        totalCount: Int,
                        diskFree: String?,
                        isLoading: Bool) -> String {
        let active = "Active: \(activePaneName)"
        let disk = diskFree.map { " · \($0) 可用" } ?? ""
        if isLoading {
            return "\(active) · 加载中…\(disk)"
        }
        if selection.isEmpty {
            return "\(active) · \(totalCount) 项\(disk)"
        }
        if selection.count == 1, let file = selection.first {
            if file.isDirectory {
                return "\(active) · 文件夹 \(file.name) · 计算中…\(disk)"
            }
            let size = ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
            return "\(active) · 1 项已选 · \(size) · \(file.kindDescription)\(disk)"
        }
        let total = selection.reduce(UInt64(0)) { $0 + $1.size }
        let size = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        return "\(active) · \(selection.count) 项已选 · 共 \(size)\(disk)"
    }
}
```

- [ ] **Step 8: 跑测试并全量回归**

Run the three test classes; Expected: PASS。然后 `make swift-test`；Expected: 190 + 新增测试全绿。

---

## Task 2: 主窗口外壳：单行工具栏、标准标签、统一状态栏、2px 活动边

**Files:**
- Create: `FlowFinder/FlowFinder/UI/FFStatusBarView.swift`
- Create: `FlowFinder/FlowFinder/UI/FFViewOptionsPopover.swift`
- Modify: `UI/PaneToolbar.swift`
- Modify: `UI/PaneTabs.swift`
- Modify: `UI/FFComponents.swift`
- Modify: `UI/MainWindowController.swift`
- Modify: `UI/SidebarView.swift`（工具药丸文案/提示）
- Test: `Tests/FlowFinderTests/FFShellLayoutTests.swift`

**Interfaces:**
- Consumes: `FFVisualTokens`, `FFStatusBarText`
- Produces:
  - `FFStatusBarView.update(text: String)`
  - `PaneToolbar.showsSingleRow` / `viewOptionsButton`
  - `PaneTabStripView` standard tab style; single tab visible
  - `FFActivePaneBorderView` 2px top edge

- [ ] **Step 1: 写外壳结构失败测试**

Create `FFShellLayoutTests.swift`:

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFShellLayoutTests: XCTestCase {
    func testActivePaneUsesTwoPointEdge() {
        let border = FFActivePaneBorderView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(FFVisualTokens.activePaneEdge, 2)
        XCTAssertEqual(border.edgeHeight, 2)
    }

    func testToolbarExposesViewOptionsInsteadOfSecondRow() {
        let toolbar = PaneToolbar(frame: .zero)
        toolbar.side = .left
        XCTAssertNotNil(toolbar.viewOptionsButton)
        XCTAssertFalse(toolbar.showsSecondaryRow)
    }

    func testSingleTabRemainsVisible() {
        let strip = PaneTabStripView(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        strip.refresh(sessions: [PaneTabSession(state: PaneState(path: "/tmp"))], activeIndex: 0)
        XCTAssertEqual(strip.allTabItems().count, 1)
        XCTAssertFalse(strip.isHidden)
    }

    func testStatusBarShowsActivePaneAndCount() {
        let bar = FFStatusBarView(frame: .zero)
        bar.update(text: "Active: Desktop · 13 项 · 62.16 GB 可用")
        XCTAssertEqual(bar.textForTesting, "Active: Desktop · 13 项 · 62.16 GB 可用")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Add stubs for `edgeHeight`, `viewOptionsButton`, `showsSecondaryRow`, `textForTesting`; run `FFShellLayoutTests`; Expected: FAIL (not compile error after stubs).

- [ ] **Step 3: 实现 2px 活动边**

Modify `UI/FFComponents.swift` `FFActivePaneBorderView`:

- 删除 14 层同心描边与 `boost` 参数使用。
- `draw(_:)` 只画顶部 2px 系统强调色线（`bounds.maxY - 2 .. bounds.maxY`），圆角跟随面板 10pt；不画整圈、不画阴影。
- 增加 `var edgeHeight: CGFloat { FFVisualTokens.activePaneEdge }`。
- 保留 `edgeOutset` 供调宽把手使用（值不变）。

- [ ] **Step 4: 实现单行工具栏 + 视图选项**

Modify `UI/PaneToolbar.swift`:
- 删除第二行常驻的排序/分组/列按钮（保留内部状态与动作）。
- 第一行控件顺序：`back`、`forward`、`up`、面包屑（flex）、搜索（展开）、`viewOptionsButton`、溢出。
- 新增 `let viewOptionsButton = NSButton()`，图标 16pt；点击弹出 `FFViewOptionsPopover`。
- `viewOptions` popover 内容：视图模式（列表/图标）、排序字段/升降序、分组、列开关、密度（标准/紧凑）。
- 保留 `showsSecondaryRow: Bool { false }` 供测试/迁移判断。

Create `FFViewOptionsPopover.swift`:
- `final class FFViewOptionsPopover: NSViewController`，用 `NSPopover` 承载；控件直接调用现有 `PaneViewModel`/菜单动作；高度约 300pt；所有行 28pt。
- 入口 `show(relativeTo:of:preferredEdge:)`。

- [ ] **Step 5: 实现标准原生标签（单标签保留）**

Modify `UI/PaneTabs.swift`:
- 标签条高度 28pt；活动标签 24pt、非活动 20pt；活动标签底部 2px 系统强调色。
- 删除焊接背板/内凹 `FFTabSilhouette` 的绘制路径；`PaneTabStripBackdrop` 退役。
- 单标签时仍显示一个轻量标签（D-12）；`+` 按钮保留。
- 保留 `PaneTabItemView` 的拖拽起手、`strip`/`index`/`titleText`；保留 `FFDropResolver` 的所有几何接口。
- `refresh` 不再调用 `layoutSubtreeIfNeeded`；由布局系统下一帧处理。
- **同步改自检**：`runTabWeldSelfTest` 的焊接几何断言改为原生标签几何（活动标签高度/2px 指示/无背板）；不再断言 `FFTabSilhouette` 凸起。`syncGlowTabRects`/`glow.tabRect` 路径随之删除或置空。

- [ ] **Step 6: 实现统一状态栏**

Create `FFStatusBarView.swift`:
- `final class FFStatusBarView: NSView`，高度 28；`update(text:)` 设置单个 `NSTextField(labelWithString:)`，11pt `secondaryLabelColor`；`textForTesting` 返回字符串。
- `MainWindowController`：删除左右 `ExpandableDetailsBar` 的常驻底部条（保留详情能力，Task 5 接 popover）；在 `mainSplitView` 底部、`taskProgressBar` 上方加 `FFStatusBarView`，横跨操作区；高度约束 28。
- `updatePaneUI` 调用 `statusBar.update(text: FFStatusBarText.summary(...))`；选中变化也要更新（通过 PaneStore 后续接入，先直接读 `state`）。
- 状态栏左侧显示 `Active: <面板名>`；右侧显示 `⌘I 详情` 与磁盘空间。

- [ ] **Step 7: 工具药丸文案/提示**

Modify `SidebarView` / `FFDiscoverPanel`:
- `FFPillButton(title: "工具", icon: .wrench)`；tooltip `工具组（作用于当前面板/选择）`；保留原位置（品牌右侧）。
- `FFDiscoverPanel` 标题加上下文：`工具 · 作用于 <activePane 名称>`；工具行显示可用性/原因；未完成能力标注“未启用”。
- 不迁移入口、不新增工作台。

- [ ] **Step 8: 构建 + 截图 + 全量回归**

```bash
make build
pkill -f "MacOS/FlowFinder" || true
FF_SKIP_PERMISSION_GATE=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" &
sleep 5
screencapture -x /tmp/ff-shell.png
make swift-test
```

Expected: BUILD SUCCEEDED；截图无粉红发光/双工具栏/双详情栏；全量测试绿。把截图归档到 `docs/images/2026-10-21-uiux-shell.png`。

---

## Task 3: PaneStore + WindowFocusModel（单一真值）

**Files:**
- Create: `FlowFinder/FlowFinder/Model/PaneStore.swift`
- Create: `FlowFinder/FlowFinder/UI/WindowFocusModel.swift`
- Modify: `Model/PaneState.swift`（selection 逐步迁出）
- Modify: `Model/PaneViewModel.swift`（作为加载服务写入 Store）
- Modify: `UI/MainWindowController.swift`（订阅 Store）
- Modify: `UI/FileListView.swift` / `FileGridView.swift`（选择写入 Store）
- Test: `Tests/FlowFinderTests/PaneStoreTests.swift`
- Test: `Tests/FlowFinderTests/FFActivePaneIntegrationTests.swift`

**Interfaces:**
- Produces:
  - `enum PaneChange: Equatable { case initial, files, selection, filter, viewMode, all }`
  - `final class PaneStore`：`state`、`selection`、`@Published change`、`apply(state:)`、`setSelection(_:)`、`setFilter(_:)`、`setViewMode(_:)`
  - `final class WindowFocusModel`：`@Published activePane`、`activate(_:)`、`toggle()`

- [ ] **Step 1: 写 PaneStore 失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class PaneStoreTests: XCTestCase {
    func testSelectionDoesNotEmitFilesChange() {
        let store = PaneStore(initial: PaneState(path: "/tmp"))
        var changes: [PaneChange] = []
        let c = store.$change.sink { changes.append($0) }
        defer { c.cancel() }

        store.setSelection(["a"])
        XCTAssertFalse(changes.contains(.files))
        XCTAssertTrue(changes.contains(.selection))
    }

    func testFilesChangeEmitsFiles() {
        let store = PaneStore(initial: PaneState(path: "/tmp"))
        var state = store.state
        state.files = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false)]
        store.apply(state: state)
        XCTAssertEqual(store.change, .files)
    }

    func testFocusModelIsSingleSource() {
        let focus = WindowFocusModel()
        XCTAssertEqual(focus.activePane, .left)
        focus.activate(.right)
        XCTAssertEqual(focus.activePane, .right)
        focus.toggle()
        XCTAssertEqual(focus.activePane, .left)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Create a minimal `PaneStore`/`WindowFocusModel` stub; run `PaneStoreTests`; Expected: FAIL.

- [ ] **Step 3: 实现 PaneStore**

```swift
import Combine
import Foundation

enum PaneChange: Equatable {
    case initial, files, selection, filter, viewMode, all
}

final class PaneStore {
    private(set) var state: PaneState
    private(set) var selection: Set<FileEntry.ID> = []
    @Published private(set) var change: PaneChange = .initial

    init(initial: PaneState) { self.state = initial }

    func apply(state newState: PaneState) {
        let filesChanged = newState.files != state.files || newState.path != state.path
        let filterChanged = newState.searchQuery != state.searchQuery || newState.tagFilter != state.tagFilter
        let viewChanged = newState.viewMode != state.viewMode || newState.sortField != state.sortField
            || newState.sortAscending != state.sortAscending || newState.groupBy != state.groupBy
        state = newState
        if filesChanged { change = .files }
        else if filterChanged { change = .filter }
        else if viewChanged { change = .viewMode }
    }

    func setSelection(_ ids: Set<FileEntry.ID>) {
        guard ids != selection else { return }
        selection = ids
        change = .selection
    }

    func setFilter(_ tag: Tag?) {
        state.tagFilter = tag
        change = .filter
    }

    func setViewMode(_ mode: ViewMode) {
        state.viewMode = mode
        change = .viewMode
    }
}
```

Note: `FileEntry.ID` is `String` (path). `selection` uses `Set<String>`.

- [ ] **Step 4: 实现 WindowFocusModel**

```swift
import Combine

final class WindowFocusModel {
    @Published private(set) var activePane: PaneSide = .left
    func activate(_ side: PaneSide) { activePane = side }
    func toggle() { activePane = activePane == .left ? .right : .left }
}
```

- [ ] **Step 5: 接入 MainWindowController**

- 新增 `let leftStore = PaneStore(initial: leftPaneViewModel.state)`、`rightStore`、`let focus = WindowFocusModel()`。
- `setupBindings`：`leftPaneViewModel.$state.sink { self.leftStore.apply(state: $0) }`，右同理；`leftStore.$change`/`rightStore.$change` 驱动 `updatePaneUI` 的粒度分支（Task 4 完整接）。
- `activePane` 改为 `focus.activePane` 的计算属性，setter 调 `focus.activate`；`ffUndoManager` 不变。
- 所有 `activePane =` 的写入迁移到 `focus.activate`；`firstResponder` 只作为焦点显示，不再决定命令目标。
- `paneSideForHitView` 返回 side 时 `focus.activate(side)`；`activatePane` 内部同步 focus。
- 侧栏标签/位置回调读取 `focus.activePane`。

- [ ] **Step 6: 选择写入 Store**

- `FileListView`/`FileGridView` 的 `state.selectedFiles = ...` 写入替换为 `store.setSelection(ids)`；视图本地只保留高亮/滚动。
- 读取选中仍可从 `store.selection` 派生；`PaneState.selectedFiles` 暂时保留为兼容缓存，但只由 Store 写。
- `updatePaneUI` 的 `FFPaneReloadPolicy` 改为基于 `PaneChange`；选择变化不 reload。

- [ ] **Step 7: 写 activePane 集成测试**

```swift
func testClickingRightPaneActivatesIt() {
    let c = MainWindowController(startsWithSinglePane: false, showImmediately: false, runsSelfTests: false)
    defer { c.close() }
    c.window?.contentView?.layoutSubtreeIfNeeded()
    c.focus.activate(.left)
    c.focus.activate(.right)
    XCTAssertEqual(c.focus.activePane, .right)
}

func testSidebarTagTargetsActivePane() {
    let c = MainWindowController(startsWithSinglePane: false, showImmediately: false, runsSelfTests: false)
    defer { c.close() }
    c.focus.activate(.right)
    XCTAssertEqual(c.focus.activePane, .right)
    // 触发侧栏 tag 回调后断言 state.tagFilter 写在右侧 store
}
```

Run `PaneStoreTests` + `FFActivePaneIntegrationTests`; Expected: PASS。

- [ ] **Step 8: 全量回归**

`make build` + `make swift-test`；Expected: 全绿。

---

## Task 4: RenderPipeline 与选择不重载

**Files:**
- Create: `FlowFinder/FlowFinder/UI/RenderPipeline.swift`
- Modify: `UI/FileListView.swift`
- Modify: `UI/FileGridView.swift`
- Modify: `UI/MainWindowController.swift`
- Test: `Tests/FlowFinderTests/RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `PaneStore`, `PaneChange`
- Produces:
  - `protocol FFRenderTarget: AnyObject { func applyFiles(_ rows: [FileEntry]); func applySelection(_ ids: Set<String>) }`
  - `final class RenderPipeline { func consume(store: PaneStore, list: FFRenderTarget, grid: FFRenderTarget) }`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import FlowFinder

final class RenderPipelineTests: XCTestCase {
    final class Spy: FFRenderTarget {
        var fileUpdates = 0
        var selectionUpdates = 0
        func applyFiles(_ rows: [FileEntry]) { fileUpdates += 1 }
        func applySelection(_ ids: Set<String>) { selectionUpdates += 1 }
    }

    func testSelectionOnlyUpdatesSelection() {
        let store = PaneStore(initial: PaneState(path: "/tmp"))
        let list = Spy(), grid = Spy()
        let pipeline = RenderPipeline()
        pipeline.consume(store: store, list: list, grid: grid)
        store.setSelection(["a"])
        pipeline.consume(store: store, list: list, grid: grid)
        XCTAssertEqual(list.fileUpdates, 0)
        XCTAssertEqual(list.selectionUpdates, 1)
        XCTAssertEqual(grid.fileUpdates, 0)
        XCTAssertEqual(grid.selectionUpdates, 1)
    }

    func testFilesChangeUpdatesOncePerTarget() {
        let store = PaneStore(initial: PaneState(path: "/tmp"))
        let list = Spy(), grid = Spy()
        let pipeline = RenderPipeline()
        var state = store.state
        state.files = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false)]
        store.apply(state: state)
        pipeline.consume(store: store, list: list, grid: grid)
        XCTAssertEqual(list.fileUpdates, 1)
        XCTAssertEqual(grid.fileUpdates, 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Minimal stub; `RenderPipelineTests`; Expected: FAIL.

- [ ] **Step 3: 实现 RenderPipeline**

```swift
protocol FFRenderTarget: AnyObject {
    func applyFiles(_ rows: [FileEntry])
    func applySelection(_ ids: Set<String>)
}

final class RenderPipeline {
    func consume(store: PaneStore, list: FFRenderTarget, grid: FFRenderTarget) {
        guard store.change != .initial else { return }
        switch store.change {
        case .initial, .files, .filter, .viewMode, .all:
            list.applyFiles(store.state.files)
            grid.applyFiles(store.state.files)
        case .selection:
            list.applySelection(store.selection)
            grid.applySelection(store.selection)
        }
    }
}
```

- [ ] **Step 4: 让 FileListView/FileGridView 实现 FFRenderTarget**

- `applyFiles(_:)`：设置 `viewModel` 的展示快照（不重建列；列由视图选项触发一次）；`tableView.reloadData()` / `collectionView.reloadData()` 各一次。
- `applySelection(_:)`：只更新 `selectedRowIndexes`/`collectionView.selectionIndexPaths`，不 reload、不重建 key loop、不取消缩略图。
- 删除 `updateViewMode` 中的 `reloadData`/key-loop 重建；视图模式变化由 `applyFiles` 或一次显式 rebuild 处理。
- **删除 FileListView/FileGridView 对 `viewModel.$state` 的直接 reload 订阅**；只保留加载完成/选择事件，渲染由 RenderPipeline 驱动。
- `FileListView.rebuildDisplayRows` 删除诊断全量比较；分页追加用 `insertRows` 或一次 `reloadData`，二选一，不能多路。

- [ ] **Step 5: 接入 MainWindowController**

- `updatePaneUI` 不再直接 `reloadData`；改为 `RenderPipeline.consume(...)`。
- 保留 toolbar/breadcrumb/status 的轻量更新；`syncTabStrip` 只在 `.files` 或路径变化时调用。
- 每次 `PaneChange` 只消费一次；在 `DispatchQueue.main.async` 合并同一 runloop 的多次变更（用一个 pending flag）。

- [ ] **Step 6: 结构测试 + 全量回归**

Run `RenderPipelineTests`、`make swift-test`；Expected: 全绿。用 `sample` 在真机选中 100 次，确认无 `reloadData` 风暴（后续 Task 11 正式采样）。

---

## Task 5: MetadataService + 按需详情 + 缩略图缓存

**Files:**
- Create: `FlowFinder/FlowFinder/Bridge/MetadataService.swift`
- Create: `FlowFinder/FlowFinder/UI/FFDetailsPopoverController.swift`
- Modify: `UI/ExpandableDetailsBar.swift`（收编为详情内容视图）
- Modify: `UI/MainWindowController.swift`（⌘I、状态栏详情入口）
- Modify: `Bridge/ThumbnailManager.swift`
- Test: `Tests/FlowFinderTests/FFMetadataServiceTests.swift`
- Test: `Tests/FlowFinderTests/FFDetailsIntegrationTests.swift`

**Interfaces:**
- Produces:
  - `struct FFFileMetadata: Equatable`（带默认参数的 init，见 Step 3）
  - `protocol FFMetadataProviding { func load(path: String, completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID; func cancel(_ token: UUID) }`
  - `final class FFMetadataService: FFMetadataProviding`（`init(provider: FFMetadataProviding)`）
  - `FFDetailsPopoverController.show(for:relativeTo:of:)`

- [ ] **Step 1: 写 generation/cancel 失败测试**

```swift
import XCTest
@testable import FlowFinder

final class FFMockMetadataProvider: FFMetadataProviding {
    var requests: [(String, (Result<FFFileMetadata, Error>) -> Void, UUID)] = []
    func load(path: String, completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID {
        let id = UUID(); requests.append((path, completion, id)); return id
    }
    func cancel(_ token: UUID) {}
}

final class FFMetadataServiceTests: XCTestCase {
    func testOldResultIsDroppedAfterNewRequest() {
        let provider = FFMockMetadataProvider()
        let service = FFMetadataService(provider: provider)
        var got: [String] = []
        service.request(path: "/a") { got.append($0.path) }
        service.request(path: "/b") { got.append($0.path) }
        provider.requests[0].1(.success(FFFileMetadata(path: "/a", kind: "", size: 0, modified: nil, created: nil, pageCount: nil, duration: nil)))
        provider.requests[1].1(.success(FFFileMetadata(path: "/b", kind: "", size: 0, modified: nil, created: nil, pageCount: nil, duration: nil)))
        XCTAssertEqual(got, ["/b"])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Stub `FFMetadataService`; run; Expected: FAIL.

- [ ] **Step 3: 实现 MetadataService**

先定义 `FFFileMetadata`（默认参数保证测试与生产都可用）：

```swift
struct FFFileMetadata: Equatable {
    let path: String
    let kind: String
    let size: UInt64
    let modified: Date?
    let created: Date?
    let pageCount: Int?
    let duration: TimeInterval?
    let finderComment: String?
    let folderItemCount: Int?

    init(path: String, kind: String, size: UInt64,
         modified: Date? = nil, created: Date? = nil,
         pageCount: Int? = nil, duration: TimeInterval? = nil,
         finderComment: String? = nil, folderItemCount: Int? = nil) {
        self.path = path; self.kind = kind; self.size = size
        self.modified = modified; self.created = created
        self.pageCount = pageCount; self.duration = duration
        self.finderComment = finderComment; self.folderItemCount = folderItemCount
    }
}
```

`FFMetadataService` 用 `DispatchQueue(qos: .utility)` + generation token（每次 request 递增）。
- 读取内容：文件大小/类型/日期、`kMDItemFinderComment`、PDF 页数、AV 时长、文件夹项数；全部后台。
- 主线程回调前检查 token 是否仍是当前请求；关闭/取消时丢弃。
- 提供 `request(path:completion:) -> UUID` 与 `cancel(_:)`。

- [ ] **Step 4: 实现详情 popover**

- `FFDetailsPopoverController` 用 `NSPopover`，内容用 `ExpandableDetailsBar` 的详情视图（去掉常驻底栏/浮动卡样式）。
- `show(for: FileEntry, relativeTo: NSView, of: NSView)`；打开时显示骨架，元数据到达后更新。
- 关闭时 `service.cancel(token)`；多选显示聚合摘要，不加载媒体。
- `MainWindowController` 绑定 `⌘I`：`showDetailsForActiveSelection()`；状态栏“详情 ⌘I”也可点击。

- [ ] **Step 5: 修缩略图缓存**

Modify `ThumbnailManager`:
- key 使用 `SHA256(path + size + mtime)` 或 `path.hashValue` 的十六进制字符串，不含 `/`。
- 写盘前 `createDirectory`；失败只记录一次，不每次重试。
- `cleanupDiskCacheIfNeeded` 改为按时间/容量摊销（例如每 100 次写或启动一次），不在每次写后枚举。

- [ ] **Step 6: 详情集成测试**

```swift
func testCmdIOpensDetailsPopoverForActivePane() {
    let c = MainWindowController(startsWithSinglePane: false, showImmediately: false, runsSelfTests: false)
    defer { c.close() }
    c.focus.activate(.right)
    c.showDetailsForActiveSelection()
    XCTAssertNotNil(c.detailsPopoverForTesting)
}
```

Run `FFMetadataServiceTests` + `FFDetailsIntegrationTests`; Expected: PASS.

- [ ] **Step 7: 全量回归 + 真机检查**

`make build` + `make swift-test`；打开视频/PDF/大目录，确认选中不再卡、详情按需加载。

---

## Task 6: 标签计数、任务轮询、诊断与同步 FFI 止血

**Files:**
- Modify: `UI/MainWindowController.swift`（tag count gating、diagnostics）
- Modify: `UI/TagCountService.swift`
- Modify: `Bridge/TaskSchedulerManager.swift`
- Modify: `UI/TaskProgressBar.swift`
- Modify: `UI/TaskPanelWindowController.swift`
- Modify: `Bridge/CoreBridge.swift`（`invalidateCache` async）
- Modify: `Model/PaneState.swift`
- Test: `Tests/FlowFinderTests/FFPerformancePolicyTests.swift`

**Interfaces:**
- Produces:
  - `FFPerformancePolicy.shouldRefreshTagCounts(previous:current:) -> Bool`
  - `FFPerformancePolicy.shouldPublishTasks(previous:next:) -> Bool`
  - `CoreBridge.invalidateCacheAsync(completion:)`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import FlowFinder

final class FFPerformancePolicyTests: XCTestCase {
    func testTagCountsOnlyRefreshOnPathOrFilesChange() {
        var a = PaneState(path: "/tmp")
        a.files = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false)]
        var b = a
        b.selectedFiles = a.files
        XCTAssertFalse(FFPerformancePolicy.shouldRefreshTagCounts(previous: a, current: b))
        b.files.append(FileEntry(path: "/tmp/b", name: "b", isDirectory: false))
        XCTAssertTrue(FFPerformancePolicy.shouldRefreshTagCounts(previous: a, current: b))
    }

    func testTaskPublishOnlyOnChange() {
        let a = [FFTaskSummary(id: "1", title: "Copy", progress: 0.5, state: .running)]
        XCTAssertFalse(FFPerformancePolicy.shouldPublishTasks(previous: a, next: a))
        let b = [FFTaskSummary(id: "1", title: "Copy", progress: 0.6, state: .running)]
        XCTAssertTrue(FFPerformancePolicy.shouldPublishTasks(previous: a, next: b))
    }
}
```

- [ ] **Step 2: 实现策略并接入**

- `FFPerformancePolicy` 纯函数；`scheduleTagCountRefresh` 只在 path/files 变化时调用。
- `TaskSchedulerManager` 只在任务数组变化时发布；无任务时停表；`TaskPanelWindowController` 不再每 tick reload。
- `FileListView.rebuildDisplayRows` 删除诊断名称数组比较。
- `CoreBridge.invalidateCache` 改为 async（不阻塞主线程）；`PaneState.refresh` 调用 async 版本。

- [ ] **Step 3: 测试 + 全量回归**

Run `FFPerformancePolicyTests` + `make swift-test`；Expected: 全绿。真机选中/导航，确认标签计数不再每次状态发射触发。

---

## Task 7: ToolProtocol/Registry + 工具 popover

**Files:**
- Create: `FlowFinder/FlowFinder/UI/FFToolProtocol.swift`
- Create: `FlowFinder/FlowFinder/UI/FFToolRegistry.swift`
- Create: `FlowFinder/FlowFinder/UI/FFToolPopoverController.swift`
- Modify: `UI/FFDiscoverPanel.swift` / `UI/SidebarView.swift`
- Modify: `UI/MainWindowController.swift`（工具入口、上下文）
- Test: `Tests/FlowFinderTests/FFToolRegistryTests.swift`

**Interfaces:**
- Produces:
  - `final class FFToolContext { let activePane: PaneSide; let currentPath: String; let selection: [FileEntry]; weak var window: MainWindowController? }`
  - `enum FFToolAvailability: Equatable { case available, needsSelection, needsFolder, disabled(String) }`
  - `protocol FFTool { var id: String { get }; var title: String { get }; var icon: FFIconName { get }; var keywords: [String] { get }; func availability(in: FFToolContext) -> FFToolAvailability; func run(in: FFToolContext) }`
  - `final class FFToolRegistry { static let shared; func register(_:); func availableTools(for:) -> [(FFTool, FFToolAvailability)] }`

- [ ] **Step 1: 写注册表失败测试**

```swift
import XCTest
@testable import FlowFinder

final class FFToolRegistryTests: XCTestCase {
    struct FakeTool: FFTool {
        let id: String
        let title: String
        var icon: FFIconName { .folder }
        var keywords: [String] { [] }
        func availability(in context: FFToolContext) -> FFToolAvailability { .available }
        func run(in context: FFToolContext) {}
    }

    func testRegisterAndAvailability() {
        let registry = FFToolRegistry()
        registry.register(FakeTool(id: "dup", title: "重复文件"))
        let context = FFToolContext(activePane: .left, currentPath: "/tmp", selection: [], window: nil)
        XCTAssertEqual(registry.availableTools(for: context).count, 1)
        XCTAssertEqual(registry.availableTools(for: context).first?.1, .available)
    }

    func testDuplicateIDIsRejected() {
        let registry = FFToolRegistry()
        registry.register(FakeTool(id: "dup", title: "A"))
        registry.register(FakeTool(id: "dup", title: "B"))
        XCTAssertEqual(registry.availableTools(for: FFToolContext(activePane: .left, currentPath: "/tmp", selection: [], window: nil)).count, 1)
    }
}
```

- [ ] **Step 2: 实现协议/注册表**

- `FFToolRegistry` 用 `[String: FFTool]`；重复 id 保留第一个并记录断言日志；`availableTools` 按注册顺序返回 `(tool, availability)`。
- `FFToolContext` 由 `MainWindowController.toolContext()` 构建：activePane、当前 path、selection（从 PaneStore）、weak window。
- `FFToolPopoverController`：标题 `工具 · 作用于 <面板>`；副标题路径/选择；工具卡显示可用性；点击运行；未启用显示原因。
- `SidebarView` 工具药丸改为打开 `FFToolPopoverController`；`FFDiscoverPanel` 的硬编码枚举逐步退役。

- [ ] **Step 3: 接入现有工具**

- 重复文件扫描：`FFTool` 包装，`run` 调用现有 `menuDuplicateScan`，扫描默认当前活动路径（修 `DuplicateScanWindowController` 的 `~`）。
- 批量重命名：`FFTool` 包装，`run` 调用现有 `menuBatchRename`；传入当前选择。
- 标签整理/任务面板：按现有能力注册；未完成能力 `disabled("未启用")`。
- 工具执行结果仍用现有窗口；Phase 3 再统一 workspace。

- [ ] **Step 4: 测试 + 真机检查**

Run `FFToolRegistryTests` + `make swift-test`；打开工具药丸，确认上下文/可用性/执行路径正确。

---

## Task 8: TaskService 与统一进度/任务中心

**Files:**
- Create: `FlowFinder/FlowFinder/Bridge/TaskService.swift`
- Modify: `UI/TaskProgressBar.swift`
- Modify: `UI/TaskPanelWindowController.swift`
- Modify: `UI/MainWindowController+MenuActions.swift`（复制/移动）
- Modify: `UI/DuplicateScanWindowController.swift` / `BatchRenameWindowController.swift`（接入任务）
- Test: `Tests/FlowFinderTests/FFTaskServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct FFTask: Identifiable, Equatable { id, title, detail, completedBytes, totalBytes, state, startedAt }`
  - `enum FFTaskState: Equatable { queued, running, paused, finished, failed(String), cancelled }`
  - `final class FFTaskService: ObservableObject { @Published private(set) var tasks: [FFTask]; func upsert(_:); func cancel(_:); func retry(_:) }`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import FlowFinder

final class FFTaskServiceTests: XCTestCase {
    func testProgressPublishesAndCompletes() {
        let service = FFTaskService()
        var task = FFTask(id: "1", title: "Copy", detail: "a.txt", completedBytes: 0, totalBytes: 100, state: .running, startedAt: Date())
        service.upsert(task)
        XCTAssertEqual(service.tasks.count, 1)
        task.completedBytes = 100
        task.state = .finished
        service.upsert(task)
        XCTAssertEqual(service.tasks.first?.state, .finished)
    }

    func testCancelMarksState() {
        let service = FFTaskService()
        let task = FFTask(id: "1", title: "Copy", detail: "", completedBytes: 0, totalBytes: 100, state: .running, startedAt: Date())
        service.upsert(task)
        service.cancel("1")
        XCTAssertEqual(service.tasks.first?.state, .cancelled)
    }
}
```

- [ ] **Step 2: 实现 TaskService**

- `@Published tasks`；`upsert` 只在变化时发布（按 id 替换）。
- 取消/重试回调由任务拥有者注入；服务本身不执行文件操作。
- `TaskProgressBar` 订阅服务，显示当前任务文件名 + 字节进度 + 取消按钮；不再 2s 自动隐藏。
- `TaskPanelWindowController` 订阅服务，按变化 reload；无任务显示空状态；不再每 0.5s reload。
- 复制/移动/查重/批量调用 `TaskService.upsert` 更新进度；取消时调用现有操作取消路径（如可用）。

- [ ] **Step 3: 测试 + 全量回归**

Run `FFTaskServiceTests` + `make swift-test`；真机复制大文件，确认进度/取消/任务中心。

---

## Task 9: 拆分 MainWindowController 并删除旧路径

**Files:**
- Create: `UI/WindowShellCoordinator.swift`
- Create: `UI/PaneCoordinator.swift`
- Create: `UI/SidebarCoordinator.swift`
- Create: `UI/ToolCoordinator.swift`
- Create: `UI/TaskCoordinator.swift`
- Modify: `UI/MainWindowController.swift`（瘦身/转发）
- Delete/retire: `UI/FFDiscoverPanel.swift` 的旧枚举、`UI/ExpandableDetailsBar.swift` 的常驻栏路径、旧 `updateViewMode` reload 路径
- Test: existing + `FFShellCoordinatorTests.swift`

**Interfaces:**
- `WindowShellCoordinator` 持有 window、sidebar、pane、status、task 子协调器；`MainWindowController` 只保留生命周期与转发。
- 每个 coordinator 只依赖 `PaneStore`/`WindowFocusModel`/`TaskService`/`ToolRegistry`，不反向依赖 MainWindowController 的具体视图。

- [ ] **Step 1: 写 coordinator 结构测试**

- 断言 `WindowShellCoordinator` 创建后包含 sidebar/pane/status/task 引用；`PaneCoordinator` 的 activePane 与 focus 同步；`ToolCoordinator` 使用 registry；`TaskCoordinator` 订阅 task service。

- [ ] **Step 2: 搬迁代码**

- 按职责把 MainWindowController 的布局/侧栏/面板/工具/任务代码搬到 coordinators；保留原有 public/internal API 作为转发，避免一次性断掉测试。
- 删除旧 `updateViewMode` reload、旧详情栏、旧 Discover 枚举、旧快捷键 switch。
- 全量构建/测试；逐项比对 `MainWindowController` 行数下降。

- [ ] **Step 3: 回归**

`make build` + `make swift-test` + `FF_SELFTEST=1`；检查所有主旅程。旧路径删除后，任何测试失败都先回滚该片，不继续。

---

## Task 10: 设置/搜索/查重/批量的一致性与安全默认

**Files:**
- Modify: `UI/SettingsWindowController.swift`
- Modify: `UI/SearchPanelController.swift`
- Modify: `UI/DuplicateScanWindowController.swift`
- Modify: `UI/BatchRenameWindowController.swift`
- Modify: `UI/ConflictResolver.swift`
- Modify: `UI/DeleteConfirmDialog.swift`
- Test: `Tests/FlowFinderTests/FFDestructivePolicyTests.swift`
- Test: `Tests/FlowFinderTests/FFShortcutSettingsTests.swift`

**Interfaces:**
- `FFConflictPolicy.defaultDecision` = `.skip`/`.keepBoth`；Replace 必须显式。
- `FFShortcutSettings` 使用 `FFKeyboardContract`；冲突检测。
- 查重默认扫描活动路径；默认不勾选；永久删除与废纸篓分开。

定义最小类型（Step 2 实现）：

```swift
enum FFConflictDecision: Equatable { case skip, keepBoth, replace }
enum FFConflictPolicy { static let defaultDecision: FFConflictDecision = .skip }
enum FFDuplicateSelectionPolicy {
    static func initialSelection(groups: [Any]) -> Set<String> { [] }
}
enum FFDeleteCopy { static let permanentDeleteMentionsUndo = false }
```

- [ ] **Step 1: 写安全默认失败测试**

```swift
func testConflictDefaultIsNotReplace() {
    XCTAssertNotEqual(FFConflictPolicy.defaultDecision, .replace)
}
func testDuplicateScanDefaultsToNoSelection() {
    XCTAssertTrue(FFDuplicateSelectionPolicy.initialSelection(groups: []).isEmpty)
}
func testPermanentDeleteDoesNotPromiseUndo() {
    XCTAssertFalse(FFDeleteCopy.permanentDeleteMentionsUndo)
}
```

- [ ] **Step 2: 实现策略 + UI**

- 冲突默认“跳过/保留两者”；Replace 需要显式点击；支持“全部应用”。
- 永久删除文案明确不可撤销；删除默认移到废纸篓；`DeleteConfirmDialog` 的“不再询问”可重置。
- 查重默认活动路径；结果默认不勾选；永久删除二次确认；扫描可取消。
- 批量重命名先预览后执行；冲突检测；可返回修改。
- 设置：删除死开关；快捷键编辑器读 `FFKeyboardContract`，显示冲突/恢复默认；修正“关闭窗口/关闭标签”标签。
- 搜索：统一 28pt 搜索框、范围 chip、清除按钮；双击结果在活动面板定位并选中父目录。

- [ ] **Step 3: 测试 + 真机截图**

Run the new tests + `make swift-test`；截图设置/搜索/查重/批量，确认 tokens/状态一致。

---

## Task 11: 性能验收、视觉验收与文档

**Files:**
- Modify: `UI/FFPaneDrag.swift` / relevant hot paths（signposts）
- Modify: `docs/HANDOVER.md`
- Modify: `docs/REQUIREMENTS-LEDGER.md`（R-15）
- Modify: `CHANGELOG.md`
- Modify: `docs/SPEC-2026-10-20-UIUX-REDO.md`（状态/实测）
- Create: `docs/PLAN-2026-10-20-UIUX-REDO.md`（本文件）

- [ ] **Step 1: 加 signposts**

- `FFRender.frame`（RenderPipeline consume）
- `FFDetails.request` / `FFDetails.load`
- `FFTask.publish`
- `FFPaneStore.change`
- 只用 Debug/性能构建；Release 不输出日志。

- [ ] **Step 2: 性能采样**

```bash
make build
pkill -f "MacOS/FlowFinder" || true
FF_SKIP_PERMISSION_GATE=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" &
PID=$(pgrep -f "MacOS/FlowFinder" | head -1)
# 用户执行：选中 100 次、滚动 500 项目录、打开详情、拖 3 秒
sample "$PID" 5 -file /tmp/ff-uiux-perf.txt
```

检查：
- 无 `reloadData` 在选中路径；
- 无主线程 >100ms；
- 无同步 `getattrlist`/`attributesOfFileSystem`/`contentsOfDirectory` 在选中/详情打开路径；
- 缩略图缓存命中。

- [ ] **Step 3: 视觉验收**

- 1060×700 / 1400×900；浅/深色；高对比/Reduce Motion。
- 主窗口、设置、搜索、查重、批量、工具 popover、详情 popover、空/错误/加载。
- 截图归档 `docs/images/2026-10-21-uiux-*`。
- 对照 D-06：无粉红发光/玻璃白边/多层阴影；系统强调色；2px 活动边。

- [ ] **Step 4: 可访问性验收**

- 所有图标按钮有 `accessibilityLabel`/`toolTip`；标签关闭、工具栏、工具卡、详情按钮均可键盘到达。
- 焦点顺序 = 视觉顺序；焦点环 2px 系统强调色。
- 工具卡/列表行/标签/关闭按钮的 hit target ≥24pt（桌面）；不再出现 14×14 的“×”。
- VoiceOver 走查主旅程：⌘1/⌘2 → 方向键选择 → Space → Return → ⌘⌫ → 工具 popover → 详情。
- Reduce Motion 下无弹跳/长动画；高对比模式下分隔线与选中可见。
- 增加 `FFAccessibilityTests`：关键控件 label 非空、hit target 尺寸、状态栏文本可读。

- [ ] **Step 5: 全量验证**

```bash
make build
make swift-test
pkill -f "MacOS/FlowFinder" || true
rm -f /tmp/ff-debug.log
FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" &
sleep 9
pkill -f "MacOS/FlowFinder" || true
grep -c "FAIL" /tmp/ff-debug.log
```

Expected: BUILD SUCCEEDED；所有 XCTest 绿；自检 FAIL 0；性能采样满足 D-11。

- [ ] **Step 6: 更新文档**

- `HANDOVER.md`：新增“UI/UX 与结构整改”章节；模块表、迁移切片、性能门槛、未验项。
- `REQUIREMENTS-LEDGER.md`：新增 R-15，逐条引用 D-01..D-12；更新测试/自检数字。
- `CHANGELOG.md`：未发版段新增条目（视觉/交互/结构/性能）。
- 本规格状态改为“已实现/已验证（注明人工未验项）”。
- **不要提交 commit**；由用户决定提交。

---

## Self-Review

**Spec coverage:**
- §0 D-01..D-12 → 全文与 Task 1/2/3/7/10 对应。
- §1 审查证据 → 本计划的任务直接对应 F-01..F-14。
- §2 目标/非目标 → Global Constraints + Task 11 验收。
- §3 目标 IA/布局 → Task 2（外壳）、Task 7（工具）、Task 10（设置/搜索/查重/批量）。
- §4 视觉系统 → Task 1（tokens）、Task 2（外壳）、Task 11（视觉验收）。
- §5 交互契约 → Task 1（快捷键）、Task 3（activePane）、Task 5（详情）、Task 10（安全默认）。
- §6 架构/迁移 → Task 3/4/5/6/7/8/9。
- §7 性能验收 → Task 4/5/6/11。
- §8 测试策略 → 每个任务的测试步骤 + Task 11。
- §9 风险 → Global Constraints + Task 9 回滚纪律。
- §10 文件落点 → File Structure。
- §11 验收清单 → Task 11 + 各任务验收。
- §12 显式假设 → Global Constraints。

**Placeholder scan:** 无 TBD/TODO；每个任务含具体文件、代码或命令。

**Type consistency:**
- `PaneStore`/`PaneChange` 在 Task 3 定义，Task 4/6/9 使用一致。
- `FFRenderTarget`/`RenderPipeline` 在 Task 4 定义，Task 9 使用。
- `FFMetadataProviding`/`FFMetadataService` 在 Task 5 定义，Task 10/11 使用。
- `FFTool`/`FFToolRegistry`/`FFToolContext` 在 Task 7 定义，Task 9 使用。
- `FFTask`/`FFTaskService` 在 Task 8 定义，Task 11 使用。
- `FFKeyboardContract` 在 Task 1 定义，Task 10 使用。
- `FFStatusBarText` 在 Task 1 定义，Task 2 使用。

**Known sequencing note:** Task 2 先做视觉外壳，但详情/工具仍用旧路径；Task 5/7 再接新路径，符合 D-10 的原地绞杀顺序。每片验收后再删旧路径。

---

## Execution Handoff

Plan complete and saved to `docs/PLAN-2026-10-20-UIUX-REDO.md`. 两种执行方式：

1. **Subagent-Driven（推荐）**：每个 Task 派一个新子代理，任务间做两阶段审查；适合独立任务，但本计划跨文件强耦合，交接成本高。
2. **Inline Execution**：在当前会话按 Task 1→11 顺序执行，每个 Task 完成即跑测试/截图并停下汇报；适合共享上下文与强耦合改动。

用户未授权 commit；执行时只改工作树，不提交。
