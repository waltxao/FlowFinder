# 分隔线手柄「渐变跟随 + 拖动完全跟随」实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 双操作区分隔线悬停手柄的最亮点跟随鼠标上下位置（上下各 60pt 渐隐），拖动全程与鼠标 1:1 绝对跟随、彻底消除迟滞。

**Architecture:** 纯数学核心（`FFDividerGlowMath`，可单元测试）+ 薄视觉接线（`FFSplitView`）。迟滞根因是 CAGradientLayer 更新默认带约 0.25s 隐式动画——所有 layer 更新包进禁用动画的 `CATransaction`；拖动改为绝对模型（目标位置 = clamp(鼠标X)，无起点记账）；亮点 Y 由渐变 `locations` 动态表达。

**Tech Stack:** Swift / AppKit / Core Animation / XCTest（经 xcodebuild）

**设计文档:** `docs/superpowers/specs/2026-08-28-divider-handle-glow-follow-design.md`

## Global Constraints

- 所有代码注释与 UI 文案使用简体中文。
- **不新增任何文件**（规避 pbxproj 风险；HANDOVER 记录 pbxproj 修改史脆弱）。数学核心追加到 `FFCommon.swift`，测试追加到 `FlowFinderNativeTests.swift`，两文件均已在 target 内。
- 每条 xcodebuild 命令前必须 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。
- 关键参数（与 delegate 约束一致）：`fadeRadius = 60pt`、`hotZoneRadius = 6pt`、`minPaneWidth = 450pt`。
- 拖动中亮线 X 必须用「计算出的 clamp 值」，**不得回读** `subviews[0].frame.maxX`（布局可能滞后一拍）；静止状态（悬停/拖动结束）回读无碍。
- 所有 `gradientLineLayer` 的 frame/locations 更新必须包在 `CATransaction.setDisableActions(true)` 内。
- 测试基线：Rust 200 passed / Swift 73 passed；完成后 Swift 应为 **85 passed**（新增 12）。
- HANDOVER「编译缓存陷阱」：采信最终测试数字前必须 `make clean` 强制重编译（Task 3 执行）。
- 不触碰：布局约束、卡片边距、`FFNoDividerSplitView`（侧边栏分隔）、pbxproj。

---

### Task 1: FFDividerGlowMath 纯计算核心（TDD）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FFCommon.swift`（文件末尾追加）
- Test: `FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift`（文件末尾追加）

**Interfaces:**
- Consumes: 无（纯函数，无外部依赖）
- Produces（Task 2 依赖的精确签名）:
  - `enum FFDividerGlowMath`
  - `static let fadeRadius: CGFloat` (= 60)
  - `static let hotZoneRadius: CGFloat` (= 6)
  - `static let minPaneWidth: CGFloat` (= 450)
  - `static func glowCenter(mouseY: CGFloat, boundsHeight: CGFloat) -> CGFloat`
  - `static func gradientLocations(center: CGFloat, radiusFraction: CGFloat) -> [CGFloat]`
  - `static func clampedDividerPosition(mouseX: CGFloat, boundsWidth: CGFloat) -> CGFloat`

- [ ] **Step 1: 写失败测试（追加到 FlowFinderNativeTests.swift 末尾）**

