import AppKit
import CoreImage
import QuartzCore
import os.log

/// 玻璃材质视图：封装 NSGlassEffectView/NSVisualEffectView + 噪声 + 高光 + 内阴影
///
/// 替换现有 `GlassSectionMaskView`，作为所有面板/对话框/子组件玻璃背景的统一入口。
/// 三层全玻璃架构：
/// - `.window`：透传，FFGlassView 不接管（窗口级玻璃由 MainWindowController 等窗口控制器持有）
/// - `.panel`：NSGlassEffectView/NSVisualEffectView + tint + 噪声 + 顶部高光 + 内阴影
/// - `.component`：纯 CALayer（tint + 圆角 + 高光 + 内阴影），不创建 NSGlassEffectView
class FFGlassView: NSView {

    // MARK: - 玻璃样式（macOS 26+ NSGlassEffectView.Style 的平台无关映射）

    /// 玻璃样式枚举：对应 NSGlassEffectView.Style（macOS 26+）
    /// 使用自定义枚举避免在类型注解中直接引用 macOS 26+ API
    enum GlassStyle {
        case clear
    }

    // MARK: - 配置

    let level: FFDesign.Glass.Level
    /// 仅 macOS<26 回退路径使用（.panel 级）
    let material: NSVisualEffectView.Material?
    /// 仅 macOS 26+ 使用（.panel 级），通过 GlassStyle 映射到 NSGlassEffectView.Style
    let glassStyle: GlassStyle
    let cornerRadius: CGFloat

    // MARK: - 子层引用

    /// tint 背景层（.panel/.component 都有）
    private var tintLayer: CALayer?
    /// 噪声平铺层
    private var noiseLayer: CALayer?
    /// 顶部高光线
    private var highlightLayer: CAShapeLayer?
    /// 内阴影层（底部）
    private var innerShadowLayer: CALayer?
    /// 原生玻璃视图（.panel 级，macOS 26+ 用 NSGlassEffectView，旧版用 NSVisualEffectView）
    private var nativeGlassView: NSView?

    // MARK: - 全局实例跟踪

    /// 所有存活的 FFGlassView 实例（弱引用，用于主题刷新）
    /// 跟踪 `.panel` 和 `.component` 级（两者均需在主题切换时刷新 tint/noise/highlight）。
    /// `.window` 级由窗口控制器独立持有，不在此计数。
    private static let allInstances = NSHashTable<FFGlassView>.weakObjects()

    /// 当前 `.panel` 级实例数（用于性能预算检查）
    static var panelInstanceCount: Int {
        return allInstances.allObjects.filter { $0.level == .panel }.count
    }

    // MARK: - 初始化

    /// 创建玻璃视图
    /// - Parameters:
    ///   - level: 玻璃层级
    ///   - cornerRadius: 圆角（nil 时按 level 取默认值）
    ///   - material: 仅 macOS<26 回退路径使用（.panel 级），如 .sidebar/.headerView/.sheet
    ///   - glassStyle: 仅 macOS 26+ 使用（.panel 级），默认 .clear
    init(level: FFDesign.Glass.Level,
         cornerRadius: CGFloat? = nil,
         material: NSVisualEffectView.Material? = nil,
         glassStyle: GlassStyle = .clear) {
        self.level = level
        self.material = material
        self.glassStyle = glassStyle
        self.cornerRadius = cornerRadius ?? FFDesign.Glass.defaultCornerRadius(for: level)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if level != .window {
            FFGlassView.allInstances.remove(self)
        }
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor

        switch level {
        case .window:
            // 窗口级玻璃由窗口控制器持有独立的 NSGlassEffectView，FFGlassView 不接管。
            // 这里仅作为透明容器（保持 API 一致性）。
            layer?.backgroundColor = NSColor.clear.cgColor
        case .panel:
            setupPanelGlass()
            FFGlassView.allInstances.add(self)
            #if DEBUG
            if FFGlassView.panelInstanceCount > FFDesign.Glass.maxGlassInstances {
                FFLog.warning("FFGlassView: panel 实例数 \(FFGlassView.panelInstanceCount) 超过预算 \(FFDesign.Glass.maxGlassInstances)", log: FFLog.glass)
            }
            #endif
        case .component:
            // 纯 CALayer，无原生玻璃
            setupComponentGlass()
            FFGlassView.allInstances.add(self)
        }
    }

