import Cocoa
import os

private let dragLog = OSLog(subsystem: "com.flowfinder.native",
                            category: .pointsOfInterest)

// MARK: - 标签拖动（2026-10-20 #4 重做）
//
// 规格见 docs/SPEC-2026-10-20.md §1.12。
//
// 本轮把拖动对象从「整块面板」改成「标签」，并支持跨窗口：
//
//   拖标签（出缓冲）→ 带着这个标签走（1:1 标签浮层）
//   落点            → 决定这个标签去哪：
//                      · 某个窗口的标签条   → 并入那个面板
//                      · 某个窗口的操作区   → 单栏窗口拆出第二块面板 / 双栏窗口并入该侧
//                      · 窗口外             → 独立成新窗口
//   标签条空白      → 拖窗口（性质等同系统标题栏）
//   工具栏 / 列表   → 不产生拖动（只给按压反馈，且**不消费事件**）
//
// 为什么全部自管、不用 NSDraggingSession：
// 标签条在窗口顶部那一行（与红绿灯同高），那一带的 mouseDown 会被系统标题栏
// 先于内容视图抢走；NSDraggingSession 要求拖拽源就是收到 mouseDown 的视图，
// 根本做不到。窗口级 local monitor 在事件分发之前就能拦下来。
//
// 跨窗口：local monitor 是 app 级的，能收到本应用所有窗口的事件；
// 拖动中按屏幕坐标遍历已注册窗口做命中判定，即可知道落在哪个窗口的哪块区域。

/// 标签重排时的插入指示线（竖线）
final class FFTabInsertionIndicator: NSView {

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: bounds.midX - 1, y: 0, width: 2, height: bounds.height)
        FFAccent.current.setFill()
        rect.fill()
    }
}

/// 一次拖动的落点
enum FFDropTarget {

    /// 落在某个窗口某侧面板的标签条上（index = nil 表示并到末尾）
    case tabStrip(window: MainWindowController, side: PaneSide, index: Int?)

    /// 落在某个窗口的操作区（单栏 = 拆出第二块面板；双栏 = 并入该侧面板）
    case paneContent(window: MainWindowController, side: PaneSide)

    /// 落点所属的窗口
    var window: MainWindowController {
        switch self {
        case .tabStrip(let w, _, _): return w
        case .paneContent(let w, _): return w
        }
    }
}

/// 系统窗口按钮（红绿灯）的命中判定。
///
/// fullSizeContentView 下 contentView 会铺到标题栏，`contentView.hitTest` 在红绿灯
/// 位置返回的是背后的侧栏/标签条，而不是系统按钮。窗口级 mouseDown 监视器如果
/// 直接把这套命中翻译成 `.window` / `.title`，就会把红绿灯点击当成拖窗口消费。
enum FFWindowChrome {

    /// 纯几何命中：用于单测，避免依赖真实 NSWindow。
    static func contains(point: NSPoint, in rects: [NSRect]) -> Bool {
        rects.contains { NSPointInRect(point, $0) }
    }

    /// 三个系统窗口按钮在窗口坐标系里的矩形。
    static func standardButtonFrames(in window: NSWindow) -> [NSRect] {
        var rects: [NSRect] = []
        func append(_ type: NSWindow.ButtonType) {
            guard let button = window.standardWindowButton(type),
                  !button.isHidden,
                  button.superview != nil else { return }
            rects.append(button.convert(button.bounds, to: nil))
        }
        append(.closeButton)
        append(.miniaturizeButton)
        append(.zoomButton)
        return rects
    }

    static func hitsStandardButton(window: NSWindow, point: NSPoint) -> Bool {
        contains(point: point, in: standardButtonFrames(in: window))
    }
}

/// 面板拖拽的工具方法
enum FFPaneDrag {

    /// 拖起阈值：移动超过 4pt 才算拖动，否则视为点击
    static let threshold: CGFloat = 4

    /// 标签条矩形外扩的缓冲：
    /// 指针在标签条矩形外扩 20pt 内仍算「条内重排」，出了才算拖出。
    /// 标签条只有 36pt 高，无缓冲会导致垂直抖动误触发、重排几乎无法完成。
    static let stripBuffer: CGFloat = 20

    /// 标签快照：1:1 尺寸、0.55 不透明度
    static func snapshot(of view: NSView, background: NSColor? = nil) -> NSImage? {
        let size = view.bounds.size
        guard size.width > 1, size.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)

