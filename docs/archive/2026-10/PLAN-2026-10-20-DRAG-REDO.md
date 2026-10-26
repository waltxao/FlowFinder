# 标签拖拽重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按路线 B 重做标签拖拽：保留同窗口/跨窗口全部能力，修掉单栏落点错侧与兄弟标签丢失，把拖动热路径做到严格 60fps，并建立纯函数 + 真实链路 + 性能结构的测试护栏。

**Architecture:** 四层——`FFDropResolver`（纯落点决策）、`FFDragGeometryCache`（每窗口屏幕坐标几何）、`FFDragOverlay`（轻量浮层/插入线/描边，不参与 Auto Layout）、`FFPaneDragController`（会话与帧调度）。窗口拖动优先走系统 `performDrag(with:)`，失败回退 60Hz 合并的自管拖动。

**Tech Stack:** Swift 5 / AppKit / XCTest；Rust core 不动。

**Spec:** `docs/SPEC-2026-10-20-DRAG-REDO.md`

## Global Constraints

- 部署目标 macOS 12.0；不要引入新依赖。
- **不要提交 commit**：用户未授权 git commit。每个任务结束只做构建与测试，改动留在工作树。
- **TDD**：先写失败测试并亲眼确认失败，再写最小实现；禁止先写生产代码再补测试。
- 现有 190 条 XCTest 必须保持全绿；应用内 `FF_SELFTEST=1` 必须保持 0 失败。
- 性能门槛：连续拖 3 秒，主线程单次阻塞 <16ms，帧间隔 p95 <16.7ms；拖动期不得出现 `FileListView.layout → applyColumnFit → rebuildColumns`。
- 保留现有标签焊接、36pt 标题带、窗口圆角、主题令牌；不做真位移、列表列、主题重设计。
- 新 Swift 文件必须在 `FlowFinder.xcodeproj/project.pbxproj` 注册四处（PBXBuildFile / PBXFileReference / Group / Sources），使用未占用的独立 ID 段；注册前先 grep 候选 ID。
- 测试命令：
  - 全量：`make swift-test`
  - 单类：`xcodebuild test -project FlowFinder/FlowFinder.xcodeproj -scheme FlowFinderTests -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -only-testing:FlowFinderTests/<ClassName>`
- 构建：`make build`；桌面副本：`make demo`（只在需要人工手感验证时执行）。

---

## 执行状态（2026-10-20）

| Task | 状态 | 证据 |
|---|---|---|
| 0 窗口拖动 spike | **代码已接，人工待验** | `performDrag` 默认路径构建通过；`FF_NATIVE_WINDOW_DRAG=0` 回退可用；合成事件无法可靠驱动窗口 |
| 1 纯 resolver | 完成 | 14 条测试，修前 13 失败 → 全绿 |
| 2 几何缓存 | 完成 | 3 条测试全绿 |
| 3 单栏落点/兄弟标签 | 完成 | 6 条集成测试，修前 5 失败 → 全绿 |
| 4 插入线/列重算守卫 | 完成 | 3 条结构测试全绿 |
| 5 控制器接入 + 60Hz | 完成 | 构建 + 自检 + 全量测试通过 |
| 6 轻量浮层 | **代码完成，视觉待人工** | 构建/自检通过；完整胶囊与 1px 描边需真机拖拽确认 |
| 7 窗口落地/性能守卫 | 完成 | 重开测试 + 策略测试 + 全量测试通过 |
| 8 自检真实链路 | 完成 | 自检 ①–⑩ 全 PASS，135 项 0 失败 |
| 9 性能/文档 | **文档完成，60fps 待采样** | `make swift-test` 190/0；真实拖拽采样受合成事件限制 |

最终自动化基线：**190 条 XCTest / 0 失败；FF_SELFTEST 135 项 / 0 失败**。
未完成项：真实拖拽 60fps 采样、活动标签浮层/窗口拖动手感人工复验。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `FlowFinder/FlowFinder/UI/FFDropResolver.swift`（新） | 落点纯函数 + 几何/决策类型 |
| `FlowFinder/FlowFinder/UI/FFDragGeometryCache.swift`（新） | 从 MainWindowController 构建/缓存屏幕坐标几何 |
| `FlowFinder/FlowFinder/UI/FFDragOverlay.swift`（新） | 浮层、插入线、落点描边；无 Auto Layout |
| `FlowFinder/FlowFinder/UI/FFPaneDrag.swift` | 会话、帧调度、窗口拖动、执行决策 |
| `FlowFinder/FlowFinder/UI/PaneTabs.swift` | 插入线改为 frame-based；暴露测试访问器；修快照背景 |
| `FlowFinder/FlowFinder/UI/MainWindowController.swift` | `operationSide` 按半区；几何构建；监视器清理；`updatePaneUI` 拆分；磁盘空间异步 |
| `FlowFinder/FlowFinder/UI/MainWindowController+Tabs.swift` | 单栏拆双栏保留标签；源空折叠/关窗；自检改真实链路 |
| `FlowFinder/FlowFinder/UI/FileListView.swift` | 列重算宽度守卫 |
| `FlowFinder/FlowFinder/UI/FFListColumns.swift` | `FFColumnFitPolicy.shouldFit` 纯函数 |
| `FlowFinder/FlowFinder/Model/PaneState.swift` | `PaneState` / `SortField` / `ViewMode` 加 Equatable |
| `FlowFinder/FlowFinder/App/AppDelegate.swift` | `applicationShouldHandleReopen` |
| `FlowFinder/Tests/FlowFinderTests/FFDropResolverTests.swift`（新） | 纯函数穷举 |
| `FlowFinder/Tests/FlowFinderTests/FFDragGeometryCacheTests.swift`（新） | 几何缓存 |
| `FlowFinder/Tests/FlowFinderTests/FFDragIntegrationTests.swift`（新） | 真实窗口链路 |
| `FlowFinder/Tests/FlowFinderTests/FFDragPerformanceStructureTests.swift`（新） | 结构性性能护栏 |
| `FlowFinder/FlowFinder.xcodeproj/project.pbxproj` | 注册新文件 |

---

## Task 0: 窗口拖动可行性 spike（先验证最大技术风险）

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFPaneDrag.swift:294-356`

**Interfaces:**
- Produces: `FF_NATIVE_WINDOW_DRAG=0` 回退开关；结论写入 `docs/SPEC-2026-10-20-DRAG-REDO.md` 的风险表。

- [ ] **Step 1: 加开关与原生拖动**

在 `FFPaneDragController` 加：

```swift
private var useNativeWindowDrag: Bool {
    ProcessInfo.processInfo.environment["FF_NATIVE_WINDOW_DRAG"] != "0"
}
```

在 `.dragWindow` 分支：

```swift
case .dragWindow:
    guard let window = event.window else { return event }
    if useNativeWindowDrag {
        mode = .none
        window.performDrag(with: event)
        return nil
    }
    mode = .windowDrag
    dragOwner = owner
    didExceedThreshold = false
    startScreenPoint = window.convertPoint(toScreen: point)
    startWindowOrigin = window.frame.origin
    return event