    /// `.panel` 级：原生玻璃 + tint + 噪声 + 高光 + 内阴影
    ///
    /// 实现说明：曾尝试 macOS 26+ 用 NSGlassEffectView(style: .clear) 替代 NSVisualEffectView，
    /// 但 .clear style 在液态玻璃中几乎完全透明（仅有微弱模糊），导致侧边栏/工具栏/详情栏等
    /// panel 级组件肉眼看是"透明"的，无法辨识边界（与 MainWindowController 窗口级 .clear
    /// 透明问题同源）。因此 panel 级统一走 NSVisualEffectView 路径，由调用方通过 material
    /// 参数指定材质（.sidebar/.headerView/.sheet 等），在所有 macOS 版本上稳定可见。
    /// 液态玻璃增强（噪声/高光/内阴影/tint）仍由下方 CALayer 叠加层提供，保留设计语言。
    private func setupPanelGlass() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = material ?? .headerView
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        // 修复主题反转: NSVisualEffectView 必须显式设置 appearance 以跟随 NSApp.appearance，
        // 否则 state = .active 时它会跟随系统外观而非应用强制外观，导致浅色/深色模式反转。
        visualEffect.appearance = NSApp.appearance
        // NSVisualEffectView 无 cornerRadius 属性，圆角由外层 layer.cornerRadius 控制
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 0
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffect)
        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        nativeGlassView = visualEffect

        // 2. CALayer 叠加层（顺序：tint → 噪声 → 高光 → 内阴影）
        let tint = CALayer()
        tint.backgroundColor = FFDesign.glassTint.cgColor
        layer?.addSublayer(tint)
        tintLayer = tint

        let noise = FFGlassNoise.noiseLayer()
        noise.opacity = Float(FFDesign.noiseAlpha)
        layer?.addSublayer(noise)
        noiseLayer = noise

        let highlight = makeHighlightLayer()
        layer?.addSublayer(highlight)
        highlightLayer = highlight

        let inner = makeInnerShadowLayer()
        layer?.addSublayer(inner)
        innerShadowLayer = inner
    }

    /// `.component` 级：纯 CALayer
    private func setupComponentGlass() {
        // tint 背景
        let tint = CALayer()
        tint.backgroundColor = FFDesign.glassTint.cgColor
        layer?.addSublayer(tint)
        tintLayer = tint

        // 噪声（component 级可选，默认开启）
        let noise = FFGlassNoise.noiseLayer()
        noise.opacity = Float(FFDesign.noiseAlpha)
        layer?.addSublayer(noise)
        noiseLayer = noise

        // 顶部高光
        let highlight = makeHighlightLayer()
        layer?.addSublayer(highlight)
        highlightLayer = highlight

        // 内阴影
        let inner = makeInnerShadowLayer()
        layer?.addSublayer(inner)
        innerShadowLayer = inner
    }

    // MARK: - 子层构造

    /// 顶部 0.5pt 高光线（沿圆角矩形顶边）
    private func makeHighlightLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = FFDesign.Glass.highlightInset
        layer.opacity = Float(FFDesign.highlightAlpha)
        return layer
    }

    /// 内阴影层（底部深度感）
    /// 用一个被反向 mask 的 CALayer 实现：内圈透明，外圈投射阴影向内
    private func makeInnerShadowLayer() -> CALayer {
        let shadowLayer = CALayer()
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = Float(FFDesign.innerShadowAlpha)
        shadowLayer.shadowOffset = FFDesign.Glass.innerShadowOffset
        shadowLayer.shadowRadius = FFDesign.Glass.innerShadowRadius
        return shadowLayer
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateSublayerFrames()
    }

    /// 根据 bounds 更新所有 CALayer 子层的 frame 与路径
    private func updateSublayerFrames() {
        let bounds = self.bounds
        guard !bounds.isEmpty else { return }

        // tint / 噪声：填满
        tintLayer?.frame = bounds
        noiseLayer?.frame = bounds

        // 高光：沿圆角矩形顶部弧线
        if let highlight = highlightLayer {
            let path = highlightPath(in: bounds)
            highlight.path = path
        }

        // 内阴影：用 shadowPath 限定为外圈（让阴影向内投射）
        if let inner = innerShadowLayer {
            inner.frame = bounds
            // 外圈路径（含阴影扩散区域）减去内圈路径
            let inset = -FFDesign.Glass.innerShadowRadius * 2
            let outerRect = bounds.insetBy(dx: inset, dy: inset)
            let outerPath = CGPath(roundedRect: outerRect,
                                   cornerWidth: cornerRadius + FFDesign.Glass.innerShadowRadius * 2,
                                   cornerHeight: cornerRadius + FFDesign.Glass.innerShadowRadius * 2,
                                   transform: nil)
            let innerPath = CGPath(roundedRect: bounds,
                                   cornerWidth: cornerRadius,
                                   cornerHeight: cornerRadius,
                                   transform: nil)
            // 用 even-odd 规则让外圈减去内圈
            let combined = CGMutablePath()
            combined.addPath(outerPath)
            combined.addPath(innerPath)
            inner.shadowPath = combined
            // 让阴影只在内侧显示：mask 为内圈路径（外圈透明）
            let maskLayer = CAShapeLayer()
            maskLayer.path = innerPath
            maskLayer.fillRule = .evenOdd
            // 反转 mask：用外圈减内圈作为可见区
            let invertPath = CGMutablePath()
            invertPath.addRect(bounds)
            invertPath.addPath(innerPath)
            let invertMask = CAShapeLayer()
            invertMask.path = invertPath
            invertMask.fillRule = .evenOdd
            inner.mask = invertMask
        }
    }

    /// 顶部高光路径：沿圆角矩形顶部弧线
    private func highlightPath(in bounds: CGRect) -> CGPath {
        let r = cornerRadius
        let path = CGMutablePath()
        // 从左上角圆弧起点 → 顶部 → 右上角圆弧终点
        path.move(to: CGPoint(x: bounds.minX + r, y: bounds.maxY - FFDesign.Glass.highlightInset / 2))
        path.addLine(to: CGPoint(x: bounds.maxX - r, y: bounds.maxY - FFDesign.Glass.highlightInset / 2))
        // 左上角弧
        path.addArc(center: CGPoint(x: bounds.minX + r, y: bounds.maxY - r),
                    radius: r - FFDesign.Glass.highlightInset / 2,
                    startAngle: .pi / 2,
                    endAngle: .pi,
                    clockwise: false)
        // 右上角弧
        path.addArc(center: CGPoint(x: bounds.maxX - r, y: bounds.maxY - r),
                    radius: r - FFDesign.Glass.highlightInset / 2,
                    startAngle: 0,
                    endAngle: .pi / 2,
                    clockwise: false)
        return path
    }

    // MARK: - 主题刷新

    /// 主题变更时刷新噪声/高光/内阴影令牌
    /// 由 `ThemeManager.onModeChanged` 统一调用
    func refreshAppearance() {
        // 修复主题反转: 更新 NSVisualEffectView 的 appearance 以跟随 NSApp.appearance
        if let glassView = nativeGlassView as? NSVisualEffectView {
            glassView.appearance = NSApp.appearance
        }
        // tint
        tintLayer?.backgroundColor = FFDesign.glassTint.cgColor
        // 噪声 alpha
        noiseLayer?.opacity = Float(FFDesign.noiseAlpha)
        // 高光 alpha
        highlightLayer?.opacity = Float(FFDesign.highlightAlpha)
        // 内阴影 alpha
        innerShadowLayer?.shadowOpacity = Float(FFDesign.innerShadowAlpha)
        // 强制重新布局以更新路径（dark/light 下圆角不变，但保险起见）
        needsLayout = true
    }

    /// 全局刷新所有 FFGlassView 实例（主题切换时调用）
    static func refreshAllInstances() {
        for instance in allInstances.allObjects {
            instance.refreshAppearance()
        }
    }

    // MARK: - 调试

    #if DEBUG
    /// 打印当前所有 panel 级实例的调试信息
    static func debugPrintInstances() {
        let instances = allInstances.allObjects
        let panelCount = instances.filter { $0.level == .panel }.count
        let componentCount = instances.filter { $0.level == .component }.count
        FFLog.debug("FFGlassView 实例: panel=\(panelCount) / 预算 \(FFDesign.Glass.maxGlassInstances), component=\(componentCount)", log: FFLog.glass)
    }
    #endif
}

