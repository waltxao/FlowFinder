# 详情栏重设计实现计划（可调高度 + 三模块可调宽 + 流动填充）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 详情栏展开态支持上边缘拖拽调高、图标/列1/列2 三模块宽度可拖（拖图标边界=调图标）、信息项按高度流动填充排列（装不下隐藏），尺寸记忆并左右面板同步。

**Architecture:** 纯数学核心（`FFDetailsFlowLayout`，TDD）+ 手写拖拽条（`FFDetailsDragStrip`，垂直/水平共用）+ 三模块手动约束结构（替代 NSStackView 布局）+ 流动填充接线（`rearrangeFlow()`）。沿用分隔线手柄已验证的「数学核心 + 薄接线 + 禁隐式动画」模式。

**Tech Stack:** Swift / AppKit / Auto Layout / UserDefaults / NotificationCenter / XCTest（xcodebuild）

**设计文档:** `docs/superpowers/specs/2026-08-29-details-bar-redesign-design.md`

## Global Constraints

- 所有代码注释使用简体中文。
- **不新增任何文件**：`FFDetailsFlowLayout` 追加到 `FlowFinderNative/FlowFinderNative/UI/FFCommon.swift`（`FFDividerGlowMath` 同模式）；测试追加到 `FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift`；`FFDetailsDragStrip` 作为 private class 放在 `ExpandableDetailsBar.swift` 文件内（`FFSplitView` 先例）。
- 关键数值（spec §3）：展开高度 clamp **[100, 面板高度 − 120]**，默认 210；图标区宽度 clamp **[32, 内容行总宽 − 240]**，默认 112；列1 宽度 **≥120**，默认 220；图标边长 = min(图标区宽度 − 16, 内容区高度 − 16)，下限 32；上边缘热区 6pt（尾部让出 32pt 给箭头按钮）；分界线热区 8pt 宽 + 1pt 可见线；行间距 4。
- 记忆 key：`FFDetailsBarExpandedHeight` / `FFDetailsBarIconWidth` / `FFDetailsBarColumn1Width`（左右面板共用）；同步通知名 `.FFDetailsBarLayoutChanged`（加到 FFCommon.swift 的 Notification.Name 扩展）。
- `computedExpandedHeight()` 退役：用户拖出的高度为权威值，溢出内容由流动填充隐藏。
- 每条 xcodebuild/make 命令前 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`；验证一律用 `make swift-test`（`make build` 的 SPM 路径已损坏，勿用）。
- 提交前测试判定不得用「管道尾接 grep」掩盖退出码：`make swift-test > /tmp/ff-swift-test.log 2>&1; grep ... /tmp/ff-swift-test.log`。
- git 规则：只 stage 改动的 .swift 文件；`Libraries/libflowfinder_core.a/.dylib` 为构建触碰产物永不提交。
- 收起态（54pt）不显示任何拖拽热区；状态栏（18pt）始终可见。
- 不触碰：视觉风格、pbxproj、文件列表浮层关系、多选汇总内容定义。

---

### Task 1: FFDetailsFlowLayout 流动填充纯函数（TDD）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FFCommon.swift`（文件末尾追加）
- Test: `FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift`（文件末尾追加）

**Interfaces:**
- Consumes: 无（纯函数）
- Produces（Task 4 依赖的精确签名）:
  - `enum FFDetailsFlowLayout`
  - `static let rowSpacing: CGFloat` (= 4)
  - `static func flowSplit(itemHeights: [CGFloat], availableHeight: CGFloat) -> Int`
  - `static func visibleItemCount(itemHeights: [CGFloat], availableHeight: CGFloat) -> Int`

- [ ] **Step 1: 写失败测试（追加到 FlowFinderNativeTests.swift 末尾）**

```swift
// MARK: - FFDetailsFlowLayout（详情栏流动填充分配）

final class FFDetailsFlowLayoutTests: XCTestCase {

    func testFlowSplitBasic() {
        // 4 行每行 16pt、间距 4：累计 16/36/56/76
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [16, 16, 16, 16], availableHeight: 68), 3)
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [16, 16, 16, 16], availableHeight: 76), 4)
    }

    func testFlowSplitUneven() {
        // 首行较高（如名称行）：30/50/70 → 恰好 3 行
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [30, 16, 16, 16, 16], availableHeight: 70), 3)
    }

    func testFlowSplitAtLeastOne() {
        // 可用高度不足首行时仍返回 1（名称行始终可见）；高度 0 同理
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [30, 16, 16], availableHeight: 10), 1)
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [16, 16], availableHeight: 0), 1)
    }

    func testFlowSplitEmpty() {
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [], availableHeight: 100), 0)
    }

    func testVisibleItemCountBothColumns() {
        let heights = [CGFloat](repeating: 16, count: 10)
        // 列1 装 3，剩余 7 中列2 再装 3 → 可见 6
        XCTAssertEqual(FFDetailsFlowLayout.visibleItemCount(itemHeights: heights, availableHeight: 68), 6)
        // 列1 装 6（累计 116）、剩余 4 全进列2 → 全可见
        XCTAssertEqual(FFDetailsFlowLayout.visibleItemCount(itemHeights: heights, availableHeight: 120), 10)
    }

    func testVisibleItemCountEmpty() {
        XCTAssertEqual(FFDetailsFlowLayout.visibleItemCount(itemHeights: [], availableHeight: 100), 0)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
xcodebuild test \
  -project FlowFinderNative/FlowFinderNative.xcodeproj \
  -scheme FlowFinderNativeTests \
  -destination 'platform=macOS' \
  -only-testing:FlowFinderNativeTests/FFDetailsFlowLayoutTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO 2>&1 | tail -15
```

