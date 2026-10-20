import Cocoa

// MARK: - 面板拖拽（2026-10-20 #1 重做）
//
// 规格见 docs/SPEC-2026-10-20.md §1.8。三件事彻底分开：
//
//   拖窗口：侧栏空白 / 面板卡片四周 8pt 留白 / 标签条空白
//   拖面板：只有标签条上的「标签」能触发
//           条内（含 20pt 缓冲）= 重排标签
//           出缓冲 = 搬整块面板（1:1 浮层跟随）
//   不拖：  工具栏、文件列表（给按压反馈，但不产生任何拖动）
//
// 为什么全部自管、不用 NSDraggingSession：
// 标签条在窗口顶部那一行（与红绿灯同高），那一带的 mouseDown 会被系统标题栏
// 先于内容视图抢走；NSDraggingSession 要求拖拽源就是收到 mouseDown 的视图，
// 根本做不到。窗口级 local monitor 在事件分发之前就能拦下来。
//
// 落点（整块面板的移动）：
//   同一窗口的空槽（单栏时的右半区）→ 面板挪过去，原槽空掉，窗口收窄
//   已被占用的槽（对面面板）        → 两块合并成一个（标签并集），窗口变单栏
//   窗口外                          → 拆成独立新窗口
//   其它                            → 回原位

/// 原位置占位框：面板被拖起时留在原处的虚线轮廓
final class FFPanePlaceholderView: NSView {

    override var isOpaque: Bool { false }

    /// 只做视觉提示，不参与事件分发（否则会吃掉面板内的点击）
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        FFAccent.current.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }
}

/// 标签重排时的插入指示线（竖线）
final class FFTabInsertionIndicator: NSView {

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: bounds.midX - 1, y: 0, width: 2, height: bounds.height)
        NSColor.controlAccentColor.setFill()
        rect.fill()
    }
}

/// 面板拖拽的工具方法
enum FFPaneDrag {

    private static let placeholderID = NSUserInterfaceItemIdentifier("ff.pane.placeholder")

    /// 拖起阈值：移动超过 4pt 才算拖动，否则视为点击
    static let threshold: CGFloat = 4

    /// 标签条矩形外扩的缓冲：
    /// 指针在标签条矩形外扩 20pt 内仍算「条内重排」，出了才算拖出搬面板。
    /// 标签条只有 28pt 高，无缓冲会导致垂直抖动误触发、重排几乎无法完成。
    static let stripBuffer: CGFloat = 20

    /// 面板卡片快照：1:1 尺寸、0.55 不透明度
    static func snapshot(of card: NSView) -> NSImage? {
        let size = card.bounds.size
        guard size.width > 1, size.height > 1,
              let rep = card.bitmapImageRepForCachingDisplay(in: card.bounds) else { return nil }
        card.cacheDisplay(in: card.bounds, to: rep)

        let opaque = NSImage(size: size)
        opaque.addRepresentation(rep)

        let faded = NSImage(size: size)
        faded.lockFocus()
        opaque.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 0.55)
        faded.unlockFocus()
        return faded
    }

    /// 在原位置显示虚线占位框
    static func showPlaceholder(in card: NSView) {
        guard placeholder(in: card) == nil else { return }
        let view = FFPanePlaceholderView()
        view.identifier = placeholderID
        view.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: card.topAnchor),
            view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    /// 移除占位框
    static func hidePlaceholder(in card: NSView) {
        placeholder(in: card)?.removeFromSuperview()
    }

    private static func placeholder(in card: NSView) -> FFPanePlaceholderView? {
        card.subviews.first { $0.identifier == placeholderID } as? FFPanePlaceholderView
    }
}

// MARK: - 窗口级面板拖拽控制器

/// 面板拖拽的窗口级控制器。
///
/// 靠 `NSEvent.addLocalMonitorForEvents` 在事件分发**之前**接管 mouseDown：
/// 窗口顶部 28pt 是系统标题栏的拖动区，会先于内容视图吃掉事件，
/// 只有在分发前拦下来，才能把「拖标签 / 拖窗口 / 按压无反应」三者分开。
final class FFPaneDragController {