// MARK: - 全局共享噪声纹理

/// 全局共享噪声纹理（CIFilter 程序化生成，避免每实例重复生成）
enum FFGlassNoise {
    /// 缓存的 256x256 灰度噪声 CGImage
    private static var cachedImage: CGImage?
    private static let cacheQueue = DispatchQueue(label: "FFGlassNoise.cache")

    /// 获取共享噪声 CGImage（线程安全）
    static func sharedImage() -> CGImage {
        if let cached = cachedImage { return cached }
        return cacheQueue.sync {
            if let cached = cachedImage { return cached }
            let image = generateNoiseImage()
            cachedImage = image
            return image
        }
    }

    /// 创建平铺噪声 CALayer（contents=sharedImage, backgroundColor=clear）
    static func noiseLayer() -> CALayer {
        let layer = CALayer()
        layer.contents = sharedImage()
        // CALayer 的 contentsGravity 不支持 repeat 平铺。
        // 通过 contentsRect 实现 N x N 平铺（此处 4x4，覆盖大区域不失真）
        layer.contentsGravity = .resizeAspectFill
        layer.contentsRect = CGRect(x: 0, y: 0, width: 4, height: 4)  // 4x4 平铺
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }

    /// 程序化生成 256x256 灰度噪声 CGImage
    private static func generateNoiseImage() -> CGImage {
        let size = Int(FFDesign.Glass.noiseTileSize)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)

