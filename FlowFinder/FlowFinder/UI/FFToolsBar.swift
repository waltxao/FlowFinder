import AppKit
import Combine

// MARK: - 图标注水（任务进度）

/// 22pt 模板图标：已完成部分从底部向上注强调色，100% 注满。
final class FFWaterFillIconView: NSView {

    private let iconSize: CGFloat
    private let baseIcon = NSImageView()
    private let fillIcon = NSImageView()
    private let waterMask = CALayer()
    private(set) var progress: Double = 0

    var progressForTesting: Double { progress }

    init(icon: FFIconName, size: CGFloat) {
        self.iconSize = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        baseIcon.image = FFIcon.template(icon, size: size)
        baseIcon.imageScaling = .scaleProportionallyUpOrDown
        baseIcon.contentTintColor = .secondaryLabelColor
        baseIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(baseIcon)

        fillIcon.image = FFIcon.template(icon, size: size)
        fillIcon.imageScaling = .scaleProportionallyUpOrDown
        fillIcon.contentTintColor = FFAccent.current
        fillIcon.translatesAutoresizingMaskIntoConstraints = false
        fillIcon.wantsLayer = true
        addSubview(fillIcon)

        waterMask.anchorPoint = .zero
        waterMask.position = .zero
        waterMask.bounds = CGRect(x: 0, y: 0, width: size, height: 0)
        waterMask.backgroundColor = NSColor.white.cgColor
        fillIcon.layer?.mask = waterMask

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            baseIcon.leadingAnchor.constraint(equalTo: leadingAnchor),
            baseIcon.trailingAnchor.constraint(equalTo: trailingAnchor),
            baseIcon.topAnchor.constraint(equalTo: topAnchor),
            baseIcon.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillIcon.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillIcon.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillIcon.topAnchor.constraint(equalTo: topAnchor),
            fillIcon.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        fillIcon.isHidden = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("FFWaterFillIconView 不支持 IB 初始化") }

    func setProgress(_ value: Double, animated: Bool) {
        let clamped = min(1, max(0, value))
        let oldBounds = waterMask.bounds
        let newBounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize * clamped)
        progress = clamped

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waterMask.bounds = newBounds
        CATransaction.commit()

        fillIcon.isHidden = clamped <= 0.001
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              abs(oldBounds.height - newBounds.height) > 0.01 else { return }
        let anim = CABasicAnimation(keyPath: "bounds")
        anim.fromValue = NSValue(rect: oldBounds)
        anim.toValue = NSValue(rect: newBounds)
        anim.duration = 0.30
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        waterMask.add(anim, forKey: "water")
    }
}

// MARK: - 54pt 玻璃圆钮基类

/// 底栏统一的 54pt 液态玻璃圆钮：与折叠态详情药丸同高。
/// 玻璃表面只负责材质；圆钮彼此独立，不共享药丸形容器。
class FFGlassCircleButton: NSView {

    static let diameter: CGFloat = 54
    static let radius: CGFloat = diameter / 2

    var onClick: (() -> Void)?

    let iconView = NSImageView()
    private let waterIcon = FFWaterFillIconView(icon: .listChecks, size: 22)
    private let normalLabel: String
    private let normalHelp: String?
    private(set) var isTaskMode = false
    private(set) var isPressed = false
    private let hoverOverlay = NSView()
    private var hovering = false
    private var tracking: NSTrackingArea?

    var isTaskModeForTesting: Bool { isTaskMode }
    var waterProgressForTesting: Double? { isTaskMode ? waterIcon.progressForTesting : nil }
    var isPressedForTesting: Bool { isPressed }

    init(icon: FFIconName, iconSize: CGFloat, label: String, help: String? = nil) {
        normalLabel = label
        normalHelp = help
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: 2)

        installGlass()

        hoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        hoverOverlay.wantsLayer = true
        hoverOverlay.layer?.cornerRadius = Self.radius
        hoverOverlay.layer?.cornerCurve = .continuous
        hoverOverlay.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(hoverOverlay)