```swift
// MARK: - FFDividerGlowMath（分隔线手柄光效纯计算）

final class FFDividerGlowMathTests: XCTestCase {

    // MARK: glowCenter — 鼠标 Y → 渐变轴中心比例

    func testGlowCenterTopMiddleBottom() {
        // AppKit 对 layer-backed 视图保持 layer 与 view 翻转一致，
        // f = mouseY/height 恒成立：视图高 800 时顶部 800→1.0、中部 400→0.5、底部 0→0.0
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 800, boundsHeight: 800), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 400, boundsHeight: 800), 0.5, accuracy: 0.0001)
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 0, boundsHeight: 800), 0.0, accuracy: 0.0001)
    }

    func testGlowCenterClampsOutOfRangeMouseY() {
        // 事件坐标可能越界（拖拽划出窗口），clamp 到 [0,1]
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 1000, boundsHeight: 800), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: -50, boundsHeight: 800), 0.0, accuracy: 0.0001)
    }

    func testGlowCenterZeroHeightSafeDefault() {
        // 高度 0（窗口最小化等）时返回 0.5 正中，避免除零
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 0, boundsHeight: 0), 0.5, accuracy: 0.0001)
    }

    // MARK: gradientLocations — 中心比例 + 渐隐半径比例 → locations

    func testGradientLocationsCentered() {
        XCTAssertEqual(FFDividerGlowMath.gradientLocations(center: 0.5, radiusFraction: 0.15),
                       [0.35, 0.5, 0.65], accuracy: 0.0001)
    }

    func testGradientLocationsClampsAtBottomEdge() {
        // 亮点贴边：下端截断为 0，locations 仍保持递增（贴边截断需求）
        XCTAssertEqual(FFDividerGlowMath.gradientLocations(center: 0.02, radiusFraction: 0.1),
                       [0.0, 0.02, 0.12], accuracy: 0.0001)
    }

    func testGradientLocationsClampsAtTopEdge() {
        XCTAssertEqual(FFDividerGlowMath.gradientLocations(center: 0.98, radiusFraction: 0.1),
                       [0.88, 0.98, 1.0], accuracy: 0.0001)
    }

    func testGradientLocationsOversizedRadiusClamps() {
        XCTAssertEqual(FFDividerGlowMath.gradientLocations(center: 0.5, radiusFraction: 1.5),
                       [0.0, 0.5, 1.0], accuracy: 0.0001)
    }

    func testGradientLocationsOutOfRangeCenterStillOrdered() {
        // 防御：中心超出 [0,1] 时先收敛再算端点，保证 locations 恒有序
        XCTAssertEqual(FFDividerGlowMath.gradientLocations(center: 1.2, radiusFraction: 0.1),
                       [0.9, 1.0, 1.0], accuracy: 0.0001)
    }

    // MARK: clampedDividerPosition — 鼠标 X → 分隔线目标位置

    func testClampedDividerPositionWithinRange() {
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 500, boundsWidth: 1400), 500)
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 460, boundsWidth: 1400), 460)
    }

    func testClampedDividerPositionEnforcesMinPaneWidth() {
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 100, boundsWidth: 1400), 450)
    }

    func testClampedDividerPositionEnforcesMaxPaneWidth() {
        // 左侧最大 = 总宽 - 450（右面板最小宽度）
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 1300, boundsWidth: 1400), 950)
    }

    func testClampedDividerPositionNarrowWindow() {
        // 窗口过窄（<900pt）时上下限收敛到 450
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 700, boundsWidth: 800), 450)
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 100, boundsWidth: 800), 450)
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
  -only-testing:FlowFinderNativeTests/FFDividerGlowMathTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO 2>&1 | tail -20
```

预期：**编译失败**，错误为 `cannot find 'FFDividerGlowMath' in scope`（红 = 正确的失败）。

- [ ] **Step 3: 在 FFCommon.swift 末尾追加实现**

```swift

/// 分隔线手柄光效纯计算（v0.7.6 发布后修复轮）。
/// 设计文档：docs/superpowers/specs/2026-08-28-divider-handle-glow-follow-design.md
/// FFSplitView 负责视觉接线，本枚举只做可单元测试的数学核心。
enum FFDividerGlowMath {
    /// 渐隐半径（pt）：亮点上下各 60pt 渐隐至透明（总高约 120pt）
    static let fadeRadius: CGFloat = 60
    /// 拖拽热区半径（pt）：分隔线 X ±6pt 内按下/悬停生效
    static let hotZoneRadius: CGFloat = 6
    /// 每侧面板最小宽度（pt）：与 MainWindowController 的 NSSplitViewDelegate 约束一致
    static let minPaneWidth: CGFloat = 450

    /// 鼠标 Y（视图坐标系）→ 渐变轴中心比例（0~1）。
    /// AppKit 对 layer-backed 视图保持 layer 与 view 翻转一致，
    /// 因此 f = mouseY / height 恒成立，无需感知 isFlipped/isGeometryFlipped。
    static func glowCenter(mouseY: CGFloat, boundsHeight: CGFloat) -> CGFloat {
        guard boundsHeight > 0 else { return 0.5 }
        return min(max(mouseY / boundsHeight, 0), 1)
    }

    /// 渐变 locations：最亮点在 center，向上下渐隐 r 比例。
    /// 输出恒有序且 clamp 在 [0,1]（亮点贴窗口顶/底时自然截断）。
    static func gradientLocations(center: CGFloat, radiusFraction: CGFloat) -> [CGFloat] {
        let c = min(max(center, 0), 1)
        let r = min(max(radiusFraction, 0), 1)
        return [max(0, c - r), c, min(1, c + r)]
    }

    /// 鼠标 X → 分隔线目标位置（绝对跟随模型）：clamp 到每侧最小 450pt 约束内
    static func clampedDividerPosition(mouseX: CGFloat, boundsWidth: CGFloat) -> CGFloat {
        let maxPosition = max(minPaneWidth, boundsWidth - minPaneWidth)
        return min(max(mouseX, minPaneWidth), maxPosition)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

同 Step 2 命令。预期：**TEST SUCCEEDED**，`Executed 12 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add FlowFinderNative/FlowFinderNative/UI/FFCommon.swift \
        FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift
