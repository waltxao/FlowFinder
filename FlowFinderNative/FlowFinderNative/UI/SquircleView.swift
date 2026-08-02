import Cocoa

/// 超椭圆（Squircle）圆角工具类
/// 使用 n 次方曲线公式 |x/a|^n + |y/b|^n = 1 生成平滑路径，
/// 通过 CAShapeLayer mask 实现超椭圆圆角，替代标准 cornerRadius
public class SquircleView: NSView {

    /// 超椭圆指数（n 越大越接近矩形，n=2 为标准椭圆，n≈4-5 为 iOS 风格超椭圆）
    private let squircleFactor: CGFloat

    /// 圆角半径
    private let cornerRadius: CGFloat

    /// 是否在 layout 时自动更新 mask
    private var autoUpdateMask: Bool

    /// 初始化超椭圆视图
    /// - Parameters:
    ///   - cornerRadius: 圆角半径
    ///   - squircleFactor: 超椭圆指数（默认 5.0，iOS 风格）
    ///   - autoUpdateMask: 是否在 layout 时自动更新 mask
    public init(cornerRadius: CGFloat, squircleFactor: CGFloat = 5.0, autoUpdateMask: Bool = true) {
        self.cornerRadius = cornerRadius
        self.squircleFactor = squircleFactor
        self.autoUpdateMask = autoUpdateMask
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        if autoUpdateMask {
            applySquircleMask()
        }
    }

    /// 应用圆角（使用标准 cornerRadius，不使用 mask，避免裁剪子视图内容）
    public func applySquircleMask() {
        let bounds = self.bounds
        if bounds.isEmpty { return }

        // 使用标准 cornerRadius 圆角背景
        // 不使用 mask：mask 会裁剪所有子视图内容，导致大量内容被遮挡
        layer?.cornerRadius = cornerRadius
    }

    /// 生成超椭圆圆角路径
    ///
    /// 正确实现：直边沿 rect 边界延伸，仅在四个角用超椭圆曲线段连接。
    /// 之前的实现用 `a = width/2 - r` 创建完整超椭圆，导致整个形状从四边
    /// 向内收缩 r 像素，大量裁剪内容。此版本修复该缺陷。
    ///
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - radius: 圆角半径
    ///   - factor: 超椭圆指数（默认 5.0，iOS 风格）
    /// - Returns: 超椭圆路径
    public static func squirclePath(in rect: CGRect, radius: CGFloat, factor: CGFloat = 5.0) -> CGPath {
        let w = rect.width
        let h = rect.height
        // 确保半径不超过宽高的一半
        let r = min(radius, w / 2.0, h / 2.0)

        // 如果半径为 0，直接返回矩形路径
        if r <= 0 {
            return CGPath(rect: rect, transform: nil)
        }

        let path = CGMutablePath()
        let origin = rect.origin
        let segments = 30  // 每个角的采样点数

        // 辅助：生成一个角的超椭圆曲线段
        // 圆角中心 (cx, cy)，半径 r，从角度 startAngle 到 endAngle
        // 超椭圆参数方程：x = cx + r * sign(cos(t)) * |cos(t)|^(2/factor)
        //                 y = cy + r * sign(sin(t)) * |sin(t)|^(2/factor)
        func cornerPoints(cx: CGFloat, cy: CGFloat, r: CGFloat,
                          startAngle: CGFloat, endAngle: CGFloat) -> [CGPoint] {
            var pts: [CGPoint] = []
            for i in 0...segments {
                let t = startAngle + (endAngle - startAngle) * CGFloat(i) / CGFloat(segments)
                let cosT = cos(t)
                let sinT = sin(t)
                let x = cx + r * Self.sign(cosT) * pow(abs(cosT), 2.0 / factor)
                let y = cy + r * Self.sign(sinT) * pow(abs(sinT), 2.0 / factor)
                pts.append(CGPoint(x: x, y: y))
            }
            return pts
        }

        // 四个角的圆角中心：
        // 左上 (r, 0+r)，右上 (w-r, r)，右下 (w-r, h-r)，左下 (r, h-r)
        // 角度（标准数学坐标系，y轴向上；但 CGPath y轴向下，需要翻转）

        // 左上角：从 (0, r) 到 (r, 0)
        // 在 CGPath 坐标系中，角中心 (r, r)，角度从 π 到 3π/2
        let tlPoints = cornerPoints(cx: origin.x + r, cy: origin.y + r, r: r,
                                     startAngle: .pi, endAngle: 3.0 * .pi / 2.0)

        // 右上角：从 (w, r) 到 (w-r, 0)
        // 角中心 (w-r, r)，角度从 3π/2 到 2π
        let trPoints = cornerPoints(cx: origin.x + w - r, cy: origin.y + r, r: r,
                                     startAngle: 3.0 * .pi / 2.0, endAngle: 2.0 * .pi)

        // 右下角：从 (w-r, h) 到 (w, h-r)
        // 角中心 (w-r, h-r)，角度从 0 到 π/2
        let brPoints = cornerPoints(cx: origin.x + w - r, cy: origin.y + h - r, r: r,
                                     startAngle: 0, endAngle: .pi / 2.0)

        // 左下角：从 (0, h-r) 到 (r, h)
        // 角中心 (r, h-r)，角度从 π/2 到 π
        let blPoints = cornerPoints(cx: origin.x + r, cy: origin.y + h - r, r: r,
                                     startAngle: .pi / 2.0, endAngle: .pi)

        // 构建路径：从左上角第一个点开始，顺时针
        // 左上角曲线
        path.addLines(between: tlPoints)
        // 顶边直线（从左上角终点到右上角起点）
        path.addLine(to: trPoints[0])
        // 右上角曲线
        path.addLines(between: trPoints)
        // 右边直线
        path.addLine(to: brPoints[0])
        // 右下角曲线
        path.addLines(between: brPoints)
        // 底边直线
        path.addLine(to: blPoints[0])
        // 左下角曲线
        path.addLines(between: blPoints)
        // 闭合（回到左上角起点）
        path.closeSubpath()

        return path
    }