    static let shared = FFPaneDragController()

    /// 宿主窗口控制器（提供面板卡片、标签组等数据）
    weak var owner: MainWindowController?

    private weak var window: NSWindow?
    private var monitors: [Any] = []

    private enum Mode {
        case none
        case windowDrag
        case tabDrag
        case press
    }
    private var mode: Mode = .none

    // 窗口拖动
    private var startScreenPoint: NSPoint = .zero
    private var startWindowOrigin: NSPoint = .zero

    // 标签拖动
    private weak var sourceStrip: PaneTabStripView?
    private var sourceSide: PaneSide = .left
    private var sourceIndex: Int = 0
    private var didExceedThreshold = false
    private var isPanelMove = false
    private var currentInsertionIndex: Int = 0
    private var ghostPanel: NSPanel?
    private var grabOffset: NSPoint = .zero
    private weak var movedCard: NSView?

    // 按压反馈
    private weak var pressedCard: NSView?

    // MARK: 安装

    func install(for window: NSWindow) {
        self.window = window
        guard monitors.isEmpty else { return }
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
                self?.handleDown(e)
            },
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] e in
                self?.handleDragged(e)
            },
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] e in
                self?.handleUp(e)
            },
        ]
    }

    func uninstall() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        endGhost()
    }

    // MARK: 事件

    private func handleDown(_ event: NSEvent) -> NSEvent? {
        guard mode == .none, let window, event.window === window,
              let contentView = window.contentView else { return event }
        let point = event.locationInWindow
        guard let hit = contentView.hitTest(point) else { return event }

        // ① 标签 → 拖动（条内重排 / 出缓冲搬面板）
        if let item = hit as? PaneTabItemView, let strip = item.strip {
            sourceStrip = strip
            sourceSide = strip.side
            sourceIndex = item.index
            startScreenPoint = NSEvent.mouseLocation
            didExceedThreshold = false
            isPanelMove = false
            mode = .tabDrag
            return nil
        }

        // ② 标签条空白 → 拖窗口（标签条在窗口顶部那一行，性质等同标题栏）
        if hit is PaneTabStripView {
            mode = .windowDrag
            startScreenPoint = NSEvent.mouseLocation
            startWindowOrigin = window.frame.origin
            return nil
        }

        // ③ 工具栏 → 按压反馈，但不产生任何拖动
        if hit is PaneToolbar {
            mode = .press
            pressedCard = owner?.paneCard(for: sourceSide)
            applyPressFeedback()
            return nil
        }

        // ④ 其余（列表 / 卡片留白 / 侧栏）交给各自的视图处理
        return event
    }

    private func handleDragged(_ event: NSEvent) -> NSEvent? {
        switch mode {
        case .none:
            return event
        case .windowDrag:
            let now = NSEvent.mouseLocation
            guard let window else { return nil }
            window.setFrameOrigin(NSPoint(x: startWindowOrigin.x + (now.x - startScreenPoint.x),
                                          y: startWindowOrigin.y + (now.y - startScreenPoint.y)))
            return nil
        case .press:
            return nil
        case .tabDrag:
            return handleTabDragged()
        }
    }

    private func handleTabDragged() -> NSEvent? {
        guard let window else { return nil }
        let now = NSEvent.mouseLocation
        if !didExceedThreshold {
            let dx = now.x - startScreenPoint.x
            let dy = now.y - startScreenPoint.y
            guard hypot(dx, dy) > FFPaneDrag.threshold else { return nil }
            didExceedThreshold = true
        }
        let winPoint = window.convertPoint(fromScreen: now)

        if !isPanelMove {
            if isOutsideStripBuffer(winPoint) {
                // 出缓冲 → 升级为「搬整块面板」
                isPanelMove = true
                sourceStrip?.hideInsertionIndicator()
                beginPanelGhost()
            } else {
                // 条内 → 重排，更新插入指示线
                if let strip = sourceStrip, let index = strip.insertionIndex(atWindowPoint: winPoint) {
                    currentInsertionIndex = index
                    strip.showInsertionIndicator(atIndex: index)
                }
            }
        }
        if isPanelMove { moveGhost(to: now) }
        return nil
    }

    private func handleUp(_ event: NSEvent) -> NSEvent? {
        let wasMode = mode
        let moved = didExceedThreshold
        let wasPanelMove = isPanelMove
        mode = .none
        didExceedThreshold = false
        isPanelMove = false

        switch wasMode {
        case .none:
            return event
        case .windowDrag:
            return nil
        case .press:
            removePressFeedback()
            pressedCard = nil
            return nil
        case .tabDrag:
            sourceStrip?.hideInsertionIndicator()
            let strip = sourceStrip
            let side = sourceSide
            let from = sourceIndex
            let to = currentInsertionIndex
            sourceStrip = nil

            if wasPanelMove {
                endGhost()
                if let card = movedCard { FFPaneDrag.hidePlaceholder(in: card) }
                movedCard = nil
                guard moved, let window else { return nil }
                let screenPoint = NSEvent.mouseLocation
                if window.frame.contains(screenPoint) {
                    owner?.handlePanelMove(toWindowPoint: window.convertPoint(fromScreen: screenPoint),
                                          from: side)
                } else {
                    owner?.handlePanelMoveOutside(screenPoint: screenPoint, from: side)
                }
            } else if moved, let owner {
                // 条内重排
                owner.moveTab(side: side, from: from, to: to)
            } else if let owner {
                // 没移动 → 视为点击标签：选中它
                // （mouseDown 被本控制器吞掉了，选中必须在这里补上）
                owner.selectTab(side: side, index: from)
            }
            return nil
        }
    }

    // MARK: 判定

    /// 指针是否离开了「标签条矩形 + 20pt 缓冲」
    private func isOutsideStripBuffer(_ windowPoint: NSPoint) -> Bool {
        guard let strip = sourceStrip else { return true }
        let frame = strip.convert(strip.bounds, to: nil)
        let buffer = frame.insetBy(dx: -FFPaneDrag.stripBuffer, dy: -FFPaneDrag.stripBuffer)
        return !buffer.contains(windowPoint)
    }

    // MARK: 浮层

    private func beginPanelGhost() {
        guard let card = owner?.paneCard(for: sourceSide),
              let window else { return }
        guard let image = FFPaneDrag.snapshot(of: card) else { return }
        let size = image.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level.floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        panel.contentView = imageView

        // 抓取点在卡片内的相对位置，浮层要保持它不动
        let cardFrame = card.convert(card.bounds, to: nil)
        let grab = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        grabOffset = NSPoint(x: grab.x - cardFrame.minX, y: grab.y - cardFrame.minY)

        ghostPanel = panel
        movedCard = card
        FFPaneDrag.showPlaceholder(in: card)
        moveGhost(to: NSEvent.mouseLocation)
    }

    private func moveGhost(to screenPoint: NSPoint) {
        guard let panel = ghostPanel else { return }
        panel.setFrameOrigin(NSPoint(x: screenPoint.x - grabOffset.x,
                                     y: screenPoint.y - grabOffset.y))
        panel.orderFrontRegardless()
    }

    private func endGhost() {
        ghostPanel?.orderOut(nil)
        ghostPanel = nil
    }

    // MARK: 按压反馈

    /// 面板本体的按压反馈：卡片轻微下沉 0.5pt，松开还原。
    /// 只作为「这块是实的、拖不动」的提示，不产生任何拖动。
    private func applyPressFeedback() {
        guard let card = pressedCard, let layer = card.layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        layer.transform = CATransform3DMakeTranslation(0, -0.5, 0)
        CATransaction.commit()
    }

    private func removePressFeedback() {
        guard let card = pressedCard, let layer = card.layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }
}