        iconView.image = FFIcon.template(icon, size: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        waterIcon.isHidden = true
        addSubview(waterIcon)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            hoverOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            waterIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            waterIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityHelp(help ?? "")
        toolTip = help
    }

    required init?(coder: NSCoder) { fatalError("FFGlassCircleButton 不支持 IB 初始化") }

    private func installGlass() {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.cornerRadius = Self.radius
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        addSubview(host)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Self.radius
            glass.appearance = NSApp.appearance
            glass.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                glass.topAnchor.constraint(equalTo: host.topAnchor),
                glass.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        } else {
            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.appearance = NSApp.appearance
            effect.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(effect)
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                effect.topAnchor.constraint(equalTo: host.topAnchor),
                effect.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let border = NSView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.wantsLayer = true
        border.layer?.cornerRadius = Self.radius
        border.layer?.cornerCurve = .continuous
        border.layer?.borderWidth = 0.5
        border.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        addSubview(border)
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hovering = true
        hoverOverlay.layer?.backgroundColor = FFAccent.current.withAlphaComponent(0.12).cgColor
        iconView.contentTintColor = .labelColor
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovering = false
        hoverOverlay.layer?.backgroundColor = NSColor.clear.cgColor
        iconView.contentTintColor = .secondaryLabelColor
        NSCursor.arrow.set()
    }

    /// 任务模式：nil = 普通扳手/工具图标；有值 = 任务图标 + 图标注水。
    func showTaskProgress(_ progress: Double?, label: String = "任务") {
        let targetTask = progress != nil
        if let progress {
            waterIcon.setProgress(progress, animated: isTaskMode)
            setAccessibilityLabel(label)
            setAccessibilityValue("进度 \(Int((progress * 100).rounded()))%")
            setAccessibilityHelp("打开底栏工具，任务进度 \(Int((progress * 100).rounded()))%")
        } else {
            setAccessibilityLabel(normalLabel)
            setAccessibilityValue(nil)
            setAccessibilityHelp(normalHelp ?? "")
        }

        guard targetTask != isTaskMode else { return }
        isTaskMode = targetTask
        let incoming = targetTask ? waterIcon : iconView
        let outgoing = targetTask ? iconView : waterIcon
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard window != nil, !reduceMotion else {
            incoming.isHidden = false
            incoming.alphaValue = 1
            outgoing.isHidden = true
            outgoing.alphaValue = 1
            return
        }
        incoming.isHidden = false
        incoming.alphaValue = 0
        outgoing.isHidden = false
        outgoing.alphaValue = 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            incoming.animator().alphaValue = 1
            outgoing.animator().alphaValue = 0
        } completionHandler: {
            outgoing.isHidden = true
            outgoing.alphaValue = 1
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    /// 窗口未激活时首击也要生效（否则第一次点击只激活窗口）。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        !isHidden && alphaValue > 0.01
    }

    /// 整颗圆钮都是热区：图标子视图不拦截点击。
    /// 隐藏/淡出中的圆钮必须返回 nil——工具钮与关闭钮共用同一位置，
    /// 若隐藏视图仍参与命中，后添加的关闭钮会吞掉工具钮的点击。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isHidden else { return false }
        onClick?()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        animatePressDown()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.contains(point) {
            isPressed = false
            animatePressUp()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        animatePressUp()
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    private func animatePressDown() {
        guard let layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        layer.removeAnimation(forKey: "press")
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 0.94
        anim.duration = 0.08
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "press")
    }

    private func animatePressUp() {
        guard let layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        layer.removeAnimation(forKey: "press")
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.94
        spring.toValue = 1.0
        spring.mass = 1
        spring.stiffness = 260
        spring.damping = 14
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "press")
    }
}

// MARK: - 工具入口 / 关闭

/// 默认态右端 54pt 扳手圆钮：与折叠详情药丸同高。
final class FFRoundToolButton: FFGlassCircleButton {
    init() {
        super.init(icon: .wrench, iconSize: 22, label: "工具", help: "打开底栏工具")
    }
    required init?(coder: NSCoder) { fatalError("FFRoundToolButton 不支持 IB 初始化") }
}