```

- [ ] **Step 2: 构建并人工验证**

```bash
make build
pkill -f "MacOS/FlowFinder" || true
FF_SKIP_PERMISSION_GATE=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder"
```

检查：
- 拖侧栏空白：窗口跟手，不再逐事件迟滞。
- 拖标签：标签拖动正常，窗口不动。
- 拖标签条空白：窗口动，标签不动。
- 拖标签途中经过标题条空白：不触发窗口拖动。

- [ ] **Step 3: 记录结论**

- 若通过：保留默认 `useNativeWindowDrag = true`；Task 7 只做监视器清理与回退路径。
- 若冲突（窗口与标签同时动、mouseUp 丢失、点击失效）：设置 `FF_NATIVE_WINDOW_DRAG=0`，在 Task 7 实现 60Hz 合并回退；把现象与结论写入规格 §8 风险表。
- 不要为了 spike 提交 commit。

---

## Task 1: 纯落点决策 `FFDropResolver`

**Files:**
- Create: `FlowFinder/FlowFinder/UI/FFDropResolver.swift`
- Create: `FlowFinder/Tests/FlowFinderTests/FFDropResolverTests.swift`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift:2799`（`PaneSide` 加 `Equatable, CaseIterable`）
- Modify: `FlowFinder/FlowFinder.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  - `struct FFDragSource { let windowID: ObjectIdentifier; let side: PaneSide; let index: Int }`
  - `struct FFTabStripGeometry { let rect: CGRect; let tabRects: [CGRect] }`
  - `struct FFPaneGeometry { let rect: CGRect; let realTabCount: Int }`
  - `struct FFWindowDropGeometry { ... }`
  - `enum FFDropDecision: Equatable { case reorder(...), merge(...), split(...), newWindow, returnToSource }`
  - `enum FFDropResolver { static func resolve(source:pointer:geometries:) -> FFDropDecision }`

- [ ] **Step 1: 写失败测试**

Create `FlowFinder/Tests/FlowFinderTests/FFDropResolverTests.swift`:

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFDropResolverTests: XCTestCase {

    private final class WindowToken {}

    private var tokenA: WindowToken!
    private var tokenB: WindowToken!

    override func setUp() {
        super.setUp()
        tokenA = WindowToken()
        tokenB = WindowToken()
    }

    override func tearDown() {
        tokenA = nil
        tokenB = nil
        super.tearDown()
    }

    private func tabRects(x: CGFloat, y: CGFloat, widths: [CGFloat], height: CGFloat = 28) -> [CGRect] {
        var result: [CGRect] = []
        var cursor = x
        for width in widths {
            result.append(CGRect(x: cursor, y: y, width: width, height: height))
            cursor += width + 6
        }
        return result
    }

    private func geometry(
        id: ObjectIdentifier,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1200, height: 900),
        single: Bool = false,
        active: PaneSide = .left,
        leftTabs: [CGRect]? = nil,
        rightTabs: [CGRect]? = nil,
        leftPane: CGRect? = nil,
        rightPane: CGRect? = nil,
        leftReal: Int = 2,
        rightReal: Int = 2,
        invalid: [CGRect] = []
    ) -> FFWindowDropGeometry {
        let lTabs = leftTabs ?? tabRects(x: 120, y: 820, widths: [100, 120])
        let rTabs = rightTabs ?? tabRects(x: 620, y: 820, widths: [100, 120])
        var strips: [PaneSide: FFTabStripGeometry] = [:]
        if single {
            let stripRect = active == .left
                ? CGRect(x: 100, y: 800, width: 460, height: 60)
                : CGRect(x: 600, y: 800, width: 460, height: 60)
            strips[active] = FFTabStripGeometry(rect: stripRect,
                                                tabRects: active == .left ? lTabs : rTabs)
        } else {
            strips[.left] = FFTabStripGeometry(rect: CGRect(x: 100, y: 800, width: 460, height: 60),
                                               tabRects: lTabs)
            strips[.right] = FFTabStripGeometry(rect: CGRect(x: 600, y: 800, width: 460, height: 60),
                                                tabRects: rTabs)
        }
        var panes: [PaneSide: FFPaneGeometry] = [:]
        if single {
            let rect = active == .left
                ? (leftPane ?? CGRect(x: 100, y: 100, width: 1000, height: 700))
                : (rightPane ?? CGRect(x: 100, y: 100, width: 1000, height: 700))
            panes[active] = FFPaneGeometry(rect: rect,
                                           realTabCount: active == .left ? leftReal : rightReal)
        } else {
            panes[.left] = FFPaneGeometry(rect: leftPane ?? CGRect(x: 100, y: 100, width: 460, height: 700),
                                          realTabCount: leftReal)
            panes[.right] = FFPaneGeometry(rect: rightPane ?? CGRect(x: 600, y: 100, width: 460, height: 700),
                                           realTabCount: rightReal)
        }
        return FFWindowDropGeometry(windowID: id,
                                    frame: frame,
                                    isSinglePane: single,
                                    activePane: active,
                                    tabStrips: strips,
                                    paneContents: panes,
                                    invalidRects: invalid)
    }

    func testSameWindowTabStripReordersAtPointerIndex() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 300, y: 830),
                                              geometries: [g])
        XCTAssertEqual(decision, .reorder(windowID: g.windowID, side: .left, index: 2))
    }

    func testSameWindowOtherTabStripMerges() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 700, y: 830),
                                              geometries: [g])
        XCTAssertEqual(decision, .merge(windowID: g.windowID, side: .right, index: 1))
    }

    func testSameWindowDoublePaneSameSideReturns() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 200, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testSameWindowDoublePaneOtherSideMerges() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 700, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .merge(windowID: g.windowID, side: .right, index: nil))
    }

    func testSinglePaneRightHalfSplitsRight() {
        let g = geometry(id: ObjectIdentifier(tokenA), single: true, active: .left)
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .split(windowID: g.windowID, dropSide: .right))
    }

    func testSinglePaneLeftHalfSplitsLeft() {
        let g = geometry(id: ObjectIdentifier(tokenA), single: true, active: .left)
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 400, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .split(windowID: g.windowID, dropSide: .left))
    }

    func testSinglePaneOnlyTabReturnsToSource() {
        let g = geometry(id: ObjectIdentifier(tokenA), single: true, active: .left, leftReal: 1)
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testTargetSinglePaneEmptyMergesInsteadOfSplitting() {
        let a = geometry(id: ObjectIdentifier(tokenA),
                         frame: CGRect(x: -2000, y: -2000, width: 1200, height: 900),
                         single: true, active: .left)
        let b = geometry(id: ObjectIdentifier(tokenB), single: true, active: .left, leftReal: 0)
        let source = FFDragSource(windowID: a.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [a, b])
        XCTAssertEqual(decision, .merge(windowID: b.windowID, side: .left, index: nil))
    }

    func testTargetSinglePaneWithTabsSplits() {
        let a = geometry(id: ObjectIdentifier(tokenA),
                         frame: CGRect(x: -2000, y: -2000, width: 1200, height: 900),
                         single: true, active: .left)
        let b = geometry(id: ObjectIdentifier(tokenB), single: true, active: .left, leftReal: 2)
        let source = FFDragSource(windowID: a.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [a, b])
        XCTAssertEqual(decision, .split(windowID: b.windowID, dropSide: .right))
    }

    func testOtherWindowDoublePaneMergesIntoPointerSide() {
        let a = geometry(id: ObjectIdentifier(tokenA),
                         frame: CGRect(x: -2000, y: -2000, width: 1200, height: 900),
                         single: false)
        let b = geometry(id: ObjectIdentifier(tokenB), single: false)
        let source = FFDragSource(windowID: a.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 700, y: 400),
                                              geometries: [a, b])
        XCTAssertEqual(decision, .merge(windowID: b.windowID, side: .right, index: nil))
    }

    func testOutsideAllWindowsCreatesWindow() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 3000, y: 3000),
                                              geometries: [g])
        XCTAssertEqual(decision, .newWindow)
    }

    func testInvalidZoneWinsOverTabStrip() {
        let plus = CGRect(x: 500, y: 810, width: 20, height: 20)
        let g = geometry(id: ObjectIdentifier(tokenA), invalid: [plus])
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 510, y: 820),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testWindowFrameButNoValidZoneReturns() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 400, y: 890),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testTabStripBufferStillReorders() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 300, y: 790),
                                              geometries: [g])
        XCTAssertEqual(decision, .reorder(windowID: g.windowID, side: .left, index: 2))
    }
}
```

- [ ] **Step 2: 注册测试文件并加类型桩，确认测试失败**

1. 在 `project.pbxproj` 注册 `FFDropResolverTests.swift`（四处）。
2. 在 `MainWindowController.swift:2799` 把 `enum PaneSide {` 改为 `enum PaneSide: Hashable, CaseIterable {`（字典键需要 Hashable，`allCases` 需要 CaseIterable）。
3. 创建 `FFDropResolver.swift` 的最小桩：

```swift
import CoreGraphics

enum FFDropDecision: Equatable {
    case reorder(windowID: ObjectIdentifier, side: PaneSide, index: Int)
    case merge(windowID: ObjectIdentifier, side: PaneSide, index: Int?)
    case split(windowID: ObjectIdentifier, dropSide: PaneSide)
    case newWindow
    case returnToSource
}

struct FFDragSource {
    let windowID: ObjectIdentifier
    let side: PaneSide
    let index: Int
}

struct FFTabStripGeometry {
    let rect: CGRect
    let tabRects: [CGRect]
}

struct FFPaneGeometry {
    let rect: CGRect
    let realTabCount: Int
}

struct FFWindowDropGeometry {
    let windowID: ObjectIdentifier
    let frame: CGRect
    let isSinglePane: Bool
    let activePane: PaneSide
    let tabStrips: [PaneSide: FFTabStripGeometry]
    let paneContents: [PaneSide: FFPaneGeometry]
    let invalidRects: [CGRect]
}

enum FFDropResolver {
    static func resolve(source: FFDragSource,
                        pointer: CGPoint,
                        geometries: [FFWindowDropGeometry]) -> FFDropDecision {
        .newWindow
    }
}
```

