import Cocoa

// MARK: - 药丸按钮

/// 程序名称旁的「发现功能」药丸（2026-10-19 #9）。
///
/// 用 NSView 自绘而不是 NSButton：无边框 NSButton 拿不到内边距，
/// 图标与文字会贴到胶囊边上；这层只有一条标签和一个图标，自绘更可控。
final class FFPillButton: NSView, FFRegionAware {

    /// 自绘按钮属于面板区：按压反馈不消费事件，`mouseUp` 仍会到达本视图。
    var ffRegion: FFRegion { .panel }

    var onClick: (() -> Void)?

    /// 选中态（如工具页打开时的「工具」胶囊）：强调色底 + 强调色字/图标。
    var isSelected = false {
        didSet {
            needsDisplay = true
            refreshContentTint()
            setAccessibilityValue(isSelected ? "已打开" : "已关闭")
        }
    }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(title: String, icon: FFIconName, height: CGFloat = 20) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        iconView.image = FFIcon.template(icon, size: 12)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.stringValue = title
        label.font = FFDesign.Text.sm
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
        ])

        // 批次 1 B1-10：VoiceOver 与键盘可达
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityHelp("\(title)（空格或回车）")
        setAccessibilityValue("已关闭")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onClick?()
            return
        }
        super.keyDown(with: event)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshContentTint() {
        let color: NSColor = isSelected ? FFAccent.current : .secondaryLabelColor
        iconView.contentTintColor = color
        label.textColor = isSelected ? FFAccent.current : .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }

    /// 标签 / 图标都是 NSTextField / NSImageView；让它们把点击让给药丸本身，
    /// 否则点文字时 `mouseDown` 被文本控件吃掉，`onClick` 永远不触发。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        if isSelected {
            FFAccent.current.withAlphaComponent(isPressed ? 0.30 : (isHovered ? 0.24 : 0.18)).setFill()
        } else {
            let alpha: CGFloat = isPressed ? 0.16 : (isHovered ? 0.12 : 0.07)
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
        }
        path.fill()

        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -2, dy: -2),
                                    xRadius: bounds.height / 2 + 2,
                                    yRadius: bounds.height / 2 + 2)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