        // CIRandomGenerator 输出彩色噪声，转灰度
        guard let randomFilter = CIFilter(name: "CIRandomGenerator"),
              let monochromeFilter = CIFilter(name: "CIColorMonochrome") else {
            // 回退：返回纯白 CGImage
            return fallbackWhiteImage(size: size)
        }

        guard let randomOutput = randomFilter.outputImage?.cropped(to: rect) else {
            return fallbackWhiteImage(size: size)
        }
        monochromeFilter.setValue(randomOutput, forKey: kCIInputImageKey)
        monochromeFilter.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor")
        monochromeFilter.setValue(1.0, forKey: "inputIntensity")

        let context = CIContext(options: nil)
        guard let monochromeOutput = monochromeFilter.outputImage,
              let cgImage = context.createCGImage(monochromeOutput, from: rect) else {
            return fallbackWhiteImage(size: size)
        }
        return cgImage
    }

    /// 回退方案：纯白 CGImage（噪声生成失败时）
    private static func fallbackWhiteImage(size: Int) -> CGImage {
        guard let context = CGContext(data: nil,
                                width: size,
                                height: size,
                                bitsPerComponent: 8,
                                bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            // 极端情况：连 CGContext 都创建失败，尝试 1x1 尺寸
            return fallbackWhiteImage1x1()
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if let img = context.makeImage() {
            return img
        }
        return fallbackWhiteImage1x1()
    }

    /// 1x1 纯白图片的终极回退方案
    private static func fallbackWhiteImage1x1() -> CGImage {
        let ctx = CGContext(data: nil, width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.setFillColor(NSColor.white.cgColor)
        ctx?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        if let img = ctx?.makeImage() {
            return img
        }
        // 理论上不可能到达这里，但编译器需要保证返回值
        return NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