Run:
```bash
xcodebuild test -project FlowFinder/FlowFinder.xcodeproj -scheme FlowFinderTests \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:FlowFinderTests/FFDropResolverTests
```
Expected: 多条 FAIL（单栏 split、无效落点、目标单栏等），不是编译错误。

- [ ] **Step 3: 实现最小 resolver**

Replace the stub `resolve` with:

```swift
enum FFDropResolver {
    static let stripBuffer: CGFloat = 20

    static func resolve(source: FFDragSource,
                        pointer: CGPoint,
                        geometries: [FFWindowDropGeometry]) -> FFDropDecision {
        guard let window = geometries.first(where: { $0.frame.contains(pointer) }) else {
            return .newWindow
        }
        if window.invalidRects.contains(where: { $0.contains(pointer) }) {
            return .returnToSource
        }

        for side in PaneSide.allCases {
            guard let strip = window.tabStrips[side] else { continue }
            let zone = strip.rect.insetBy(dx: -stripBuffer, dy: -stripBuffer)
            guard zone.contains(pointer) else { continue }
            let index = insertionIndex(pointerX: pointer.x, tabRects: strip.tabRects)
            if window.windowID == source.windowID && side == source.side {
                return .reorder(windowID: window.windowID, side: side, index: index)
            }
            return .merge(windowID: window.windowID, side: side, index: index)
        }

        if window.isSinglePane {
            guard let pane = window.paneContents[window.activePane],
                  pane.rect.contains(pointer) else {
                return .returnToSource
            }
            if window.windowID == source.windowID,
               source.side == window.activePane,
               pane.realTabCount <= 1 {
                return .returnToSource
            }
            if pane.realTabCount == 0 {
                return .merge(windowID: window.windowID, side: window.activePane, index: nil)
            }
            let dropSide: PaneSide = pointer.x < pane.rect.midX ? .left : .right
            return .split(windowID: window.windowID, dropSide: dropSide)
        }

        for side in PaneSide.allCases {
            guard let pane = window.paneContents[side], pane.rect.contains(pointer) else { continue }
            if window.windowID == source.windowID && side == source.side {
                return .returnToSource
            }
            return .merge(windowID: window.windowID, side: side, index: nil)
        }
        return .returnToSource
    }

    private static func insertionIndex(pointerX: CGFloat, tabRects: [CGRect]) -> Int {
        guard !tabRects.isEmpty else { return 0 }
        for (index, rect) in tabRects.enumerated() where pointerX < rect.midX {
            return index
        }
        return tabRects.count
    }
}
```

- [ ] **Step 4: 跑测试确认全绿**

```bash
xcodebuild test -project FlowFinder/FlowFinder.xcodeproj -scheme FlowFinderTests \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:FlowFinderTests/FFDropResolverTests
```
Expected: `TEST SUCCEEDED`，14 条全 PASS。

- [ ] **Step 5: 跑全量测试**

`make swift-test`，Expected: 162 + 14 = 176 条，0 失败。

---

## Task 2: 几何缓存 `FFDragGeometryCache`

**Files:**
- Create: `FlowFinder/FlowFinder/UI/FFDragGeometryCache.swift`
- Create: `FlowFinder/Tests/FlowFinderTests/FFDragGeometryCacheTests.swift`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift`（加 `dragGeometry()` 与几何刷新钩子）
- Modify: `FlowFinder/FlowFinder/UI/PaneTabs.swift`（暴露 `addButtonFrame`）
- Modify: `project.pbxproj`

**Interfaces:**
- Consumes: Task 1 的几何类型。
- Produces:
  - `MainWindowController.dragGeometry() -> FFWindowDropGeometry?`
  - `final class FFDragGeometryCache { func update(for:); func remove(_:); func all() -> [FFWindowDropGeometry] }`

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFDragGeometryCacheTests: XCTestCase {

    func testCacheBuildsTabStripAndPaneGeometry() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let cache = FFDragGeometryCache()
        cache.update(for: controller)

        let geometry = cache.all().first
        XCTAssertNotNil(geometry)
        XCTAssertEqual(geometry?.isSinglePane, false)
        XCTAssertNotNil(geometry?.tabStrips[.left])
        XCTAssertNotNil(geometry?.tabStrips[.right])
        XCTAssertNotNil(geometry?.paneContents[.left])
        XCTAssertNotNil(geometry?.paneContents[.right])
        XCTAssertFalse(geometry?.invalidRects.isEmpty ?? true)
    }

    func testSinglePaneCacheHasOnlyVisibleStrip() {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let cache = FFDragGeometryCache()
        cache.update(for: controller)
        let geometry = cache.all().first

        XCTAssertEqual(geometry?.isSinglePane, true)
        XCTAssertEqual(geometry?.tabStrips.count, 1)
        XCTAssertEqual(geometry?.paneContents.count, 1)
    }

    func testRemoveDropsGeometry() {
        let controller = MainWindowController(showImmediately: false, runsSelfTests: false)
        defer { controller.close() }
        let cache = FFDragGeometryCache()
        cache.update(for: controller)
        XCTAssertEqual(cache.all().count, 1)
        cache.remove(controller)
        XCTAssertTrue(cache.all().isEmpty)
    }
}
```

Run the same `-only-testing:FlowFinderTests/FFDragGeometryCacheTests`; Expected: compile error `cannot find 'FFDragGeometryCache'` → add a stub that returns nothing, rerun to see assertion failures, then implement.

- [ ] **Step 2: 加 `dragGeometry()`**

In `MainWindowController.swift`, add an internal method:

```swift
func dragGeometry() -> FFWindowDropGeometry? {
    guard let window, let contentView = window.contentView else { return nil }

    func screenRect(_ view: NSView) -> CGRect {
        let inWindow = view.convert(view.bounds, to: nil)
        return window.convertToScreen(inWindow)
    }
    func screenRect(_ rect: NSRect, in view: NSView) -> CGRect {
        let inWindow = view.convert(rect, to: nil)
        return window.convertToScreen(inWindow)
    }

    var tabStrips: [PaneSide: FFTabStripGeometry] = [:]
    var paneContents: [PaneSide: FFPaneGeometry] = [:]
    var invalidRects: [CGRect] = []

    if isSidebarVisible, let sidebar = sidebarView {
        invalidRects.append(screenRect(sidebar))
    }
    // 侧栏隐藏时红绿灯浮在内容上；无论侧栏是否可见都加一条交通灯无效带。
    let traffic = NSRect(x: 0, y: contentView.bounds.height - 36, width: 90, height: 36)
    invalidRects.append(screenRect(traffic, in: contentView))

    for side in PaneSide.allCases {
        guard let strip = tabStrip(for: side), !strip.isHidden else { continue }
        tabStrips[side] = FFTabStripGeometry(
            rect: screenRect(strip),
            tabRects: strip.allTabItems().map(screenRect)
        )
        if let addButtonRect = strip.addButtonFrame {
            invalidRects.append(screenRect(addButtonRect, in: strip))
        }
        guard let wrapper = paneWrapper(for: side), !wrapper.isHidden else { continue }
        let realCount = tabsStore(for: side)?.tabs.filter { !$0.isPlaceholder }.count ?? 0
        paneContents[side] = FFPaneGeometry(rect: screenRect(wrapper), realTabCount: realCount)
    }

    return FFWindowDropGeometry(
        windowID: ObjectIdentifier(self),
        frame: window.frame,
        isSinglePane: isSinglePaneMode,
        activePane: activePane,
        tabStrips: tabStrips,
        paneContents: paneContents,
        invalidRects: invalidRects
    )
}
```

Add to `PaneTabStripView`:

```swift
var addButtonFrame: NSRect? {
    guard addButton.superview != nil else { return nil }
    return addButton.convert(addButton.bounds, to: self)
}
```

- [ ] **Step 3: 实现缓存**

