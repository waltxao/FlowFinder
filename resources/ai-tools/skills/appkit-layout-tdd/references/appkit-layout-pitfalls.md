# AppKit 布局回归：坐标与组件陷阱

## 1. 先固定坐标系

AppKit 普通视图的原点在左下角；`isFlipped == true` 的视图原点是左上角。不要凭“看起来在上面”推断 y 值，也不要把一个坐标系的矩形直接和另一个坐标系的矩形比较。

```swift
func frameInAncestor(_ view: NSView, ancestor: NSView) -> NSRect? {
    guard let parent = view.superview else { return nil }
    return ancestor.convert(view.frame, from: parent)
}

func distanceFromTop(_ rect: NSRect, in ancestor: NSView) -> CGFloat {
    ancestor.isFlipped ? rect.midY : ancestor.bounds.height - rect.midY
}
```

把以下信息一起写入帧快照，避免误判：

- `view.isFlipped`
- `frame`、`bounds`、`alignmentRect`
- `isHidden`、`superview` 链
- 视图与目标祖先的统一坐标系矩形

真实失败案例：详情栏的 `y=8` 被断言成“距顶部 8”，但 AppKit 默认原点在左下，`y=8` 恰好表示贴底。先修坐标断言，再判断生产布局是否错误。

## 2. `NSButton` 的视觉中心用 `alignmentRect`

`NSButton` 的 `frame` 包含 SF Symbol 的内边距和按钮装饰，直接比较 `frame.midY` 会出现约 0.5–2pt 的“假错位”。视觉对齐要使用 `alignmentRect`。

```swift
func visualRect(_ view: NSView, in ancestor: NSView) -> NSRect? {
    guard let parent = view.superview else { return nil }
    let rect = view.alignmentRect(forFrame: view.frame)
    return ancestor.convert(rect, from: parent)
}
```

注意：

- `alignmentRect(forFrame:)` 接收与 `frame` 同坐标系的矩形，通常传 `view.frame`，不要传 `view.bounds`。
- 返回矩形仍按传入坐标系解释；上例从 `view.superview` 转到目标祖先。
- 自定义控件若仍偏移，检查 `alignmentRectInsets` 是否被覆盖。
- 断言示例：

```swift
guard
    let plusFrame = visualRect(plusButton, in: strip),
    let activeFrame = visualRect(activeTab, in: strip)
else {
    return XCTFail("控件未进入同一视图层级")
}

XCTAssertEqual(plusFrame.midY, activeFrame.midY, accuracy: 0.5)
```

## 3. 不要把辅助视图加进 `NSSplitView`

`NSSplitView` 会把直接加入的子视图当作面板。把宽度浮标、拖拽标签或分隔线装饰加进去，会凭空多出第三个 pane，导致分栏几何和命中都异常。

```swift
final class LayoutBadge: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// 放在分栏的父容器；不要调用 splitView.addSubview(badge)
container.addSubview(badge)
```

要求：

- 浮标只负责显示，`hitTest` 返回 `nil`，不能吞掉拖拽或点击。
- 浮标位置从分栏坐标转换到父容器后设置。
- 修改后检查分栏的实际 pane 数量没有增加，并验证每个 pane 的 frame。
- 需要覆盖在分栏上方时，用父容器或独立 overlay，不要借分栏自己的子视图层级。

## 4. `NStackView` 的 flipped 方向

在 flipped 的 stack 或父视图中，正的 `centerY` 常量通常向下；想让内容上移，约束符号可能必须反过来。不要硬编码“正数就是上移”。

```swift
let direction: CGFloat = stack.isFlipped ? -1 : 1
content.centerYAnchor.constraint(
    equalTo: stack.centerYAnchor,
    constant: direction * offset
).isActive = true
```

验证时不要只检查约束常量。把内容与目标参照都转到同一祖先坐标系，再断言 `midY`：