预期：**编译失败** `cannot find 'FFDetailsFlowLayout' in scope`（正确的 RED）。

- [ ] **Step 3: 在 FFCommon.swift 末尾追加实现**

```swift

/// 详情栏流动填充分配纯计算（v0.7.6 发布后详情栏重设计）。
/// 设计文档：docs/superpowers/specs/2026-08-29-details-bar-redesign-design.md
/// ExpandableDetailsBar 负责视觉接线，本枚举只做可单元测试的数学核心。
enum FFDetailsFlowLayout {
    /// 信息行之间的垂直间距（与列 NSStackView spacing 一致）
    static let rowSpacing: CGFloat = 4

    /// 列1 应装项数：按顺序累计高度（首项不计间距，其后每项 +rowSpacing），
    /// 超出 availableHeight 前的项数；项非空时至少返回 1（名称行始终可见）。
    static func flowSplit(itemHeights: [CGFloat], availableHeight: CGFloat) -> Int {
        var cumulative: CGFloat = 0
        for (index, height) in itemHeights.enumerated() {
            cumulative += (index == 0 ? 0 : rowSpacing) + height
            if cumulative > availableHeight {
                return max(index, 1)
            }
        }
        return itemHeights.count
    }

    /// 两列合计可见项数：列1 取 flowSplit，剩余项再按同一可用高度分配给列2，
    /// 列2 也装不下的项隐藏（返回值不含）。
    static func visibleItemCount(itemHeights: [CGFloat], availableHeight: CGFloat) -> Int {
        guard !itemHeights.isEmpty else { return 0 }
        let first = flowSplit(itemHeights: itemHeights, availableHeight: availableHeight)
        let rest = Array(itemHeights[first...])
        let second = flowSplit(itemHeights: rest, availableHeight: availableHeight)
        return first + second
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

同 Step 2 命令。预期：**TEST SUCCEEDED**，`Executed 6 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add FlowFinderNative/FlowFinderNative/UI/FFCommon.swift \
        FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift
git commit -m "feat(ui): 详情栏流动填充分配纯计算核心 FFDetailsFlowLayout（含单元测试）"
```

---

### Task 2: 上边缘拖拽调高 + 记忆/同步 + computedExpandedHeight 退役

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/FFCommon.swift`（Notification.Name 扩展追加一项）

**Interfaces:**
- Consumes: 无
- Produces（Task 3/4 依赖）:
  - `FFDetailsDragStrip` private 类（文件内）：`init(axis: Axis, cursor: NSCursor, showsLine: Bool)`；`var onDrag: ((CGFloat) -> Void)?`（参数 = 本次事件位移，水平条为 dx、垂直条为 dy）；`var onDragEnd: (() -> Void)?`
  - `ExpandableDetailsBar` 属性：`userExpandedHeight`（CGFloat）、`topEdgeStrip`（FFDetailsDragStrip）
  - 静态 key：`Self.heightKey / iconWidthKey / column1WidthKey`（Task 3 用后两者）
  - `applyHeightDrag(deltaY:)`、`observeLayoutChanged()` 模式（Task 3 在同一 observer 里补宽度应用）
  - `.FFDetailsBarLayoutChanged` 通知名

- [ ] **Step 1: FFCommon.swift 的 Notification.Name 扩展追加通知名**

在 `extension Notification.Name { static let accentColorChanged ... }` 块内追加：

```swift
    /// 详情栏布局尺寸（高度/图标区宽/列宽）变更广播：左右两个面板的详情栏互相同步
    static let FFDetailsBarLayoutChanged = Notification.Name("FFDetailsBarLayoutChanged")
```

- [ ] **Step 2: ExpandableDetailsBar.swift 文件顶部（class ExpandableDetailsBar 之前）追加 FFDetailsDragStrip 类**

```swift
/// 详情栏拖拽条：一段透明热区 + 悬停光标 + 拖拽回调。
/// 上边缘调高（垂直）与内部两条分界线（水平，带 1pt 可见线）共用。
/// 不用 NSSplitView：分隔样式与圆角卡片浮层难融合，且项目有布局约束风险史（设计文档方案 A）。
private class FFDetailsDragStrip: NSView {
    enum Axis { case horizontal, vertical }

    private let axis: Axis
    private let cursor: NSCursor
    private var tracking: NSTrackingArea?
    private var dragStart: CGPoint?

    /// 拖拽回调：参数为本次鼠标拖动事件的位移（视图坐标系，dx 或 dy）
    var onDrag: ((CGFloat) -> Void)?
    /// 拖拽结束回调（松开鼠标）
    var onDragEnd: (() -> Void)?

    /// 1pt 可见线（showsLine = true 时创建，水平分界线用）
    private let lineView = NSView()

    init(axis: Axis, cursor: NSCursor, showsLine: Bool) {
        self.axis = axis
        self.cursor = cursor
        super.init(frame: .zero)
        wantsLayer = true
        if showsLine {
            lineView.wantsLayer = true
            lineView.layer?.backgroundColor = NSColor.separatorColor.cgColor
            lineView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(lineView)
            if axis == .horizontal {
                NSLayoutConstraint.activate([
                    lineView.centerXAnchor.constraint(equalTo: centerXAnchor),
                    lineView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                    lineView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                    lineView.widthAnchor.constraint(equalToConstant: 1),
                ])
            } else {
                NSLayoutConstraint.activate([
                    lineView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    lineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    lineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                    lineView.heightAnchor.constraint(equalToConstant: 1),
                ])
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("FFDetailsDragStrip 不支持 IB 初始化")
    }

    /// 悬停提亮可见线（分界线手柄反馈，与双栏分隔线一致）
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        cursor.set()
        if lineView.superview != nil {
            lineView.layer?.backgroundColor = FFAccent.current.withAlphaComponent(0.6).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
        if lineView.superview != nil {
            lineView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let loc = convert(event.locationInWindow, from: nil)
        // 报「相对上次事件的增量」，dragStart 随事件前移；使用方以增量累积更新
        let delta = (axis == .horizontal) ? loc.x - start.x : loc.y - start.y
        dragStart = loc
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        onDragEnd?()
    }
}
```