```swift
import AppKit

final class FFDragGeometryCache {

    private var geometries: [ObjectIdentifier: FFWindowDropGeometry] = [:]

    func update(for controller: MainWindowController) {
        guard let geometry = controller.dragGeometry() else {
            geometries.removeValue(forKey: ObjectIdentifier(controller))
            return
        }
        geometries[geometry.windowID] = geometry
    }

    func remove(_ controller: MainWindowController) {
        geometries.removeValue(forKey: ObjectIdentifier(controller))
    }

    func all() -> [FFWindowDropGeometry] {
        let orderedIDs = NSApp.orderedWindows.compactMap { window -> ObjectIdentifier? in
            guard let controller = window.windowController as? MainWindowController else { return nil }
            return ObjectIdentifier(controller)
        }
        let ordered = orderedIDs.compactMap { geometries[$0] }
        let orderedSet = Set(orderedIDs)
        let remaining = geometries.values.filter { !orderedSet.contains($0.windowID) }
        return ordered + remaining
    }
}
```

- [ ] **Step 4: 运行测试并全量回归**

Run the geometry tests, then `make swift-test`. Expected: +3 tests, all green.

---

## Task 3: 单栏落点与兄弟标签

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift:1168-1177`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController+Tabs.swift:186-216`
- Create: `FlowFinder/Tests/FlowFinderTests/FFDragIntegrationTests.swift`
- Modify: `project.pbxproj`

**Interfaces:**
- Consumes: `PaneTabsStore`, `MainWindowController` existing APIs.
- Produces: `operationSide(near:)` returns pointer half in single-pane; `acceptTabIntoPane` preserves existing tabs.

- [ ] **Step 1: 写失败测试**

Create `FFDragIntegrationTests.swift`:

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFDragIntegrationTests: XCTestCase {

    private func session(_ path: String) -> PaneTabSession {
        PaneTabSession(state: PaneState(path: path))
    }

    private func makeSinglePaneController(paths: [String]) -> MainWindowController {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let sessions = paths.map(session)
        controller.leftTabsStore?.replaceAll(sessions, activeAt: 0)
        controller.refreshTabStrip(side: .left)
        return controller
    }

    private func operationPoint(_ controller: MainWindowController,
                                rightHalf: Bool) -> NSPoint {
        let content = controller.window!.contentView!
        let sidebarRight = controller.sidebarView.convert(controller.sidebarView.bounds,
                                                          to: content).maxX
        let midX = (sidebarRight + content.bounds.maxX) / 2
        return NSPoint(x: rightHalf ? midX + 60 : midX - 60,
                       y: content.bounds.midY)
    }

    func testSinglePaneRightHalfReportsRight() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b", "/tmp/c"])
        defer { controller.close() }
        XCTAssertEqual(controller.operationSide(near: operationPoint(controller, rightHalf: true)),
                       .right)
    }

    func testSinglePaneDropOnRightHalfPreservesSiblings() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b", "/tmp/c"])
        defer { controller.close() }
        let point = operationPoint(controller, rightHalf: true)
        let side = controller.operationSide(near: point)!
        guard let taken = controller.takeTabOut(side: .left, index: 1) else {
            return XCTFail("takeTabOut failed")
        }
        controller.acceptTab(taken, into: .paneContent(window: controller, side: side))

        XCTAssertEqual(controller.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/a", "/tmp/c"])
        XCTAssertEqual(controller.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/b"])
        XCTAssertFalse(controller.isSinglePaneMode)
    }

    func testSinglePaneDropOnLeftHalfPreservesSiblings() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b", "/tmp/c"])
        defer { controller.close() }
        let point = operationPoint(controller, rightHalf: false)
        let side = controller.operationSide(near: point)!
        guard let taken = controller.takeTabOut(side: .left, index: 1) else {
            return XCTFail("takeTabOut failed")
        }
        controller.acceptTab(taken, into: .paneContent(window: controller, side: side))

        XCTAssertEqual(controller.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/b"])
        XCTAssertEqual(controller.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/a", "/tmp/c"])
        XCTAssertFalse(controller.isSinglePaneMode)
    }

    func testTargetSinglePaneSplitPreservesTargetTabs() {
        let source = makeSinglePaneController(paths: ["/tmp/source"])
        let target = makeSinglePaneController(paths: ["/tmp/x", "/tmp/y"])
        defer { source.close(); target.close() }

        guard let taken = source.takeTabOut(side: .left, index: 0) else {
            return XCTFail("takeTabOut failed")
        }
        target.acceptTab(taken, into: .paneContent(window: target, side: .right))

        XCTAssertEqual(target.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/x", "/tmp/y"])
        XCTAssertEqual(target.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/source"])
        XCTAssertFalse(target.isSinglePaneMode)
    }

    func testInvalidDropDoesNotCreateWindow() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b"])
        defer { controller.close() }
        let before = NSApp.windows.filter { $0.windowController is MainWindowController }.count
        let geometry = controller.dragGeometry()!
        let sidebar = geometry.invalidRects.first!
        let source = FFDragSource(windowID: geometry.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: sidebar.midX, y: sidebar.midY),
                                              geometries: [geometry])
        XCTAssertEqual(decision, .returnToSource)
        let after = NSApp.windows.filter { $0.windowController is MainWindowController }.count
        XCTAssertEqual(before, after)
    }
}
```

Expected before fix: `testSinglePaneRightHalfReportsRight` fails (`left`), `testSinglePaneDropOnRightHalfPreservesSiblings` fails on the side assertion or tab arrays, `testSinglePaneDropOnLeftHalfPreservesSiblings` loses A/C, `testTargetSinglePaneSplitPreservesTargetTabs` may pass or fail depending on target side.

Run:
```bash
xcodebuild test -project FlowFinder/FlowFinder.xcodeproj -scheme FlowFinderTests \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:FlowFinderTests/FFDragIntegrationTests
```

- [ ] **Step 2: 修 `operationSide`**

Replace the single-pane early return:

```swift
func operationSide(near point: NSPoint) -> PaneSide? {
    guard let cv = window?.contentView else { return nil }
    let localX = cv.convert(NSPoint(x: point.x, y: 0), from: nil).x
    let sidebarRight = sidebarView.flatMap { view in
        view.superview.map { cv.convert(view.frame, from: $0).maxX }
    } ?? 0
    let midX = (sidebarRight + cv.bounds.maxX) / 2
    return localX < midX ? .left : .right
}
```

Update the doc comment: 单栏时返回的是**落点半区**（新面板将出现的一侧），不是活动面板。

- [ ] **Step 3: 重写 `acceptTabIntoPane`**

```swift
private func acceptTabIntoPane(_ session: PaneTabSession, side: PaneSide) {
    if isSinglePaneMode {
        let active = activePane
        guard let activeStore = tabsStore(for: active),
              let newStore = tabsStore(for: side),
              tabsStore(for: side == .left ? .right : .left) != nil else { return }

        let existingTabs = activeStore.tabs.filter { !$0.isPlaceholder }
        if existingTabs.isEmpty {
            activeStore.replaceAll([session])
            loadActiveTab(side: active)
            return
        }

        newStore.replaceAll([session])
        let otherSide: PaneSide = side == .left ? .right : .left
        tabsStore(for: otherSide)?.replaceAll(existingTabs)
        isSinglePaneMode = false
        UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
        activePane = side
        applyPaneMode()
        widenWindowForSecondPane(newSide: side)
        loadActiveTab(side: side)
        loadActiveTab(side: otherSide)
        return
    }

    guard let store = tabsStore(for: side) else { return }
    store.insert(session, at: store.count)
    refreshTabStrip(side: side)
    loadActiveTab(side: side)
    activatePane(side)
}
```

Notes:
- `existingTabs` 必须在 `newStore.replaceAll` 之前读取；同侧落点时 `newStore === activeStore`。
- `otherStore` 变量只用于 guard；真正写入用 `tabsStore(for: otherSide)?.replaceAll`。
- `loadActiveTab` 只加载活动侧；另一侧在切回双栏时由 `applyPaneMode`/`loadActiveTab` 处理。若发现另一侧未刷新，在 `applyPaneMode()` 后显式 `loadActiveTab(side: otherSide)`。
- 这个改动只动单栏分支；双栏分支保持原样。

- [ ] **Step 4: 跑集成测试**

Run the integration tests. Expected: 5 条全 PASS。

- [ ] **Step 5: 全量回归**

`make swift-test`。Expected: 全绿。

---

## Task 4: 插入线不再走 Auto Layout

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/PaneTabs.swift:561-606`
- Modify: `FlowFinder/FlowFinder/UI/FFPaneDrag.swift:31-35`
- Modify: `FlowFinder/FlowFinder/UI/FileListView.swift`（layout 宽度守卫）
- Modify: `FlowFinder/FlowFinder/UI/FFListColumns.swift`（新增 `FFColumnFitPolicy`）
- Create: `FlowFinder/Tests/FlowFinderTests/FFDragPerformanceStructureTests.swift`
- Modify: `project.pbxproj`

**Interfaces:**
- Produces: `PaneTabStripView.insertionIndicatorForTesting: FFTabInsertionIndicator?`
- Produces: `FFTabInsertionIndicator` 使用 `FFAccent.current`，frame-based。

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import FlowFinder

final class FFDragPerformanceStructureTests: XCTestCase {

    private func session(_ path: String) -> PaneTabSession {
        PaneTabSession(state: PaneState(path: path))
    }

    func testInsertionIndicatorUsesFrameNotAutoLayout() {
        let strip = PaneTabStripView(frame: NSRect(x: 0, y: 0, width: 500, height: 36))
        strip.side = .left
        strip.refresh(sessions: [session("/tmp/a"), session("/tmp/b")], activeIndex: 0)
        strip.layoutSubtreeIfNeeded()

        strip.showInsertionIndicator(atIndex: 1)

        let indicator = strip.insertionIndicatorForTesting
        XCTAssertNotNil(indicator)
        XCTAssertTrue(indicator!.translatesAutoresizingMaskIntoConstraints,
                      "插入线必须用 frame，不能再加 Auto Layout 约束")
        XCTAssertTrue(indicator!.constraints.isEmpty)
    }

    func testColumnFitPolicyOnlyFitsWhenWidthChanges() {
        XCTAssertFalse(FFColumnFitPolicy.shouldFit(previousWidth: 500, currentWidth: 500.2))
        XCTAssertTrue(FFColumnFitPolicy.shouldFit(previousWidth: 500, currentWidth: 520))
    }
}
```

Run; Expected: compile errors for `insertionIndicatorForTesting` / `FFColumnFitPolicy`; add stubs, rerun to see failures, then implement.

- [ ] **Step 2: 改插入线为 frame-based**

In `PaneTabs.swift`, add the test accessor:

```swift
var insertionIndicatorForTesting: FFTabInsertionIndicator? { insertionIndicator }
```

Replace `showInsertionIndicator`:

```swift
func showInsertionIndicator(atIndex index: Int) {
    guard let x = insertionIndicatorX(forIndex: index) else { return }
    if insertionIndicator == nil {
        let view = FFTabInsertionIndicator()
        view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(view)
        insertionIndicator = view
    }
    guard let view = insertionIndicator else { return }
    view.frame = NSRect(x: x - 1, y: 3, width: 2, height: bounds.height - 6)
    view.isHidden = false
    view.needsDisplay = true
}
```

Remove the old constraints block. `insertionIndicatorX(forIndex:)` stays as is.

Change `FFTabInsertionIndicator.draw`:

```swift
FFAccent.current.setFill()
```

- [ ] **Step 3: 加 `FFColumnFitPolicy`**

In `FFListColumns.swift`, add:

```swift
enum FFColumnFitPolicy {
    static func shouldFit(previousWidth: CGFloat, currentWidth: CGFloat) -> Bool {
        abs(currentWidth - previousWidth) > 0.5
    }
}
```

Modify `FileListView.layout()`:

```swift
private var lastColumnFitWidth: CGFloat = -1

public override func layout() {
    super.layout()
    tableView.appearance = NSApp.appearance
    updateStickyHeader()

    guard !isApplyingColumnFit,
          FFColumnFitPolicy.shouldFit(previousWidth: lastColumnFitWidth,
                                      currentWidth: bounds.width) else { return }
    lastColumnFitWidth = bounds.width
    isApplyingColumnFit = true
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isApplyingColumnFit = false
        self.applyColumnFit()
    }
}
```

- [ ] **Step 4: 跑结构测试与全量**

Run `-only-testing:FlowFinderTests/FFDragPerformanceStructureTests`, then `make swift-test`. Expected: 2 条 PASS，全量绿。

---

## Task 5: 拖动控制器接入 resolver + 60Hz 帧调度

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFPaneDrag.swift`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift`（几何刷新钩子）
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController+Tabs.swift`（执行决策）

