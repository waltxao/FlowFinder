import Cocoa

/// 超椭圆（Squircle）圆角工具类
/// 使用 n 次方曲线公式 |x/a|^n + |y/b|^n = 1 生成平滑路径，
/// 通过 CAShapeLayer mask 实现超椭圆圆角，替代标准 cornerRadius
public class SquircleView: NSView {

    /// 超椭圆指数（n 越大越接近矩形，n=2 为标准椭圆，n≈4-5 为 iOS 风格超椭圆）
    private let squircleFactor: CGFloat

    /// 圆角半径
    private let cornerRadius: CGFloat

    /// mask layer 缓存
    private var maskLayer: CAShapeLayer?

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

    /// 应用超椭圆 mask（复用 maskLayer，仅更新 path，避免高频 layout 时反复创建销毁 layer）
    public func applySquircleMask() {
        let bounds = self.bounds
        if bounds.isEmpty { return }

        let path = Self.squirclePath(in: bounds, radius: cornerRadius, factor: squircleFactor)

        if maskLayer == nil {
            // 首次调用：创建 mask layer
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path
            shapeLayer.fillRule = .evenOdd
            maskLayer = shapeLayer
            layer?.mask = shapeLayer
        } else {
            // 后续调用：仅更新 path（避免 layer 创建/销毁开销）
            maskLayer?.path = path
        }
    }

    /// 移除超椭圆 mask
    public func removeSquircleMask() {
        maskLayer?.removeFromSuperlayer()
        maskLayer = nil
        layer?.mask = nil
    }

    /// 生成超椭圆 CGPath
    /// - Parameters:
    ///   - rect: 绘制区域
    ///   - radius: 圆角半径
    ///   - factor: 超椭圆指数
    /// - Returns: 超椭圆路径
    public static func squirclePath(in rect: CGRect, radius: CGFloat, factor: CGFloat = 5.0) -> CGPath {
        // 确保半径不超过宽高的一半
        let maxRadius = min(rect.width, rect.height) / 2.0
        let r = min(radius, maxRadius)

        // 如果半径为 0，直接返回矩形路径
        if r <= 0 {
            return CGPath(rect: rect, transform: nil)
        }

        let path = CGMutablePath()

        // 超椭圆中心点
        let cx = rect.midX
        let cy = rect.midY
        // 超椭圆半轴
        let a = rect.width / 2.0 - r
        let b = rect.height / 2.0 - r

        // 生成超椭圆路径点
        // 使用参数方程：x = a * sign(cos(t)) * |cos(t)|^(2/n), y = b * sign(sin(t)) * |sin(t)|^(2/n)
        // 加上圆角部分的偏移
        let segments = 120
        var points: [CGPoint] = []
        points.reserveCapacity(segments + 1)

        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments) * 2.0 * .pi
            let cosT = cos(t)
            let sinT = sin(t)

            // 超椭圆公式
            let x = a * Self.sign(cosT) * pow(abs(cosT), 2.0 / factor) + cx
            let y = b * Self.sign(sinT) * pow(abs(sinT), 2.0 / factor) + cy

            points.append(CGPoint(x: x, y: y))
        }

        path.addLines(between: points)
        path.closeSubpath()

        return path
    }

    private static func sign(_ value: CGFloat) -> CGFloat {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }
}

/// 为任意 NSView 应用超椭圆圆角
public extension NSView {
    /// 应用超椭圆 mask
    /// - Parameters:
    ///   - cornerRadius: 圆角半径
    ///   - factor: 超椭圆指数（默认 5.0）
    func applySquircleCorners(cornerRadius: CGFloat, factor: CGFloat = 5.0) {
        guard let layer = self.layer else {
            self.wantsLayer = true
            DispatchQueue.main.async { [weak self] in
                self?.applySquircleCorners(cornerRadius: cornerRadius, factor: factor)
            }
            return
        }

        let bounds = self.bounds
        if bounds.isEmpty {
            // 延迟到 layout 后再应用
            DispatchQueue.main.async { [weak self] in
                self?.applySquircleCorners(cornerRadius: cornerRadius, factor: factor)
            }
            return
        }

        let path = SquircleView.squirclePath(in: bounds, radius: cornerRadius, factor: factor)
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path
        layer.mask = shapeLayer
    }
}