（即：`mouseDragged` 用「更新 dragStart 后报增量」的版本；`mouseUp` 如上。）

- [ ] **Step 3: ExpandableDetailsBar 常量、状态与静态 key**

在 `// MARK: - Constants` 区块（`statusBarHeight` 之后）追加：

```swift
    /// 展开态高度下限（图标 + 至少两行信息 + 状态栏）
    private let minExpandedHeight: CGFloat = 100
    /// 展开态高度相对面板高度的最大让位（保证文件列表露出一截）
    private let maxHeightReserve: CGFloat = 120
    /// 上边缘拖拽热区高度
    private let topEdgeHeight: CGFloat = 6
    /// 箭头按钮占位（上边缘热区尾部让出，避免盖住按钮）
    private let chevronReserve: CGFloat = 32

    /// 记忆 key（左右面板共用）
    private static let heightKey = "FFDetailsBarExpandedHeight"
    static let iconWidthKey = "FFDetailsBarIconWidth"
    static let column1WidthKey = "FFDetailsBarColumn1Width"
```

（`iconWidthKey`/`column1WidthKey` 用 internal：Task 3 的同文件 private 类无需访问，但保持可测。）

在 `// MARK: - State` 区块（`selectedFiles` 之后）追加：

```swift
    /// 用户拖出的展开高度（权威值，computedExpandedHeight 已退役）
    private var userExpandedHeight: CGFloat
    /// 上边缘调高手柄
    private var topEdgeStrip: FFDetailsDragStrip!
    /// 同步应用远端布局时为 true（抑制再次广播造成回环）
    private var isApplyingRemoteLayout = false
```

`init(frame:)` 里 `setupUI()` 之前初始化：

```swift
    override init(frame frameRect: NSRect) {
        userExpandedHeight = (UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight") as? CGFloat) ?? 210
        super.init(frame: frameRect)
        setupUI()
    }
```

`init?(coder:)` 同样处理。

- [ ] **Step 4: setupUI 中创建上边缘手柄（在 chevronButton 创建与约束之后、heightConstraint 创建之前）**

```swift
        // 上边缘调高手柄：按住上下拖动调整展开高度（v0.7.6 详情栏重设计）
        let topStrip = FFDetailsDragStrip(axis: .vertical, cursor: .resizeUpDown, showsLine: false)
        topStrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStrip)   // 在 mouseInterceptor 之后添加 → 位于其上层，事件不被拦截
        topEdgeStrip = topStrip
```

在 `NSLayoutConstraint.activate([...])` 的数组内追加：

```swift
            // 上边缘热区：尾部让出箭头按钮区域
            topStrip.topAnchor.constraint(equalTo: topAnchor),
            topStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
            topStrip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -chevronReserve),
            topStrip.heightAnchor.constraint(equalToConstant: topEdgeHeight),
```

并在 activate 之后接上回调：

```swift
        topStrip.onDrag = { [weak self] dy in
            self?.applyHeightDrag(deltaY: dy)
        }
        topStrip.onDragEnd = { [weak self] in
            guard let self else { return }
            // 拖高后内容区高度变化 → 图标边长与流动填充重排
            updateIconEdge()
            rearrangeFlow()
        }
```

（`updateIconEdge()` / `rearrangeFlow()` 在 Task 3/4 实现；本 Task 先以空实现占位并注释「Task 3/4 接入」，保证可编译：

```swift
    /// Task 3 接入：按内容区高度与图标区宽度重算图标边长
    func updateIconEdge() {}
    /// Task 4 接入：流动填充重排
    func rearrangeFlow() {}
```
）

- [ ] **Step 5: 高度拖拽应用与同步观察**

在 `// MARK: - Toggle` 区块追加：

