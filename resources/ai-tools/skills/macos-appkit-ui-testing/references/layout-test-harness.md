# AppKit 布局测试配方

以下代码是模式骨架。把 `AppWindowController`、`paneSplitView`、`detailsBar`、`setSidebarVisible` 等替换为项目实际类型和方法；不要直接复制类名。

## 1. 默认值快照与恢复

先保存“键是否存在”，恢复时按原样写回或删除；不要用 `defaults delete` 清整个域。

```swift
import Foundation

struct LayoutDefaultsSnapshot {
    private let defaults: UserDefaults
    private let keys: [String]
    private let values: [String: Any]

    init(keys: [String], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keys = keys
        self.values = keys.reduce(into: [:]) { result, key in
            if let value = defaults.object(forKey: key) {
                result[key] = value
            }
        }
    }

    func restore() {
        for key in keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
```

```swift
func testShellLayoutIsStable() throws {
    let snapshot = LayoutDefaultsSnapshot(keys: [
        "sidebar_hidden",
        "sidebar_width",
        "single_pane_mode",
        "pane_left_width"
    ])
    defer { snapshot.restore() }

    // 测试体
}
```

常见布局键：`sidebar_hidden`、`sidebar_width`、`single_pane_mode`、`pane_left_width`。再检查项目自己的详情栏宽度、窗口 frame、列宽、主题/密度等会影响布局的键。优先让被测代码接受注入的 `UserDefaults(suiteName:)`；只能使用 `.standard` 时用上面的快照。

## 2. 同祖先坐标与视觉中心

```swift
func frameInAncestor(_ view: NSView, ancestor: NSView) -> NSRect? {
    guard let parent = view.superview else { return nil }
    return ancestor.convert(view.frame, from: parent)
}

func visualRect(_ view: NSView, in ancestor: NSView) -> NSRect? {
    guard let parent = view.superview else { return nil }
    let rect = view.alignmentRect(forFrame: view.frame)
    return ancestor.convert(rect, from: parent)
}
```

- `alignmentRect(forFrame:)` 接收与 `frame` 同坐标系的矩形，传 `view.frame`，不要传 `view.bounds`。
- 返回矩形仍在传入坐标系中；从 `view.superview` 转到目标祖先，不要直接把不同坐标系的 `midY` 相比。
- 自定义控件若仍偏移，检查 `alignmentRectInsets` 是否被覆盖。
- 失败信息同时输出 `frame`、`alignmentRect`、`isFlipped` 和 `superview` 链。

```swift
guard
    let plusRect = visualRect(plusButton, in: strip),
    let tabRect = visualRect(activeTab, in: strip)
else {
    return XCTFail("控件不在同一视图层级")
}
XCTAssertEqual(plusRect.midY, tabRect.midY, accuracy: 0.5)
```

## 3. flipped 方向的显式处理

在 flipped 的宿主里，正的 `centerY` 常量通常向下；想让内容上移，常量可能必须取负。不要硬编码“正数就是上移”。

```swift
func signedCenterOffset(_ offset: CGFloat, in host: NSView) -> CGFloat {
    host.isFlipped ? -offset : offset
}
```

```swift
content.centerYAnchor.constraint(
    equalTo: host.centerYAnchor,
    constant: signedCenterOffset(3, in: host)
).isActive = true
```

`NSStackView` 及其子视图可能给出与预期相反的方向。先读 `isFlipped`，再用两个中心值验证；如果只能靠经验，至少加一条断言锁定实测方向：

```swift
XCTAssertEqual(contentRect.midY, referenceRect.midY, accuracy: 0.5,
               "host.isFlipped=\(host.isFlipped), content=\(contentRect), ref=\(referenceRect)")
```

## 4. 面板数与辅助视图

```swift
XCTAssertEqual(split.arrangedSubviews.count, expectedCount,
               "面板数异常：arranged=\(split.arrangedSubviews.count), subviews=\(split.subviews.count)")
```

- 断言面板数用 `arrangedSubviews`，不要用 `subviews`；分隔线、拖拽标签、宽度浮标都可能让 `subviews.count` 多 1。
- 不要把辅助视图 `addSubview` 到 `NSSplitView`；`NSSplitView` 会把直接子视图当成 pane。放在分栏的父容器或独立 overlay。
- 辅助视图只负责显示时，让 `hitTest` 返回 `nil`，不要吞掉拖拽或点击。

```swift
final class LayoutBadge: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

container.addSubview(badge) // 不要 split.addSubview(badge)
```

添加/恢复 panel 后，先让分栏完成布局，再设置 divider：

```swift
split.adjustSubviews()
split.layoutSubtreeIfNeeded()
split.setPosition(target, ofDividerAt: 0)
split.adjustSubviews()
split.layoutSubtreeIfNeeded()
```

## 5. 显示前布局测试

窗口用 `showImmediately: false` 创建时，测试应覆盖“还没显示就已经有正确首帧”。