git commit -m "feat(ui): 分隔线手柄光效纯计算核心 FFDividerGlowMath（含单元测试）"
```

---

### Task 2: FFSplitView 视觉接线（亮点跟随 + 禁动画 + 绝对拖拽）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:13-158`（整块替换 `private class FFSplitView`；**保留** 6-11 行的 `FFNoDividerSplitView` 不动）

**Interfaces:**
- Consumes: Task 1 的 `FFDividerGlowMath`（签名见上）
- Produces: 无新对外接口（`FFSplitView` 为 private 类，仅 373 行 `paneSplitView = FFSplitView()` 一处使用；`paneSplitView` 声明类型为 `NSSplitView!` 不变）

- [ ] **Step 1: 整块替换 FFSplitView（第 13 行 `private class FFSplitView` 起至第 158 行闭括号）**

删除原类体（含 `isHoveringDivider`、`dragStartX`、`dragStartWidth`、`updateDividerLine`），替换为：

```swift
/// 自定义 NSSplitView 子类：任务 R5 — divider 悬停高亮
/// v0.7.6 发布后修复轮：亮点跟随鼠标 Y（上下各 60pt 渐隐）+ 拖动绝对跟随（禁隐式动画消迟滞）。
/// 设计文档：docs/superpowers/specs/2026-08-28-divider-handle-glow-follow-design.md
private class FFSplitView: NSSplitView {
    private var dividerTrackingArea: NSTrackingArea?

    /// 渐变亮线 layer（悬停/拖动时显示，复用避免重复创建）
    private var gradientLineLayer: CAGradientLayer?

    /// 手动拖拽状态（dividerThickness=0 时 NSSplitView 内置拖拽不生效）
    private var isDragging = false

    /// v0.6.9: divider 厚度为 0（移除可见分割线，间隙由卡片边距提供）
    override var dividerThickness: CGFloat {
        return 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = dividerTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        dividerTrackingArea = area
    }

    /// 分隔线当前 X（左子视图右边缘）。仅限静止状态（悬停/拖动结束）回读；
    /// 拖动中必须使用 applyDividerPosition 返回的计算值（布局可能滞后一拍）。
    private var currentDividerX: CGFloat {
        return subviews.count >= 2 ? subviews[0].frame.maxX : 0
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let loc = convert(event.locationInWindow, from: nil)
        let hovering = abs(loc.x - currentDividerX) <= FFDividerGlowMath.hotZoneRadius
        if hovering {
            updateGlow(mouseInView: loc, dividerX: currentDividerX)
            NSCursor.resizeLeftRight.set()
        } else if !isDragging {
            hideGlow()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // 拖拽中鼠标快速划出边界时保持亮线，避免拖拽中途闪烁
        if !isDragging {
            hideGlow()
        }
    }

    /// 创建渐变亮线 layer（复用，避免重复创建）
    private func createGradientLine() {
        guard gradientLineLayer == nil else { return }
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            FFAccent.current.cgColor,
            NSColor.clear.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        self.layer?.addSublayer(gradientLayer)
        gradientLineLayer = gradientLayer
    }

    /// 统一更新亮线：frame 与渐变 locations 全部禁用隐式动画（「慢半拍」根因修复）。
    /// - mouseInView: 鼠标在视图坐标系的位置；nil 表示保持当前亮点不动（仅归位 X）
    /// - dividerX: 亮线 X。拖动中必须传「计算出的目标位置」，不回读布局结果
    private func updateGlow(mouseInView loc: CGPoint?, dividerX: CGFloat) {
        createGradientLine()
        guard let layer = gradientLineLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(x: dividerX - 1, y: 0, width: 2, height: self.bounds.height)
        if let loc = loc {
            let center = FFDividerGlowMath.glowCenter(mouseY: loc.y, boundsHeight: self.bounds.height)
            layer.locations = FFDividerGlowMath.gradientLocations(
                center: center,
                radiusFraction: FFDividerGlowMath.fadeRadius / max(self.bounds.height, 1)
            ).map { NSNumber(value: Double($0)) }
        }
        layer.isHidden = false
        CATransaction.commit()
    }

    private func hideGlow() {
        gradientLineLayer?.isHidden = true
        NSCursor.arrow.set()
    }

    /// 绝对跟随：分隔线目标位置一律取 clamp(鼠标X)，返回实际生效的位置。
    /// 按下瞬间即对齐鼠标正下方（跳动 ≤ 热区半径 6pt）。
    @discardableResult
    private func applyDividerPosition(mouseX: CGFloat) -> CGFloat {
        let clamped = FFDividerGlowMath.clampedDividerPosition(mouseX: mouseX, boundsWidth: self.bounds.width)
        setPosition(clamped, ofDividerAt: 0)
        return clamped
    }

    /// 命中热区（±6pt）：按下即对齐并进入拖拽；未命中：交给系统处理
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard subviews.count >= 2,
              abs(point.x - currentDividerX) <= FFDividerGlowMath.hotZoneRadius else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        let effectiveX = applyDividerPosition(mouseX: point.x)
        updateGlow(mouseInView: point, dividerX: effectiveX)
        NSCursor.resizeLeftRight.set()
    }

    /// 拖拽全程 1:1 跟随鼠标 X（绝对模型，无起点记账），亮点同时跟随鼠标 Y
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, subviews.count >= 2 else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let effectiveX = applyDividerPosition(mouseX: point.x)
        updateGlow(mouseInView: point, dividerX: effectiveX)
    }

    /// 拖拽结束：亮线归位到分隔线最终位置（已静止，回读布局无碍）；
    /// 若鼠标已离开热区则隐藏（含光标复位）
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            updateGlow(mouseInView: nil, dividerX: currentDividerX)
        } else {
            super.mouseUp(with: event)
        }
        let loc = convert(event.locationInWindow, from: nil)
        if abs(loc.x - currentDividerX) > FFDividerGlowMath.hotZoneRadius {
            hideGlow()
        }
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
make build 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 3: 运行 Swift 测试全量**

```bash
make swift-test 2>&1 | tail -8
```

预期：`Executed 85 tests, with 0 failures`（73 原有 + 12 新增）。

- [ ] **Step 4: 提交**

```bash
git add FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "feat(ui): 分隔线手柄亮点跟随鼠标 + 拖动绝对跟随（禁隐式动画消迟滞）"
```

---

### Task 3: 全量基线验证 + 用户实测交接

**Files:** 无代码改动（验证与交接）

**Interfaces:**
- Consumes: Task 1/2 全部产出
- Produces: 干净基线下的测试数字；正在运行的应用供用户验收

- [ ] **Step 1: 清洁全量基线（HANDOVER「编译缓存陷阱」：采信数字前必须 clean）**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
make clean && make test 2>&1 | tail -15
```