```swift
    /// 上边缘拖拽：更新记忆高度并实时应用（clamp [100, 面板高度−120]）
    private func applyHeightDrag(deltaY: CGFloat) {
        guard isExpanded else { return }
        let paneHeight = superview?.bounds.height ?? 0
        let maxHeight = max(minExpandedHeight, paneHeight - maxHeightReserve)
        let newHeight = min(max(userExpandedHeight + deltaY, minExpandedHeight), maxHeight)
        guard newHeight != userExpandedHeight else { return }
        userExpandedHeight = newHeight
        heightConstraint.constant = newHeight
        UserDefaults.standard.set(newHeight, forKey: Self.heightKey)
        rearrangeFlow()
        if !isApplyingRemoteLayout {
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
        }
    }

    /// 监听另一侧详情栏的布局变更（拖左栏右栏同步）
    private func observeLayoutChanged() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutChangedRemotely),
            name: .FFDetailsBarLayoutChanged, object: nil
        )
    }

    @objc private func layoutChangedRemotely(_ note: Notification) {
        guard note.object !== self else { return }
        isApplyingRemoteLayout = true
        defer { isApplyingRemoteLayout = false }
        userExpandedHeight = (UserDefaults.standard.object(forKey: Self.heightKey) as? CGFloat) ?? userExpandedHeight
        if isExpanded {
            heightConstraint.constant = userExpandedHeight
            updateIconEdge()
            rearrangeFlow()
        }
    }
```

`setupUI()` 末尾（`refresh()` 之前）调用 `observeLayoutChanged()`；类中加 deinit：

```swift
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
```

`applyExpandedState(animated:)` 中替换高度来源：

```swift
    private func applyExpandedState(animated: Bool) {
        let newHeight = isExpanded ? userExpandedHeight : collapsedHeight
        heightConstraint.constant = newHeight
        topEdgeStrip?.isHidden = !isExpanded
        compactView.isHidden = isExpanded
        expandedView.isHidden = !isExpanded
        // ……其余保持不变（chevron 图标、loadThumbnail、动画块）
```

- [ ] **Step 6: computedExpandedHeight() 退役**

- 删除整个 `computedExpandedHeight()` 方法；
- `refresh()` 多选分支（约 798-800 行）删除：
  ```swift
            if isExpanded {
                heightConstraint.constant = computedExpandedHeight()
            }
  ```
- `refresh()` 单选分支末尾（约 829-832 行）删除同样的 `if isExpanded { heightConstraint.constant = computedExpandedHeight() }` 块及其注释「动态高度：……」。

- [ ] **Step 7: 编译与全量测试**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
make swift-test > /tmp/ff-swift-test.log 2>&1; grep -E "Executed 91|TEST" /tmp/ff-swift-test.log | tail -3
```

预期：`Executed 91 tests, with 0 failures`、`** TEST SUCCEEDED **`（85 + Task 1 的 6）。

- [ ] **Step 8: 提交**

```bash
git add FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift \
        FlowFinderNative/FlowFinderNative/UI/FFCommon.swift
git commit -m "feat(ui): 详情栏上边缘拖拽调高 + 记忆/双栏同步 + computedExpandedHeight 退役"
```

---

### Task 3: 三模块结构改造 + 两条分界线拖拽 + 图标缩放

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift`

**Interfaces:**
- Consumes: Task 2 的 `FFDetailsDragStrip`、`iconWidthKey/column1WidthKey`、`updateIconEdge()` 占位、`.FFDetailsBarLayoutChanged`
- Produces（Task 4 依赖）:
  - 属性：`mainColumn1`/`mainColumn2`（保留原名）、`bigIconView`/`multiIconView`（保留原名，约束改为动态）、`iconWidthC`（iconSlot 宽度约束）、`bigIconWidthC/bigIconHeightC/multiIconWidthC/multiIconHeightC`（图标边长约束）、`column1WidthC`（列1 宽度约束）
  - 私有状态：`iconWidth`、`column1Width`（CGFloat，UserDefaults 初始化：112 / 220）
  - `applyIconWidthDrag(deltaX:)`、`applyColumn1WidthDrag(deltaX:)`
  - `updateIconEdge()` 实装

- [ ] **Step 1: 状态属性（State 区块追加）**

```swift
    /// 图标区宽度（记忆值；图标边长由此与内容区高度推导）
    private var iconWidth: CGFloat
    /// 列1 宽度（记忆值；列2 兜底剩余宽度）
    private var column1Width: CGFloat
    // 约束引用（Task 3 setupUI 中赋值）
    private var iconWidthC: NSLayoutConstraint!
    private var column1WidthC: NSLayoutConstraint!
    private var bigIconWidthC: NSLayoutConstraint!
    private var bigIconHeightC: NSLayoutConstraint!
    private var multiIconWidthC: NSLayoutConstraint!
    private var multiIconHeightC: NSLayoutConstraint!
    /// 两条内部分界线
    private var dividerIconToCol1: FFDetailsDragStrip!
    private var dividerCol1ToCol2: FFDetailsDragStrip!
    /// 内容模块容器（替代原 contentRow / columnsContainer 两个 NSStackView）
    private var contentModules: NSView!
    private var columnsArea: NSView!
```

两个 init 中初始化（UserDefaults，Task 2 模式）：

```swift
        iconWidth = (UserDefaults.standard.object(forKey: "FFDetailsBarIconWidth") as? CGFloat) ?? 112
        column1Width = (UserDefaults.standard.object(forKey: "FFDetailsBarColumn1Width") as? CGFloat) ?? 220
```

- [ ] **Step 2: 重写 setupUI 的展开态内容行结构（约 244-260 行的 contentRow/columnsContainer 段与 387-389 行的组装、405-408 行 multiIcon 尺寸约束、530-539 行相关约束）**