```swift
func testNewWindowPreparesFirstFrameBeforeShow() throws {
    let controller = AppWindowController(
        startsWithSinglePane: true,
        showImmediately: false,
        runsSelfTests: false
    )
    defer { controller.close() }

    controller.window?.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(controller.window?.isVisible ?? true,
                   "本测试验证 show 之前的布局，窗口不应提前显示")

    let split = try XCTUnwrap(controller.paneSplitView)
    XCTAssertEqual(split.arrangedSubviews.count, 1,
                   "单栏显示前只能排列一块面板")

    let pane = try XCTUnwrap(split.arrangedSubviews.first)
    XCTAssertEqual(pane.frame.width, split.bounds.width, accuracy: 1,
                   "可见面板必须填满分栏")
    XCTAssertEqual(pane.frame.height, split.bounds.height, accuracy: 1)

    let details = try XCTUnwrap(controller.detailsBar)
    let distance = visualBottomDistance(details, in: controller.paneContainer)
    XCTAssertLessThan(distance, 80, "详情栏应贴视觉底部")
}
```

```swift
func visualBottomDistance(_ view: NSView, in container: NSView) -> CGFloat {
    guard let rect = frameInAncestor(view, ancestor: container) else {
        return .greatestFiniteMagnitude
    }
    return container.isFlipped
        ? container.bounds.height - rect.maxY
        : rect.minY
}
```

首帧 50/50 的回归要断言“等于记忆宽度”，不要只断言“不等于一半”。如果 50% 恰好是合法默认值，单独标注这是预期默认值。

## 6. 20 轮交替压力循环

```swift
func testAlternatingShellStatesKeepContentLaidOut() throws {
    let snapshot = LayoutDefaultsSnapshot(keys: [
        "sidebar_hidden", "sidebar_width", "single_pane_mode", "pane_left_width"
    ])
    defer { snapshot.restore() }

    let controller = AppWindowController(
        startsWithSinglePane: false,
        showImmediately: false,
        runsSelfTests: false
    )
    defer { controller.close() }

    for cycle in 1...20 {
        controller.setSidebarVisible(cycle.isMultiple(of: 2), animated: false)
        controller.isSinglePaneMode = cycle.isMultiple(of: 3)
        controller.applyPaneMode()
        controller.activePane = cycle.isMultiple(of: 2) ? .left : .right

        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let split = try XCTUnwrap(controller.paneSplitView)
        let expected = controller.isSinglePaneMode ? 1 : 2
        XCTAssertEqual(split.arrangedSubviews.count, expected,
                       "第 \(cycle) 轮：面板数应为 \(expected)")

        for pane in split.arrangedSubviews {
            XCTAssertFalse(pane.isHidden, "第 \(cycle) 轮：排列中的面板不应隐藏")
            XCTAssertGreaterThan(pane.frame.width, 100,
                                 "第 \(cycle) 轮：面板宽度异常")
            XCTAssertEqual(pane.frame.height, split.bounds.height,
                           accuracy: 2, "第 \(cycle) 轮：面板高度塌陷")
        }

        let totalWidth = split.arrangedSubviews.reduce(CGFloat.zero) { $0 + $1.frame.width }
        if expected == 1 {
            XCTAssertEqual(totalWidth, split.bounds.width, accuracy: 1,
                           "第 \(cycle) 轮：单栏应填满分栏")
        } else {
            XCTAssertEqual(totalWidth, split.bounds.width, accuracy: 8,
                           "第 \(cycle) 轮：双栏总宽应接近分栏宽度（允许 divider）")
        }

        let content = try XCTUnwrap(controller.activePaneContent)
        XCTAssertGreaterThan(content.frame.height, 100,
                             "第 \(cycle) 轮：内容区高度塌陷")

        let details = try XCTUnwrap(controller.detailsBar)
        XCTAssertLessThan(visualBottomDistance(details, in: controller.paneContainer), 80,
                          "第 \(cycle) 轮：详情栏悬空")
    }
}
```

- 上方 API 是占位符；按项目实际方法替换。
- 20 轮只是起点；偶发问题可以增加轮数或交替同步/异步路径，但报告必须写清实际轮数和“是否复现”。
- 每轮只输出必要的帧摘要；不要打印整棵视图树。
- 测试结束在 `defer` 中恢复默认值，并在关闭窗口前再读一次确认恢复。

## 7. 只读帧诊断

```swift
enum LayoutDiagnostics {
    static func log(_ tag: String, window: NSWindow) {
        guard let content = window.contentView else { return }
        let summary = "window=\(window.frame) content=\(content.frame) flipped=\(content.isFlipped)"
        print("[LAYOUT] \(tag) \(summary)")
    }
}
```

规则：

- 诊断函数只读当前状态，不调用 `layoutSubtreeIfNeeded`、不改 frame、不主动重绘。
- 测试可以先触发布局，再读取快照；触发与读取分开。
- 在异步过渡后补一拍只读快照，捕捉瞬态；但不要为了“看起来对”在诊断里强制布局。
- 记录 `isFlipped`、`frame`、`alignmentRect`、`isHidden` 和父视图链，避免把隐藏视图的空 frame 当成异常。

## 8. 推荐验证顺序

1. 默认值快照 + 恢复。
2. 纯几何函数测试先红。
3. pre-show 布局测试、面板数/alignment/flipped 测试转绿。
4. 20 轮交替压力循环转绿。
5. 全量 XCTest 与项目自检通过，记录 exact 执行数。
6. 再进入隔离实机验证，见 [isolated-device-verification.md](isolated-device-verification.md)。
