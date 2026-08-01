import AppKit

/// FlowFinder 设计令牌
///
/// 集中定义颜色/尺寸/玻璃材质令牌，作为硬编码值的单一来源。
/// 使用 NSColor 系统色为主，避免 HTML 设计稿中违反单主色调规则的变量。
enum FFDesign {
    // MARK: - 玻璃材质令牌（液态玻璃增强）
    enum Glass {
        /// 玻璃层级
        enum Level {
            /// 窗口背景：单实例 NSGlassEffectView，整窗背景模糊
            case window
            /// 面板/侧边栏 section/工具栏/对话框：NSGlassEffectView + 噪声 + 高光
            case panel
            /// 子组件（详情栏卡片、task bar、悬停态）：半透明 tint + 圆角 + 边缘高光（不创建 NSGlassEffectView）
            case component
        }

        // 噪声纹理参数（亚克力磨砂质感核心）
        static let noiseTileSize: CGFloat = 256           // 平铺尺寸（程序化生成的 CGImage）
        static let noiseAlphaLight: CGFloat = 0.040       // 浅色模式噪声 alpha
        static let noiseAlphaDark: CGFloat = 0.055        // 深色模式噪声 alpha（略强以补偿深底对比）

        // 边缘高光（液态玻璃折射感）
        static let highlightInset: CGFloat = 0.5          // 顶部高光线宽度
        // 修复亮色块: 降低 highlightAlphaLight 从 0.45 到 0.15，避免浅色模式顶部高光过亮
        static let highlightAlphaLight: CGFloat = 0.15    // 浅色模式高光 alpha
        static let highlightAlphaDark: CGFloat = 0.06     // 深色模式高光 alpha

        // 内阴影（深度感）
        static let innerShadowRadius: CGFloat = 3
        static let innerShadowOffset: CGSize = CGSize(width: 0, height: -1)
        static let innerShadowAlphaLight: CGFloat = 0.10
        static let innerShadowAlphaDark: CGFloat = 0.25

        // 玻璃 tint 底色（叠在原生材质之上，强化亚克力质感）
        // 修复亮色块: 降低 tintLight alpha 从 0.55 到 0.25，避免浅色模式面板过亮
        // 降低 tintDark alpha 从 0.42 到 0.35，避免深色模式面板过暗
        static let tintLight: NSColor = NSColor.white.withAlphaComponent(0.25)
        static let tintDark: NSColor = NSColor.black.withAlphaComponent(0.35)

        // 性能预算：NSGlassEffectView/NSVisualEffectView 实例数上限
        static let maxGlassInstances = 8

        // 圆角（按层级）
        static let cornerRadiusWindow: CGFloat = 12
        static let cornerRadiusPanel: CGFloat = 10
        static let cornerRadiusComponent: CGFloat = 8

        /// 按层级取默认圆角
        static func defaultCornerRadius(for level: Level) -> CGFloat {
            switch level {
            case .window:    return cornerRadiusWindow
            case .panel:     return cornerRadiusPanel
            case .component: return cornerRadiusComponent
            }
        }
    }

    // MARK: - 主题相关便捷访问

    /// 当前是否深色（供玻璃层判断令牌）
    static var isDark: Bool {
        // 使用 ThemeManager.resolvedIsDark 而非 NSApp.effectiveAppearance，
        // 因为 applyMode 设置 NSApp.appearance 后 effectiveAppearance 可能延迟更新，
        // 导致主题切换时 FFGlassView 刷新读取到旧的深浅色值。
        ThemeManager.shared.resolvedIsDark
    }

    /// 当前噪声 alpha
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

    /// 当前 tint
    static var glassTint: NSColor {
        isDark ? Glass.tintDark : Glass.tintLight
    }
}