删除「内容行：图标 + 两列信息（单选）」的 NSStackView 结构与「两列信息容器」NSStackView，替换为：

```swift
        // 内容模块区（v0.7.6 重设计）：图标区 | 分界线1 | 两列区（列1 | 分界线2 | 列2）
        // 用手动约束替代 NSStackView，为三条可拖边界与图标动态缩放提供锚点
        let modules = NSView()
        modules.translatesAutoresizingMaskIntoConstraints = false
        contentModules = modules

        bigIconView.imageScaling = .scaleProportionallyUpOrDown
        bigIconView.translatesAutoresizingMaskIntoConstraints = false

        // 图标区容器：大图标与多选堆叠图标同槽居中，二选一显示
        let iconSlot = NSView()
        iconSlot.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(bigIconView)
```

多选段（约 392-408 行）保留 multiRow 结构但改为加入 iconSlot/columnsArea：

```swift
        multiIconView = multiIcon
        iconSlot.addSubview(multiIcon)   // 替换原 multiRow.addArrangedSubview(multiIcon)
```

删除原 96×96 约束（405-408），图标边长约束统一动态：

```swift
        bigIconWidthC = bigIconView.widthAnchor.constraint(equalToConstant: 96)
        bigIconHeightC = bigIconView.heightAnchor.constraint(equalToConstant: 96)
        multiIconWidthC = multiIcon.widthAnchor.constraint(equalToConstant: 96)
        multiIconHeightC = multiIcon.heightAnchor.constraint(equalToConstant: 96)
        NSLayoutConstraint.activate(bigIconWidthC, bigIconHeightC, multiIconWidthC, multiIconHeightC,
            bigIconView.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            bigIconView.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            multiIconView.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            multiIconView.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
        )
```

（`NSLayoutConstraint.activate` 可变参数逐个传。）

两列容器（columnsContainer NSStackView）替换为：

```swift
        let area = NSView()
        area.translatesAutoresizingMaskIntoConstraints = false
        columnsArea = area
```

column1/column2 的 NSStackView 本体保留（流动填充需要 arrangedSubviews 语义），删除它们的 `greaterThanOrEqualToConstant: 120` 与 column1 的 60% 上限约束，改为：

```swift
        column1WidthC = column1.widthAnchor.constraint(equalToConstant: column1Width)
        column1WidthC.priority = .required
```

两条分界线：

```swift
        let div1 = FFDetailsDragStrip(axis: .horizontal, cursor: .resizeLeftRight, showsLine: true)
        let div2 = FFDetailsDragStrip(axis: .horizontal, cursor: .resizeLeftRight, showsLine: true)
        div1.translatesAutoresizingMaskIntoConstraints = false
        div2.translatesAutoresizingMaskIntoConstraints = false
        dividerIconToCol1 = div1
        dividerCol1ToCol2 = div2
```

组装与约束（替换原 `columnsContainer.addArrangedSubview…`、`contentRow.addArrangedSubview…`）：

```swift
        modules.addSubviews([iconSlot, div1, area])
        area.addSubviews([column1, div2, column2])
```

注意：column1/column2 现为 plain NSView 的子视图（不再是 stack arranged），垂直流式布局由 Task 4 的 rearrangeFlow 用 `setColumn` 管理；本 Task 中间态先 `column1.addArrangedSubview(...)` 保持原有行添加代码不动（NSStackView 作为普通子视图仍可自管理 arranged 行）。column1/2 的 `translatesAutoresizingMaskIntoConstraints` 保持 false。

约束 activate（加入原大数组）：

```swift
            // 内容模块区填满 expandedView 顶部
            modules.leadingAnchor.constraint(equalTo: expandedView.leadingAnchor),
            modules.trailingAnchor.constraint(equalTo: expandedView.trailingAnchor),
            modules.topAnchor.constraint(equalTo: expandedView.topAnchor),
            modules.bottomAnchor.constraint(lessThanOrEqualTo: expandedView.bottomAnchor),

            // 图标区：宽度 = 记忆值，高度撑满（图标在其中居中）
            iconSlot.leadingAnchor.constraint(equalTo: modules.leadingAnchor),
            iconSlot.topAnchor.constraint(equalTo: modules.topAnchor),
            iconSlot.bottomAnchor.constraint(equalTo: modules.bottomAnchor),
            iconWidthC,   // iconSlot.widthAnchor.constraint(equalToConstant: iconWidth)

            // 分界线1：图标区 | 两列区
            div1.leadingAnchor.constraint(equalTo: iconSlot.trailingAnchor),
            div1.topAnchor.constraint(equalTo: modules.topAnchor),
            div1.bottomAnchor.constraint(equalTo: modules.bottomAnchor),
            div1.widthAnchor.constraint(equalToConstant: 8),

            // 两列区：分界线1 右侧到模块区右缘
            area.leadingAnchor.constraint(equalTo: div1.trailingAnchor),
            area.trailingAnchor.constraint(equalTo: modules.trailingAnchor),
            area.topAnchor.constraint(equalTo: modules.topAnchor),
            area.bottomAnchor.constraint(equalTo: modules.bottomAnchor),

            // 列1：宽度 = 记忆值
            column1.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            column1.topAnchor.constraint(equalTo: area.topAnchor),
            column1WidthC,

            // 分界线2：列1 | 列2
            div2.leadingAnchor.constraint(equalTo: column1.trailingAnchor),
            div2.topAnchor.constraint(equalTo: area.topAnchor),
            div2.bottomAnchor.constraint(equalTo: area.bottomAnchor),
            div2.widthAnchor.constraint(equalToConstant: 8),

            // 列2：兜底剩余宽度
            column2.leadingAnchor.constraint(equalTo: div2.trailingAnchor),
            column2.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            column2.topAnchor.constraint(equalTo: area.topAnchor),
```

