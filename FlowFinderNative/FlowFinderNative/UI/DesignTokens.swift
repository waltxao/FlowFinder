import AppKit

/// FlowFinder 设计令牌
///
/// 集中定义颜色/尺寸/玻璃材质令牌，作为硬编码值的单一来源。
/// 使用 NSColor 系统色为主，避免 HTML 设计稿中违反单主色调规则的变量。
enum FFDesign {
    // MARK: - 玻璃材质令牌（按 Apple "Liquid Glass" 设计规范重设计 v0.7.2）
    //
    // 设计原则（WWDC25 Session 219 "Liquid Glass everywhere"）：
    //   1) 玻璃应让下方内容"模糊地透出来"，不应用 tint 整片染色——液态玻璃本就是动态材质
    //   2) 平滑材质，不叠噪声（亚克力磨砂才用噪声；液态玻璃是平滑的）
    //   3) 顶部柔光（被光照射的边缘感），不是 0.5pt 细硬线
    //   4) 1.5~2pt 宽的"磨边"亮线（边缘像被打磨的反光），不是细描边
    //   5) 仅浮层玻璃（详情栏/工具面板/设备栏）有外阴影显"浮起"；嵌入式小元素（搜索框、卡片）
    //      贴在已有玻璃之上不浮起，无外阴影
    //   6) 浮层用 .regular style（标准液态玻璃，有厚度感）；嵌入式小元素用 .clear style（轻盈半浮）
    enum Glass {
        /// 玻璃层级
        enum Level {
            /// 窗口背景：整窗背景玻璃（NSGlassEffectView 由窗口控制器持有）
            case window
            /// 浮在内容之上的浮层（详情栏 / 工具面板 / 设备栏）：.regular style + 浮起阴影
            case panel
            /// 嵌入在已有玻璃之上的小元素（搜索框 / 工具卡片）：.clear style 无外阴影
            case component
        }

        // 噪声——液态玻璃不用（保留常量供旧调用引用，但 FFGlassView 不再叠加 noiseLayer）
        static let noiseTileSize: CGFloat = 256
        static let noiseAlphaLight: CGFloat = 0
        static let noiseAlphaDark: CGFloat = 0

        // 顶部柔光（液态玻璃被光照射的边缘感）
        static let highlightInset: CGFloat = 1            // 1pt 宽柔光（替代旧 0.5pt 细硬线）
        static let highlightAlphaLight: CGFloat = 0.22   // 浅色 0.22（柔光，不刺眼）
        static let highlightAlphaDark: CGFloat = 0.10     // 深色 0.10（边缘微亮）

        // 内阴影——保留，但浅色降低（液态玻璃自身已有厚度感，少叠）
        static let innerShadowRadius: CGFloat = 2
        static let innerShadowOffset: CGSize = CGSize(width: 0, height: -1)
        static let innerShadowAlphaLight: CGFloat = 0.06
        static let innerShadowAlphaDark: CGFloat = 0.18

        // 玻璃 tint——液态玻璃几乎不染色，靠原生材质自身色调；tint 仅作"弱苍白化"提高文字可读
        static let tintLight: NSColor = NSColor.white.withAlphaComponent(0.10)  // 浅色极淡
        static let tintDark: NSColor = NSColor.black.withAlphaComponent(0.18)   // 深色微暗

        // 性能预算
        static let maxGlassInstances = 8

        // 圆角（按层级）——Wave4 Task 2 收敛为两档：容器级 16 / 浮层级 10
        static let cornerRadiusWindow: CGFloat = 12
        static let cornerRadiusPanel: CGFloat = 10     // 浮层 10（与详情栏/设备/工具面板统一）
        static let cornerRadiusComponent: CGFloat = 10 // 嵌入式 10

        // 液态玻璃描边："磨边"亮线，宽 1.75pt，alpha 较高，边缘反光感
        // 嵌入式小元素的描边略弱（贴在大玻璃上不应突兀）
        static let borderLight: NSColor = NSColor.white.withAlphaComponent(0.65)
        static let borderDark: NSColor = NSColor.white.withAlphaComponent(0.20)
        static let borderWidth: CGFloat = 1.75
        // 嵌入式小元素的描边略弱（贴在大玻璃上不应突兀）
        static let borderLightComponent: NSColor = NSColor.white.withAlphaComponent(0.45)
        static let borderDarkComponent: NSColor = NSColor.white.withAlphaComponent(0.14)

