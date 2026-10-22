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

        // 圆角（按层级）——统一自 FFVisualTokens.Radius：窗口/面板 12，浮层/卡片 8
        static let cornerRadiusWindow: CGFloat = FFVisualTokens.Radius.window
        static let cornerRadiusPanel: CGFloat = FFVisualTokens.Radius.panel
        static let cornerRadiusComponent: CGFloat = FFVisualTokens.Radius.card

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


    // MARK: - 字体令牌（唯一来源，对应 docs/DESIGN-SPEC.md §3.2）

    //
    // 2026-10-17 收敛：删除并存的 Typography（10/11/11sb/13sb）与 Text 两套令牌。
    // 每档只有一个条目，任何字号都必须指向此处，不得再直接写 systemFont(ofSize:)。
    enum Text {
        /// 17 semibold：空态主标题、引导页标题
        static let xl = NSFont.systemFont(ofSize: 17, weight: .semibold)
        /// 15 semibold：详情栏文件名、弹窗标题
        static let lg = NSFont.systemFont(ofSize: 15, weight: .semibold)
        /// 13 regular：列表/网格文件名、侧栏条目、按钮
        static let base = NSFont.systemFont(ofSize: 13)
        /// 13 medium：选中项、当前分区
        static let baseEmphasis = NSFont.systemFont(ofSize: 13, weight: .medium)
        /// 13 semibold：语义上需要强调但尺寸同正文（如详情栏多选汇总标题）
        static let baseSemibold = NSFont.systemFont(ofSize: 13, weight: .semibold)
        /// 12 regular：次要说明、路径
        static let caption = NSFont.systemFont(ofSize: 12)
        /// 11 semibold：列头、分组标题
        static let captionEmphasis = NSFont.systemFont(ofSize: 11, weight: .semibold)
        /// 11 regular：辅助信息、tooltip
        static let sm = NSFont.systemFont(ofSize: 11)
        /// 10 regular：徽标、计数、快捷键提示
        static let xs = NSFont.systemFont(ofSize: 10)
        /// 12 等宽：路径、大小、日期列
        static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }
}