同时把 expandedStack 的 `addArrangedSubview(contentRow)` 改为 `addArrangedSubview(modules)`，删除 `singleContentRow` 相关赋值（`singleContentRow = contentRow` 与声明保留至 Task 4 清理；本 Task 先让 `singleContentRow = modules` 以维持编译）。

`multiColumns` NSStackView 保留不动（多选列布局 Task 4 再并入 flow）。

- [ ] **Step 3: 分界线回调与宽度应用（// MARK: - Toggle 区块追加）**

```swift
    /// 分界线1 拖拽：图标区宽度 = 图标大小（clamp [32, 内容行总宽 − 240]）
    private func applyIconWidthDrag(deltaX: CGFloat) {
        guard isExpanded else { return }
        let modulesWidth = contentModules?.bounds.width ?? 0
        let maxIcon = max(32, modulesWidth - 240)
        let newWidth = min(max(iconWidth + deltaX, 32), maxIcon)
        guard newWidth != iconWidth else { return }
        iconWidth = newWidth
        iconWidthC.constant = newWidth
        UserDefaults.standard.set(newWidth, forKey: Self.iconWidthKey)
        updateIconEdge()
        rearrangeFlow()
        if !isApplyingRemoteLayout {
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
        }
    }

    /// 分界线2 拖拽：列1 宽度（clamp [120, 总宽 − 图标区 − 240]）
    private func applyColumn1WidthDrag(deltaX: CGFloat) {
        guard isExpanded else { return }
        let modulesWidth = contentModules?.bounds.width ?? 0
        let maxCol1 = max(120, modulesWidth - iconWidth - 240)
        let newWidth = min(max(column1Width + deltaX, 120), maxCol1)
        guard newWidth != column1Width else { return }
        column1Width = newWidth
        column1WidthC.constant = newWidth
        UserDefaults.standard.set(newWidth, forKey: Self.column1WidthKey)
        rearrangeFlow()
        if !isApplyingRemoteLayout {
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
        }
    }
```

setupUI 末尾接回调：

```swift
        div1.onDrag = { [weak self] dx in self?.applyIconWidthDrag(deltaX: dx) }
        div1.onDragEnd = { [weak self] in self?.rearrangeFlow() }
        div2.onDrag = { [weak self] dx in self?.applyColumn1WidthDrag(deltaX: dx) }
        div2.onDragEnd = { [weak self] in self?.rearrangeFlow() }
```

- [ ] **Step 4: updateIconEdge() 实装（替换 Task 2 占位）**

```swift
    /// 按内容区高度与图标区宽度重算图标边长：min(图标区宽 − 16, 内容区高 − 16)，下限 32
    func updateIconEdge() {
        let contentHeight = expandedView.bounds.height
        let edge = max(min(iconWidth - 16, contentHeight - 16), 32)
        bigIconWidthC.constant = edge
        bigIconHeightC.constant = edge
        multiIconWidthC.constant = edge
        multiIconHeightC.constant = edge
    }
```

`layoutChangedRemotely`（Task 2）中追加宽度同步（`if isExpanded { ... }` 块内）：

```swift
            iconWidth = (UserDefaults.standard.object(forKey: Self.iconWidthKey) as? CGFloat) ?? iconWidth
            column1Width = (UserDefaults.standard.object(forKey: Self.column1WidthKey) as? CGFloat) ?? column1Width
            iconWidthC.constant = iconWidth
            column1WidthC.constant = column1Width
```

- [ ] **Step 5: 收起态隐藏分界线**

`applyExpandedState(animated:)` 中追加：

```swift
        dividerIconToCol1?.isHidden = !isExpanded
        dividerCol1ToCol2?.isHidden = !isExpanded
```

- [ ] **Step 6: 编译与全量测试**

同 Task 2 Step 7。预期：`Executed 91 tests, with 0 failures`。
（中间态视觉：列内行数超过可用高度时会溢出卡片底部，属预期，Task 4 流动填充接入后消除。）

- [ ] **Step 7: 提交**

```bash
git add FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift
git commit -m "feat(ui): 详情栏三模块手动约束结构 + 两条分界线拖拽 + 图标动态缩放"
```

---

### Task 4: 流动填充接线（rearrangeFlow + 单选/多选统一 + 溢出隐藏）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift`

**Interfaces:**
- Consumes: Task 1 的 `FFDetailsFlowLayout.flowSplit/visibleItemCount`；Task 3 的 `mainColumn1/mainColumn2/columnsArea/contentModules`
- Produces: `rearrangeFlow()` 实装（替换 Task 2 占位）；`multiRows` 行注册表

- [ ] **Step 1: 多选行注册表（setupUI 多选段，约 424-434 行）**

把四个 `multiCol1.addArrangedSubview(makeInfoRow(...))` / `multiCol2.addArrangedSubview(...)` 改为先存引用：

