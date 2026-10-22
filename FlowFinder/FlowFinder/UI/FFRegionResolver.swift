import AppKit

// MARK: - 区域协议

/// 视图自我声明自己属于哪个语义区域。
///
/// 收拢的要点：命中测试**不再靠各个视图覆写 hitTest 去猜**，
/// 而是每个视图只回答「我是什么」——区域由 `FFInteractionPolicy` 统一翻译成意图。
/// 新增功能时是「给新视图加一行协议实现」，不是「再加一个 if」。
protocol FFRegionAware: AnyObject {
    var ffRegion: FFRegion { get }
}

// MARK: - 区域解析

/// 把命中的视图解析成区域，再交给决策表翻译成意图。
///
/// 这是**唯一**做「视图 → 意图」转换的地方。
enum FFAreaResolver {

    /// 解析命中链上的区域。
    ///
    /// 从命中的视图向上走，取**第一个**声明了区域的祖先。
    /// 这样「标签胶囊在标签条里」会先命中胶囊自己（.tab），
    /// 而「标签条空白」会跳过标签、命中标签条（.title）。
    static func region(of hit: NSView?) -> FFRegion? {
        guard let hit else { return nil }

        // 控件与带点击手势的自绘控件自己消费鼠标事件。
        // 但只在祖先区域是 .window / .title 时才短路——这两类区域会把按下翻译成
        // 「拖窗口」，并吞掉 mouseUp，侧栏按钮 / 标签条「+」就永远不触发。
        // .panel / .tab 必须保留原区域：拖标签落到文件列表上仍要能命中操作区。
        var view: NSView? = hit
        var interactive = false
        while let current = view {
            if current is NSControl { interactive = true }
            if current.gestureRecognizers.contains(where: { $0 is NSClickGestureRecognizer }) {
                interactive = true
            }
            if let aware = current as? FFRegionAware {
                let region = aware.ffRegion
                if interactive && (region == .window || region == .title) {
                    return nil
                }
                return region
            }
            view = current.superview
        }
        return nil
    }

    /// 一次点击的完整判定：区域 → 意图。
    ///
    /// 命中链上**没有**任何区域声明时返回 `.handledByControl`——
    /// 交给控件自己处理，而不是「什么都不发生」。
    static func intent(for hit: NSView?, state: FFInteractionState) -> FFIntent {
        guard let region = region(of: hit) else { return .handledByControl }
        return FFInteractionPolicy.intent(region: region, state: state)
    }
}
