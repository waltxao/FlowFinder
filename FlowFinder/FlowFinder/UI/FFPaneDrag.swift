import Cocoa

// MARK: - 面板拖拽（2026-10-20 #1）
//
// 模型：**拖操作面板 = 拖它当前那个标签**（SPEC-2026-10-20 §1）。
//
// 起手区：工具栏空白 + 标签条空白。
//         文件列表空白处**保留框选**（访达习惯），不参与面板拖动。
// 落点：
//   - 单面板 + 单标签   → 拖面板即拖窗口（没有第二个标签可搬）
//   - 单面板 + 多标签   → 窗口右半区 = 拆出右面板；窗口外 = 独立新窗口
//   - 双面板            → 落在对面面板 = 只搬当前标签；源面板被搬空才消失（合并成单面板）
//   - 其余              → 回原位
//
// 拖影：整块面板的 1:1 快照 + 0.55 不透明度，原位置留虚线占位框。

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

/// 面板拖拽的拖拽源。
///
/// 工具栏与标签条各自实现；`paneCard` 指向被拖起的那块面板卡片。
protocol FFPaneDragSource: AnyObject {
    /// 被拖起的面板卡片
    var paneCard: NSView? { get }
    /// 起手面板所在侧
    var side: PaneSide { get }
    /// 单面板 + 单标签时，拖面板退化为拖窗口
    var dragsWindowInstead: Bool { get }
}

/// 面板拖拽的工具方法
enum FFPaneDrag {

    private static let placeholderID = NSUserInterfaceItemIdentifier("ff.pane.placeholder")

    /// 拖起阈值：移动超过 4pt 才算拖动，否则视为点击
    static let threshold: CGFloat = 4

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
/// **为什么不用 NSDraggingSession**：窗口顶部 28pt 是系统标题栏的拖动区，
/// 正好压在操作面板工具栏的第一行上。标题栏会先于内容视图吃掉 mouseDown——
/// 这正是「按住操作面板拖动，动的却是整个窗口」的根因。
/// 窗口级 local monitor 在事件分发**之前**就能拦下来，把它改造成「拖面板」。
///
/// 拖影是一块无边框浮层（不是拖拽图像），落点由自己判定，
/// 因此也不需要 pasteboard、不需要 NSDraggingDestination。
final class FFPaneDragController {

    static let shared = FFPaneDragController()

    /// 拖动落在窗口内（窗口坐标）
    var onDropInside: ((NSPoint) -> Void)?
    /// 拖动落在窗口外（屏幕坐标）
    var onDropOutside: ((NSPoint) -> Void)?

    private weak var window: NSWindow?
    private var monitors: [Any] = []

    private enum Mode { case none, pane, window }
    private var mode: Mode = .none
    private weak var source: (any FFPaneDragSource)?
    private weak var card: NSView?
    private var startScreenPoint: NSPoint = .zero
    private var startWindowPoint: NSPoint = .zero
    private var grabOffset: NSPoint = .zero
    private var startWindowOrigin: NSPoint = .zero
    private var ghostPanel: NSPanel?
    private var didMove = false

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
        // 只有「工具栏空白」与「标签条空白」会命中这两个视图本身
        // （两者都把空白归并到自己身上，见各自 hitTest 覆写）
        guard hit is PaneToolbar || hit is PaneTabStripView,
              let source = hit as? (any FFPaneDragSource) else { return event }

        startScreenPoint = NSEvent.mouseLocation
        startWindowPoint = point
        didMove = false

        if source.dragsWindowInstead {
            // 单面板 + 单标签：没有第二个标签可搬，拖面板 = 拖窗口
            mode = .window
            startWindowOrigin = window.frame.origin
        } else {
            mode = .pane
            self.source = source
            self.card = source.paneCard
            // 落点分流要用到源面板侧
            PaneTabDragContext.shared.sourceSide = source.side
        }
        // 吞掉事件：标题栏因此不会开始拖窗口
        return nil
    }

    private func handleDragged(_ event: NSEvent) -> NSEvent? {
        switch mode {
        case .none:
            return event
        case .window:
            let now = NSEvent.mouseLocation
            guard let window else { return nil }
            window.setFrameOrigin(NSPoint(x: startWindowOrigin.x + (now.x - startScreenPoint.x),
                                          y: startWindowOrigin.y + (now.y - startScreenPoint.y)))
            return nil
        case .pane:
            let now = NSEvent.mouseLocation
            if !didMove {
                let dx = now.x - startScreenPoint.x
                let dy = now.y - startScreenPoint.y
                guard hypot(dx, dy) > FFPaneDrag.threshold else { return nil }
                didMove = true
                beginGhost()
            }
            moveGhost(to: now)
            return nil
        }
    }

    private func handleUp(_ event: NSEvent) -> NSEvent? {
        let wasMode = mode
        let moved = didMove
        mode = .none
        didMove = false

        switch wasMode {
        case .none:
            return event
        case .window:
            return nil
        case .pane:
            let source = self.source
            let card = self.card
            self.source = nil
            self.card = nil
            endGhost()
            if let card { FFPaneDrag.hidePlaceholder(in: card) }
            guard moved, let source, let window else { return nil }
            let screenPoint = NSEvent.mouseLocation
            if window.frame.contains(screenPoint) {
                onDropInside?(window.convertPoint(fromScreen: screenPoint))
            } else {
                onDropOutside?(screenPoint)
            }
            return nil
        }
    }

    // MARK: 浮层

    private func beginGhost() {
        guard let card else { return }
        guard let image = FFPaneDrag.snapshot(of: card) else { return }
        let size = image.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        panel.contentView = imageView
        // 抓取点在卡片内的相对位置，浮层要保持它不动
        let cardFrameInWindow = card.convert(card.bounds, to: nil)
        grabOffset = NSPoint(x: startWindowPoint.x - cardFrameInWindow.minX,
                             y: startWindowPoint.y - cardFrameInWindow.minY)
        ghostPanel = panel
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
}
