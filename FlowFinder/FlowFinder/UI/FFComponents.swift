import AppKit
import CoreText

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

/// 活动面板的强调色发光边缘——贴卡片外缘向外发散。
///
/// 2026-10-18 三次修订（用户验收：发光位置在操作区里面，要在操作区边缘）。
///
/// 布局契约：本视图铺满操作区卡片的**外层包裹视图**（wrapper），卡片本身相对包裹视图
/// 四周内缩 `edgeOutset`；因此「卡片边缘」在本视图坐标里就是一条内缩 `edgeOutset`
/// 的圆角路径。所有描边以这条路径为**中心线**绘制：
/// - 内半圈被卡片自身的不透明背景盖住（本视图在卡片下层，见 makeCardWrapper）
/// - 外半圈留在卡片外的 8pt 留白里，成为边缘发光
///
/// 由此得到的效果是「光从操作区边缘往外渗」，而不是此前那种整条画在操作区内部的描边。
/// 深色模式整体提高透明度，浅色模式略降；开启「增强对比度」时降级为 2pt 实线。
/// 视图不参与命中测试，鼠标事件全部穿透，否则会把列表/工具栏的点击吃掉。
/// 「面板 + 活动标签」合并轮廓的构造器。
///
/// 2026-10-20 #4：标签焊在面板顶边上之后，轮廓不再是矩形——
/// 面板顶边在标签处向上鼓出一个凸起，接缝处是 r2 的内凹圆角。
/// 发光（`FFActivePaneBorderView`）与标签条背板（`PaneTabStripBackdrop`）
/// **必须共用这一条路径**，否则两者对不上，接缝会露出错位的一圈。
enum FFTabSilhouette {

    /// 面板圆角（与 SquircleView 的 16pt 对应）
    static let panelCorner: CGFloat = 16

