import CoreGraphics

struct FFGlowSpec: Equatable {
    let blurRadius: CGFloat
    let opacity: CGFloat
    let fadeStart: CGFloat

    static let standard = FFGlowSpec(blurRadius: 9, opacity: 0.50, fadeStart: 0.42)

    /// y=0 底部，y=1 顶部。
    func alpha(atNormalizedY y: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, y))
        guard clamped > fadeStart else { return opacity }
        let t = (clamped - fadeStart) / (1 - fadeStart)
        return opacity * (1 - t)
    }
}
