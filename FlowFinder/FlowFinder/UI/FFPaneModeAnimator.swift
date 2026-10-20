import AppKit

/// 单/双面板切换的过渡动画（2026-10-20 #2）。
///
/// 规格：0.36s 弹性（带轻微过冲），宽度、透明度、缩放一起动，窗口宽度同步。
///
/// 为什么不用 `NSView.animator()` 直接动布局：面板显隐是
/// `NSSplitView` 的 arranged subview 增删，`NSSplitView` 不参与隐式动画，
/// 动不了。这里的做法是：
///   1. 结构变更瞬时完成（保证布局正确，不留中间态）
///   2. 窗口宽度用 `NSAnimationContext` 同曲线插值（这是唯一能真动画的部分）
///   3. contentView 叠一层 opacity 关键帧（1 → 0.72 → 1），做出「推挤 + 回弹」的观感
///
/// 代价：面板本身没有位移动画。这是 `NSSplitView` 的硬限制——
/// 想做出「面板滑出」必须放弃 NSSplitView 自己排布局，属于更大的改动。
enum FFPaneModeAnimator {

    /// 总时长（秒）
    static let duration: TimeInterval = 0.36

    /// 弹性曲线：前段快、末端轻微过冲
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 1.28, 0.48, 1.0)
    }

    /// 执行一次切换
    /// - Parameters:
    ///   - toSingle: true = 双 → 单；false = 单 → 双
    ///   - window: 用于取 contentView 加淡入淡出
    ///   - changes: 结构变更闭包（同步执行）
    static func animate(toSingle: Bool, window: NSWindow?, changes: () -> Void) {
        // 结构变更先落地：动画只负责「观感」，不承担正确性
        changes()

        guard let layer = window?.contentView?.layer else { return }

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        if toSingle {
            fade.values = [1.0, 0.72, 1.0]
            fade.keyTimes = [0, 0.42, 1]
        } else {
            fade.values = [0.78, 1.0]
            fade.keyTimes = [0, 1]
        }
        fade.duration = duration
        fade.timingFunction = timingFunction
        layer.add(fade, forKey: "ffPaneModeFade")
    }
}