预期：Rust `200 passed`；Swift `Executed 85 tests, with 0 failures`；integration-test 通过。

- [ ] **Step 2: 启动应用交用户实测**

```bash
make run 2>&1 | tail -3
```

- [ ] **Step 3: 输出用户验收清单（等待用户反馈）**

用户按以下顺序实测（文字描述反馈）：

1. **悬停亮点跟随**：鼠标移到左右两栏之间的空隙，缓慢上下移动——最亮点应实时跟随鼠标高度，亮点上下各约 60 像素处光完全消失；鼠标贴到窗口顶/底时亮点贴边。
2. **按下即对齐**：在空隙内按下鼠标——分隔线应立即位于鼠标正下方（最多跳动约 6 像素）。
3. **拖动完全跟随**：按住左右拖动——分隔线与亮线应与鼠标完全贴合、任何时刻无迟滞；亮点同时跟随鼠标上下位置。
4. **极限保护**：拖到很左/很右——线在每侧剩 450 像素处停住，属正常。
5. **回归检查**：空隙之外点击文件、框选、拖拽文件等一切如常；侧边栏拖动宽度不受影响。

**方向兜底预案**（理论不会触发，AppKit 保持 layer 与 view 翻转一致）：若实测亮点方向颠倒（鼠标越靠上亮点越靠下），将 `FFCommon.swift` 中 `glowCenter` 的返回值改为 `1 - min(max(mouseY / boundsHeight, 0), 1)` 并重跑 Task 1 测试（`testGlowCenterTopMiddleBottom` 断言同步翻转）。

- [ ] **Step 4: 用户验收通过后收尾**

- 如有反馈问题：回到 Task 2 修复后重跑 Task 3。
- 验收通过：本计划完成。版本号提升、CHANGELOG/HANDOVER 更新与打 DMG 发版属下一轮发布工作，**不在本计划范围**。

---

## Self-Review 记录（已执行）

1. **Spec 覆盖**：3.1 改动位置→Task 2；3.2 迟滞修复（禁动画+计算值）→Task 2 `updateGlow`/`applyDividerPosition`；3.3 亮点跟随→Task 1 数学 + Task 2 接线（mouseMoved/mouseDragged 双路径）；3.4 绝对拖拽（含 clamp 口径统一 450）→Task 1 `clampedDividerPosition` + Task 2；3.5 事件表→Task 2 五个 override；§4 验收 1-5→Task 3 清单；§4 验收 5（基线全绿）→Task 1/2/3 测试步骤；§5 不做清单→Global Constraints「不触碰」+Task 3 Step 4。
2. **占位符扫描**：无 TBD/TODO；所有代码步骤含完整代码。
3. **类型一致性**：`FFDividerGlowMath` 三函数签名在 Task 1 Produces 与 Task 2 调用处逐一比对一致；`locations` 类型转换用 `.map { NSNumber(value: Double($0)) }`（避免 `[CGFloat] as [NSNumber]` 桥接歧义）。