```swift
        let multiCountRow = makeInfoRow(label: makeLabel("数量"), value: multiCountField)
        let multiSizeRow = makeInfoRow(label: makeLabel("总大小"), value: multiSizeField)
        let multiTypesRow = makeInfoRow(label: makeLabel("包含类型"), value: multiTypesField)
        let multiTagsRow = makeInfoRow(label: makeLabel("包含标签"), value: multiTagsContainer)
        multiCol1.addArrangedSubview(multiCountRow)
        multiCol1.addArrangedSubview(multiSizeRow)
        multiCol1.addArrangedSubview(multiTypesRow)
        multiCol2.addArrangedSubview(multiTagsRow)
```

State 区块追加（顺序即流动顺序）：

```swift
    /// 多选汇总行（流动顺序：数量 → 总大小 → 包含类型 → 包含标签）
    private var multiRows: [NSView] = []
```

setupUI 末尾赋值：`multiRows = [multiCountRow, multiSizeRow, multiTypesRow, multiTagsRow]`（注意：`multiCol1/multiCol2` 在 multiColumns stack 内的初始摆放保留，rearrangeFlow 会重新分配；为避免初始双归属，改为不加入 multiColumns：`multiColumns.addArrangedSubview(multiCol1/multiCol2)` 保留但四个行初始不放入列——由 rearrangeFlow 统一摆放。因此上面四行 `multiCol1.addArrangedSubview(...)` **不执行**，只保留引用数组。）

- [ ] **Step 2: 流动顺序与测量、摆放辅助方法（// MARK: - Toggle 区块追加）**

```swift
    // MARK: - 流动填充

    /// 流动顺序的全部行：单选 = 前 6 常规行 + 类型专属行 + 后 3 行；多选 = 4 汇总行
    private var flowOrderedRows: [NSView] {
        if selectedCount > 1 { return multiRows }
        guard entry != nil else { return [] }
        let base = infoRows
        guard base.count >= 9 else { return base }
        return Array(base[0..<6]) + appendedTypeInfoRows + Array(base[6..<base.count])
    }

    /// 按列宽测量行高（locationField 等可换行行随宽度变化），下限 16
    private func measureRowHeight(_ row: NSView, width: CGFloat) -> CGFloat {
        let size = row.systemLayoutSizeFitting(
            NSSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return max(size.height, 16)
    }

    /// 重新摆放一列的行（全量替换 arranged 行；被移除的行从父视图摘除，由注册表数组持有生命周期）
    private func setColumn(_ column: NSStackView, rows: [NSView]) {
        for view in column.arrangedSubviews {
            column.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in rows {
            column.addArrangedSubview(row)
        }
    }

    /// 流动填充重排：按固定顺序把行分配到列1/列2，装不下的隐藏。
    /// 触发点：高度/分界线拖拽、展开切换、refresh 末尾、面板尺寸变化。
    func rearrangeFlow() {
        guard isExpanded, window != nil else { return }
        updateIconEdge()
        layoutSubtreeIfNeeded()
        let ordered = flowOrderedRows
        guard !ordered.isEmpty else {
            setColumn(mainColumn1, rows: [])
            setColumn(mainColumn2, rows: [])
            return
        }
        let columnWidth = max(mainColumn1.bounds.width, 120)
        let heights = ordered.map { measureRowHeight($0, width: columnWidth) }
        let available = max(expandedView.bounds.height - 4, 32)
        let split = FFDetailsFlowLayout.flowSplit(itemHeights: heights, availableHeight: available)
        let visible = FFDetailsFlowLayout.visibleItemCount(itemHeights: heights, availableHeight: available)
        let firstCount = min(split, ordered.count)
        let first = Array(ordered[0..<firstCount])
        let second = Array(ordered[firstCount..<min(visible, ordered.count)])
        setColumn(mainColumn1, rows: first)
        setColumn(mainColumn2, rows: second)
        for row in ordered where !first.contains(row) && !second.contains(row) {
            row.removeFromSuperview()
        }
        lastArrangedSize = bounds.size
    }
```

State 区块追加：

```swift
    /// 上次流动填充时的 bar 尺寸（layout 中防重复重排）
    private var lastArrangedSize: NSSize = .zero
```

- [ ] **Step 3: layout 覆盖（面板尺寸变化触发重排）**

```swift
    override func layout() {
        super.layout()
        guard isExpanded, bounds.size != lastArrangedSize else { return }
        rearrangeFlow()
    }
```

- [ ] **Step 4: refresh() 与 applyExpandedState 接入**

- `refresh()` 无选中分支：`for row in infoRows { row.isHidden = true }` 之后追加 `multiRows.forEach { $0.removeFromSuperview() }`（多选行摘除）。
- 多选分支：`singleContentRow.isHidden = true` / `multiContentRow.isHidden = false` 替换为图标槽切换（contentModules 结构下两内容行已不存在——Task 3 已令 `singleContentRow = modules`，此处改为）：

```swift
            bigIconView.isHidden = true
            multiIconView.isHidden = false
```

  末尾 `populateMultiSelectSummary()` 之后追加 `rearrangeFlow()`。
- 单选分支（约 805-807 行）：`singleContentRow.isHidden = false` / `multiContentRow.isHidden = true` 替换为：

```swift
        bigIconView.isHidden = false
        multiIconView.isHidden = true
        multiRows.forEach { $0.removeFromSuperview() }
```

  方法末尾 `if isExpanded { loadThumbnail() }` 之前追加 `rearrangeFlow()`。