        let rendered = NSImage(size: size)
        rendered.addRepresentation(rep)

        let result = NSImage(size: size)
        result.lockFocus()
        if let background {
            let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                    xRadius: 8, yRadius: 8)
            background.setFill()
            path.fill()
        }
        rendered.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }
}

/// 60Hz 帧调度：事件只记录最新指针，每帧最多跑一次落点解析与浮层更新。
final class FFDragFrameScheduler {

    private var timer: Timer?
    private var latest: CGPoint = .zero
    private let onFrame: (CGPoint) -> Void

    var latestPoint: CGPoint { latest }

    init(onFrame: @escaping (CGPoint) -> Void) {
        self.onFrame = onFrame
    }

    func update(_ point: CGPoint) {
        latest = point
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onFrame(self.latest)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - 窗口级标签拖动控制器

/// 标签拖动的窗口级控制器。
///
/// 靠 `NSEvent.addLocalMonitorForEvents` 在事件分发**之前**接管 mouseDown：
/// 窗口顶部 36pt 是系统标题栏的拖动区，会先于内容视图吃掉事件，
/// 只有在分发前拦下来，才能把「拖标签 / 拖窗口 / 按压无反应」三者分开。
final class FFPaneDragController {

    static let shared = FFPaneDragController()

    /// 已注册的窗口宿主（弱引用，窗口关掉自动失效）
    ///
    /// 2026-10-20 #4：原先只有一个 `owner` + 一个 `window`，而 `install(for:)` 由每个
    /// 窗口调用——第二个窗口创建时把 `self.window` 覆盖掉，于是只有最后创建的窗口
    /// 会被接管，其余窗口的点击与拖动全部失灵。改为按 `event.window` 路由。
    private final class WeakOwner {
        weak var value: MainWindowController?
        init(_ value: MainWindowController) { self.value = value }
    }
    private var registeredOwners: [WeakOwner] = []

    private var monitors: [Any] = []
    /// 全局监视器（事件发生在**别的 App** 上时也能收到）
    private var globalMonitors: [Any] = []

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
    private var isTabDragOut = false
    private var currentInsertionIndex: Int = 0
    private let overlay = FFDragOverlay()
    private var grabOffset: NSPoint = .zero

    // 第七轮：落点决策 + 几何缓存 + 帧调度
    private let geometryCache = FFDragGeometryCache()
    private var sourceRef: FFDragSource?
    private var latestPointer: CGPoint = .zero
    private var currentDecision: FFDropDecision?
    /// 拖动开始时快照的窗口几何（按窗口层级排好），拖动中不再重建。
    private var dragGeometries: [FFWindowDropGeometry] = []
    private lazy var frameScheduler = FFDragFrameScheduler { [weak self] point in
        self?.processDragFrame(at: point)
    }
    private lazy var windowFrameScheduler = FFDragFrameScheduler { [weak self] point in
        self?.processWindowDragFrame(at: point)
    }

    /// 本次拖拽的宿主窗口控制器（拖拽开始时锁定，避免中途路由变化）
    private weak var dragOwner: MainWindowController?

    // 按压反馈
    private weak var pressedCard: NSView?

    // MARK: 安装

    /// 注册一个窗口宿主。monitor 只装一次（local monitor 是 app 级的，
    /// 装多个会出现调用顺序问题），事件按窗口路由到对应宿主。
    func register(owner: MainWindowController, window: NSWindow) {
        registeredOwners.removeAll { $0.value == nil }
        if !registeredOwners.contains(where: { $0.value === owner }) {
            registeredOwners.append(WeakOwner(owner))
        }
        geometryCache.update(for: owner)
        installMonitorsIfNeeded()
    }

    func unregister(owner: MainWindowController) {
        registeredOwners.removeAll { $0.value === owner || $0.value == nil }
        geometryCache.remove(owner)
    }

    /// 事件按窗口路由到宿主；找不到就返回 nil
    private func owner(for window: NSWindow?) -> MainWindowController? {
        guard let window else { return nil }
        return registeredOwners.first { $0.value?.window === window }?.value
    }

    private func installMonitorsIfNeeded() {
        guard monitors.isEmpty else { return }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resetForInactiveApp()
        }
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
        // 2026-10-20 #4：全局监视器。
        //
        // 为什么必须有：拖动时我们**消费**了 mouseDown（否则系统标题栏会抢走），
        // 如果指针拖到别的 App 上松手，那个 mouseUp 只会派发给别的 App，
        // 我们的 local monitor 永远收不到 →
        //   ① 拖拽没有「结束」，浮层与占位框留在屏幕上；
        //   ② 系统认为鼠标还按着，之后整个操作系统的点击都被当成拖拽续接。
        // global monitor 正好补上这一段：local 覆盖本 App 的事件，global 覆盖别处的。
        globalMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] e in
                self?.handleDragged(e)
            },
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] e in
                self?.handleUp(e)
            },
        ]
    }

    func uninstall() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        globalMonitors.forEach { NSEvent.removeMonitor($0) }
        globalMonitors.removeAll()
        frameScheduler.stop()
        endGhost()
    }

    /// 应用失焦：复位所有拖拽状态。
    ///
    /// 2026-10-20 #4：如果我们在拖拽中途吞掉了 mouseDown，而 mouseUp 没有回到
    /// 本应用（切到别的 App 松手），系统会认为「鼠标还按着」——之后整个操作系统的
    /// 点击都被当成拖拽续接，别的 App 全点不动。这里主动复位，并补发一次 mouseUp
    /// 释放系统端的按键状态。
    private func resetForInactiveApp() {
        let hadConsumedDown = (mode == .windowDrag || mode == .tabDrag)
        resetDragState()
        if hadConsumedDown {
            let p = NSEvent.mouseLocation
            CGEvent(mouseEventSource: nil,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: p,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    private func resetDragState() {
        mode = .none
        didExceedThreshold = false
        isTabDragOut = false
        frameScheduler.stop()
        windowFrameScheduler.stop()
        sourceRef = nil
        currentDecision = nil
        dragGeometries = []
        sourceStrip?.hideInsertionIndicator()
        sourceStrip = nil
        dragOwner = nil
        endGhost()
        endHighlight()
        removePressFeedback()
        pressedCard = nil
    }

    /// 窗口拖动优先走系统 `performDrag(with:)`：服务端合并移动事件，
    /// 避免逐事件 `setFrameOrigin` 在透明/模糊窗口上反复重合成。
    /// `FF_NATIVE_WINDOW_DRAG=0` 可回退到 60Hz 合并的自管拖动。
    private var useNativeWindowDrag: Bool {
        ProcessInfo.processInfo.environment["FF_NATIVE_WINDOW_DRAG"] != "0"
    }

    // MARK: 事件

    /// 一次 mouseDown 的判定：**全部走决策表**，不再有散落的 if。
    private func handleDown(_ event: NSEvent) -> NSEvent? {
        guard mode == .none,
              let window = event.window,
              let owner = owner(for: window),
              let contentView = window.contentView else { return event }
        let point = event.locationInWindow

        // 红绿灯在标题栏上层，但 contentView 铺满整窗；必须先放行标准窗口按钮，
        // 否则点击会命中背后的侧栏/标签条并被当成拖窗口。
        if FFWindowChrome.hitsStandardButton(window: window, point: point) {
            FFDebug.log("[WINDOWCHROME] 放行系统窗口按钮 point=\(point)")
            return event
        }

        guard let hit = contentView.hitTest(point) else { return event }

        let state = currentState(for: owner, windowPoint: point)
        let intent = FFAreaResolver.intent(for: hit, state: state)

        switch intent {
        case .dragPane, .reorderTab, .activateTab:
            // 三者都从「按住标签」起手：条内重排 / 出缓冲拖出 / 点击激活
            guard let item = hit as? PaneTabItemView, let strip = item.strip else {
                return event
            }
            sourceStrip = strip
            sourceSide = strip.side
            sourceIndex = item.index
            sourceRef = FFDragSource(windowID: ObjectIdentifier(owner),
                                     side: strip.side,
                                     index: item.index)
            latestPointer = NSEvent.mouseLocation
            // 起手就记成原位置：若指针一直在缓冲内但没命中插入点，
            // 松手时不能把标签误移到 0。
            currentInsertionIndex = item.index
            dragOwner = owner
            startScreenPoint = NSEvent.mouseLocation
            didExceedThreshold = false
            isTabDragOut = false
            mode = .tabDrag
            FFDebug.log("[TABDRAG] 起手 side=\(strip.side) index=\(item.index) 标题=\(item.titleText)")
            // 2026-10-20 #4：**不消费 mouseDown**。
            // 消费掉的话，AppKit 不再认为本应用持有鼠标，拖到别的 App 上松手时
            // mouseUp 不会回到我们 → 拖拽没有结束，且系统认为鼠标还按着
            // （整个操作系统的点击都失灵）。
            // 现在事件原样放行：窗口 isMovable=false，标题栏不会自己拖窗口，
            // 拖动完全由我们接管，而 mouseUp 一定回来。
            return event

        case .dragWindow:
            guard let window = event.window else { return event }
            if useNativeWindowDrag {
                mode = .none
                // 系统接管整个拖动循环（含 mouseUp/窗口移动合并）。
                // 这里同步调用，返回时本次拖动已结束。
                window.performDrag(with: event)
                return nil
            }
            mode = .windowDrag
            dragOwner = owner
            didExceedThreshold = false
            startScreenPoint = window.convertPoint(toScreen: point)
            startWindowOrigin = window.frame.origin
            windowFrameScheduler.start()
            // 同样不消费：保住鼠标归属，mouseUp 才会回来（见 .tab 分支的说明）
            return event

        case .pressFeedback:
            // 2026-10-20 #4：**不消费事件**。
            // 原来这里返回 nil，把 mouseDown / mouseUp 都吞了，于是
            // 点文件、点工具栏按钮、点侧栏行全部没反应；
            // 而且每一次点击的 mouseDown 都被吞，若拖出窗口外松手，
            // mouseUp 回不来 → 系统认为鼠标还按着 → 整个系统的点击都失灵。
            mode = .press
            // 按命中视图所属的面板取卡片。旧实现用 sourceSide，而它只在
            // 上次拖标签时才被写入——点右面板会闪左面板。
            pressedCard = owner.paneSide(containing: hit).flatMap { owner.paneCard(for: $0) }
            applyPressFeedback()
            return event

        case .resizeDivider:
            // 命中调宽把手：事件原样放行，`FFSplitView.mouseDown` 接手调宽。
            // 关键：不设 mode——本控制器对这次按下完全不参与，
            // 「拖窗口」与「调宽」两个手势不再打架（2026-10-20 第五轮）。
            return event

        case .marqueeSelect, .handledByControl:
            return event
        }
    }

    /// 当前状态快照（决策表需要的维度；含「是否命中调宽把手」）
    private func currentState(for owner: MainWindowController,
                              windowPoint: NSPoint) -> FFInteractionState {
        FFInteractionState(sidebarVisible: owner.isSidebarVisible,
                           singlePane: owner.isSinglePaneMode,
                           pointerInsideTabBuffer: true,
                           onResizeHandle: owner.isPointOnResizeHandle(windowPoint: windowPoint))
    }

    private func handleDragged(_ event: NSEvent) -> NSEvent? {
        switch mode {
        case .none:
            return event
        case .windowDrag:
            guard let window = dragOwner?.window else { return nil }
            // 用**事件自带的位置**而不是 NSEvent.mouseLocation：
            // 后者是真实光标位置，应用内合成事件时不会变。
            let now = event.locationInWindow
            let nowScreen = window.convertPoint(toScreen: now)
            latestPointer = nowScreen
            windowFrameScheduler.update(nowScreen)
            if !didExceedThreshold {
                let dx = nowScreen.x - startScreenPoint.x
                let dy = nowScreen.y - startScreenPoint.y
                guard hypot(dx, dy) > FFPaneDrag.threshold else { return nil }
                didExceedThreshold = true
            }
            return nil
        case .press:
            // 按压反馈期间不干预拖动（列表内部的拖拽、框选都要正常）
            return event
        case .tabDrag:
            return handleTabDragged()
        }
    }

    private func handleTabDragged() -> NSEvent? {
        guard dragOwner != nil else { return nil }
        let now = NSEvent.mouseLocation
        latestPointer = now
        if !didExceedThreshold {
            let dx = now.x - startScreenPoint.x
            let dy = now.y - startScreenPoint.y
            guard hypot(dx, dy) > FFPaneDrag.threshold else { return nil }
            didExceedThreshold = true
        }

        if !isTabDragOut {
            // 还在源窗口的标签条缓冲内 → 重排
            if let strip = sourceStrip,
               let window = dragOwner?.window,
               !isOutsideStripBuffer(strip, screenPoint: now) {
                let winPoint = window.convertPoint(fromScreen: now)
                if let index = strip.insertionIndex(atWindowPoint: winPoint) {
                    currentInsertionIndex = index
                    strip.showInsertionIndicator(atIndex: index)
                }
                return nil
            }
            // 出缓冲 → 升级为「拖出这个标签」
            isTabDragOut = true
            os_signpost(.event, log: dragLog, name: "FFDrag.begin")
            sourceStrip?.hideInsertionIndicator()
            beginTabGhost()
            refreshGeometryForDragStart()
            frameScheduler.start()
        }

        // 事件本身只记录最新指针；浮层与落点由 60Hz 帧调度处理。
        frameScheduler.update(now)
        return nil
    }

    private func refreshGeometryForDragStart() {
        for weakOwner in registeredOwners {
            if let owner = weakOwner.value {
                geometryCache.update(for: owner)
            }
        }
        dragGeometries = geometryCache.all()
    }

    private func processDragFrame(at point: CGPoint) {
        os_signpost(.begin, log: dragLog, name: "FFDrag.frame")
        defer { os_signpost(.end, log: dragLog, name: "FFDrag.frame") }
        guard isTabDragOut, let source = sourceRef else { return }
        moveGhost(to: point)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: point,
                                              geometries: dragGeometries)
        if decision != currentDecision {
            currentDecision = decision
            applyOverlay(for: decision)
            os_signpost(.event, log: dragLog, name: "FFDrag.decision")
            FFDebug.log("[TABDRAG] 决策=\(String(describing: decision))")
        }
    }

    private func processWindowDragFrame(at screenPoint: CGPoint) {
        os_signpost(.begin, log: dragLog, name: "FFDrag.windowFrame")
        defer { os_signpost(.end, log: dragLog, name: "FFDrag.windowFrame") }
        guard mode == .windowDrag, let window = dragOwner?.window else { return }
        window.setFrameOrigin(NSPoint(x: startWindowOrigin.x + (screenPoint.x - startScreenPoint.x),
                                      y: startWindowOrigin.y + (screenPoint.y - startScreenPoint.y)))
    }

    private func handleUp(_ event: NSEvent) -> NSEvent? {
        let wasMode = mode
        let moved = didExceedThreshold
        let wasTabDragOut = isTabDragOut
        let strip = sourceStrip
        let draggedSide = sourceSide
        let from = sourceIndex
        let to = currentInsertionIndex
        let decision = currentDecision
        mode = .none
        didExceedThreshold = false
        isTabDragOut = false
        frameScheduler.stop()
        sourceStrip = nil
        sourceRef = nil
        currentDecision = nil
        dragGeometries = []
        endHighlight()

        switch wasMode {
        case .none:
            return event
        case .windowDrag:
            windowFrameScheduler.stop()
            os_signpost(.event, log: dragLog, name: "FFDrag.windowEnd")
            // 没超过阈值的按下是点击，mouseUp 必须放行给下面的视图
            // （侧栏品牌名 / 自绘药丸都靠 mouseUp 触发动作）。
            return moved ? nil : event
        case .press:
            removePressFeedback()
            pressedCard = nil
            return event
        case .tabDrag:
            FFDebug.log("[TABDRAG] 松手 moved=\(moved) 出缓冲=\(wasTabDragOut) 决策=\(String(describing: decision)) dragOwner=\(dragOwner != nil)")
            os_signpost(.event, log: dragLog, name: "FFDrag.drop")
            strip?.hideInsertionIndicator()
            guard let sourceOwner = dragOwner else { return nil }
            dragOwner = nil

            if wasTabDragOut {
                endGhost()
                switch decision {
                case .some(.reorder(_, _, let index)):
                    sourceOwner.moveTab(side: draggedSide, from: from, to: index)
                case .some(.merge(let windowID, let targetSide, let index)):
                    guard let target = owner(for: windowID) else { break }
                    sourceOwner.transferTab(side: draggedSide, index: from,
                                            to: .tabStrip(window: target, side: targetSide, index: index))
                case .some(.split(let windowID, let dropSide)):
                    guard let target = owner(for: windowID) else { break }
                    sourceOwner.transferTab(side: draggedSide, index: from,
                                            to: .paneContent(window: target, side: dropSide))
                case .some(.newWindow):
                    sourceOwner.detachTabToNewWindow(side: draggedSide, index: from,
                                                     atScreenPoint: latestPointer)
                case .some(.returnToSource), .none:
                    break
                }
            } else if moved {
                // 条内重排
                sourceOwner.moveTab(side: draggedSide, from: from, to: to)
            } else {
                // 没移动 → 视为点击标签：选中它
                sourceOwner.selectTab(side: draggedSide, index: from)
            }
            os_signpost(.event, log: dragLog, name: "FFDrag.end")
            return nil
        }
    }

    // MARK: 判定

    /// 指针是否离开了「标签条矩形 + 20pt 缓冲」
    ///
    /// 2026-10-20 第五轮修复：**坐标系必须先统一**。
    /// `strip.convert(strip.bounds, to: nil)` 是**窗口坐标**（y≈864..900），
    /// 而 `NSEvent.mouseLocation` 是**屏幕坐标**（y 可能是 1028）——
    /// 直接比较 y 永远对不上，缓冲判定恒为「已出条」，
    /// 表现就是**条内重排整个失效、一碰标签就被判成拖出**。
    /// 先把屏幕点转成窗口点再比较。
    private func isOutsideStripBuffer(_ strip: PaneTabStripView, screenPoint: NSPoint) -> Bool {
        guard let window = strip.window else { return true }
        let frame = strip.convert(strip.bounds, to: nil)
        let buffer = frame.insetBy(dx: -FFPaneDrag.stripBuffer, dy: -FFPaneDrag.stripBuffer)
        let local = window.convertPoint(fromScreen: screenPoint)
        return !buffer.contains(local)
    }

    /// 把纯决策渲染成浮层/插入线/描边。
    private func applyOverlay(for decision: FFDropDecision?) {
        guard let decision else {
            sourceStrip?.hideInsertionIndicator()
            endHighlight()
            return
        }
        switch decision {
        case .reorder(_, _, let index):
            sourceStrip?.showInsertionIndicator(atIndex: index)
            endHighlight()
        case .merge(let windowID, let targetSide, let index):
            guard let target = owner(for: windowID),
                  let strip = target.tabStrip(for: targetSide) else { return }
            if let index {
                strip.showInsertionIndicator(atIndex: index)
            }
            showOutline(around: strip)
        case .split(let windowID, let dropSide):
            guard let target = owner(for: windowID) else { return }
            showPaneOutline(owner: target, dropSide: dropSide)
        case .newWindow, .returnToSource:
            sourceStrip?.hideInsertionIndicator()
            endHighlight()
        }
    }

    private func owner(for windowID: ObjectIdentifier) -> MainWindowController? {
        registeredOwners.compactMap { $0.value }.first { ObjectIdentifier($0) == windowID }
    }

    private func showOutline(around view: NSView) {
        guard let host = view.superview else { return }
        let rect = view.convert(view.bounds, to: host).insetBy(dx: 1, dy: 1)
        showOutline(rect: rect, in: host)
    }

    private func showOutline(rect: NSRect, in host: NSView) {
        overlay.showOutline(rect: rect, in: host)
    }

    private func showPaneOutline(owner: MainWindowController, dropSide: PaneSide) {
        let visibleSide = owner.isSinglePaneMode ? owner.activePane : dropSide
        guard let wrapper = owner.paneWrapper(for: visibleSide),
              let host = wrapper.superview else { return }
        let full = wrapper.convert(wrapper.bounds, to: host)
        let rect = dropSide == .left
            ? NSRect(x: full.minX, y: full.minY, width: full.width / 2, height: full.height)
            : NSRect(x: full.midX, y: full.minY, width: full.width / 2, height: full.height)
        showOutline(rect: rect, in: host)
    }

    // MARK: 浮层

    /// 起拖浮层：跟手的是**那个标签**（1:1 标签快照），不是整块面板
    private func beginTabGhost() {
        guard let strip = sourceStrip,
              let item = strip.itemView(at: sourceIndex),
              let window = dragOwner?.window else { return }

        // 抓取点在标签内的相对位置，浮层要保持它不动
        let itemFrame = item.convert(item.bounds, to: nil)
        let grab = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        grabOffset = NSPoint(x: grab.x - itemFrame.minX, y: grab.y - itemFrame.minY)
        overlay.beginGhost(from: item,
                           at: NSEvent.mouseLocation,
                           grabOffset: grabOffset)
    }

    private func moveGhost(to screenPoint: NSPoint) {
        overlay.moveGhost(to: screenPoint, grabOffset: grabOffset)
    }

    private func endGhost() {
        overlay.end()
    }

    // MARK: 落点高亮

    private func endHighlight() {
        overlay.hideOutline()
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
