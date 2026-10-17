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