- 无选中分支的 `singleContentRow.isHidden = true` / `multiContentRow.isHidden = true` 替换为：

```swift
            bigIconView.isHidden = false
            multiIconView.isHidden = true
            setColumn(mainColumn1, rows: [])
            setColumn(mainColumn2, rows: [])
            multiRows.forEach { $0.removeFromSuperview() }
```

- `applyExpandedState(animated:)` 的动画块 `performLayout` 中追加：

```swift
            self?.rearrangeFlow()
            self?.lastArrangedSize = self?.bounds.size ?? .zero
```

- `updateFileTypeSpecificInfo` 与 `appendedTypeInfoRows` 不改（行先落在 mainColumn1，rearrangeFlow 统一重排；`gatherFileInfo` 行数即 flow 顺序中「修改日期」之后的一段）。
- `populateMultiSelectSummary()` 内若对 multiCol1/multiCol2 有直接引用需改为不依赖（行由 rearrangeFlow 摆放）；实现者检查该方法（约 842 行起）确保只更新字段文本/标签药丸，不动列结构。

- [ ] **Step 5: 编译与全量测试**

同 Task 2 Step 7。预期：`Executed 91 tests, with 0 failures`。

- [ ] **Step 6: 提交**

```bash
git add FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift
git commit -m "feat(ui): 详情栏流动填充接线 — 单选/多选统一重排 + 溢出隐藏"
```

---

### Task 5: 全量基线验证 + 用户实测交接（控制器执行，无代码）

**Files:** 无代码改动

- [ ] **Step 1: 清洁全量基线（编译缓存陷阱：采信数字前必须 clean）**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
make clean && make rust && make test
```

预期：Rust `200 passed`；Swift `Executed 91 tests, with 0 failures`；integration-test 通过。
注意：`make clean` 会删除 git 跟踪的 xcodeproj 工作区/方案文件与 Libraries 二进制——测完执行：

```bash
git checkout -- FlowFinderNative/FlowFinderNative.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
  FlowFinderNative/FlowFinderNative.xcodeproj/project.xcworkspace/xcuserdata/waltxao.xcuserdatad/UserInterfaceState.xcuserstate \
  FlowFinderNative/FlowFinderNative.xcodeproj/xcuserdata/waltxao.xcuserdatad/xcschemes/xcschememanagement.plist
```

- [ ] **Step 2: 构建并启动应用交用户实测**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild build -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNativeTests \
  -destination 'platform=macOS' -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
open ~/Library/Developer/Xcode/DerivedData/FlowFinderNative-*/Build/Products/Debug/FlowFinderNative.app
```

- [ ] **Step 3: 用户验收清单（等待用户反馈；有问题回对应 Task 修复）**

1. 上边缘拖高：按住详情栏上边缘上下拖，高度实时变化；拖到很矮（100pt）和很高（面板高 −120pt）都停住；重启后高度恢复。
2. 箭头按钮：收起/展开正常，展开高度 = 拖出的记忆高度。
3. 拖图标区分界线：图标实时缩放居中，不超栏高；拖列1 分界线：两列宽度变化。
4. 流动填充：栏拖矮时列1 装不下的项自动出现在列2，再矮时剩余项隐藏；拖高时项流回、全部可见；选中一张图片（类型专属行多时）确认不截断。
5. 双栏同步：拖左栏高度/分界线，右栏实时跟随；重启后一致。
6. 回归：多选汇总布局正常、状态栏始终可见、收起态无拖拽热区、文件列表滚动正常。

- [ ] **Step 4: 验收通过后收尾**

- 如有反馈问题：回对应 Task 修复后重跑本 Task。
- 本计划完成。版本号、CHANGELOG/HANDOVER、DMG 打包属下一轮发布工作（HANDOVER 待办清单在 `.superpowers/sdd/progress.md` 台账累积）。

---

## Self-Review 记录（已执行）

1. **Spec 覆盖**：§3.2 高度拖拽→Task 2（含 clamp/记忆/同步/computedExpandedHeight 退役/收起态隐藏热区）；§3.3 分界线→Task 3（结构/拖拽/图标缩放/记忆/收口）；§3.4 流动填充→Task 1（纯函数）+Task 4（接线/触发点/多选行/溢出隐藏）；§3.5 交互细节→Task 2/3/4（热区互不重叠：上边缘尾部让 32pt；状态栏不动；收起态隐藏）；§4 验收 1-6→Task 5 清单；验收 7（基线）→Task 1/2/3/4 测试步 + Task 5 清洁基线；§5 不做→Global Constraints。
2. **占位符扫描**：无 TBD；所有代码步骤含完整代码；Task 2 Step 2 的 mouseDragged 以「更正块」给出唯一权威版本。
3. **类型一致性**：`FFDetailsFlowLayout` 签名在 Task 1 Produces 与 Task 4 调用一致；`FFDetailsDragStrip(axis:cursor:showsLine:)` + `onDrag/onDragEnd` 在 Task 2 定义、Task 3 使用一致；`updateIconEdge()/rearrangeFlow()` Task 2 占位 → Task 3/4 实装，调用点签名一致；UserDefaults key 字符串与静态 key 一致（`Self.heightKey` 与 init 中字面量 "FFDetailsBarExpandedHeight" 同值）。