/// 工具态右端 54pt × 关闭钮；× 是唯一手动关闭入口。
final class FFCloseToolButton: FFGlassCircleButton {
    init() {
        super.init(icon: .x, iconSize: 20, label: "关闭工具", help: "返回详情栏")
    }
    required init?(coder: NSCoder) { fatalError("FFCloseToolButton 不支持 IB 初始化") }
}

/// 单个工具圆钮：独立 54pt 玻璃圆，不带文字。
final class FFToolCircleButton: FFGlassCircleButton {
    let entry: FFToolPageCatalog.Entry
    var toolIDForTesting: String { entry.tool.id }

    init(entry: FFToolPageCatalog.Entry) {
        self.entry = entry
        super.init(icon: entry.tool.icon,
                   iconSize: 22,
                   label: entry.tool.title,
                   help: entry.tool.contextHint)
        setAccessibilityEnabled(entry.availability.isAvailable)
    }

    required init?(coder: NSCoder) { fatalError("FFToolCircleButton 不支持 IB 初始化") }
}

// MARK: - 详情圆（工具态左侧，只显示当前文件图标）

final class FFDetailsCircleView: NSView {
    private let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = FFGlassCircleButton.radius
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: 2)

        installGlass()

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: FFGlassCircleButton.diameter),
            heightAnchor.constraint(equalToConstant: FFGlassCircleButton.diameter),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
        ])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("FFDetailsCircleView 不支持 IB 初始化") }

    private func installGlass() {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.cornerRadius = FFGlassCircleButton.radius
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        addSubview(host)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = FFGlassCircleButton.radius
            glass.appearance = NSApp.appearance
            glass.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                glass.topAnchor.constraint(equalTo: host.topAnchor),
                glass.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        } else {
            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.appearance = NSApp.appearance
            effect.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(effect)
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                effect.topAnchor.constraint(equalTo: host.topAnchor),
                effect.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func updateIcon(_ image: NSImage?) {
        iconView.image = image ?? FFIcon.image(.folder, size: 32, color: .secondaryLabelColor)
    }
}

// MARK: - 工具簇（独立圆钮，无药丸容器）

/// N 个独立 54pt 工具圆：右对齐紧贴关闭钮；宽度不足时先压缩间隙 8→2，再横向滚动。
final class FFToolsClusterView: NSView {

    static let gap: CGFloat = 8
    static let compressedGap: CGFloat = 2

    var onRun: ((FFToolPageCatalog.Entry) -> Void)?
    /// 任务中心圆的注水进度；nil = 无任务（但此时通常已被可用性过滤掉）。
    var taskProgress: Double?

    private let scrollView = NSScrollView()
    private let documentView = FFToolsClusterDocumentView()
    private let stack = NSStackView()
    private var buttons: [FFToolCircleButton] = []
    private var documentWidth: NSLayoutConstraint!

    var spacingForTesting: CGFloat { stack.spacing }
    var isHorizontallyScrollableForTesting: Bool { scrollView.hasHorizontalScroller }
    var documentWidthForTesting: CGFloat { documentWidth.constant }
    var toolButtonsForTesting: [FFToolCircleButton] { buttons }
    var toolIDsForTesting: [String] { buttons.map(\.toolIDForTesting) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("FFToolsClusterView 不支持 IB 初始化") }

