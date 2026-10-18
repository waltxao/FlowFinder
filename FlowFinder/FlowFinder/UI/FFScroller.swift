import AppKit

/// 自定义细滚动条：透明轨道 + 半透明圆角 thumb（macOS overlay 风格）
/// 不依赖 NSUserDefaults AppleShowScrollBars，显式控制样式
/// 任务 S1: 解决"全局滚动条依然很粗"问题
class FFScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollerStyle = .overlay
        controlSize = .mini
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scrollerStyle = .overlay
        controlSize = .mini
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    override func draw(_ dirtyRect: NSRect) {
        // 透明轨道，不绘制背景
        NSColor.clear.setFill()
        dirtyRect.fill()

        // 绘制 thumb：半透明圆角矩形
        // 使用 rect(for:) 获取 knob 区域（macOS AppKit NSScroller.Part.knob）
        let thumbRect = rect(for: .knob)
        guard !thumbRect.isEmpty else { return }

        let path = NSBezierPath(roundedRect: thumbRect.insetBy(dx: 2, dy: 2),
                                xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.3).setFill()
        path.fill()
    }

    // 标记需要重绘（floatValue 变化时）
    override var floatValue: Float {
        didSet {
            needsDisplay = true
        }
    }
}
