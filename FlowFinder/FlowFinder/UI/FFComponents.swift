import AppKit

// MARK: - 实体面板框（设备浮层唯一使用者）
//
// 2026-10-17 收敛说明：
//   本文件原先承载 ZCode 设计语言的四个通用组件（FFPanelView / FFSectionHeaderView /
//   FFEmptyStateView / FFSeparatorView）。ZCode 方向已于 17cfbeb 撤销并回归访达基线，
//   其中三个组件在生产代码中零引用（空态实际由 FFCommon.FFPaneStateOverlayView 承担），
//   故删除，避免「主界面一套、设计系统另一套」的双皮现象。
//
//   仅保留 FFPanelView：设备浮层按 DESIGN-SPEC M-04 需要实体卡片（玻璃上设备名与容量
//   可读性差）。材质改挂操作区令牌（C-01 / C-02），边框改挂分隔线令牌（C-03），
//   不再依赖已删除的 ZCode Color 令牌。
final class FFPanelView: NSView {

    /// 面板背景层级（映射到操作区令牌，不再有独立的 ZCode 色板）
    enum Tone {
        /// 侧栏一档（较深）
        case sidebar
        /// 常规内容面板
        case panel
        /// 头部/工具栏一档（较浅）
        case header
        /// 卡片/弹层
        case card
    }

    private let tone: Tone
    private let cornerRadius: CGFloat

    init(tone: Tone = .panel, cornerRadius: CGFloat = FFDesign.Glass.cornerRadiusPanel) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 是否绘制边框（嵌套面板可关掉，避免双线）
    var showsBorder: Bool = true {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer = layer else { return }
        let bg: NSColor
        switch tone {
        case .sidebar, .panel: bg = FFDesign.operationAreaBackground
        case .header, .card:   bg = FFDesign.operationAreaElevated
        }
        var bgColor = NSColor.clear.cgColor
        var borderColor = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bgColor = bg.cgColor
            borderColor = NSColor.separatorColor.cgColor
        }
        layer.backgroundColor = bgColor
        layer.borderWidth = showsBorder ? 1 : 0
        layer.borderColor = borderColor
        layer.cornerRadius = cornerRadius
    }

    /// 主题/外观变化时刷新（NSView 默认会在 appearance 变化时重新 updateLayer，
    /// 此处显式提供入口供无法自动触发的场景调用）
    func refreshAppearance() {
        needsDisplay = true
    }
}

// MARK: - 活动面板描边（发光）

/// 活动面板的强调色发光边缘。
///
/// 2026-10-18 #6：由 1.5pt 硬描边改为「发光」——由外到内叠三层不同宽度/透明度的
/// 圆角描边模拟羽化光晕（7pt@10% / 3.5pt@20% / 1.2pt@55%），不再有单根硬线。
/// 深色模式整体提高透明度，浅色模式略降；开启「增强对比度」时降级为 2pt 实线，
/// 保证低视力用户仍能看清边界。
/// 视图不参与命中测试，鼠标事件全部穿透，否则会把列表/工具栏的点击吃掉。
final class FFActivePaneBorderView: NSView {

    /// 发光颜色（随强调色设置变化）
    var ringColor: NSColor = FFAccent.current {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 颜色由 draw(_:) 自行绘制，不使用 layer 边框
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    /// 点击穿透：只做视觉提示，不参与事件分发
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden else { return }
        // 描边以路径为中心向两侧扩，最外层 7pt 会外扩 3.5pt，故内缩 3pt 防裁切
        let rect = bounds.insetBy(dx: 3, dy: 3)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)

        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            ringColor.setStroke()
            path.lineWidth = 2
            path.stroke()
            return
        }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let boost: CGFloat = isDark ? 1.25 : 0.85
        // (线宽, 透明度)：从外到内，外圈淡而宽，内圈亮而细
        let strokes: [(CGFloat, CGFloat)] = [
            (7.0, 0.10 * boost),
            (3.5, 0.20 * boost),
            (1.2, 0.55 * boost),
        ]
        for (width, alpha) in strokes {
            ringColor.withAlphaComponent(min(alpha, 1)).setStroke()
            path.lineWidth = width
            path.stroke()
        }
    }
}