    /// 完整合并轮廓：面板四边 + 顶部凸起的标签。
    ///
    /// - Parameters:
    ///   - panel: 面板矩形（调用方坐标系，原点左下）
    ///   - tab: 标签矩形，要求 `tab.minY == panel.maxY`（底边与面板顶边共线）
    static func composite(panel: NSRect,
                          tab: NSRect?,
                          panelCorner: CGFloat = panelCorner,
                          tabCorner: CGFloat = FFInteractionPolicy.tabCornerRadius,
                          seam: CGFloat = FFInteractionPolicy.tabSeamFillet) -> NSBezierPath {
        // 没有标签、或标签太窄画不出内凹 → 退化成普通圆角矩形
        guard let tab,
              tab.width > seam * 2 + tabCorner * 2,
              abs(tab.minY - panel.maxY) < 0.5,
              tab.minX - seam > panel.minX + panelCorner,
              tab.maxX + seam < panel.maxX - panelCorner
        else {
            return NSBezierPath(roundedRect: panel, xRadius: panelCorner, yRadius: panelCorner)
        }

        let r = panelCorner
        let rc = tabCorner
        let path = NSBezierPath()

        // 面板顶边左段 → 左内凹
        path.move(to: NSPoint(x: panel.minX + r, y: panel.maxY))
        path.line(to: NSPoint(x: tab.minX - seam, y: panel.maxY))
        path.curve(to: NSPoint(x: tab.minX, y: panel.maxY + seam),
                   controlPoint1: NSPoint(x: tab.minX, y: panel.maxY),
                   controlPoint2: NSPoint(x: tab.minX, y: panel.maxY))

        // 标签左边 → 左上圆角 → 顶边 → 右上圆角 → 右边
        path.line(to: NSPoint(x: tab.minX, y: tab.maxY - rc))
        path.appendArc(withCenter: NSPoint(x: tab.minX + rc, y: tab.maxY - rc),
                       radius: rc, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: tab.maxX - rc, y: tab.maxY))
        path.appendArc(withCenter: NSPoint(x: tab.maxX - rc, y: tab.maxY - rc),
                       radius: rc, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: tab.maxX, y: panel.maxY + seam))

        // 右内凹 → 面板顶边右段 → 右上圆角
        path.curve(to: NSPoint(x: tab.maxX + seam, y: panel.maxY),
                   controlPoint1: NSPoint(x: tab.maxX, y: panel.maxY),
                   controlPoint2: NSPoint(x: tab.maxX, y: panel.maxY))
        path.line(to: NSPoint(x: panel.maxX - r, y: panel.maxY))
        path.appendArc(withCenter: NSPoint(x: panel.maxX - r, y: panel.maxY - r),
                       radius: r, startAngle: 90, endAngle: 0, clockwise: true)

        // 右边 → 右下圆角 → 底边 → 左下圆角 → 左边 → 左上圆角
        path.line(to: NSPoint(x: panel.maxX, y: panel.minY + r))
        path.appendArc(withCenter: NSPoint(x: panel.maxX - r, y: panel.minY + r),
                       radius: r, startAngle: 0, endAngle: -90, clockwise: true)
        path.line(to: NSPoint(x: panel.minX + r, y: panel.minY))
        path.appendArc(withCenter: NSPoint(x: panel.minX + r, y: panel.minY + r),
                       radius: r, startAngle: -90, endAngle: -180, clockwise: true)
        path.line(to: NSPoint(x: panel.minX, y: panel.maxY - r))
        path.appendArc(withCenter: NSPoint(x: panel.minX + r, y: panel.maxY - r),
                       radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        path.close()
        return path
    }

    /// 只有「标签 + 两处内凹」的封闭形状，以下沿 baseline 封口。
    ///
    /// 标签条背板用这个：背板只负责填标签那一块，面板本体由卡片自己画。
    static func tabFootprint(tab: NSRect,
                             baseline: CGFloat,
                             tabCorner: CGFloat = FFInteractionPolicy.tabCornerRadius,
                             seam: CGFloat = FFInteractionPolicy.tabSeamFillet) -> NSBezierPath {
        let rc = tabCorner
        let path = NSBezierPath()
        path.move(to: NSPoint(x: tab.minX - seam, y: baseline))
        path.curve(to: NSPoint(x: tab.minX, y: baseline + seam),
                   controlPoint1: NSPoint(x: tab.minX, y: baseline),
                   controlPoint2: NSPoint(x: tab.minX, y: baseline))
        path.line(to: NSPoint(x: tab.minX, y: tab.maxY - rc))
        path.appendArc(withCenter: NSPoint(x: tab.minX + rc, y: tab.maxY - rc),
                       radius: rc, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: tab.maxX - rc, y: tab.maxY))
        path.appendArc(withCenter: NSPoint(x: tab.maxX - rc, y: tab.maxY - rc),
                       radius: rc, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: tab.maxX, y: baseline + seam))
        path.curve(to: NSPoint(x: tab.maxX + seam, y: baseline),
                   controlPoint1: NSPoint(x: tab.maxX, y: baseline),
                   controlPoint2: NSPoint(x: tab.maxX, y: baseline))
        path.close()
        return path
    }
}

final class FFActivePaneBorderView: NSView {

    /// 卡片边缘相对本视图外框的缩进。
    /// 必须与 `MainWindowController.makeCardWrapper` 的留白一致（8pt）——
    /// 留白同时是发光向外的可用空间：最外层描边宽 13pt，外扩 6.5pt < 8pt 不会被裁。
    static let edgeOutset: CGFloat = 8

    /// 卡片圆角（与 SquircleView 的 16pt 对应，发光路径沿用同半径）
    static let cornerRadius: CGFloat = 16