```swift
let contentRect = frameInAncestor(content, ancestor: host)
let referenceRect = frameInAncestor(reference, ancestor: host)
XCTAssertEqual(contentRect?.midY, referenceRect?.midY, accuracy: 0.5)
```

若 `NSStackView` 与内容视图的 flipped 状态不同，以实际参与布局的祖先为准，并在快照里记录两边的 `isFlipped`。

## 5. 隔离 `UserDefaults`

应用真实状态会污染测试：用户设置过的强调色、窗口尺寸、侧栏宽度都可能在测试进程里被读到。曾经出现单个测试读到了持久化的强调色，修正隔离后才转绿。

优先让被测代码注入 `UserDefaults`：

```swift
let suiteName = "AppKitLayoutTDDTests"
let defaults = UserDefaults(suiteName: suiteName)!
defaults.removePersistentDomain(forName: suiteName)
```

如果代码只能使用 `.standard`，按 key 备份与恢复：

```swift
private var savedValue: Any?
private let key = "accent_color"

override func setUp() {
    super.setUp()
    savedValue = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
}

override func tearDown() {
    if let savedValue {
        UserDefaults.standard.set(savedValue, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
    super.tearDown()
}
```

不要用 `defaults delete` 清理整个域，也不要把用户的真实偏好当作测试基线。

## 6. 安全地找到并运行测试

先确认 scheme，不猜：

```bash
xcodebuild -list -project App.xcodeproj
# 或：xcodebuild -list -workspace App.xcworkspace
```

运行定向测试时，使用明确的 target/类/方法标识：

```bash
xcodebuild test \
  -project App.xcodeproj \
  -scheme AppTests \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/appkit-layout-tdd-derived \
  -only-testing:AppTests/LayoutTests/testVisualCenterline
```

运行后检查：

- 出现了 `Test Case ... started` 和对应结果。
- `Executed N tests` 的 `N > 0`；`0 tests` 视为测试选择器错误，不是通过。
- 失败数为 0，且没有编译错误或测试进程崩溃。

### 防止 `make` 目标杀掉用户副本

先检查测试入口：

```bash
rg -n "pkill|killall|swift-test|test:" Makefile
```

如果 Makefile 里有类似 `pkill -f "MacOS/AppName"`，不要直接运行 `make swift-test`。改用上面的定向 `xcodebuild test`，并使用独立 DerivedData。确实需要停止进程时先取得用户同意；只终止自己启动的测试实例，按 PID 精确停止，不要按进程名批量杀。

## 7. 只读布局快照

诊断逻辑只读取当前状态，不触发布局：

```swift
enum LayoutDiagnostics {
    static func log(_ tag: String, window: NSWindow) {
        guard let content = window.contentView else { return }
        // 只读取已有 frame；不要在这里调用 layoutSubtreeIfNeeded
        let summary = "window=\(window.frame) content=\(content.frame) flipped=\(content.isFlipped)"
        print("[LAYOUT] \(tag) \(summary)")
    }
}
```

规则：

- 诊断本身不改帧、不主动重绘、不调用 `layoutSubtreeIfNeeded`。
- 测试可以先显式触发布局，再读取快照；触发布局与诊断读取分开。
- 在异步过渡后补一拍只读快照，捕捉 `setPosition` 或约束收敛造成的瞬态。
- 同时记录 `isHidden` 和父视图链，避免把隐藏视图的空 frame 当成异常。
- 需要压力测试时，循环切换状态并在每轮后读取快照，最后恢复用户原来的状态。

## 8. 推荐的验证顺序

1. 纯几何函数的单元测试先红。
2. 视图层级测试或只读帧断言转绿。
3. 运行完整 XCTest 套件，确认没有隔离问题。
4. 运行应用内自检或布局压力检查。
5. 启动真实应用，截图或检查辅助功能树；合成鼠标事件不可靠时改用人机配合。
6. 恢复默认值、窗口和分栏状态，再报告 exact 测试数字与未验证项。
