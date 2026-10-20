import AppKit

/// 窗口圆角（2026-10-20 #5）。
///
/// 目标：窗口与面板用同一族曲线（超椭圆/连续曲率），半径 12。
///
/// 走过的两条路，结果不同，记在这里免得以后重复踩：
///
/// 1. **CAShapeLayer 遮罩**（`SquircleView.squirclePath` 那条路径）——
///    实测整窗内容区渲染成空白（侧栏、面板全不见，只剩红绿灯），
///    换容器承载遮罩也一样。原因推测与窗口 backing layer 的合成方式有关。
/// 2. **`CALayer.cornerCurve = .continuous`** —— 正常渲染，且这就是 Apple
///    自己用的连续曲率圆角（与面板 squircle 同族），视觉上与面板一致。
///
/// 因此采用第 2 条。`NSVisualEffectView` 的 backdrop 层不能直接改圆角，
/// 所以外面套一层普通容器 `FFWindowRootView`，圆角加在容器上。
enum FFWindowShape {

    /// 窗口圆角半径（面板卡片 16、操作区 10，窗口取 12）
    static let cornerRadius: CGFloat = 12

    /// 安装（幂等）
    static func install(on window: NSWindow) {
        if !(window.contentView is FFWindowRootView), let original = window.contentView {
            let root = FFWindowRootView(frame: original.frame)
            root.autoresizingMask = [.width, .height]
            original.autoresizingMask = [.width, .height]
            original.frame = root.bounds
            root.addSubview(original)
            window.contentView = root
        }
        // 圆角外要透出桌面，否则方角会露出来
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        update(on: window)
    }

    /// 重算圆角（窗口尺寸变化 / 进出全屏时调用）
    static func update(on window: NSWindow) {
        guard let view = window.contentView else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }

        // 全屏由系统接管外观，带圆角会露黑边
        if window.styleMask.contains(.fullScreen) {
            layer.cornerRadius = 0
            layer.masksToBounds = false
            return
        }
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        // 连续曲率圆角：与面板的超椭圆同族，不是普通圆弧
        layer.cornerCurve = .continuous
    }
}

/// 窗口内容根容器：只做圆角宿主，不参与任何交互判定。
///
/// 存在的唯一理由：`NSVisualEffectView` 的 backdrop 层不能直接改圆角，
/// 否则内容区不渲染。
final class FFWindowRootView: NSView {

    /// 命中测试照常下发给子视图；自己没有可点区域
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