**Interfaces:**
- Consumes: `FFDropResolver`, `FFDragGeometryCache`.
- Produces: `FFPaneDragController` 每帧最多一次 `resolve + overlay update`。

- [ ] **Step 1: 写一个可失败的会话测试（纯调度器）**

Add to `FFDragPerformanceStructureTests.swift`:

```swift
func testFrameSchedulerCoalescesToLatestPointer() {
    var received: [CGPoint] = []
    let scheduler = FFDragFrameScheduler { received.append($0) }
    scheduler.update(CGPoint(x: 1, y: 1))
    scheduler.update(CGPoint(x: 2, y: 2))
    scheduler.update(CGPoint(x: 3, y: 3))
    XCTAssertEqual(scheduler.latestPoint, CGPoint(x: 3, y: 3))
    scheduler.stop()
}
```

Implement `FFDragFrameScheduler` in `FFPaneDrag.swift`:

```swift
final class FFDragFrameScheduler {
    private var timer: Timer?
    private var latest: CGPoint = .zero
    private let onFrame: (CGPoint) -> Void

    var latestPoint: CGPoint { latest }

    init(onFrame: @escaping (CGPoint) -> Void) {
        self.onFrame = onFrame
    }

    func update(_ point: CGPoint) {
        latest = point
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onFrame(self.latest)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

Run the structure test; Expected: PASS after implementation.

- [ ] **Step 2: 接入几何缓存与 resolver**

In `FFPaneDragController`:

```swift
private let geometryCache = FFDragGeometryCache()
private var sourceRef: FFDragSource?
private var latestPointer: CGPoint = .zero
private var currentDecision: FFDropDecision?
private lazy var frameScheduler = FFDragFrameScheduler { [weak self] point in
    self?.processDragFrame(at: point)
}
```

In `register(owner:window:)` add `geometryCache.update(for: owner)`.

In `handleDown` `.dragPane, .reorderTab, .activateTab`:

```swift
sourceRef = FFDragSource(windowID: ObjectIdentifier(owner),
                         side: strip.side,
                         index: item.index)
```

In `handleDragged` `.tabDrag`:

```swift
latestPointer = now
if !didExceedThreshold {
    let dx = now.x - startScreenPoint.x
    let dy = now.y - startScreenPoint.y
    guard hypot(dx, dy) > FFPaneDrag.threshold else { return nil }
    didExceedThreshold = true
}
if !isTabDragOut {
    if let strip = sourceStrip,
       !isOutsideStripBuffer(strip, screenPoint: now) {
        let windowPoint = dragOwner?.window?.convertPoint(fromScreen: now) ?? .zero
        if let index = strip.insertionIndex(atWindowPoint: windowPoint) {
            currentInsertionIndex = index
            strip.showInsertionIndicator(atIndex: index)
        }
        return nil
    }
    isTabDragOut = true
    sourceStrip?.hideInsertionIndicator()
    beginTabGhost()
    refreshGeometryForDragStart()
    frameScheduler.start()
}
return nil
```

`refreshGeometryForDragStart()`:

```swift
private func refreshGeometryForDragStart() {
    for weakOwner in registeredOwners {
        if let owner = weakOwner.value {
            geometryCache.update(for: owner)
        }
    }
}
```

`processDragFrame(at:)`:

```swift
private func processDragFrame(at point: CGPoint) {
    guard isTabDragOut, let source = sourceRef else { return }
    moveGhost(to: point)
    let decision = FFDropResolver.resolve(source: source,
                                          pointer: point,
                                          geometries: geometryCache.all())
    if decision != currentDecision {
        currentDecision = decision
        applyOverlay(for: decision)
        FFDebug.log("[TABDRAG] 决策=\(String(describing: decision))")
    }
}
```

- [ ] **Step 3: 把 `computeDropTarget` 换成决策渲染**

Replace `updateDropTarget` / `computeDropTarget` with `applyOverlay(for:)`。这一步先用现有的 `highlightView` 画 1px 描边；Task 6 再把它换成 `FFDragOverlay`。

```swift
private func applyOverlay(for decision: FFDropDecision?) {
    guard let decision else {
        sourceStrip?.hideInsertionIndicator()
        endHighlight()
        return
    }
    switch decision {
    case .reorder(_, _, let index):
        sourceStrip?.showInsertionIndicator(atIndex: index)
        endHighlight()
    case .merge(let windowID, let targetSide, let index):
        guard let target = owner(for: windowID),
              let strip = target.tabStrip(for: targetSide) else { return }
        if let index {
            strip.showInsertionIndicator(atIndex: index)
        }
        showOutline(around: strip)
    case .split(let windowID, let dropSide):
        guard let target = owner(for: windowID) else { return }
        showPaneOutline(owner: target, dropSide: dropSide)
    case .newWindow, .returnToSource:
        sourceStrip?.hideInsertionIndicator()
        endHighlight()
    }
}