    private static func sign(_ value: CGFloat) -> CGFloat {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }
}

// MARK: - SquircleMaskedView

/// 可动态更新超椭圆 mask 的 NSView 子类
/// 适用于需要超椭圆圆角但尺寸可能变化的视图（如标签药丸、容器、按钮等）
/// 替代标准 `layer?.cornerRadius`，在 layout 时自动更新 mask path
public class SquircleMaskedView: NSView {

    /// 超椭圆圆角半径（设为高度的一半即为胶囊形）
    /// 设为 0 时自动移除 mask，恢复完整矩形（无圆角裁剪），便于动态切换圆角/无圆角
    public var squircleRadius: CGFloat = 0 {
        didSet {
            if squircleRadius <= 0 {
                // 半径为 0：移除 mask 并清空缓存，使子视图不再被裁剪
                layer?.mask = nil
                maskLayer = nil
            }
            needsLayout = true
        }
    }

    /// 超椭圆指数（n 越大越接近矩形，n=2 为标准椭圆，n≈5 为 iOS 风格）
    public var squircleFactor: CGFloat = 5.0

    /// mask layer 缓存（复用，避免高频 layout 时反复创建销毁）
    private var maskLayer: CAShapeLayer?

    public override func layout() {
        super.layout()
        guard squircleRadius > 0, !bounds.isEmpty else { return }

        let path = SquircleView.squirclePath(in: bounds, radius: squircleRadius, factor: squircleFactor)

        if maskLayer == nil {
            wantsLayer = true
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path
            maskLayer = shapeLayer
            layer?.mask = shapeLayer
        } else {
            maskLayer?.path = path
        }
    }
}

// MARK: - NSView Extension

extension NSView {
    /// 应用超椭圆圆角（适用于 NSTextField/NSButton 等无法替换为 SquircleMaskedView 的控件）
    /// 在下一个布局周期应用 mask，确保 bounds 已确定。对于固定尺寸的标签药丸等小组件足够使用。
    /// - Parameters:
    ///   - radius: 圆角半径
    ///   - factor: 超椭圆指数（默认 5.0，iOS 风格）
    func applySquircleCornerRadius(_ radius: CGFloat, factor: CGFloat = 5.0) {
        guard radius > 0 else { return }
        wantsLayer = true
        // 移除标准 cornerRadius，改用超椭圆 mask
        layer?.cornerRadius = 0
        // 在下一个布局周期应用 mask（确保 bounds 已确定）
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.bounds.isEmpty else { return }
            let path = SquircleView.squirclePath(in: self.bounds, radius: radius, factor: factor)
            if let existing = self.layer?.mask as? CAShapeLayer {
                existing.path = path
            } else {
                let mask = CAShapeLayer()
                mask.path = path
                self.layer?.mask = mask
            }
        }
    }
}