    /// 活动标签的矩形（本视图坐标系，原点左下）。nil = 不画凸起。
    ///
    /// 2026-10-20 #4：标签焊在面板顶边上之后，发光必须沿「面板 + 标签」的
    /// 合并轮廓走，否则光只绕在面板矩形上，与凸出的标签错开一截。
    var tabRect: NSRect? {
        didSet {
            guard tabRect != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 活动面板强调色（保留 API；实际发光由 FFPaneGlow 的阴影实现）。
    var ringColor: NSColor = FFAccent.current

    /// 活动面板边缘高度（D-06：2px 细边，不再画 14 层发光）。
    var edgeHeight: CGFloat { FFVisualTokens.activePaneEdge }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 颜色由 FFPaneGlow 的阴影绘制，本视图不再画描边。
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    /// 点击穿透：只做视觉提示，不参与事件分发
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 顶部不画强调线：活动面板只由左/右/下三边微光提示，标签区保持干净。
    }
}

/// 活动面板的柔和边缘光：原生 layer 阴影，不画描边。
/// 阴影向下偏移，让底部/左右更明显、顶部尽量弱；颜色统一取应用强调色。
enum FFPaneGlow {
    static func apply(to view: NSView, active: Bool, color: NSColor = FFAccent.current) {
        guard let layer = view.layer else { return }
        let spec = FFGlowSpec.standard
        layer.masksToBounds = false
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = active ? Float(spec.opacity * 0.62) : 0
        layer.shadowRadius = spec.blurRadius + 4
        // 负 y = 向下偏移，顶部光更少；底部/左右形成柔和光晕。
        layer.shadowOffset = CGSize(width: 0, height: -5)
        updateShadowPath(for: view)
    }

    static func updateShadowPath(for view: NSView) {
        guard let layer = view.layer, layer.shadowOpacity > 0 else { return }
        layer.shadowPath = CGPath(roundedRect: view.bounds.insetBy(dx: 8, dy: 8),
                                  cornerWidth: FFVisualTokens.Radius.panel,
                                  cornerHeight: FFVisualTokens.Radius.panel,
                                  transform: nil)
    }
}

// MARK: - 品牌渐变（侧栏应用名）

/// 侧栏品牌名渐变用的「蓝 → 紫」两端色，取自应用图标（2026-10-18 #7）。
///
/// 取色策略：把图标缩绘成 64×64 位图，逐像素转 HSB，只保留蓝紫区间
/// （色相 0.52–0.82、饱和度 > 0.30、非透明）。按色相中位数把样本切成「蓝」「紫」
/// 两簇，各取饱和度加权平均色；再按明暗模式调亮度，保证 17pt 粗体在侧栏背景上可读。
/// 取色失败（图标缺失/无蓝紫像素）时回退到内置蓝紫色对，功能不受影响。
enum FFBrandGradient {

    /// 浅色模式回退色对（蓝 → 紫）
    private static let lightFallback: [NSColor] = [
        NSColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.28, blue: 0.92, alpha: 1),
    ]
    /// 深色模式回退色对（提亮，深底可读）
    private static let darkFallback: [NSColor] = [
        NSColor(srgbRed: 0.38, green: 0.63, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.75, green: 0.55, blue: 1.00, alpha: 1),
    ]

    /// 缓存：按明暗模式各算一次（图标不会在运行期变）
    private static var cache: [String: [NSColor]] = [:]

    /// 图标取色的单个像素样本
    private struct IconSample {
        let hue: CGFloat
        let saturation: CGFloat
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
    }

    /// 取「蓝 → 紫」两端色
    static func colors(isDark: Bool) -> [NSColor] {
        let key = isDark ? "dark" : "light"
        if let cached = cache[key] { return cached }
        let sampled = sampleFromIcon(isDark: isDark)
        cache[key] = sampled
        return sampled
    }

    private static func sampleFromIcon(isDark: Bool) -> [NSColor] {
        let fallback = isDark ? darkFallback : lightFallback
        guard let icon = NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return fallback }

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        var samples: [IconSample] = []
        for y in 0..<64 {
            for x in 0..<64 {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.alphaComponent > 0.6 else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
                guard s > 0.30, br > 0.18, h >= 0.52, h <= 0.82 else { continue }
                samples.append(IconSample(hue: h, saturation: s,
                                          r: color.redComponent, g: color.greenComponent, b: color.blueComponent))
            }
        }
        guard samples.count >= 24 else { return fallback }

        let hues = samples.map(\.hue).sorted()
        let split = hues[hues.count / 2]
        let blues = samples.filter { $0.hue < split }
        let purples = samples.filter { $0.hue >= split }
        guard let blue = weightedAverage(blues), let purple = weightedAverage(purples) else { return fallback }