private func owner(for windowID: ObjectIdentifier) -> MainWindowController? {
    registeredOwners.compactMap { $0.value }.first { ObjectIdentifier($0) == windowID }
}

private func showOutline(around view: NSView) {
    guard let host = view.superview else { return }
    let rect = view.convert(view.bounds, to: host).insetBy(dx: 1, dy: 1)
    showOutline(rect: rect, in: host)
}

private func showOutline(rect: NSRect, in host: NSView) {
    if highlightView == nil || highlightHost !== host {
        endHighlight()
        let view = FFDropHighlightView()
        view.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(view)
        highlightView = view
        highlightHost = host
    }
    highlightView?.frame = rect
    highlightView?.needsDisplay = true
}

private func showPaneOutline(owner: MainWindowController, dropSide: PaneSide) {
    let visibleSide = owner.isSinglePaneMode ? owner.activePane : dropSide
    guard let wrapper = owner.paneWrapper(for: visibleSide),
          let host = wrapper.superview else { return }
    let full = wrapper.convert(wrapper.bounds, to: host)
    let rect = dropSide == .left
        ? NSRect(x: full.minX, y: full.minY, width: full.width / 2, height: full.height)
        : NSRect(x: full.midX, y: full.minY, width: full.width / 2, height: full.height)
    showOutline(rect: rect, in: host)
}
```

`FFDropHighlightView.draw` 在这一步先保留现有画法；Task 6 改成只描边、不填充。

- [ ] **Step 4: 松手执行决策**

In `handleUp` `.tabDrag`，先把源侧变量改名为 `draggedSide`，避免和决策里的目标侧 `side` 混淆：

```swift
let draggedSide = sourceSide
let decision = currentDecision
frameScheduler.stop()
sourceRef = nil
currentDecision = nil
if wasTabDragOut {
    endGhost()
    switch decision {
    case .some(.reorder(_, _, let index)):
        owner.moveTab(side: draggedSide, from: from, to: index)
    case .some(.merge(let windowID, let targetSide, let index)):
        guard let target = owner(for: windowID) else { break }
        owner.transferTab(side: draggedSide, index: from,
                          to: .tabStrip(window: target, side: targetSide, index: index))
    case .some(.split(let windowID, let dropSide)):
        guard let target = owner(for: windowID) else { break }
        owner.transferTab(side: draggedSide, index: from,
                          to: .paneContent(window: target, side: dropSide))
    case .some(.newWindow):
        owner.detachTabToNewWindow(side: draggedSide, index: from,
                                   atScreenPoint: latestPointer)
    case .some(.returnToSource), .none:
        break
    }
} else if moved {
    owner.moveTab(side: draggedSide, from: from, to: to)
} else {
    owner.selectTab(side: draggedSide, index: from)
}
```

Important: `case .reorder` 在 `wasTabDragOut` 为 false 时由原有 `moveTab` 分支处理；为 true 时（拖出后又回到源条）也走 `moveTab`。`transferTab` 内部会 `takeTabOut(side: draggedSide, index: from)`，所以源侧必须是 `draggedSide`，不能是目标侧。

- [ ] **Step 5: 全量测试 + 手工冒烟**

`make build`；launch with `FF_SELFTEST=1`; confirm existing self-test still passes. Tab reorder and cross-window drop manual check.

---

## Task 6: 轻量浮层 `FFDragOverlay`

**Files:**
- Create: `FlowFinder/FlowFinder/UI/FFDragOverlay.swift`
- Modify: `FlowFinder/FlowFinder/UI/FFPaneDrag.swift`（替换 ghost/highlight 实现）
- Modify: `FlowFinder/FlowFinder/UI/PaneTabs.swift`（快照背景）

**Interfaces:**
- Produces:
  - `final class FFDragOverlay { func beginGhost(from: NSView); func moveGhost(to:grabOffset:); func showOutline(rect:in:); func hideOutline(); func end() }`
- `FFPaneDrag.snapshot(of:background:)` 支持背景胶囊。

- [ ] **Step 1: 写快照背景测试（能失败的最小断言）**

Add to `FFDragPerformanceStructureTests.swift`:

```swift
func testSnapshotWithBackgroundHasOpaquePixels() {
    let label = NSTextField(labelWithString: "B")
    label.frame = NSRect(x: 0, y: 0, width: 80, height: 28)
    let image = FFPaneDrag.snapshot(of: label, background: .white)
    XCTAssertNotNil(image)
    XCTAssertEqual(image?.size.width, 80)
    XCTAssertEqual(image?.size.height, 28)
}
```

This only checks the API exists; visual verification is manual.

- [ ] **Step 2: 实现 `FFDragOverlay`**

```swift
import AppKit

final class FFDragOverlay {

    private var ghostPanel: NSPanel?
    private var ghostImageView: NSImageView?
    private var outlineView: NSView?

    func beginGhost(from item: NSView) {
        guard let image = FFPaneDrag.snapshot(of: item,
                                              background: FFDesign.operationAreaBackground) else { return }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: image.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0.55
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        panel.contentView = imageView
        ghostPanel = panel
        ghostImageView = imageView
        panel.orderFrontRegardless()
    }

    func moveGhost(to point: CGPoint, grabOffset: CGPoint) {
        ghostPanel?.setFrameOrigin(NSPoint(x: point.x - grabOffset.x,
                                           y: point.y - grabOffset.y))
    }

    func showOutline(rect: CGRect, in host: NSView, color: NSColor = FFAccent.current) {
        let view: NSView
        if let outlineView {
            view = outlineView
        } else {
            view = NSView()
            view.wantsLayer = true
            view.layer?.borderWidth = 1
            view.layer?.cornerRadius = 8
            view.translatesAutoresizingMaskIntoConstraints = true
            outlineView = view
        }
        if view.superview !== host {
            view.removeFromSuperview()
            host.addSubview(view)
        }
        view.layer?.borderColor = color.cgColor
        view.frame = rect
        view.isHidden = false
    }

    func hideOutline() {
        outlineView?.isHidden = true
    }

    func end() {
        ghostPanel?.orderOut(nil)
        ghostPanel = nil
        ghostImageView = nil
        outlineView?.removeFromSuperview()
        outlineView = nil
    }
}
```

- [ ] **Step 3: 快照背景**

Modify `FFPaneDrag.snapshot`:

```swift
static func snapshot(of view: NSView, background: NSColor? = nil) -> NSImage? {
    let size = view.bounds.size
    guard size.width > 1, size.height > 1,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)

    let rendered = NSImage(size: size)
    rendered.addRepresentation(rep)

    let result = NSImage(size: size)
    result.lockFocus()
    if let background {
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                xRadius: 8, yRadius: 8)
        background.setFill()
        path.fill()
    }
    rendered.draw(in: NSRect(origin: .zero, size: size))
    result.unlockFocus()
    return result
}
```

活动标签的背景本来就是透明（靠面板背板焊接），所以必须先用 `background` 画一层胶囊底色，再把 `cacheDisplay` 的透明渲染叠上去；否则浮层仍然只有文字。

- [ ] **Step 4: 替换 `FFPaneDrag` 里的 ghost/highlight**

- Remove `ghostPanel`, `highlightView`, `highlightHost`, `beginTabGhost`, `moveGhost`, `endGhost`, `showHighlight`, `endHighlight`.
- Add `private let overlay = FFDragOverlay()`.
- At drag start: `overlay.beginGhost(from: item)`.
- Each frame: `overlay.moveGhost(to: point, grabOffset: grabOffset)`.
- On decision: `overlay.showOutline(...)` / `overlay.hideOutline()`.
- On end/cancel: `overlay.end()`.

同时把 `FFDropHighlightView` 改成**只描边、不填充**，匹配轻量反馈：

```swift
final class FFDropHighlightView: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 8, yRadius: 8)
        FFAccent.current.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
