import Foundation

// MARK: - 交互决策表（2026-10-20 #3 架构收拢）
//
// 背景：前几轮返工的四个症状（拖面板拖走窗口 / 单栏单标签行为不同 /
// 卡片上下边缘不一致 / 侧栏隐藏后标签不避让）看似四个独立 bug，
// 实为同一个架构问题的四次显形——「按下去会发生什么」这个判定被拆散在
// hitTest 归并、mouseDownCanMoveWindow、标题栏带、Auto Layout 约束
// 四处，各自决定，结果是同一区域的行为取决于当下状态。
//
// 出路（借鉴 Chromium 的 TabDragController 做法）：把判定收成一张显式的表。
// 本文件是那张表的唯一来源，且**不依赖任何 AppKit 对象**——因此可以被
// FF_SELFTEST 在启动时穷举所有「区域 × 状态」组合逐条断言。
//
// Chromium 值得借鉴的不是 TabStrip 代码（它深度绑定 WebContents /
// TabStripModel / content:: 通知机制，无法摘出来复用），而是它把拖拽
// 判定收进单一状态机这件事：当前贴在哪个条上 / 能不能分离 / 落点算哪个条。

// MARK: - 区域

/// 「这次按下归谁管」——按语义划分，不按视图清单。
///
/// 刻意不按视图层级列：那样会得到 11 个区域（hitTest 覆写点归并后的集合），
/// × 5 个意图 × N 个状态 = 几百行，而且「侧栏行 vs 侧栏空白」这类细分
/// 仍要靠 hitTest 归并去猜，本质只是把 if 换个地方堆。
enum FFRegion: String, CaseIterable {
    /// 窗口区：侧栏空白、面板卡片四周 8pt 留白 → 拖窗口
    case window
    /// 标题区：窗口顶部 0..28（含标签条空白、红绿灯带）→ 拖窗口
    case title
    /// 面板区：工具栏、文件列表、详情栏浮层、侧栏行 → 不产生拖动
    case panel
    /// 标签本体：标签胶囊 → 唯一能拖面板的把手
    case tab
}

// MARK: - 意图

/// 一次按下最终要执行的动作。
enum FFIntent: String, CaseIterable {
    /// 拖动整个窗口
    case dragWindow
    /// 拖动整块操作面板（1:1 浮层跟随）
    case dragPane
    /// 在标签条内重排标签
    case reorderTab
    /// 激活被点击的标签
    case activateTab
    /// 文件列表空白处框选
    case marqueeSelect
    /// 不产生任何拖动（给按压反馈）
    case pressFeedback
    /// 命中调宽把手：事件放行，交给 `FFSplitView` 处理（2026-10-20 第五轮）
    case resizeDivider
    /// 交给子控件自己处理（按钮、输入框等）
    case handledByControl
}

// MARK: - 状态

/// 决策真正需要的三个状态维度。
///
/// 刻意只留这三个：状态维度越多，组合数越爆炸，表格越难穷举。
/// 与决策无关的状态（如当前是哪个目录、选中了几个文件）不进这里。
struct FFInteractionState: Equatable {
    /// 侧栏是否可见——决定标签条与工具栏的避让量
    var sidebarVisible: Bool = true
    /// 是否单面板——决定拖面板的落点语义
    var singlePane: Bool = true
    /// 指针是否仍在标签条的 20pt 缓冲区内
    /// （true = 条内重排，false = 出缓冲搬面板）
    var pointerInsideTabBuffer: Bool = true
    /// 是否命中调宽把手（卡片 8pt 留白上的把手热区）。
    /// 2026-10-20 第五轮：卡片留白同时是「拖窗口」与「调宽」把手，
    /// 两套手势在同一块区域打架（窗口跟跑 + 分隔线同动）——
    /// 裁定：留白只做调宽，此维度为 true 时优先于拖窗口。
    var onResizeHandle: Bool = false

    /// 穷举用：所有状态维度的组合
    static var allCombinations: [FFInteractionState] {
        var out: [FFInteractionState] = []
        for sidebarVisible in [true, false] {
            for singlePane in [true, false] {
                for pointerInsideTabBuffer in [true, false] {
                    for onResizeHandle in [true, false] {
                        out.append(FFInteractionState(sidebarVisible: sidebarVisible,
                                                     singlePane: singlePane,
                                                     pointerInsideTabBuffer: pointerInsideTabBuffer,
                                                     onResizeHandle: onResizeHandle))
                    }
                }
            }
        }
        return out
    }
}

// MARK: - 决策表

/// 交互决策表：区域 + 状态 → 意图。
///
/// 纯函数，不依赖 AppKit，因此可以被穷举断言。
enum FFInteractionPolicy {

    /// 决策表本体。
    ///
    /// 规则用「守卫 + 结果」的形式写，每条规则都有名字，
    /// 便于自检逐条点名断言（而不是只比一个总数）。
    struct Rule {
        let name: String
        let matches: (FFRegion, FFInteractionState) -> Bool
        let intent: FFIntent
    }