        // 明暗模式调亮度：浅色底要压暗，深色底要提亮；饱和度统一拉高，避免塑料感
        let brightness: CGFloat = isDark ? 0.97 : 0.68
        let saturation: CGFloat = isDark ? 0.72 : 0.90
        var hb: CGFloat = 0, sb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
        blue.getHue(&hb, saturation: &sb, brightness: &bb, alpha: &ab)
        var hp: CGFloat = 0, sp: CGFloat = 0, bp: CGFloat = 0, ap: CGFloat = 0
        purple.getHue(&hp, saturation: &sp, brightness: &bp, alpha: &ap)
        return [
            NSColor(calibratedHue: hb, saturation: saturation, brightness: brightness, alpha: 1),
            NSColor(calibratedHue: hp, saturation: saturation, brightness: brightness, alpha: 1),
        ]
    }

    private static func weightedAverage(_ samples: [IconSample]) -> NSColor? {
        guard !samples.isEmpty else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, w: CGFloat = 0
        for s in samples {
            let weight = 0.2 + s.saturation
            r += s.r * weight; g += s.g * weight; b += s.b * weight; w += weight
        }
        guard w > 0 else { return nil }
        return NSColor(srgbRed: r / w, green: g / w, blue: b / w, alpha: 1)
    }
}

/// 渐变文字视图（侧栏应用名）。
///
/// 逐字形取 CTFont 轮廓拼成路径 → 以路径为裁剪区 → 在路径包围盒内做水平渐变。
/// 相比「先把文字画成图片再当蒙版」，路径裁剪不受位图色域/alpha 影响，2x 屏上边缘干净。
/// 外观切换（日/夜）时重新取色并重绘。
final class FFGradientLabelView: NSView {

    private var text: String
    private var font: NSFont
    private var colors: [NSColor]

    init(text: String, font: NSFont) {
        self.text = text
        self.font = font
        self.colors = FFBrandGradient.colors(isDark: false)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyAppearance(isDark: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        let size = attributed().size()
        return NSSize(width: ceil(size.width) + 1, height: ceil(size.height))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        applyAppearance(isDark: isDark)
    }

    private func applyAppearance(isDark: Bool) {
        colors = FFBrandGradient.colors(isDark: isDark)
        needsDisplay = true
    }

    private func attributed() -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .kern: -0.3,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let attr = attributed()
        var line = CTLineCreateWithAttributedString(attr)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        var width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        // 侧栏被拖窄时名称会挤到设置/工具按钮下面。这里按可用宽度做尾部省略，
        // 而不是让字顺着 frame 溢出（渐变文字是自绘的，不会自动截断）。
        if width > bounds.width, bounds.width > 0 {
            let ellipsis = NSAttributedString(string: "…", attributes: [.font: font])
            let ellipsisLine = CTLineCreateWithAttributedString(ellipsis)
            if let truncated = CTLineCreateTruncatedLine(line, Double(bounds.width), .end, ellipsisLine) {
                line = truncated
                width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            }
        }
        let baselineY = (bounds.height - (ascent + descent)) / 2 + descent

        let path = CGMutablePath()
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let attrs = CTRunGetAttributes(run) as NSDictionary
                // CTRun 一定带字体属性（上面的 attributed 已设 .font），CF 桥接用强制转换
                guard let fontRef = attrs[kCTFontAttributeName] else { continue }
                let runFont = fontRef as! CTFont
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for i in 0..<count {
                    guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                    let transform = CGAffineTransform(translationX: positions[i].x, y: positions[i].y + baselineY)
                    path.addPath(glyphPath, transform: transform)
                }
            }
        }

        // 字形路径为空（极端字体缺失）时退回单色，至少不会空白
        guard !path.isEmpty, let gradient = NSGradient(colors: colors) else {
            attr.draw(at: NSPoint(x: 0, y: baselineY - ascent))
            return
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        gradient.draw(from: NSPoint(x: 0, y: bounds.midY),
                      to: NSPoint(x: max(width, 1), y: bounds.midY),
                      options: [])
        ctx.restoreGState()
    }
}