        // 浮层阴影（详情栏 / 工具面板 / 设备栏）：明显浮起感
        static let shadowOpacity: Float = 0.30
        static let shadowRadius: CGFloat = 14
        static let shadowOffset: CGSize = CGSize(width: 0, height: 6)

        // 嵌入式小元素：无外阴影（设 0）
        static let shadowOpacityEmbedded: Float = 0
        static let shadowRadiusEmbedded: CGFloat = 0
        static let shadowOffsetEmbedded: CGSize = CGSize(width: 0, height: 0)

        /// 按层级取默认圆角
        static func defaultCornerRadius(for level: Level) -> CGFloat {
            switch level {
            case .window:    return cornerRadiusWindow
            case .panel:     return cornerRadiusPanel
            case .component: return cornerRadiusComponent
            }
        }

        /// 按层级取是否浮层（决定是否有外阴影）
        static var isFloating: Bool {
            // panel 浮在内容上方（有外阴影），component 嵌在已有玻璃之上（无外阴影）
            // 注：FFGlassView 内通过 level 判断，这里只是文档化常量入口
            true
        }
    }

    // MARK: - 操作区颜色令牌（实体区域，Wave4 颜色统一）

    //
    // v0.6.7 决策：操作区为实体圆角卡片浮在窗口玻璃上，基色日间 #F5F5F5 / 夜间 #2D2D2D
    // （用户偏好红线：操作区基色基调不变，Wave4 只做令牌化统一）。
    // elevated 为「浅一档」灰度：供工具栏等实体区上的次级表面使用，
    // 替代此前「实体底上叠玻璃」的材质冲突（审计 §1.1）。
    // 双值纪律：与 Glass 令牌一致——读取时按 isDark 即时解析；缓存 cgColor 的调用方
    // 必须在 .appearanceChanged / 主题刷新链中重读重设。
    enum OperationArea {
        /// 基色：日间 #F5F5F5 / 夜间 #2D2D2D（v0.6.7 基调不变）
        static let backgroundLight = NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)  // #F5F5F5
        static let backgroundDark = NSColor(srgbRed: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)   // #2D2D2D
        /// 浅一档：日间 #FAFAFA / 夜间 #333333（工具栏等实体区次级表面）
        static let elevatedLight = NSColor(srgbRed: 0.980, green: 0.980, blue: 0.980, alpha: 1.0)    // #FAFAFA
        static let elevatedDark = NSColor(srgbRed: 0.200, green: 0.200, blue: 0.200, alpha: 1.0)     // #333333
    }

    /// 当前操作区基色（日间 #F5F5F5 / 夜间 #2D2D2D）
    static var operationAreaBackground: NSColor {
        isDark ? OperationArea.backgroundDark : OperationArea.backgroundLight
    }

    /// 当前操作区浅一档灰度（日间 #FAFAFA / 夜间 #333333）
    static var operationAreaElevated: NSColor {
        isDark ? OperationArea.elevatedDark : OperationArea.elevatedLight
    }

    // MARK: - 字体令牌（Wave4 Task 5）

    //
    // 审计 §3：全应用 9–20pt 字号分散硬编码、无字体令牌，同一信息档跨文件不一致。
    // 本期仅统一已确认的不一致点（分组标题 / 详情栏标签值与名称 / 同档引用），
    // 全量令牌化列入后续（避免大范围回归）。
    enum Typography {
        /// 辅助信息（预留：小型徽标/计数等 10pt 档）
        static let caption = NSFont.systemFont(ofSize: 10)
        /// 正文基准（列表/网格文件名、详情栏标签与值）
        static let body = NSFont.systemFont(ofSize: 11)
        /// 强调正文（分组标题，semibold）
        static let emphasis = NSFont.systemFont(ofSize: 11, weight: .semibold)
        /// 标题（详情栏文件名，semibold）
        static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
    }

    // MARK: - 主题相关便捷访问

    /// 当前是否深色（供玻璃层判断令牌）
    static var isDark: Bool {
        ThemeManager.shared.resolvedIsDark
    }

    /// 当前噪声 alpha（已置 0，液态玻璃不用）
    static var noiseAlpha: CGFloat {
        isDark ? Glass.noiseAlphaDark : Glass.noiseAlphaLight
    }

    /// 当前高光 alpha
    static var highlightAlpha: CGFloat {
        isDark ? Glass.highlightAlphaDark : Glass.highlightAlphaLight
    }

    /// 当前内阴影 alpha
    static var innerShadowAlpha: CGFloat {
        isDark ? Glass.innerShadowAlphaDark : Glass.innerShadowAlphaLight
    }

    /// 当前 tint（浮层）
    static var glassTint: NSColor {
        isDark ? Glass.tintDark : Glass.tintLight
    }

    /// 当前描边色（浮层 panel）
    static var glassBorder: NSColor {
        isDark ? Glass.borderDark : Glass.borderLight
    }

    /// 当前描边色（嵌入式 component，比 panel 弱）
    static var glassBorderComponent: NSColor {
        isDark ? Glass.borderDarkComponent : Glass.borderLightComponent
    }

    // MARK: - V0.8.0 设计基线（移植自 zai-org/ZCode DESIGN.md）
    //
    // 立场转变：从「液态玻璃 + 超椭圆 + 多重投影」改为「扁平、致密、以边框分层」。
    // ZCode 原文：Layer primarily through background contrast, borders, and radius
    // before relying on heavy shadows；Avoid playful gradients / bright full-surface fills。
    //
    // 命名与取值一一对应 ZCode 的 CSS 变量，便于对照上游文档：
    //   --color-background      → Color.panel
    //   --color-background-alt  → Color.window
    //   --color-sidebar         → Color.sidebar
    //   --color-border          → Color.border
    //   --color-hover/selected  → Color.rowHover / Color.rowSelected
    //
    // 实现要点：全部用 NSColor(name:dynamicProvider:) 生成动态色，
    // 由系统 appearance 自动解析，不再需要调用方判断 isDark 后重设 cgColor
    // （旧 Glass 令牌的双值纪律是大量「主题不跟随」缺陷的来源）。

    /// 取色辅助：按 appearance 返回对应值
    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.aqua, .darkAqua])
            return best == .darkAqua ? dark : light
        }
    }

    /// 语义色令牌（对应 ZCode Color Palette）
    enum Color {
        // 背景层次：窗口根 < 面板 < 卡片 < 弹层
        /// 窗口根背景（ZCode --color-background-alt）
        static let window = dynamic(
            light: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.933, alpha: 1),  // #ececee
            dark: NSColor(srgbRed: 0.059, green: 0.059, blue: 0.059, alpha: 1)    // #0f0f0f
        )
        /// 面板底（ZCode --color-background）
        static let panel = dynamic(
            light: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.973, alpha: 1),  // #f8f8f8
            dark: NSColor(srgbRed: 0.086, green: 0.086, blue: 0.086, alpha: 1)    // #161616
        )
        /// 侧栏底（ZCode --color-sidebar）
        static let sidebar = dynamic(
            light: NSColor(srgbRed: 0.941, green: 0.941, blue: 0.941, alpha: 1),  // #f0f0f0
            dark: NSColor(srgbRed: 0.086, green: 0.086, blue: 0.086, alpha: 1)    // #161616
        )
        /// 头部/工具栏底（ZCode --color-header / --color-panel）
        static let header = dynamic(
            light: NSColor.white,                                                  // #ffffff
            dark: NSColor(srgbRed: 0.125, green: 0.125, blue: 0.125, alpha: 1)     // #202020
        )
        /// 卡片/输入框/弹层底（ZCode --color-card / --color-input）
        static let card = dynamic(
            light: NSColor.white,                                                  // #ffffff
            dark: NSColor(srgbRed: 0.169, green: 0.169, blue: 0.169, alpha: 1)     // #2b2b2b
        )

        // 边框：结构分层的唯一手段（不用阴影）
        /// 默认边框（ZCode --color-border，rgba(13,13,13,.10) / rgba(255,255,255,.10)）
        static let border = dynamic(
            light: NSColor(srgbRed: 0.051, green: 0.051, blue: 0.051, alpha: 0.10),
            dark: NSColor(white: 1.0, alpha: 0.10)
        )
        /// hover 边框（ZCode --color-border-hover）
        static let borderHover = dynamic(
            light: NSColor(srgbRed: 0.051, green: 0.051, blue: 0.051, alpha: 0.15),
            dark: NSColor(white: 1.0, alpha: 0.15)
        )

        // 状态遮罩：选中不再用系统蓝填充，改中性遮罩 + 左侧强调条
        /// 行 hover（ZCode --color-hover，5% 中性）
        static let rowHover = dynamic(
            light: NSColor(srgbRed: 0.051, green: 0.051, blue: 0.051, alpha: 0.05),
            dark: NSColor(white: 1.0, alpha: 0.05)
        )
        /// 行选中（ZCode --color-selected，浅 5% / 深 10%）
        static let rowSelected = dynamic(
            light: NSColor(srgbRed: 0.051, green: 0.051, blue: 0.051, alpha: 0.05),
            dark: NSColor(white: 1.0, alpha: 0.10)
        )

        // 文字层次
        /// 主文字（ZCode --color-foreground，neutral-800 / #f5f5f5）
        static let textPrimary = dynamic(
            light: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1),   // #262626
            dark: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1)     // #f5f5f5
        )
        /// 次要文字 60%
        static let textSecondary = dynamic(
            light: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 0.60),
            dark: NSColor(white: 1.0, alpha: 0.60)
        )
        /// 三级文字 40%（占位、弱提示、拖拽指示线）
        static let textTertiary = dynamic(
            light: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 0.40),
            dark: NSColor(white: 1.0, alpha: 0.40)
        )

        /// 危险操作（删除）
        static let destructive = NSColor.systemRed
    }

    /// 布局几何令牌
    enum Layout {
        /// 窗口四边留白（ZCode: 4px outer inset）
        static let windowInset: CGFloat = 4
        /// 面板间透明间隙（间隙即拖拽热区）
        static let panelGap: CGFloat = 4
        /// 分隔拖拽指示线宽度（ZCode: 2px）
        static let resizeIndicatorWidth: CGFloat = 2
        /// 拖拽热区宽度
        static let resizeHitWidth: CGFloat = 4
        /// 面板边框宽度
        static let borderWidth: CGFloat = 1
        /// 工具栏高度（紧凑致密）
        static let toolbarHeight: CGFloat = 36
        /// 侧栏默认宽度
        static let sidebarWidth: CGFloat = 200
    }

    /// 圆角令牌：按嵌套层级递减（ZCode Radius 规则）
    enum Radius {
        /// 面板框（ZCode rounded-xl）
        static let xl: CGFloat = 12
        /// 卡片、按钮、菜单外壳（rounded-lg）
        static let lg: CGFloat = 8
        /// 菜单项、输入框（rounded-md）
        static let md: CGFloat = 6
        /// 嵌套容器、药丸内元素（rounded-sm）
        static let sm: CGFloat = 4
    }

    /// 间距令牌：全项目只用这六档（ZCode base unit 4px）
    enum Spacing {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
    }

    /// 字体令牌（V0.8.0 基准 13pt）
    ///
    /// 迁移说明：旧 Typography.body(11) / emphasis(11) / title(13) 偏小 2pt，
    /// 是「看不清、不精致」的直接来源。新令牌对齐 macOS 标准 13pt 正文。
    /// 旧令牌保留至 P2 布局重排完成（行高需同步从 26 调到 28，否则文字被裁）。
    enum Text {
        /// 17 semibold：空态主标题、引导页标题
        static let xl = NSFont.systemFont(ofSize: 17, weight: .semibold)
        /// 15 semibold：分区标题、详情栏文件名
        static let lg = NSFont.systemFont(ofSize: 15, weight: .semibold)
        /// 13 regular：正文、文件名、按钮
        static let base = NSFont.systemFont(ofSize: 13)
        /// 13 medium：选中项、当前分区
        static let baseEmphasis = NSFont.systemFont(ofSize: 13, weight: .medium)
        /// 12 regular：次要说明、路径
        static let caption = NSFont.systemFont(ofSize: 12)
        /// 11 regular：辅助信息、tooltip
        static let sm = NSFont.systemFont(ofSize: 11)
        /// 10 regular：徽标、计数、快捷键提示
        static let xs = NSFont.systemFont(ofSize: 10)
        /// 12 等宽：路径、大小、日期列
        static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }
}