```

`FFDragOverlay.beginGhost` 的签名改为 `beginGhost(from item: NSView)`，不再接收 window（初始定位由第一次 `moveGhost` 完成）。

- [ ] **Step 5: 构建 + 手工检查**

`make build`；用 `FF_SELFTEST=1` 启动，确认无崩溃；人工拖一次，确认活动标签也有完整胶囊浮层（不是文字幽灵）。

---

## Task 7: 窗口拖动落地 + 性能守卫

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFPaneDrag.swift:294-356`
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController.swift`（monitor deinit、updatePaneUI、磁盘空间）
- Modify: `FlowFinder/FlowFinder/UI/FileListView.swift`（已在 Task 4 改 layout；这里确认无遗漏）
- Modify: `FlowFinder/FlowFinder/App/AppDelegate.swift`

- [ ] **Step 1: 按 Task 0 结论落地**

- **Task 0 通过**：保留 `.dragWindow` 里的 `window.performDrag(with: event)`；在 `handleDragged` 顶部加 `if mode == .windowDrag && useNativeWindowDrag { return event }`，避免 monitor 再移动一次；`handleUp` 的 `.windowDrag` 直接 `return nil`（系统已处理 mouseUp）。
- **Task 0 失败**：保留 `FF_NATIVE_WINDOW_DRAG=0` 回退，执行 Step 2；不要同时保留两条路径。
- 清理旧的 per-event `setFrameOrigin` 代码；如果 native 生效，`startScreenPoint`/`startWindowOrigin` 只给回退路径用，确认没有死变量。

- [ ] **Step 2: 回退路径 60Hz 合并**

If native drag fails, in `handleDragged` `.windowDrag` use the scheduler instead of per-event `setFrameOrigin`:

```swift
latestPointer = nowScreen
windowFrameScheduler.update(nowScreen)
if !didExceedThreshold {
    let dx = nowScreen.x - startScreenPoint.x
    let dy = nowScreen.y - startScreenPoint.y
    guard hypot(dx, dy) > FFPaneDrag.threshold else { return nil }
    didExceedThreshold = true
}
// 不再直接 setFrameOrigin；由 windowFrameScheduler 每帧更新
return nil
```

Add a separate scheduler for the fallback:

```swift
private lazy var windowFrameScheduler = FFDragFrameScheduler { [weak self] point in
    self?.processWindowDragFrame(at: point)
}
```

In the fallback `.dragWindow` branch, call `windowFrameScheduler.start()`; in `handleUp` `.windowDrag`, call `windowFrameScheduler.stop()`.

```swift
private func processWindowDragFrame(at screenPoint: CGPoint) {
    guard mode == .windowDrag, let window = dragOwner?.window else { return }
    window.setFrameOrigin(NSPoint(x: startWindowOrigin.x + (screenPoint.x - startScreenPoint.x),
                                  y: startWindowOrigin.y + (screenPoint.y - startScreenPoint.y)))
}
```

- [ ] **Step 3: 监视器清理**

In `MainWindowController.deinit`:

```swift
if let mouseEventMonitor {
    NSEvent.removeMonitor(mouseEventMonitor)
    self.mouseEventMonitor = nil
}
if let keyEventMonitor {
    NSEvent.removeMonitor(keyEventMonitor)
    self.keyEventMonitor = nil
}
FFPaneDragController.shared.unregister(owner: self)
FFPaneDragController.shared.geometryCache.remove(self)
```

Add `unregister(owner:)` to `FFPaneDragController`:

```swift
func unregister(owner: MainWindowController) {
    registeredOwners.removeAll { $0.value === owner || $0.value == nil }
}
```

Expose `geometryCache` internal or add `func removeGeometry(for:)`.

- [ ] **Step 4: `updatePaneUI` 拆分**

Add to `PaneState.swift`: `struct PaneState: Equatable`, `enum SortField: String, CaseIterable, Equatable`, `enum ViewMode: String, CaseIterable, Equatable`.

Add a pure policy in `MainWindowController.swift`:

```swift
enum FFPaneReloadPolicy {
    static func shouldReloadList(previous: PaneState?, current: PaneState) -> Bool {
        guard let previous else { return true }
        return previous.path != current.path
            || previous.files != current.files
            || previous.viewMode != current.viewMode
            || previous.searchQuery != current.searchQuery
            || previous.tagFilter != current.tagFilter
            || previous.sortField != current.sortField
            || previous.sortAscending != current.sortAscending
            || previous.groupBy != current.groupBy
    }
}
```

In `updatePaneUI`:

```swift
private var lastRenderedState: [PaneSide: PaneState] = [:]

let shouldReload = FFPaneReloadPolicy.shouldReloadList(previous: lastRenderedState[side], current: state)
lastRenderedState[side] = state
if shouldReload {
    fileListView?.reloadData()
    grid?.reloadData()
}
```

Update toolbar/breadcrumb/details every emission as before. Move `getDiskFreeSpace` off the main thread:

```swift
private var diskFreeCache: [String: String] = [:]

private func diskFreeText(for path: String, completion: @escaping (String?) -> Void) {
    if let cached = diskFreeCache[path] {
        completion(cached)
        return
    }
    DispatchQueue.global(qos: .utility).async {
        let text = Self.readDiskFreeSpace(path)
        DispatchQueue.main.async { [weak self] in
            if let text { self?.diskFreeCache[path] = text }
            completion(text)
        }
    }
}
```

Replace the synchronous call with the async version; only update the details bar if the state's path still matches when the completion returns.

Add a test for `FFPaneReloadPolicy` in `FFDragPerformanceStructureTests.swift`:

```swift
func testSelectionOnlyChangeDoesNotReloadList() {
    var a = PaneState(path: "/tmp")
    a.files = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false)]
    var b = a
    b.selectedFiles = a.files
    XCTAssertFalse(FFPaneReloadPolicy.shouldReloadList(previous: a, current: b))
    b.files = [FileEntry(path: "/tmp/b", name: "b", isDirectory: false)]
    XCTAssertTrue(FFPaneReloadPolicy.shouldReloadList(previous: a, current: b))
}
```

- [ ] **Step 5: AppDelegate reopen**

```swift
func applicationShouldHandleReopen(_ sender: NSApplication,
                                   hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
        let controller = MainWindowController()
        registerWindowController(controller)
        controller.showWindow(nil)
        mainWindowController = controller
    }
    return true
}
```

Test in `FFDragIntegrationTests`:

```swift
func testReopenCreatesWindowWhenNoneVisible() {
    guard let delegate = NSApp.delegate as? AppDelegate else { return XCTFail("no delegate") }
    let before = NSApp.windows.filter { $0.windowController is MainWindowController }.count
    _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
    let after = NSApp.windows.filter { $0.windowController is MainWindowController }.count
    XCTAssertGreaterThan(after, before)
}
```
Close the created window after the assertion.

- [ ] **Step 6: 全量测试 + 构建**

`make swift-test`、`make build`。Expected: 全绿、BUILD SUCCEEDED。

---

## Task 8: 自检改真实链路

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/MainWindowController+Tabs.swift:360-470`

- [ ] **Step 1: 改自检 ③ 使用 resolver**

Replace the whole of step ③ with a **real single-pane scenario**（不再从隐藏的右 store 拖）：

```swift
// ③ 单栏：左面板 A/B/C，拖 B 到右半区 → 右面板只放 B，左面板保留 A/C
isSinglePaneMode = true
UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
activePane = .left
func tab(_ path: String) -> PaneTabSession {
    PaneTabSession(state: PaneState(path: path))
}
leftStore.replaceAll([tab("/tmp/a"), tab("/tmp/b"), tab("/tmp/c")], activeAt: 0)
rightStore.replaceAll([placeholderSession()])
refreshTabStrip(side: .left)
refreshTabStrip(side: .right)
applyPaneMode()
window?.contentView?.layoutSubtreeIfNeeded()

let geometry = dragGeometry()!
let pane = geometry.paneContents[.left]!
let pointer = CGPoint(x: pane.rect.midX + 40, y: pane.rect.midY)
let source = FFDragSource(windowID: geometry.windowID, side: .left, index: 1)
let decision = FFDropResolver.resolve(source: source,
                                      pointer: pointer,
                                      geometries: [geometry])

var splitOK = false
if case .split(let windowID, let dropSide) = decision,
   windowID == geometry.windowID,
   dropSide == .right,
   let taken = takeTabOut(side: .left, index: 1) {
    acceptTab(taken, into: .paneContent(window: self, side: dropSide))
    splitOK = !isSinglePaneMode
        && leftStore.count == 2
        && leftStore.tabs.map { $0.state.path } == ["/tmp/a", "/tmp/c"]
        && rightStore.count == 1
        && rightStore.tabs.first?.state.path == "/tmp/b"
}
FFDebug.log("[SELFTEST] ③ 拖到右半→新面板在右 \(splitOK ? "PASS" : "FAIL") 单栏=\(isSinglePaneMode) 左=\(leftStore.tabs.map { $0.state.path }) 右=\(rightStore.tabs.map { $0.state.path })")
```

