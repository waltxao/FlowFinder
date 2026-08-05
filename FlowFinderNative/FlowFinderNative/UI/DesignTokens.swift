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

        // 圆角（按层级）
        static let cornerRadiusWindow: CGFloat = 12
        static let cornerRadiusPanel: CGFloat = 14     // 浮层 14（柔和）
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
}