    private func setup() {
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Self.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        documentWidth = documentView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            documentWidth,

            // 右对齐：最右工具圆紧贴簇右缘（簇右缘再让 8pt 给关闭钮）
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor),
        ])
    }

    func update(entries: [FFToolPageCatalog.Entry]) {
        for button in buttons {
            stack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttons.removeAll()

        for entry in entries {
            let button = FFToolCircleButton(entry: entry)
            if entry.tool.id == "task-center", let taskProgress {
                button.showTaskProgress(taskProgress, label: entry.tool.title)
            }
            button.onClick = { [weak self] in self?.onRun?(entry) }
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        needsLayout = true
        updateSpacing()
    }

    /// 进度变化时只更新任务中心圆的水位，不重建圆钮/不重播入场动画。
    func setTaskProgress(_ progress: Double?) {
        taskProgress = progress
        guard let progress,
              let button = buttons.first(where: { $0.toolIDForTesting == "task-center" }) else { return }
        button.showTaskProgress(progress, label: button.entry.tool.title)
    }

    // MARK: - 开合动画（从 × 一侧向左弹簧滑出；关闭反向）

    func animateEntrance() {
        guard window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resetAnimationState()
            return
        }
        let now = CACurrentMediaTime()
        for (offset, button) in buttons.reversed().enumerated() {
            guard let layer = button.layer else { continue }
            let delay = Double(offset) * 0.025
            layer.removeAnimation(forKey: "toolEntrance")
            layer.removeAnimation(forKey: "toolEntranceFade")

            let spring = CASpringAnimation(keyPath: "transform.translation.x")
            spring.fromValue = FFGlassCircleButton.diameter
            spring.toValue = 0
            spring.mass = 1
            spring.stiffness = 190
            spring.damping = 14
            spring.initialVelocity = 0
            spring.beginTime = now + delay
            spring.fillMode = .backwards
            spring.duration = max(0.34, spring.settlingDuration)
            layer.add(spring, forKey: "toolEntrance")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.14
            fade.beginTime = now + delay
            fade.fillMode = .backwards
            layer.add(fade, forKey: "toolEntranceFade")
        }
    }

    func animateExit() {
        guard window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resetAnimationState()
            return
        }
        let now = CACurrentMediaTime()
        for (offset, button) in buttons.reversed().enumerated() {
            guard let layer = button.layer else { continue }
            let delay = Double(offset) * 0.015
            layer.removeAnimation(forKey: "toolEntrance")
            layer.removeAnimation(forKey: "toolEntranceFade")

            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = 0
            slide.toValue = FFGlassCircleButton.diameter
            slide.duration = 0.20
            slide.beginTime = now + delay
            slide.fillMode = .forwards
            slide.isRemovedOnCompletion = false
            slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(slide, forKey: "toolEntrance")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.16
            fade.beginTime = now + delay
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "toolEntranceFade")
        }
    }

    func resetAnimationState() {
        for button in buttons {
            button.layer?.removeAnimation(forKey: "toolEntrance")
            button.layer?.removeAnimation(forKey: "toolEntranceFade")
            button.layer?.opacity = 1
            button.layer?.transform = CATransform3DIdentity
        }
    }

    override func layout() {
        super.layout()
        updateSpacing()
    }

    /// 先压缩间隙，仍放不下再横向滚动（内容右对齐，默认滚到最右端）。
    private func updateSpacing() {
        guard bounds.width > 0 else { return }
        let count = CGFloat(buttons.count)
        let gaps = CGFloat(max(0, buttons.count - 1))
        let needAtGap8 = count * FFGlassCircleButton.diameter + gaps * Self.gap
        let needAtGap2 = count * FFGlassCircleButton.diameter + gaps * Self.compressedGap

        let gap: CGFloat
        let width: CGFloat
        let scrollable: Bool
        if needAtGap8 <= bounds.width {
            gap = Self.gap
            width = bounds.width
            scrollable = false
        } else if needAtGap2 <= bounds.width {
            gap = Self.compressedGap
            width = bounds.width
            scrollable = false
        } else {
            gap = Self.compressedGap
            width = needAtGap2
            scrollable = true
        }

        if abs(stack.spacing - gap) > 0.01 { stack.spacing = gap }
        if abs(documentWidth.constant - width) > 0.01 { documentWidth.constant = width }
        if scrollView.hasHorizontalScroller != scrollable {
            scrollView.hasHorizontalScroller = scrollable
        }
        if scrollable {
            let maxX = max(0, width - bounds.width)
            scrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class FFToolsClusterDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 协调器

/// 默认态：54pt 药丸详情栏 + 54pt 工具圆钮（同高）。
/// 展开态：工具圆钮隐藏，详情栏成为铺满宽度的胶囊。
/// 工具态：详情栏缩成左侧 54pt 图标圆，工具按钮变 ×，N 个独立 54pt 工具圆紧贴 ×。
/// 执行工具后自动回到默认态；关闭只认 ×；上下文变化只刷新圆钮。
final class FFToolsModuleCoordinator {

    private let container: NSView
    private let detailsBar: ExpandableDetailsBar
    private let side: PaneSide
    private let contextProvider: () -> FFToolContext?
    private let taskSummaryProvider: () -> FFTaskSummary

    let button = FFRoundToolButton()
    let closeButton = FFCloseToolButton()
    let cluster = FFToolsClusterView()
    let detailsCircle = FFDetailsCircleView(frame: .zero)

    private(set) var isToolsOpen = false
    private var detailsBarTrailingConstraint: NSLayoutConstraint!
    private var detailsBarWidthConstraint: NSLayoutConstraint!
    private var morphGeneration = 0
    private var lastRefreshSignature: String?
    private var currentTaskSummary: FFTaskSummary
    private var taskCancellables = Set<AnyCancellable>()

    var isToolsOpenForTesting: Bool { isToolsOpen }
    var toolButtonForTesting: FFRoundToolButton { button }
    var closeButtonForTesting: FFCloseToolButton { closeButton }
    var clusterForTesting: FFToolsClusterView { cluster }
    var detailsCircleForTesting: FFDetailsCircleView { detailsCircle }
    var detailsBarTrailingConstraintForTesting: NSLayoutConstraint { detailsBarTrailingConstraint }

    init(container: NSView,
         detailsBar: ExpandableDetailsBar,
         side: PaneSide,
         contextProvider: @escaping () -> FFToolContext?,
         taskSummaryProvider: @escaping () -> FFTaskSummary = { FFTaskPresence.summary() }) {
        self.container = container
        self.detailsBar = detailsBar
        self.side = side
        self.contextProvider = contextProvider
        self.taskSummaryProvider = taskSummaryProvider
        self.currentTaskSummary = taskSummaryProvider()
    }

    func install() {
        cluster.translatesAutoresizingMaskIntoConstraints = false
        detailsCircle.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(cluster)
        container.addSubview(detailsCircle)
        container.addSubview(button)
        container.addSubview(closeButton)

        // 详情栏默认让出 8 + 54 + 8；展开时由 onExpansionChanged 放宽到 -8。
        detailsBarTrailingConstraint = detailsBar.trailingAnchor.constraint(
            equalTo: container.trailingAnchor, constant: -70)
        // 工具簇开合时临时用宽度约束把详情栏缩成 54pt 圆；平时由 trailing 决定宽度。
        detailsBarWidthConstraint = detailsBar.widthAnchor.constraint(equalToConstant: 54)
        detailsBarWidthConstraint.isActive = false

        NSLayoutConstraint.activate([
            detailsBarTrailingConstraint,

            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            closeButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            detailsCircle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            detailsCircle.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            cluster.leadingAnchor.constraint(equalTo: detailsCircle.trailingAnchor, constant: 8),
            cluster.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            cluster.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            cluster.heightAnchor.constraint(equalToConstant: FFGlassCircleButton.diameter),
        ])

        detailsCircle.isHidden = true
        cluster.isHidden = true
        closeButton.isHidden = true

        button.onClick = { [weak self] in self?.openTools() }
        closeButton.onClick = { [weak self] in self?.closeTools() }
        cluster.onRun = { [weak self] entry in self?.run(entry) }
        detailsBar.onExpansionChanged = { [weak self] expanded in
            self?.detailsBarExpansionDidChange(expanded)
        }

        applyTaskSummary(currentTaskSummary)
        Publishers.CombineLatest(FFTaskService.shared.$tasks,
                                 TaskSchedulerManager.shared.$allTasks)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.applyTaskSummary(self.taskSummaryProvider())
            }
            .store(in: &taskCancellables)
    }

    /// 任务记录/进度变化：切换任务钮与注水；工具簇打开时刷新圆钮但不关闭。
    func applyTaskSummary(_ summary: FFTaskSummary) {
        let presenceChanged = currentTaskSummary.hasTasks != summary.hasTasks
        currentTaskSummary = summary
        button.showTaskProgress(summary.hasTasks ? summary.progress : nil)

        guard isToolsOpen else { return }
        if presenceChanged {
            if let context = contextProvider() {
                refresh(with: context, force: true)
            }
        } else {
            cluster.setTaskProgress(summary.hasTasks ? summary.progress : nil)
        }
    }

    func applyTaskSummaryForTesting(_ summary: FFTaskSummary) {
        applyTaskSummary(summary)
    }

    /// 展开/收起：展开时隐藏工具按钮并让胶囊铺到右侧 8pt；收起时恢复 54pt 圆钮。
    func detailsBarExpansionDidChange(_ expanded: Bool) {
        detailsBarTrailingConstraint.constant = expanded ? -8 : -70
        button.isHidden = expanded
        if expanded {
            closeTools()
        }
    }

    private var canAnimateMorph: Bool {
        container.window != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var collapsedBarWidth: CGFloat {
        max(FFGlassCircleButton.diameter, container.bounds.width - 78)
    }

    func openTools() {
        guard !isToolsOpen, !detailsBar.isExpanded, let context = contextProvider() else { return }

        refresh(with: context, force: true)
        isToolsOpen = true
        morphGeneration += 1
        let generation = morphGeneration

        // 详情栏保持可见，先隐藏内容，再把它从整栏宽度弹性收缩成 54pt 圆。
        detailsBar.isHidden = false
        detailsBar.alphaValue = 1
        detailsBar.prepareForMorphOut()
        container.layoutSubtreeIfNeeded()
        let startWidth = max(FFGlassCircleButton.diameter, detailsBar.bounds.width)

        detailsBarTrailingConstraint.isActive = false
        detailsBarWidthConstraint.isActive = true
        detailsBarWidthConstraint.constant = startWidth

        closeButton.isHidden = false
        detailsCircle.isHidden = false
        cluster.isHidden = false
        button.isHidden = false

        guard canAnimateMorph else {
            detailsBarWidthConstraint.constant = 54
            container.layoutSubtreeIfNeeded()
            detailsBar.isHidden = true
            detailsBar.prepareForMorphIn()
            button.isHidden = true
            button.alphaValue = 1
            closeButton.alphaValue = 1
            detailsCircle.alphaValue = 1
            cluster.alphaValue = 1
            cluster.resetAnimationState()
            return
        }

        closeButton.alphaValue = 0
        detailsCircle.alphaValue = 0
        cluster.alphaValue = 1
        button.alphaValue = 1
        container.layoutSubtreeIfNeeded()
        cluster.animateEntrance()

        detailsBarWidthConstraint.constant = 54
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.18, 0.36, 1.0)
            button.animator().alphaValue = 0
            closeButton.animator().alphaValue = 1
            detailsCircle.animator().alphaValue = 1
            container.window?.layoutIfNeeded()
        } completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation, self.isToolsOpen else { return }
            self.detailsBar.isHidden = true
            self.detailsBarWidthConstraint.constant = 54
            self.button.isHidden = true
            self.button.alphaValue = 1
            self.closeButton.alphaValue = 1
            self.detailsCircle.alphaValue = 1
        }
    }

    /// 回到默认态（执行工具 / 点 ×）。
    func closeTools() {
        guard isToolsOpen else { return }
        isToolsOpen = false
        morphGeneration += 1
        let generation = morphGeneration

        detailsBar.isHidden = false
        detailsBar.alphaValue = 1
        detailsBar.prepareForMorphOut()
        detailsBarTrailingConstraint.isActive = false
        detailsBarWidthConstraint.isActive = true
        detailsBarWidthConstraint.constant = 54

        closeButton.isHidden = false
        detailsCircle.isHidden = false
        cluster.isHidden = false
        button.isHidden = false
        closeButton.alphaValue = 1
        detailsCircle.alphaValue = 1
        cluster.alphaValue = 1
        button.alphaValue = canAnimateMorph ? 0 : 1
        container.layoutSubtreeIfNeeded()

        guard canAnimateMorph else {
            finishClosing(restoreContentAnimated: false)
            return
        }

        cluster.animateExit()
        detailsBarWidthConstraint.constant = collapsedBarWidth
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.18, 0.36, 1.0)
            button.animator().alphaValue = 1
            closeButton.animator().alphaValue = 0
            detailsCircle.animator().alphaValue = 0
            container.window?.layoutIfNeeded()
        } completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation, !self.isToolsOpen else { return }
            self.detailsBarWidthConstraint.isActive = false
            self.detailsBarTrailingConstraint.isActive = true
            self.detailsBarTrailingConstraint.constant = self.detailsBar.isExpanded ? -8 : -70
            self.container.layoutSubtreeIfNeeded()
            self.finishClosing(restoreContentAnimated: true)
        }
    }

    private func finishClosing(restoreContentAnimated: Bool) {
        detailsBar.isHidden = false
        if restoreContentAnimated {
            detailsBar.animateMorphContentIn()
        } else {
            detailsBar.prepareForMorphIn()
        }
        detailsBarWidthConstraint.isActive = false
        detailsBarTrailingConstraint.isActive = true
        detailsBarTrailingConstraint.constant = detailsBar.isExpanded ? -8 : -70
        button.isHidden = detailsBar.isExpanded
        button.alphaValue = 1
        closeButton.isHidden = true
        detailsCircle.isHidden = true
        cluster.isHidden = true
        closeButton.alphaValue = 1
        detailsCircle.alphaValue = 1
        cluster.alphaValue = 1
        cluster.resetAnimationState()
        container.layoutSubtreeIfNeeded()
    }

    /// 选中/目录变化：保持工具态，只刷新可用工具与详情圆图标。
    func contextDidChange(path: String, selection: [FileEntry]) {
        guard isToolsOpen, let context = contextProvider() else { return }
        refresh(with: context)
    }

    /// 活动面板变化：同样只刷新，不自动关闭（关闭只认 ×）。
    func closeIfActivePaneChanged() {
        guard isToolsOpen, let context = contextProvider() else { return }
        refresh(with: context)
    }

    private func refresh(with context: FFToolContext, force: Bool = false) {
        context.hasTasks = currentTaskSummary.hasTasks
        let signature = context.currentPath + "|" + context.selection.map(\.path).joined(separator: "|")
            + "|tasks:\(currentTaskSummary.hasTasks)"
        guard force || signature != lastRefreshSignature else { return }
        lastRefreshSignature = signature
        detailsCircle.updateIcon(Self.icon(for: context))
        cluster.taskProgress = currentTaskSummary.hasTasks ? currentTaskSummary.progress : nil
        let entries = FFToolPageCatalog.entries(context: context)
            .filter { $0.availability.isAvailable }
        cluster.update(entries: entries)
    }

    private func run(_ entry: FFToolPageCatalog.Entry) {
        guard isToolsOpen, entry.availability.isAvailable,
              let context = contextProvider() else { return }
        entry.tool.run(in: context)
        closeTools()
    }

    func runForTesting(_ entry: FFToolPageCatalog.Entry) {
        run(entry)
    }

    private static func icon(for context: FFToolContext) -> NSImage? {
        if let first = context.selection.first {
            let image = NSWorkspace.shared.icon(forFile: first.path)
            image.size = NSSize(width: 32, height: 32)
            return image
        }
        guard !context.currentPath.isEmpty else { return nil }
        let image = NSWorkspace.shared.icon(forFile: context.currentPath)
        image.size = NSSize(width: 32, height: 32)
        return image
    }
}