`dragGeometry()` 与 `pane.rect` 都是**屏幕坐标**，`pointer` 直接传屏幕坐标，不要再 `convertPoint(toScreen:)`。

- [ ] **Step 2: 新增自检步骤**

Add steps ⑦–⑩ after step ⑥:

- ⑦ invalid: pointer in `geometry.invalidRects.first!` → `.returnToSource`.
- ⑧ target single-pane split: create a second controller with `startsWithSinglePane: true`, two tabs; resolve pointer in its active pane's right half → `.split`; execute; assert target left tabs intact, right has dragged tab.
- ⑨ last tab: in a controller with one tab, `takeTabOut` and assert `isPaneEmpty`; then restore.
- ⑩ cross-window tab strip: resolve pointer in the target's right tab strip → `.merge`; assert index; execute; assert target count +1.

Each step logs `[SELFTEST] ... PASS/FAIL` like the existing steps. Keep the existing ①–⑥.

- [ ] **Step 3: 跑自检**

```bash
pkill -f "MacOS/FlowFinder" || true
rm -f /tmp/ff-debug.log
FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" > /tmp/ff-selftest.log 2>&1 &
sleep 8
pkill -f "MacOS/FlowFinder" || true
grep -E "\[SELFTEST\]|FAIL" /tmp/ff-debug.log | tail -40
```
Expected: ①–⑩ 全 PASS，`FAIL` 0。

- [ ] **Step 4: 全量 XCTest**

`make swift-test`。Expected: 全绿。

---

## Task 9: 性能验收与文档

**Files:**
- Modify: `FlowFinder/FlowFinder/UI/FFPaneDrag.swift`（signpost）
- Modify: `docs/HANDOVER.md`
- Modify: `docs/REQUIREMENTS-LEDGER.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/SPEC-2026-10-20-DRAG-REDO.md`（状态改“已实现/已验证”）

- [ ] **Step 1: 加 signpost**

```swift
import os

private let dragLog = OSLog(subsystem: "com.flowfinder.native",
                            category: .pointsOfInterest)

private func processDragFrame(at point: CGPoint) {
    os_signpost(.begin, log: dragLog, name: "FFDrag.frame")
    defer { os_signpost(.end, log: dragLog, name: "FFDrag.frame") }
    guard isTabDragOut, let source = sourceRef else { return }
    moveGhost(to: point)
    let decision = FFDropResolver.resolve(source: source,
                                          pointer: point,
                                          geometries: geometryCache.all())
    if decision != currentDecision {
        currentDecision = decision
        applyOverlay(for: decision)
        os_signpost(.event, log: dragLog, name: "FFDrag.decision")
    }
}
```

Also add `FFDrag.begin`, `FFDrag.decision`, `FFDrag.drop`, `FFDrag.end` at the corresponding transitions.

- [ ] **Step 2: 构建 + 全量测试**

```bash
make build
make swift-test
```
Expected: BUILD SUCCEEDED；测试全绿。

- [ ] **Step 3: 性能采样**

If the user can perform a manual drag:
```bash
pkill -f "MacOS/FlowFinder" || true
FF_SKIP_PERMISSION_GATE=1 "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" &
PID=$(pgrep -f "MacOS/FlowFinder" | head -1)
# 用户在 3 秒内连续拖标签 / 拖窗口；同时：
sample "$PID" 3 -file /tmp/ff-drag-perf.txt
```
Check:
- `grep -c "FileListView.layout" /tmp/ff-drag-perf.txt` → 0（拖动期）
- `grep -c "applyColumnFit" /tmp/ff-drag-perf.txt` → 0（拖动期）
- Main thread frames: p95 <16.7ms; max block <16ms（用 signpost 或 sample 统计）。

If no manual drag is possible, add the debug benchmark:
- `FF_DRAG_BENCH=1` 启动时，构造一个双栏窗口，连续调用 `processDragFrame` 180 次（脚本指针路径），记录每次 `CACurrentMediaTime()` 差值，输出 p50/p95/max 到 `/tmp/ff-debug.log`；不依赖系统鼠标事件。

- [ ] **Step 4: 更新文档**

- `HANDOVER.md`：新增“第七轮：标签拖拽重做”小节；XCTest 数量按实测；自检数量按实测；性能证据。
- `REQUIREMENTS-LEDGER.md`：新增 R-14（标签拖拽重做），状态与验证证据；纠正旧计数。
- `CHANGELOG.md`：未发版段新增条目，写清单栏落点/兄弟标签/60fps/无效落点/最后标签。
- `docs/SPEC-2026-10-20-DRAG-REDO.md`：状态从“待用户审阅”改为“已实现/已验证”，补实测数字。

- [ ] **Step 5: 最终验收**

- [ ] `make swift-test` 全绿（数量按实测写入文档）。
- [ ] `FF_SELFTEST=1` ①–⑩ 全 PASS，0 FAIL。
- [ ] 单栏右半拖入：右面板出现被拖标签，左面板保留其余标签。
- [ ] 目标单栏拆双栏：目标原有标签完整。
- [ ] 无效落点：不新建窗口。
- [ ] 最后标签拖出：源窗口关闭；无窗口时 Dock 重开。
- [ ] 跨窗口标签条：按指针半区插入。
- [ ] 连续拖 3 秒：p95 <16.7ms，主线程单次阻塞 <16ms；无 `FileListView.layout → applyColumnFit → rebuildColumns`。
- [ ] 窗口拖动无每事件 `setFrameOrigin`。
- [ ] 文档同步完成。
- [ ] **不提交 commit**（用户未授权）。

---

## Self-Review

**Spec coverage:**
- §1 根因 → Task 1/3/4/5/7 对应。
- §2 目标/非目标 → Global Constraints + Task 9 验收。
- §3 行为规则 → Task 1 resolver 测试 + Task 3 集成测试 + Task 8 自检。
- §4 四层架构 → Task 1/2/5/6。
- §4.5 布局隔离 → Task 4/7。
- §4.6 清理 → Task 7 monitor deinit + Task 9 文档；`highlightSide`/`canDragOut`/决策表死代码清理需在 Task 7 实现时一并删除（在代码中 grep 确认无引用后删除）。
- §5 性能验收 → Task 9。
- §6 视觉反馈 → Task 4/6。
- §7 测试策略 → Task 1/3/4/8/9。
- §8 风险 → Task 6 spike + Task 7 fallback + Task 7 reopen。
- §9 文件 → File Structure 表覆盖。
- §10 验收清单 → Task 9 Step 5。

**Placeholder scan:** 无 TBD/TODO；所有任务含具体文件、代码或命令。

**Type consistency:**
- `FFDropDecision` / `FFWindowDropGeometry` / `FFTabStripGeometry` / `FFPaneGeometry` 在 Task 1 定义，Task 2/5/8 使用一致。
- `FFDragGeometryCache` 在 Task 2 定义，Task 5 使用。
- `FFDragFrameScheduler` 在 Task 5 定义，Task 6/7 使用。
- `FFColumnFitPolicy` 在 Task 4 定义，Task 4/7 使用。
- `FFPaneReloadPolicy` 在 Task 7 定义并使用。
- `insertionIndicatorForTesting` / `addButtonFrame` 在 Task 4/2 定义并使用。

**Known gaps:**
- `FFDragOverlay` 的快照背景实现有两种写法，实施时以视觉验证为准；Task 6 已给出直接版本。
- 窗口拖动 spike 的最终结论依赖真机；计划已给出回退分支。
- 性能采样需要人工拖拽或用 debug benchmark；Task 9 给出两条路径。