    /// 规则表。顺序即优先级。
    static let rules: [Rule] = [
        // ⓪ 调宽把手优先于一切（2026-10-20 第五轮）：
        // 卡片 8pt 留白同时被指定为「拖窗口」与「调宽把手」，两套手势在同一块
        // 物理区域上打架——窗口跟跑 + 分隔线同动，手感错乱。
        // 裁定：留白只做调宽。命中把手时无论什么区域一律放行给 FFSplitView。
        Rule(name: "把手→调宽",
             matches: { _, state in state.onResizeHandle },
             intent: .resizeDivider),

        // ① 标签本体是唯一能拖面板的把手
        Rule(name: "tab-出缓冲→搬面板",
             matches: { region, state in region == .tab && !state.pointerInsideTabBuffer },
             intent: .dragPane),

        Rule(name: "tab-条内→重排",
             matches: { region, state in region == .tab && state.pointerInsideTabBuffer },
             intent: .reorderTab),

        // ② 标题区（标签条空白 / 红绿灯带）性质等同系统标题栏 → 拖窗口
        Rule(name: "title→拖窗口",
             matches: { region, _ in region == .title },
             intent: .dragWindow),

        // ③ 窗口区（侧栏空白 / 卡片 8pt 留白）→ 拖窗口
        Rule(name: "window→拖窗口",
             matches: { region, _ in region == .window },
             intent: .dragWindow),

        // ④ 面板区不产生任何拖动
        Rule(name: "panel→按压反馈",
             matches: { region, _ in region == .panel },
             intent: .pressFeedback),
    ]

    /// 决策入口。
    ///
    /// 规则表不覆盖到的组合返回 `.handledByControl`（交给子控件自己处理），
    /// 不会「什么都不发生」——那正是最早那版 bug 的形态。
    static func intent(region: FFRegion, state: FFInteractionState) -> FFIntent {
        for rule in rules where rule.matches(region, state) {
            return rule.intent
        }
        return .handledByControl
    }

    /// 命中的是哪条规则（调试与自检用；未命中返回 nil）
    static func matchedRuleName(region: FFRegion, state: FFInteractionState) -> String? {
        for rule in rules where rule.matches(region, state) {
            return rule.name
        }
        return nil
    }

    // MARK: 几何常量

    /// 标题区高度（窗口顶部 0..36）。
    ///
    /// 2026-10-20 #4：从 28 调到 36，让标签上方留出 8pt 间隙
    /// （与左右下留白 8 同值）。面板卡片顶边正好等于这个值，位置不动。
    static let titleBandHeight: CGFloat = 36

    /// 活动标签高度：底边焊在面板顶边上，向上凸出
    static let activeTabHeight: CGFloat = 28

    /// 非活动标签高度：比活动矮 6pt，底边离面板顶边 6pt
    static let inactiveTabHeight: CGFloat = 22

    /// 标签上方间隙（标题带高 − 活动标签高）
    static var tabTopGap: CGFloat { titleBandHeight - activeTabHeight }

    /// 非活动标签底边距面板顶边的空隙
    static let inactiveTabBottomGap: CGFloat = 6

    /// 活动标签顶部圆角（r1）
    static let tabCornerRadius: CGFloat = 10

    /// 接缝处内凹圆角（r2）
    static let tabSeamFillet: CGFloat = 8

    /// 首个标签左缘距面板左缘的距离。
    ///
    /// 必须 ≥ 面板圆角 16 + 根部内凹 8 = 24，否则内凹会压进面板圆角、
    /// 轮廓构造器会拒绝画凸起（退化成普通矩形，看起来就是「没焊上」）。
    /// 取 26 留 2pt 平段。
    static let tabInsetFromPanel: CGFloat = 26

    /// 标签条拖动缓冲：指针在标签条矩形外扩 20pt 内仍算「条内重排」。
    ///
    /// 标签条只有 28pt 高，无缓冲会导致垂直抖动 1pt 就「出条」，
    /// 重排手势与搬面板打架。
    static let tabBuffer: CGFloat = 20

    /// 侧栏隐藏时，标题区内容（标签条 / 工具栏）的避让起点。
    ///
    /// 红绿灯占 13..70，「显示侧栏」浮动开关占 72..96，
    /// 96 + 10 = 106。侧栏可见时不需要避让（红绿灯在侧栏范围内）。
    static let hiddenSidebarInset: CGFloat = 106

    /// 侧栏可见时标题区内容的左缘（卡片左缘内侧）
    static let visibleSidebarInset: CGFloat = 8

    /// 标题区内容的左缘避让量。
    ///
    /// 标签条与工具栏**共用**这一个值——两处由同一处算出，
    /// 改一处两处生效，不会再出现「工具栏避让了、标签条没避让」。
    static func titleContentInset(sidebarVisible: Bool) -> CGFloat {
        sidebarVisible ? visibleSidebarInset : hiddenSidebarInset
    }
}
