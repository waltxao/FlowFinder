import Cocoa
import Combine
import QuickLook
import Quartz

/// 自定义 NSSplitView 子类：任务 R5 — divider 悬停高亮
/// v0.7.6 发布后修复轮：亮点跟随鼠标 Y（上下各 60pt 渐隐）+ 拖动绝对跟随（禁隐式动画消迟滞）。
/// 2026-10-20 #8：分隔发光条与 hover 高亮**全部移除**，把手改到「面板卡片的边缘」，
/// 用户直接拖卡片外沿调宽，不必瞄准缝隙正中那条看不见的线。
class FFSplitView: NSSplitView {

    /// 手动拖拽状态（dividerThickness=0 时 NSSplitView 内置拖拽不生效）
    private var isDragging = false

    /// 鼠标按下瞬间与分隔线的水平偏移。
    /// 把手在卡片外沿、与分隔线差 8pt；不记这个偏移的话，按下瞬间卡片会跳 8pt。
    private var grabOffset: CGFloat = 0

    /// 当前可见子视图数。单窗口模式下另一侧 isHidden，此时不应响应分隔线拖拽
    /// （否则可以把隐藏面板拖出来，与单窗状态冲突）
    private var visibleSubviewCount: Int { subviews.filter { !$0.isHidden }.count }

    /// v0.6.9: divider 厚度为 0（移除可见分割线，间隙由卡片边距提供）
    override var dividerThickness: CGFloat {
        return 0
    }

    /// 把手位置（split 自身坐标系）。
    ///
    /// 2026-10-20 #8：把手贴在**面板卡片的外沿**——
    /// 双操作区是「左卡片右沿 / 右卡片左沿」，侧栏缝是「操作区左卡片左沿」。
    /// 提供器每次实时求值，布局变化后把手位置自动跟随。
    var handlePositionsProvider: (() -> [CGFloat])?

    /// 命中把手时的光标
    var handleCursor: NSCursor = .resizeLeftRight

    /// 左侧子视图最小宽度。侧栏分隔用 160（DESIGN-SPEC B-01），双操作区用 450。
    /// 分隔线厚度为 0 时系统不接管拖拽，最小/最大值只能由本类自行 clamp。
    var leadingMinWidth: CGFloat = FFDividerGlowMath.minPaneWidth

    /// 右侧子视图最小宽度（双操作区两侧各 450；侧栏分隔右侧为操作区，同样按 450 保底）
    var trailingMinWidth: CGFloat = FFDividerGlowMath.minPaneWidth

    /// 左侧子视图最大宽度（侧栏 280；双操作区不限）
    var leadingMaxWidth: CGFloat?

    /// 当前把手 X 列表
    private var handlePositions: [CGFloat] { handlePositionsProvider?() ?? [] }

    /// 分隔线当前 X（左子视图右边缘）。仅限静止状态回读；
    /// 拖动中必须使用 applyDividerPosition 返回的计算值（布局可能滞后一拍）。
    private var currentDividerX: CGFloat {
        return subviews.count >= 2 ? subviews[0].frame.maxX : 0
    }

    /// 鼠标是否落在某个把手上
    private func handleHit(atX x: CGFloat) -> Bool {
        handlePositions.contains { abs(x - $0) <= FFDividerGlowMath.hotZoneRadius }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard visibleSubviewCount >= 2 else {
            NSCursor.arrow.set()
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        if handleHit(atX: loc.x) {
            handleCursor.set()
        } else if !isDragging {
            NSCursor.arrow.set()
        }
    }

    /// 绝对跟随：分隔线目标位置一律取 clamp(鼠标X + 偏移)，返回实际生效的位置。
    /// 按下瞬间即对齐鼠标正下方（跳动 ≤ 热区半径 6pt）。
    @discardableResult
    private func applyDividerPosition(mouseX: CGFloat) -> CGFloat {
        let raw = FFDividerGlowMath.clampedDividerPosition(
            mouseX: mouseX,
            boundsWidth: bounds.width,
            leadingMin: leadingMinWidth,
            trailingMin: trailingMinWidth
        )
        let clamped = leadingMaxWidth.map { min(raw, $0) } ?? raw
        setPosition(clamped, ofDividerAt: 0)
        return clamped
    }

    /// 命中把手（±6pt）：按下即对齐并进入拖拽；未命中：交给系统处理
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard visibleSubviewCount >= 2, handleHit(atX: point.x) else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        // 记住「鼠标 ↔ 分隔线」的偏移：把手在卡片外沿，与分隔线相差一个卡片留白
        grabOffset = currentDividerX - point.x
        let effectiveX = applyDividerPosition(mouseX: point.x + grabOffset)
        _ = effectiveX
        handleCursor.set()
    }

    /// 拖拽全程 1:1 跟随鼠标 X（绝对模型 + 起始偏移，无起点记账）
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, visibleSubviewCount >= 2 else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        applyDividerPosition(mouseX: point.x + grabOffset)
    }

    /// 拖拽结束
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
        } else {
            super.mouseUp(with: event)
        }
        let loc = convert(event.locationInWindow, from: nil)
        if !handleHit(atX: loc.x) {
            NSCursor.arrow.set()
        }
    }
}

// MARK: - OpaqueContainerView

/// 重写 isOpaque 返回 true 的 NSView 子类。
///
/// 根因修复：当 window.isOpaque=false 且 backgroundColor=.clear 时，macOS 窗口服务器
/// 使用逐像素 alpha 决定鼠标事件捕获。普通 NSView 的 isOpaque 默认返回 false，
/// 且其 layer 背景为 clear（alpha=0），导致整个窗口对所有像素透明——鼠标事件全部穿透。
///
// FFOpaqueContainerView 已提取到 FFCommon.swift（统一实体背景容器）
// 原 OpaqueContainerView 已由 FFOpaqueContainerView 替代

// MARK: - FFSidebarRevealHost

/// 侧栏隐藏后窗口左上角的「显示侧栏」开关（2026-10-19 #10）。
///
/// 铺满整个内容区，但只有按钮本身接收点击（`hitTest` 对非按钮区域返回 nil），
/// 因此不会挡住文件列表。按钮位置在 `layout()` 里按红绿灯的真实位置反算——
/// 写死坐标在换机器 / 全屏切换后会错位。
final class FFSidebarRevealHost: NSView {

    let button = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = FFIcon.template(.panelLeftOpen, size: 16)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "显示侧边栏 (⌥⌘S)"
        addSubview(button)
    }

    /// 除按钮外不吃事件：文件列表的点击/拖拽要能穿透过去
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 24
        var x: CGFloat = 12
        var centerFromTop: CGFloat = 26

        if let window,
           !window.styleMask.contains(.fullScreen),
           let close = window.standardWindowButton(.zoomButton) ?? window.standardWindowButton(.closeButton),
           let closeSuperview = close.superview {
            let rectInWindow = closeSuperview.convert(close.frame, to: nil)
            let maxX = convert(NSPoint(x: rectInWindow.maxX, y: 0), from: nil).x
            let center = convert(NSPoint(x: rectInWindow.midX, y: rectInWindow.midY), from: nil)
            if maxX.isFinite, center.y.isFinite {
                x = maxX + 8
                centerFromTop = bounds.height - center.y
            }
        }

        button.frame = NSRect(x: x,
                              y: bounds.height - centerFromTop - size / 2,
                              width: size,
                              height: size)
    }
}

// MARK: - MainWindowController

public class MainWindowController: NSWindowController {

    /// 撤销/重做文件操作串行队列：保证 undo 与 redo 的文件操作按序执行，
    /// 避免快速 ⌘Z→⌘⇧Z 时 redo 文件操作与仍在飞行的 undo 文件操作重叠（问题 9）。
    /// internal 访问：FileListView/FileGridView 的拖拽撤销也需经此队列串行化。
    internal static let undoRedoQueue = DispatchQueue(label: "FlowFinder.UndoRedo.Serial")

    // MARK: - Properties

    /// 侧栏默认宽度（DESIGN-SPEC B-01）。访达侧栏约 210–220pt，取 220。
    static let sidebarDefaultWidth: CGFloat = 220
    /// 侧栏可拖最小宽度
    static let sidebarMinWidth: CGFloat = 160
    /// 侧栏可拖最大宽度
    static let sidebarMaxWidth: CGFloat = 280
    /// 侧栏宽度记忆键
    private static let sidebarWidthKey = "sidebar_width"
    /// 2026-10-20 #8：左操作面板宽度记忆键（双面板中缝拖动后的结果）
    private static let paneLeftWidthKey = "pane_left_width"
    /// 2026-10-18 #3：单/双窗口模式记忆键
    static let singlePaneModeKey = "single_pane_mode"
    /// 2026-10-19 #10：侧栏隐藏状态记忆键
    private static let sidebarHiddenKey = "sidebar_hidden"

    /// 2026-10-19 #10：侧栏隐藏动画时长（DESIGN-SPEC：0.18s 滑出）
    private static let sidebarAnimationDuration: TimeInterval = 0.18

    /// 读取上次拖拽记忆的侧栏宽度，落在 [min, max] 内才采用
    /// 恢复左操作面板宽度（双面板中缝位置）；0 表示没有记忆
    static func restoredPaneLeftWidth() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: paneLeftWidthKey)
        return saved > 0 ? saved : 0
    }

    static func restoredSidebarWidth() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: sidebarWidthKey)
        guard saved >= Double(sidebarMinWidth), saved <= Double(sidebarMaxWidth) else {
            return sidebarDefaultWidth
        }
        return CGFloat(saved)
    }

    let leftPaneViewModel = PaneViewModel()
    let rightPaneViewModel = PaneViewModel()
    var activePane: PaneSide = .left
    /// 防抖: 选中变更工作项，用于取消上一次未完成的 UI 更新，防止快速点击时窗口跳动
    private var selectionChangeWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// 全局撤销/重做栈（per-window）。通过覆盖 undoManager 计算属性让响应链使用它，
    /// Edit 菜单的 undo:/redo: 通过响应链自动路由到此 UndoManager。
    let ffUndoManager = UndoManager()

    /// 覆盖 NSResponder 的 undoManager，让响应链返回自定义的 UndoManager。
    override public var undoManager: UndoManager? {
        ffUndoManager
    }

    var sidebarView: SidebarView!
    internal var leftPaneContainer: NSView!
    private var rightPaneContainer: NSView!
    /// #3：分栏两端的卡片包装视图（单窗模式靠 isHidden 收起一侧）
    var leftPaneWrapper: NSView!
    var rightPaneWrapper: NSView!
    /// #3：当前是否单窗口模式（持久化到 single_pane_mode）
    var isSinglePaneMode = false
    /// #7：每个操作区顶部标签条与标签集合
    var leftTabStrip: PaneTabStripView?
    var rightTabStrip: PaneTabStripView?
    var leftTabsStore: PaneTabsStore?
    var rightTabsStore: PaneTabsStore?
    /// #3：标签条高度约束（单标签时收到 0，工具栏顶到卡片顶部）
    var leftTabStripHeight: NSLayoutConstraint?
    var rightTabStripHeight: NSLayoutConstraint?
    /// 标签条展开高度（DESIGN-SPEC T-10）
    /// 2026-10-20 #1：标签条提到窗口顶部那一行，与红绿灯同高 28pt
    /// 标签条高度 = 标题带高度（2026-10-20 #4：28 → 36，让标签上方留 8pt 间隙）
    static let tabStripHeight: CGFloat = FFInteractionPolicy.titleBandHeight
    /// #5：进入单窗口模式前的窗口宽度，切回双窗口时还原
    private var widthBeforeSinglePane: CGFloat?
    /// #5：上次真正应用的模式（nil = 还没完成过一次「带缩放」的切换）。
    /// 用它区分「双→单」的首次切换与「单窗内切活动面板」，避免反复缩放窗口。
    private var appliedSinglePaneMode: Bool?
    /// 切模式导致的程序化窗口/分隔线变更期间为 true：此时不写 `sidebar_width`
    private var isAdjustingPaneMode = false

    /// 单双面板切换动画进行中（窗口宽度改走 animator）
    private var isAnimatingPaneMode = false
    /// 2026-10-19 #10：侧栏是否可见（隐藏后窗口左上角留一个开关按钮）
    internal var isSidebarVisible = true
    /// 主分栏左侧最小宽度覆盖值：侧栏收起 / 动画期间为 0（默认取 sidebarMinWidth）
    private var sidebarMinWidthOverride: CGFloat?
    /// 隐藏前记住的侧栏宽度（分隔线归零后 frame 宽度就取不到了）
    private var savedSidebarWidthWhileHidden: CGFloat?
    /// 侧栏显隐动画定时器（按 0.18s 插值 divider 位置）
    private var sidebarAnimationTimer: Timer?
    /// 侧栏隐藏后左上角的「显示侧栏」开关
    private var sidebarRevealHost: FFSidebarRevealHost?
    /// 1.2 活动面板描边（替代原 2pt 色条——色条被工具栏盖住，从未可见）
    internal var leftActiveBorder: FFActivePaneBorderView!
    private var rightActiveBorder: FFActivePaneBorderView!
    private var leftDetailsBar: ExpandableDetailsBar!
    private var rightDetailsBar: ExpandableDetailsBar!
    var taskProgressBar: TaskProgressBar!
    /// 任务 F11-9：底部进度栏高度约束（0=收起 / 28=展开，复制/移动/粘贴时动态切换）
    var taskProgressBarHeightConstraint: NSLayoutConstraint!
    private var mainSplitView: FFSplitView!
    internal var paneSplitView: FFSplitView!
    /// 主内容容器引用（ThemeManager 需设置 appearance 以确保选中高亮可见）
    private var mainContainerView: NSView!
    /// 诊断：鼠标事件监听器（必须强引用，否则会被立即释放）
    private var mouseEventMonitor: Any?
    /// 全局键盘拦截（空格/Enter/Del 统一处理，见 setup 中注释）
    private var keyEventMonitor: Any?

    // Wave2：以下面板控件引用改为 internal——MainWindowController+MenuActions 跨文件扩展
    // 需要（menuSearch 聚焦工具栏、menuRename 调用面板 actionsController 等）
    var leftPaneToolbar: PaneToolbar!
    var rightPaneToolbar: PaneToolbar!
    private var leftBreadcrumbBar: BreadcrumbBar!
    private var rightBreadcrumbBar: BreadcrumbBar!
    var leftFileListView: FileListView!
    var rightFileListView: FileListView!
    var leftFileGridView: FileGridView!
    var rightFileGridView: FileGridView!

    // Clipboard support (must be in main class, not extension)
    var clipboardItems: [String] = []
    var clipboardOperation: ClipboardOperation?

    /// F9-C: 「显示简介」独立窗口控制器（强引用，避免窗口被立即释放）。
    /// 每次显示时复用同一控制器并切换文件路径（仿访达可切换内容的 Get Info 窗口）。
    var fileInfoWindowController: FileInfoWindowController?

    enum ClipboardOperation {
        case copy
        case cut
    }

    // MARK: - Initialization

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FlowFinder"
        // #7：改用应用内标签条，关闭系统窗口标签，避免两套标签并存
        window.tabbingMode = .disallowed
        // 最小尺寸按「侧栏最小 160 + 两个操作区各 450」推导 = 1060（DESIGN-SPEC W-07）。
        // 原值 1000 与 pane 的 450 保底自相矛盾：1000 − 160 = 840，两个 pane 各 420，
        // 会触发 NSSplitView 约束冲突并把工具栏控件挤重叠。
        window.minSize = NSSize(width: 1060, height: 700)
        window.center()
        // 注意：不要在这里 makeKeyAndOrderFront！
        // 必须先完成 setupUI（设置 isOpaque=false, backgroundColor=.clear, NSVisualEffectView），
        // 然后再显示窗口，否则窗口会以不透明状态先渲染一次
        // window.makeKeyAndOrderFront(nil)
        // 不使用 autosave，避免加载之前保存的小窗口尺寸
        // window.setFrameAutosaveName("MainWindow")
        // window.isRestorable = true

        super.init(window: window)

        // 确保窗口可以接收键盘事件
        window.acceptsMouseMovedEvents = true

        setupUI()

        // #3：恢复单/双窗口模式（须在 setupUI 创建完两栏包装视图之后）
        isSinglePaneMode = UserDefaults.standard.bool(forKey: Self.singlePaneModeKey)
        applyPaneMode()

        // 窗口距顶部保留 8pt 间距
        var frame = window.frame
        let screenHeight = NSScreen.main?.frame.height ?? 900
        let topGap: CGFloat = 8
        frame.origin.y = screenHeight - frame.size.height - topGap
        window.setFrame(frame, display: true)

        setupBindings()
        setupNotifications()
        loadInitialDirectories()
        // 布局稳定后对齐标签条、吐一次面板几何（自动化拖拽测试用）
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView?.layoutSubtreeIfNeeded()
            self?.updateTabStripFrames()
            self?.logPaneGeometry(" 启动")
        }

        // Wave2 P0-4（多窗口）：FSEvents 文件系统监控已上移至 AppDelegate 进程级单实例
        // （CoreBridge 的 watcher 重复 start 会顶掉旧 watcher），本窗口经
        // .fileSystemDidChange 通知接收变更并刷新受影响面板（setupNotifications 注册）。

        // setupUI 完成后再显示窗口（此时透明设置已就绪）
        window.makeKeyAndOrderFront(nil)

        #if DEBUG
        // 拖放落点自检：仅当以 FF_SELFTEST=1 启动时运行，结果写入 /tmp/ff-debug.log
        if ProcessInfo.processInfo.environment["FF_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.runDragSelfTest()
                self?.runInteractionPolicySelfTest()
                self?.runRegionResolveSelfTest()
                self?.runDragBehaviorSelfTest()
                self?.runTabWeldSelfTest()
                self?.runListShellSelfTest()
            }
        }
        #endif
        // #5：启动即单窗模式时，上面那次 applyPaneMode 还没有真实布局宽度可用，
        // 等首个布局周期结束后再补一次「收窄窗口」
        if isSinglePaneMode {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isSinglePaneMode, self.appliedSinglePaneMode != true else { return }
                self.applyPaneMode()
            }
        }
        FFDebug.log("Window state: isKey=\(window.isKeyWindow) isMain=\(window.isMainWindow) isVisible=\(window.isVisible) frame=\(window.frame) ignoresMouseEvents=\(window.ignoresMouseEvents)")
        if let cv = window.contentView {
            FFDebug.log("contentView: type=\(type(of: cv)) frame=\(cv.frame) subviews=\(cv.subviews.map { "\(type(of: $0))" })")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSWindowDelegate (窗口状态跟踪)

    /// 窗口成为 key window（可接收键盘+鼠标事件）时触发。
    /// 修复验证：此前日志显示 isKey=false，导致鼠标事件无法到达。
    public func windowDidBecomeKey(_ notification: Notification) {
        FFDebug.log("windowDidBecomeKey: window is now key window")
    }

    /// 返回自定义 UndoManager，确保 Edit 菜单的 撤销/重做 使用 ffUndoManager。
    public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        ffUndoManager
    }

    public func windowDidResignKey(_ notification: Notification) {
        FFDebug.log("windowDidResignKey: window lost key status")
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        FFDebug.log("windowDidBecomeMain: window is now main window")
    }

    public func windowDidResignMain(_ notification: Notification) {
        FFDebug.log("windowDidResignMain: window lost main status")
    }

    /// Wave2 P0-4（多窗口）：窗口关闭时通知 AppDelegate 移除强引用（仅新窗口在 extras 数组，
    /// 首窗口不在数组内移除为空操作），避免已关闭窗口的控制器残留
    public func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.unregisterWindowController(self)
        sidebarAnimationTimer?.invalidate()
        sidebarAnimationTimer = nil
    }

    // MARK: B6 #3 全屏进出（侧栏宽度固定 + 顶部重排 + 退出恢复宽度）

    /// 进入全屏：侧栏宽度由 holdingPriority 锁定（260 > 240），增量全进操作区；
    /// 顶部三图标与名称区的对齐在 SidebarView.layout() 里按红绿灯反算，随重排自动生效。
    public func windowDidEnterFullScreen(_ notification: Notification) {
        guard sidebarView != nil else { return }
        sidebarView.needsLayout = true
        sidebarView.layoutSubtreeIfNeeded()
    }

    /// 退出全屏：窗口回到原 frame。保险起见把侧栏位置钉回记忆宽度，
    /// 防止某些系统版本 divider 漂移把侧栏带歪；动画期间不写 sidebar_width。
    /// 侧栏处于隐藏态时不动作（divider 应保持 0）。
    public func windowDidExitFullScreen(_ notification: Notification) {
        guard let split = mainSplitView, sidebarView != nil else { return }
        if isSidebarVisible {
            let remembered = max(MainWindowController.sidebarMinWidth,
                                 MainWindowController.restoredSidebarWidth())
            isAdjustingPaneMode = true
            split.setPosition(remembered, ofDividerAt: 0)
            isAdjustingPaneMode = false
        }
        sidebarView.needsLayout = true
        sidebarView.layoutSubtreeIfNeeded()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else {
            FFDebug.log("setupUI: window is nil!")
            return
        }
        FFDebug.log("setupUI: started, window=\(window.frame)")

        // 窗口必须透明，否则玻璃效果无法模糊窗口背后的内容
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 2026-10-20 #1：关掉系统对标题栏/背景的窗口拖动。
        // 窗口顶部 28pt 是系统标题栏的拖动区，正好压在操作面板工具栏第一行上——
        // 于是「按住操作面板拖动」拖走的是整个窗口。关掉之后由 FFWindowDrag 按区域放行：
        // 侧栏空白与面板卡片四周留白可拖窗口，操作面板本体改为拖面板。
        window.isMovable = false
        window.title = "FlowFinder"
        // #7：改用应用内标签条，关闭系统窗口标签，避免两套标签并存
        window.tabbingMode = .disallowed

        // 任务 F10-1: 设置 window.delegate，使 windowDidBecomeKey 等回调生效（v0.6.6）
        // 虽然 NSWindowController 父类在 ObjC 层已声明 <NSWindowDelegate>，
        // 但 Swift 编译器仍要求显式声明 extension MainWindowController: NSWindowDelegate
        // 才能将 self 赋值给 (any NSWindowDelegate)?（见文件末 extension）
        // 修复问题15/16 右键菜单不生效的潜在根因
        window.delegate = self

        // Sidebar
        sidebarView = SidebarView()
        sidebarView.translatesAutoresizingMaskIntoConstraints = false

        // 左面板（工具栏 + 文件列表 + DetailsBar）—— 任务 R4: 操作区背景色
        leftPaneContainer = createPaneContainer(side: .left)
        rightPaneContainer = createPaneContainer(side: .right)

        // Pane Split View（左右操作区）— 任务 R5: 使用 FFSplitView 实现 divider 悬停高亮
        paneSplitView = FFSplitView()
        paneSplitView.isVertical = true
        paneSplitView.dividerStyle = .thin
        paneSplitView.translatesAutoresizingMaskIntoConstraints = false
        paneSplitView.delegate = self
        paneSplitView.wantsLayer = true
        paneSplitView.layer?.backgroundColor = NSColor.clear.cgColor
        // 问题13修复：左右操作区用圆角卡片包裹，四周留 8pt 边距使圆角在所有边可见
        leftPaneWrapper = makeCardWrapper(for: leftPaneContainer, side: .left)
        rightPaneWrapper = makeCardWrapper(for: rightPaneContainer, side: .right)
        paneSplitView.addArrangedSubview(leftPaneWrapper)
        paneSplitView.addArrangedSubview(rightPaneWrapper)

        // Main Split View（侧边栏 + 操作区）
        // 2026-10-17：改用 FFSplitView，使侧栏宽度可拖（DESIGN-SPEC B-01 160–280）。
        // 原先用无分割线私有子类，dividerThickness=0 时系统不接管拖拽，侧栏宽度被
        // 硬编码 220 固定，用户无法调整——规格里写了「可拖」但实现没有。
        // FFSplitView 自带热区命中 + 渐变亮线 + 绝对跟随拖拽，正好复用。
        let mainSplit = FFSplitView()
        mainSplit.leadingMinWidth = MainWindowController.sidebarMinWidth
        mainSplit.trailingMinWidth = FFDividerGlowMath.minPaneWidth
        mainSplitView = mainSplit
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false
        mainSplitView.delegate = self
        mainSplitView.wantsLayer = true
        mainSplitView.layer?.backgroundColor = NSColor.clear.cgColor
        mainSplitView.addArrangedSubview(sidebarView)
        mainSplitView.addArrangedSubview(paneSplitView)

        // 2026-10-20 #8：把手贴在「面板卡片的外沿」，不再瞄准缝隙正中那条隐形线。
        //   - 双操作区：左卡片右沿 + 右卡片左沿（两处都调同一条分界：左宽右窄）
        //   - 侧栏缝  ：操作区左卡片的左沿（往左拖 = 侧栏变窄）
        // 上下边缘不设把手——面板高度由窗口高度接管。
        paneSplitView.handlePositionsProvider = { [weak self] in
            guard let self,
                  let left = self.leftPaneWrapper,
                  let right = self.rightPaneWrapper else { return [] }
            let out = FFActivePaneBorderView.edgeOutset
            return [left.frame.maxX - out, right.frame.minX + out]
        }
        mainSplitView.handlePositionsProvider = { [weak self] in
            guard let self, let paneSplit = self.paneSplitView else { return [] }
            return [paneSplit.frame.minX + FFActivePaneBorderView.edgeOutset]
        }
        // 侧栏宽度上限 280（DESIGN-SPEC B-01）
        mainSplit.leadingMaxWidth = MainWindowController.sidebarMaxWidth

        // Task Progress Bar
        taskProgressBar = TaskProgressBar()
        taskProgressBar.translatesAutoresizingMaskIntoConstraints = false

        // 任务 F7: 使用 OpaqueContainerView 修复鼠标穿透与选中渲染（v0.6.5）
        // mainContainer（透明背景以透出玻璃效果）
        let mainContainer = FFOpaqueContainerView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        mainContainer.layer?.backgroundColor = NSColor.clear.cgColor
        mainContainer.addSubview(mainSplitView)

        // 2026-10-20 #3：标签条已在 `makeCardWrapper` 里挂到各自的卡片包裹
        // 视图上（wrapper 横跨面板全宽、随分栏自动伸缩），这里不再重复添加。
        mainContainer.addSubview(taskProgressBar)
        taskProgressBar.isHidden = true

        // 任务 F10-1: 移除 titlebarView 占位，mainSplitView 顶到顶部（v0.6.6）
        // 红绿灯由系统自动浮在侧边栏顶部上方（titlebarAppearsTransparent=true）
        // 侧边栏内部顶部留出红绿灯安全区（由 SidebarView 处理）
        // mainSplitView 的 divider 提供 1pt 发丝线（dividerStyle=.thin）
        // 任务 F11-9：底部进度栏使用动态高度约束（0=收起 / 28=展开），
        // mainSplitView.bottomAnchor 锚定到 taskProgressBar.topAnchor，
        // 这样进度栏展开时会将操作区整体上推，不会遮挡文件列表底部内容。
        taskProgressBarHeightConstraint = taskProgressBar.heightAnchor.constraint(equalToConstant: 0)
        taskProgressBarHeightConstraint.priority = .required
        NSLayoutConstraint.activate([
            // mainSplitView 顶到 mainContainer 顶部（红绿灯浮在上方）
            mainSplitView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            // mainSplitView 底部锚定到 taskProgressBar 顶部，进度栏展开时上推操作区
            mainSplitView.bottomAnchor.constraint(equalTo: taskProgressBar.topAnchor),

            taskProgressBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            taskProgressBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            taskProgressBar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            taskProgressBarHeightConstraint,
        ])

        // 统一使用 NSVisualEffectView 作为窗口背景玻璃
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.addSubview(mainContainer)
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            mainContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
        ])
        mainContainerView = mainContainer

        // 2026-10-18 #4：设备不再以浮动卡片形式挂在这里，改由 SidebarView 的「位置」分区承担
        // （访达同构：个人收藏 / 位置 / 标签 三区）。原有 devicePanel 相关属性与构建代码已删除。

        // 2026-10-19 #9：工具浮动面板已移除——查重 / 批量重命名 / AI 工具改由
        // 程序名称旁的「发现功能」药丸弹出，不再常驻一块会挡住侧栏底部的卡片。

        // 2026-10-18 #4：卷挂载/卸载监听改由 SidebarView 统一处理（它已监听并刷新「位置」分区）

        // 2026-10-19 #10：侧栏隐藏后左上角留一个开关（不展开侧栏，只负责唤回）。
        // 覆盖在内容区之上，除按钮本身外不吃鼠标事件。
        let revealHost = FFSidebarRevealHost()
        revealHost.isHidden = true
        revealHost.button.target = self
        revealHost.button.action = #selector(toggleSidebar(_:))
        mainContainer.addSubview(revealHost)
        NSLayoutConstraint.activate([
            revealHost.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            revealHost.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            revealHost.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            revealHost.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
        ])
        sidebarRevealHost = revealHost

        // 2026-10-20 #3：标签条是浮层，需要跟着分栏逐帧对齐
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowLayout),
            name: NSWindow.didResizeNotification,
            object: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowLayout),
            name: NSWindow.didEndLiveResizeNotification,
            object: window)

        window.contentView = visualEffectView
        // 2026-10-20 #5：窗口圆角改超椭圆 12（与面板同一套曲线；系统圆角是圆形弧，无 API 可改）
        // FF_SKIP_WINDOW_SHAPE=1 可关掉遮罩做对照排查
        if ProcessInfo.processInfo.environment["FF_SKIP_WINDOW_SHAPE"] != "1" {
            FFWindowShape.install(on: window)
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleWindowShapeChange),
                name: name, object: window)
        }

        // 2026-10-20 #1：窗口级面板拖拽控制器。
        // 窗口顶部 28pt 是系统标题栏的拖动区，会先于内容视图吃掉 mouseDown；
        // 这里在事件分发之前接管工具栏/标签条空白，把「拖面板」和「拖窗口」彻底分开。
        FFPaneDragController.shared.register(owner: self, window: window)

        // 窗口外观跟随 ThemeManager 设置（不强制 nil，否则夜间模式无法生效）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.appearance = NSApp.appearance
            self.mainContainerView?.appearance = NSApp.appearance
        }

        // 任务 F7: 监听主题变更，刷新所有 FileListView 的 appearance（v0.6.5）
        // 任务 F10-9: 同时刷新所有 FileGridView 的 appearance（F7 遗漏修复，v0.6.6）
        // 任务 F11-1: 同时刷新操作区/设备栏实体背景色（v0.6.7）
        // onModeChanged 是单回调，需保留前一个回调链，避免覆盖 AppearanceSettingsView 等已注册的监听
        // FileListView / FileGridView 是 NSView（非 ViewController），无 viewDidLayout，故调用 refreshAppearance()
        let previousCallback = ThemeManager.shared.onModeChanged
        ThemeManager.shared.onModeChanged = { [weak self] mode in
            previousCallback?(mode)
            DispatchQueue.main.async {
                self?.leftFileListView?.refreshAppearance()
                self?.rightFileListView?.refreshAppearance()
                self?.leftFileGridView?.refreshAppearance()
                self?.rightFileGridView?.refreshAppearance()
                // 任务 F11-1: 刷新操作区容器与设备栏浮层的实体背景色（日间/夜间切换）
                self?.refreshOperationAreaBackgrounds()
            }
        }

        // 鼠标按下 → 激活点击所在的操作面板（活动面板描边的数据源）。
        // 不能依赖各视图的选中回调：NSTableView/NSCollectionView 只有「选中变化」
        // 才触发 onActivatePane，点击空白区/已选中行/工具栏/详情栏都不会触发，
        // 描边就停在旧面板上。改为在事件分发前按命中视图的归属判定面板。
        // activatePane 内的焦点同步对文本编辑有保护（field editor 不抢焦点），
        // 点搜索框/重命名框不会被夺走焦点。
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self,
                  let win = event.window, win === self.window,
                  let content = win.contentView,
                  let hit = content.hitTest(event.locationInWindow) else { return event }
            if let side = self.paneSideForHitView(hit), side != self.activePane {
                self.activatePane(side)
            }
            return event
        }
        FFDebug.log("NSEvent monitor installed: \(mouseEventMonitor != nil)")

        // 全局键盘拦截（根治空格/Enter/Del 不触发的架构问题）：
        // 键盘事件先经 firstResponder 的 keyDown/interpretKeyEvents 分发，NSTableView/
        // NSCollectionView 会消耗空格/Enter/Del 导致 FileListView/FileGridView 的 keyDown
        // 收不到（多次修复无效的根因）。用 local monitor 在事件分发前统一拦截：
        // 仅当按键命中面板级快捷键（QuickLook/重命名/删除，经 ShortcutCenter 读设置）
        // 且焦点在文件面板且非文本编辑中时拦截。
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window, window.isKeyWindow else { return event }
            // 文本编辑中不拦截（搜索框输入空格/重命名框 Del 删字符/Enter 提交等）：
            // 关键：NSTextField 编辑时 firstResponder 是其内部 field editor（NSTextView），
            // 只判断 NSTextField 会漏掉编辑中的情况 → Del 被误拦成删除文件（用户反馈的 bug）。
            let fr = window.firstResponder
            if fr is NSTextView { return event }  // field editor / 任何文本视图编辑中
            if let tf = fr as? NSTextField, tf.isEditable { return event }
            // Wave2 P0-3：拦截键经 ShortcutCenter 读取设置（默认 空格/Return/Del，行为不变；
            // 用户改键后新键立即生效、旧键不再拦截）
            let isPaneKey = ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutQuicklook, event: event)
                || ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutRename, event: event)
                || ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutDelete, event: event)
            guard isPaneKey else { return event }
            // 焦点必须位于文件面板——按 firstResponder 归属的 FileListView/FileGridView
            // 分派（不依赖 activePane：点击网格时 activePane 可能未更新，导致分派到错误面板）
            guard let frView = window.firstResponder as? NSView,
                  let paneView = self.filePaneView(for: frView) else { return event }
            if let listView = paneView as? FileListView {
                if listView.handlePaneKey(event) { return nil }
            } else if let gridView = paneView as? FileGridView {
                if gridView.handlePaneKey(event) { return nil }
            }
            return event
        }
        FFDebug.log("KeyEvent monitor installed: \(keyEventMonitor != nil)")

        // Holding priorities
        // 2026-10-18 三次修订：侧栏改为「保住宽度」，操作区吸收窗口缩放。
        // 原先是侧栏 .defaultLow，缩窗（含单窗模式按被收起侧宽度收窄）时 NSSplitView
        // 先把侧栏压到最小 160 再动操作区，而 splitViewDidResizeSubviews 又会把 160
        // 写进 sidebar_width —— 单窗切一次，侧栏宽度就被永久压窄。

        mainSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        mainSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        mainSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        mainSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        updateActivePaneVisual()

        // 注入 UndoManager 到各 PaneViewModel
        leftPaneViewModel.undoManager = undoManager
        rightPaneViewModel.undoManager = undoManager

        // Wave1 P0-2：注入底部任务进度条与展开/收起钩子（「用所选项目新建文件夹」
        // 等批量移动操作接直连进度，参考粘贴路径）
        leftPaneViewModel.taskProgressBar = taskProgressBar
        rightPaneViewModel.taskProgressBar = taskProgressBar
        wireBatchMoveProgressHooks()

        // I1: 注入对侧 ViewModel
        leftFileListView.counterpartViewModel = rightPaneViewModel
        rightFileListView.counterpartViewModel = leftPaneViewModel
        leftFileGridView.counterpartViewModel = rightPaneViewModel
        rightFileGridView.counterpartViewModel = leftPaneViewModel

        // Wave2 P0-1：构建窗口级 keyViewLoop（左右面板控件 + 文件视图首尾相接成环），
        // Tab/⇧Tab 沿环流转；初始键盘焦点落在左面板列表（键盘优先工作流起点）
        buildKeyViewLoops()
        window.initialFirstResponder = leftFileListView.keyFocusTarget

        // 初始 divider 位置（侧栏宽度取记忆值，无记忆时 220）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.mainSplitView.setPosition(MainWindowController.restoredSidebarWidth(), ofDividerAt: 0)
            let totalWidth = self.paneSplitView.bounds.width
            if totalWidth > 0 {
                self.paneSplitView.setPosition(totalWidth / 2, ofDividerAt: 0)
            }
            // 2026-10-19 #10：还原上次退出时的侧栏显隐状态（不播动画，避免启动闪一下）
            if UserDefaults.standard.bool(forKey: MainWindowController.sidebarHiddenKey) {
                self.setSidebarVisible(false, animated: false)
            }
            // 任务 F10-3 / Wave1 P0-3: 初始化设备浮层——设备数据已改为后台加载
            // （DeviceSidebarDataSource.init 不再同步 loadDevices），经
            // refreshDevicePanel 触发首次加载，数据就绪后主线程回调重建行 + 更新汇总
            // 2026-10-18 #4：设备区已迁入 SidebarView「位置」分区，此处不再初始化浮层
        }

        // #7：两侧面板就绪后建立初始标签
        installTabStrips()

        TaskSchedulerManager.shared.startPolling()
    }

    /// 为操作区创建包裹视图（卡片四周留白 + 活动面板发光层）。
    ///
    /// 2026-10-18 三次修订：发光必须出现在「操作区边缘」，而不是画在操作区内部。
    /// 因此发光视图挂在包裹视图里、位于卡片**下层**，尺寸铺满包裹视图；卡片四周内缩
    /// `FFActivePaneBorderView.edgeOutset`（8pt）——发光以卡片边界为中心线绘制，
    /// 内半圈被卡片不透明背景盖住，外半圈留在 8pt 留白里向外发散。
    /// 留白同时是发光的外扩空间：最外层描边 13pt（外扩 6.5pt）不会被包裹视图裁掉。
    /// 两个卡片之间经 split divider 分隔，视觉上呈现为左右两张独立圆角卡片。
    private func makeCardWrapper(for content: NSView, side: PaneSide) -> NSView {
        let wrapper = FFCardWrapperView()
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        // 2026-10-20 #3：卡片留白的拖动由窗口级控制器按决策表接管，
        // 这里不再挂回调（否则两套窗口拖动机制并存）。

        let glow = FFActivePaneBorderView()
        glow.translatesAutoresizingMaskIntoConstraints = false
        glow.isHidden = true
        wrapper.addSubview(glow)

        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)   // 后加入 → 盖住发光的向内半圈

        // 2026-10-20 #3：标签条挂到卡片包裹视图（wrapper）上。
        //
        // wrapper 横跨整个面板宽度、且随分栏自动伸缩，标签条作为它的子视图
        // 就能自动跟随——不需要跨层级约束（那种约束在 arranged subview 场景下
        // 不可靠，实测 width 恒为 0）。
        //
        // 垂直方向：标签条浮在 wrapper 顶部 0..28，**盖在卡片上方**
        // （卡片顶部让出 8pt，标签条因此「悬」在标题区，与红绿灯同行）。
        if let strip = side == .left ? leftTabStrip : rightTabStrip {
            wrapper.addSubview(strip)
            strip.translatesAutoresizingMaskIntoConstraints = false
            let height = strip.heightAnchor.constraint(equalToConstant: MainWindowController.tabStripHeight)
            let leading = strip.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor)
            if side == .left { leftTabStripHeight = height; leftTabStripLeading = leading }
            else { rightTabStripHeight = height; rightTabStripLeading = leading }
            NSLayoutConstraint.activate([
                height,
                leading,
                strip.topAnchor.constraint(equalTo: wrapper.topAnchor),
                strip.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ])
            // 活动标签位置一变（切换标签 / 增删标签 / 改宽），发光轮廓跟着重算
            strip.onActiveTabFrameChanged = { [weak self] in
                self?.syncGlowTabRects()
            }
        }

        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: wrapper.topAnchor),
            glow.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            glow.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

            // 2026-10-20 #4：卡片顶边 = 标题带高度（36）。
            // 标题带里放标签（活动标签 28 高，上方留 8pt 间隙，底边正好落在
            // 卡片顶边上 → 焊死）。左右下三边仍是 8pt 留白。
            content.topAnchor.constraint(equalTo: wrapper.topAnchor,
                                         constant: FFInteractionPolicy.titleBandHeight),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: FFActivePaneBorderView.edgeOutset),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -FFActivePaneBorderView.edgeOutset),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -FFActivePaneBorderView.edgeOutset),
        ])

        switch side {
        case .left:  leftActiveBorder = glow
        case .right: rightActiveBorder = glow
        }
        return wrapper
    }

    /// 创建面板容器（工具栏 + 文件列表/网格 + DetailsBar）
    /// v0.6.9: 超椭圆圆角 16pt + 实体背景（1px 边框已按 Wave4 Task 6 删除）
    private func createPaneContainer(side: PaneSide) -> NSView {
        FFDebug.log("createPaneContainer: side=\(side)")
        let container = SquircleView(cornerRadius: 16, squircleFactor: 5.0, autoUpdateMask: true)
        // 2026-10-20 #1：面板卡片不再拖动窗口——窗口拖动只保留侧栏与卡片外留白。
        // 不改这一条的话，按住操作面板一拖，动的就是整个窗口。
        container.allowsWindowDrag = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        // v0.6.9: 操作区实体背景（日间#F5F5F5/夜间#2D2D2D，Wave4 Task 3 起走 FFDesign 令牌）
        container.layer?.backgroundColor = operationAreaBackgroundColor().cgColor
        // Wave4 Task 6（审计 §3 装饰降噪）：删除 v0.6.9 的 1px 边框——卡片已有
        // 8pt 边距 + 阴影 + 圆角分层，边框叠用显多余

        // 2026-10-18 三次修订：活动面板发光层已上移到包裹视图（见 makeCardWrapper），
        // 挂在容器内部会被 masksToBounds 裁掉外半圈，只能得到「操作区里面的描边」。

        // 任务 F3: 双行工具栏布局（v0.6.5）
        // Row1（32pt）= 后退/前进/上一级/刷新 + BreadcrumbBar（紧贴刷新）
        // Row2（32pt）= 搜索/排序/分组/视图/工具
        // PaneToolbar 总高 72pt

        // 工具栏（内含双行 + BreadcrumbBar）
        let toolbar = PaneToolbar()
        toolbar.delegate = self
        toolbar.side = side
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // 面包屑导航栏（嵌入 PaneToolbar Row1）
        let breadcrumbBar = BreadcrumbBar()
        breadcrumbBar.delegate = self
        breadcrumbBar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.setBreadcrumbBar(breadcrumbBar)

        // 文件列表
        let listView = FileListView()
        listView.identifier = NSUserInterfaceItemIdentifier(side == .left ? "left" : "right")
        listView.panelSide = side
        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.onDoubleClick = { [weak self] entry in
            self?.handleDoubleClick(entry, side: side)
        }
        listView.onSelectionChanged = { [weak self] files in
            self?.handleSelectionChanged(side: side, files: files)
        }
        listView.onActivatePane = { [weak self] in
            self?.activatePane(side)
        }

        // 网格视图（初始隐藏）
        let gridView = FileGridView()
        gridView.identifier = NSUserInterfaceItemIdentifier(side == .left ? "left" : "right")
        gridView.panelSide = side
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.isHidden = true
        gridView.onDoubleClick = { [weak self] entry in
            self?.handleDoubleClick(entry, side: side)
        }
        gridView.onSelectionChanged = { [weak self] files in
            self?.handleSelectionChanged(side: side, files: files)
        }
        gridView.onActivatePane = { [weak self] in
            self?.activatePane(side)
        }

        // DetailsBar（每面板一个，可展开/收起）
        // v0.6.9: 详情栏改为液态玻璃浮层，覆盖在文件列表上方（不再占据容器底部空间）
        let detailsBar = ExpandableDetailsBar()
        detailsBar.translatesAutoresizingMaskIntoConstraints = false

        // #7：操作区顶部标签条（浏览器式）
        //
        // 2026-10-20 #3：标签条**不再放进卡片容器**，而是作为窗口级浮层
        // 挂在窗口顶部 0..28（与红绿灯同一行）。原因：
        //   - 放进容器时，卡片顶部必须内缩到 0 才能让标签条贴顶，
        //     于是卡片上边缘 0 / 下边缘 8，上下不对称；
        //   - 浮到窗口顶后，卡片四周统一 8pt，标签条也不必挤占卡片内部空间。
        let tabStrip = PaneTabStripView()
        tabStrip.side = side
        tabStrip.delegate = self
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        if side == .left { leftTabStrip = tabStrip } else { rightTabStrip = tabStrip }

        // 添加到容器
        container.addSubview(toolbar)
        container.addSubview(listView)
        container.addSubview(gridView)
        // v0.6.9: detailsBar 最后添加（视觉最上层），作为浮层覆盖
        container.addSubview(detailsBar)

        NSLayoutConstraint.activate([
            // 2026-10-20 #3：标签条已浮到窗口顶，工具栏直接顶到容器顶部
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // v0.6.9: 文件列表底部锚定 container 底部（不再锚定 detailsBar.topAnchor）
            // 文件列表始终占满操作区全高，详情栏以浮层形式覆盖在上方
            listView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            gridView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // v0.6.9: 详情栏浮层定位——底部留 8pt 边距，左右各 8pt
            detailsBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            detailsBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            detailsBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            // 高度由 ExpandableDetailsBar 内部 heightConstraint 控制
        ])

        // V0.8.0：详情栏浮层高度 → 列表/网格底部留白同步。
        // 详情栏是浮层（v0.6.9 决策），会盖住列表最后一行；列表按浮层高度在滚动内容
        // 底部预留空白，滚到底时最后一行完整露出。收起/展开/拖拽调高都会触发。
        detailsBar.onHeightChanged = { [weak listView, weak gridView] height in
            listView?.setBottomOverlayInset(height)
            gridView?.setBottomOverlayInset(height)
        }
        // 初始同步：applyExpandedState 在 setupUI 阶段已执行过，那时回调尚未注入
        let initialOverlayHeight = detailsBar.currentHeight
        listView.setBottomOverlayInset(initialOverlayHeight)
        gridView.setBottomOverlayInset(initialOverlayHeight)

        // v0.7.4 项 3：详情栏名称行单击改名 → 调用对应侧 viewModel.renameFile
        let paneVM = side == .left ? leftPaneViewModel : rightPaneViewModel
        detailsBar.onRename = { [weak paneVM] oldPath, newName in
            paneVM?.renameFile(oldPath, to: newName)
        }
        // v0.7.4 修订 2：详情栏标签变更 → 注册撤销
        detailsBar.onUndoableTagChange = { [weak paneVM] kind, tag, path in
            switch kind {
            case .add:
                paneVM?.registerUndoAddTag(tag: tag, path: path)
            case .remove:
                paneVM?.registerUndoRemoveTag(tag: tag, path: path)
            }
        }

        // 保存引用
        switch side {
        case .left:
            leftPaneToolbar = toolbar
            leftBreadcrumbBar = breadcrumbBar
            leftFileListView = listView
            leftFileGridView = gridView
            leftDetailsBar = detailsBar
        case .right:
            rightPaneToolbar = toolbar
            rightBreadcrumbBar = breadcrumbBar
            rightFileListView = listView
            rightFileGridView = gridView
            rightDetailsBar = detailsBar
        }

        return container
    }

    // MARK: - 跨窗口落点判定（2026-10-20 #4）

    /// 找到包含某窗口坐标点的标签条
    func tabStrip(near point: NSPoint) -> PaneTabStripView? {
        for side in [PaneSide.left, .right] {
            guard let strip = tabStrip(for: side) else { continue }
            let frame = strip.convert(strip.bounds, to: nil)
            if frame.contains(point) { return strip }
        }
        return nil
    }

    /// 面板卡片包裹视图（落点高亮用）
    func paneWrapper(for side: PaneSide) -> NSView? {
        side == .left ? leftPaneWrapper : rightPaneWrapper
    }

    /// 窗口坐标点落在操作区的哪一侧
    ///
    /// 双栏：按操作区中线分；单栏：整块都属于活动面板那一侧
    /// （单栏时真正会「拆出」的是另一侧，由 `highlightSide(for:)` 标出来）。
    func operationSide(near point: NSPoint) -> PaneSide? {
        guard let cv = window?.contentView else { return nil }
        let localX = cv.convert(NSPoint(x: point.x, y: 0), from: nil).x
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.maxX) / 2
        if isSinglePaneMode { return activePane }
        return localX < midX ? .left : .right
    }

    /// 落点高亮标在哪一侧：单栏时标在「将要出现的新面板」那一侧
    func highlightSide(for side: PaneSide) -> PaneSide {
        isSinglePaneMode ? (activePane == .left ? .right : .left) : side
    }

    /// 取某个槽位的面板卡片（拖影快照用）
    func paneCard(for side: PaneSide) -> NSView? {
        switch side {
        case .left: return leftPaneContainer
        case .right: return rightPaneContainer
        }
    }

    /// 吐出关键面板几何（窗口坐标），供自动化拖拽测试定位起手点
    func logPaneGeometry(_ tag: String = "") {
        guard let cv = window?.contentView else { return }
        func frame(_ v: NSView?) -> String {
            guard let v, let sp = v.superview else { return "nil" }
            let r = cv.convert(v.frame, from: sp)
            return "x=\(Int(r.minX))..\(Int(r.maxX)) y=\(Int(r.minY))..\(Int(r.maxY))"
        }
        FFDebug.log("[GEO]\(tag) 窗口=\(Int(window?.frame.width ?? 0))x\(Int(window?.frame.height ?? 0)) 侧栏=\(frame(sidebarView)) 左卡片=\(frame(leftPaneToolbar?.superview)) 左工具栏=\(frame(leftPaneToolbar)) 右工具栏=\(frame(rightPaneToolbar)) 左标签条=\(frame(leftTabStrip)) 右标签条=\(frame(rightTabStrip))")
    }

    // MARK: - 任务 F10-3: 设备浮层（浮动在窗口左下角独立区域，v0.6.6）

    /// 任务 F11-1: 操作区实体背景色（v0.6.7）
    /// Wave4 Task 3：改读 FFDesign.operationAreaBackground 统一令牌
    /// （日间 #F5F5F5，夜间 #2D2D2D，v0.6.7 基调不变），供 createPaneContainer
    /// 初始设置与主题切换刷新共用
    private func operationAreaBackgroundColor() -> NSColor {
        FFDesign.operationAreaBackground
    }

    /// v0.6.9: 刷新左右操作区容器背景色（主题切换时调用）
    /// Wave4 Task 6：1px 边框已删除，仅剩背景色刷新
    private func refreshOperationAreaBackgrounds() {
        let bgColor = operationAreaBackgroundColor().cgColor
        leftPaneContainer?.layer?.backgroundColor = bgColor
        rightPaneContainer?.layer?.backgroundColor = bgColor
        // 2026-10-20 #4：标签焊接背板必须与卡片同色，主题切换时一起刷新，
        // 否则接缝处会露出上一套主题的底色。
        let color = operationAreaBackgroundColor()
        leftTabStrip?.setBackdropColor(color)
        rightTabStrip?.setBackdropColor(color)
    }

    deinit {
        // Bug 6 修复：移除所有 NotificationCenter observer，防止悬空回调
        NotificationCenter.default.removeObserver(self)
        // 任务 F10-3: 移除卷挂载/卸载通知监听（迁移自 SidebarView deinit）
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        // Wave3 Task 6: 取消挂起的 FSEvents 合帧 flush
        fsChangeFlushWorkItem?.cancel()
        TaskSchedulerManager.shared.stopPolling()
    }

    private func setupBindings() {
        leftPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updatePaneUI(side: .left, state: state) }
            .store(in: &cancellables)

        rightPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updatePaneUI(side: .right, state: state) }
            .store(in: &cancellables)
    }

    private func setupNotifications() {
        // 强调色变更即时生效（DESIGN-SPEC C-04）。
        // 此前 FFAccent 注释声称「设置改动即可全应用即时生效」，但全仓无人订阅
        // .accentColorChanged——用户改完颜色要等下一次重绘才看得到。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAccentColorChanged(_:)),
            name: .accentColorChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarDirectorySelected(_:)),
            name: .sidebarDidSelectDirectory, object: nil
        )
        // #3：侧栏顶部单/双窗口切换按钮
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePaneModeToggle(_:)),
            name: .sidebarDidTogglePaneMode, object: nil
        )
        // 2026-10-19 #10：侧栏显隐（侧栏顶部按钮发出）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarToggleVisibility(_:)),
            name: .sidebarDidToggleVisibility, object: nil
        )
        // v0.8.0 P1: 收藏右键菜单的窗口级动作（新标签页 / 新窗口 / 显示简介）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarOpenInNewTab(_:)),
            name: .sidebarDidRequestOpenInNewTab, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarOpenInNewWindow(_:)),
            name: .sidebarDidRequestOpenInNewWindow, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarShowFavoriteInfo(_:)),
            name: .sidebarDidRequestShowFavoriteInfo, object: nil
        )
        // 任务 F11-8: 订阅侧边栏标签点击筛选通知（问题3）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarTagSelected(_:)),
            name: .sidebarDidSelectTag, object: nil
        )
        // 订阅 FileListView 右键菜单通知
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListCopy(_:)),
            name: .fileListDidCopy, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListCut(_:)),
            name: .fileListDidCut, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListPaste(_:)),
            name: .fileListDidPaste, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListCopyToOther(_:)),
            name: .fileListDidCopyToOther, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListMoveToOther(_:)),
            name: .fileListDidMoveToOther, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListOpenInOther(_:)),
            name: .fileListDidOpenInOther, object: nil
        )
        // 订阅 QuickLook 请求
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleQuickLookRequest(_:)),
            name: .fileListRequestQuickLook, object: nil
        )
        // 订阅「添加到收藏夹」请求
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListAddFavorite(_:)),
            name: .fileListDidAddFavorite, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListAddTag(_:)),
            name: .fileListAddTag, object: nil
        )
        // F9-C: 订阅「显示简介」请求，弹出独立 FileInfoWindow
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListShowInfo(_:)),
            name: .fileListShowInfo, object: nil
        )
        // 任务 F10-10: 注册 OpenSettings 通知（v0.6.6）
        // 修复问题3：侧边栏齿轮按钮发的 "OpenSettings" 通知无观察者，导致设置窗口打不开
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenSettings(_:)),
            name: .openSettings, object: nil
        )
        // B7 #4：文件夹右键「在新标签页中打开」（当前面板组末尾新建并激活）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileListOpenInNewTab(_:)),
            name: .fileListDidOpenInNewTab, object: nil
        )
        // 任务 F11-11: 注册侧边栏工具面板入口通知（C1）
        // 查重 -> 打开 DuplicateScanWindowController；批量重命名 -> 转发 menuBatchRename；
        // AI 工具 -> 调用活动面板视图 triggerAITagGeneration
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarDedupScan(_:)),
            name: .sidebarDidRequestDedupScan, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarBatchRename(_:)),
            name: .sidebarDidRequestBatchRename, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarAITools(_:)),
            name: .sidebarDidRequestAITools, object: nil
        )
        // v0.6.9: 文件夹显示配置变更通知
        // 隐藏文件 / 系统文件切换需重新过滤文件列表（数据层）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRefreshHiddenFiles),
            name: .refreshHiddenFiles, object: nil
        )
        // v0.7.4 修复 4：监听文件内容变更（重命名等），刷新详情栏显示新名字。
        // 底层审查 FINDING：renameFile 后 state.selectedFiles 已更新（修复 2），
        // 但详情栏（ExpandableDetailsBar）仅在 selectionDidChange 触发时刷新，
        // 重命名后选中恢复可能被 isReloading 抑制，详情栏残留旧名字。此处主动刷新。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileContentChanged(_:)),
            name: .fileListContentChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRefreshSystemFiles),
            name: .refreshSystemFiles, object: nil
        )
        // 文件标签 / 文件后缀切换仅需刷新视图显示（展示层）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRefreshFileTagsDisplay),
            name: .refreshFileTags, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRefreshFileExtensionsDisplay),
            name: .refreshFileExtensions, object: nil
        )
        // Wave2 P0-4（多窗口）：FSEvents 变更由 AppDelegate 进程级 watcher 广播到各窗口，
        // 本窗口仅刷新自身受影响的面板
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFileSystemDidChangeNotification(_:)),
            name: .fileSystemDidChange, object: nil
        )
    }

    /// 任务 F10-10: 处理 OpenSettings 通知，弹出设置窗口（修复问题3）
    @objc private func handleOpenSettings(_ notification: Notification) {
        if let section = notification.userInfo?["section"] as? String, section == "about" {
            SettingsWindowController.shared.showAboutSection()
        } else {
            SettingsWindowController.shared.showWindow()
        }
    }

    /// B7 #4：文件夹「在新标签页中打开」→ 当前面板组末尾新建并激活
    @objc private func handleFileListOpenInNewTab(_ notification: Notification) {
        guard let sideName = notification.userInfo?["side"] as? String,
              let path = notification.userInfo?["path"] as? String else { return }
        let side: PaneSide = sideName == "left" ? .left : .right
        newTab(in: side, path: path)
    }

    // MARK: - v0.7.0: 工具浮动面板

    // MARK: - v0.6.9: 文件夹显示配置变更处理

    /// 隐藏文件显示/隐藏切换：重新过滤文件列表（数据层）
    @objc private func handleRefreshHiddenFiles() {
        refreshPane(.left)
        refreshPane(.right)
    }

    /// 系统文件显示/隐藏切换：重新过滤文件列表（数据层）
    @objc private func handleRefreshSystemFiles() {
        refreshPane(.left)
        refreshPane(.right)
    }

    /// 文件标签显示/隐藏切换：刷新视图（展示层）
    @objc private func handleRefreshFileTagsDisplay() {
        leftFileListView?.reloadData()
        rightFileListView?.reloadData()
        leftFileGridView?.reloadData()
        rightFileGridView?.reloadData()
    }

    /// 文件后缀显示/隐藏切换：刷新视图（展示层）
    @objc private func handleRefreshFileExtensionsDisplay() {
        leftFileListView?.reloadData()
        rightFileListView?.reloadData()
        leftFileGridView?.reloadData()
        rightFileGridView?.reloadData()
    }

    // MARK: - 任务 F11-11: 侧边栏工具面板入口通知处理（C1）

    /// 查重扫描入口：打开 DuplicateScanWindowController
    @objc private func handleSidebarDedupScan(_ notification: Notification) {
        DuplicateScanWindowController.shared.showWindow()
    }

    /// 批量重命名入口：转发到 menuBatchRename（需至少选中 2 个文件，否则提示）
    @objc private func handleSidebarBatchRename(_ notification: Notification) {
        let selected = activePaneViewModel.selectedFiles
        guard selected.count >= 2 else {
            let alert = NSAlert()
            alert.messageText = "批量重命名"
            alert.informativeText = "请至少选中 2 个文件后再使用批量重命名。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }
        menuBatchRename(nil)
    }

    /// AI 工具入口：调用活动面板视图的 triggerAITagGeneration
    /// 根据活动面板的当前视图模式（列表/图标）选择对应视图，无选中文件时提示
    @objc private func handleSidebarAITools(_ notification: Notification) {
        let selected = activePaneViewModel.selectedFiles
        guard !selected.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "AI 自动打标签"
            alert.informativeText = "请先选中一个或多个文件后再使用 AI 自动打标签。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }
        // 根据活动面板的视图可见性选择对应视图
        let isLeft = (activePane == .left)
        let listView = isLeft ? leftFileListView : rightFileListView
        let gridView = isLeft ? leftFileGridView : rightFileGridView
        // 列表视图默认可见（gridView.isHidden == true 表示当前为列表模式）
        if gridView?.isHidden == true {
            listView?.triggerAITagGeneration()
        } else {
            gridView?.triggerAITagGeneration()
        }
    }

    @objc private func handleFileListAddTag(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String else { return }
        let currentTags = TagBridge.shared.getTags(path: path)
        let allTags = sidebarView.allSidebarTags()
        let dialog = TagSelectorDialog(filePath: path, currentTags: currentTags, allTags: allTags)
        if let window = window {
            dialog.beginSheetModal(for: window)
        }
    }

    /// F9-C: 处理「显示简介」请求，弹出独立 FileInfoWindow（仿访达 Get Info）。
    /// 若通知携带有效路径则显示该文件信息；否则回退到当前活动面板选中项的第一项。
    @objc private func handleFileListShowInfo(_ notification: Notification) {
        // Wave2 P0-4（多窗口）：仅响应本窗口面板发出的请求，简介弹窗只落在发起窗口
        guard isOwnPaneNotification(notification) else { return }
        var path = (notification.userInfo?["path"] as? String) ?? ""
        if path.isEmpty {
            path = activePaneViewModel.selectedFiles.first?.path ?? ""
        }
        guard !path.isEmpty else { return }
        showFileInfo(forPath: path)
    }

    /// 沿视图层级向上查找 firstResponder 归属的 FileListView / FileGridView。
    /// 全局键盘 monitor 用它把按键分派到正确的面板视图（不依赖 activePane）。
    private func filePaneView(for view: NSView) -> NSView? {
        var v: NSView? = view
        while let current = v {
            if current is FileListView || current is FileGridView {
                return current
            }
            v = current.superview
        }
        return nil
    }

    /// Wave2 P0-4（多窗口）：面板级通知只接受本窗口两个面板视图发出的
    /// （FFPaneActionsController 以 host 视图为 object post）。object 为 nil 时兼容旧 poster。
    /// 防止 A 窗口右键复制/QuickLook/收藏等触发 B 窗口同名处理
    /// （剪贴板双写、QuickLook 双开、收藏/标签重复添加、错误面板激活等）。
    func isOwnPaneNotification(_ notification: Notification) -> Bool {
        guard let source = notification.object as? AnyObject else { return true }
        return source === leftFileListView || source === rightFileListView
            || source === leftFileGridView || source === rightFileGridView
    }

    @objc private func handleQuickLookRequest(_ notification: Notification) {
        // Wave2 P0-4（多窗口）：仅响应本窗口面板发出的请求
        guard isOwnPaneNotification(notification) else { return }
        // 切换到请求的面板
        if let side = notification.userInfo?["side"] as? String {
            FFDebug.log("handleQuickLookRequest side=\(side)")
            if side == "left" { activePane = .left } else { activePane = .right }
        }
        // 调用已有的 QuickLook 逻辑
        handleQuickLook()
    }

    // MARK: - Undo / Redo

    @objc func undo(_ sender: Any?) {
        ffUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        ffUndoManager.redo()
    }

    /// 刷新指定面板（用于 undo/redo 闭包执行后）
    func refreshPane(_ side: PaneSide) {
        let vm = side == .left ? leftPaneViewModel : rightPaneViewModel
        vm.refresh()
    }

    // MARK: - FSEvents 文件系统监控

    // Wave3 Task 6: FSEvents 风暴合帧状态（主线程专用——.fileSystemDidChange 由
    // AppDelegate 主线程广播，本状态无需加锁）
    /// 待 flush 的变更路径集合（去重）
    private var pendingChangedPaths: Set<String> = []
    /// 合帧定时器（首个事件起算 0.3s，窗口期间事件只入集合，到点一次性 flush）
    private var fsChangeFlushWorkItem: DispatchWorkItem?
    /// 合帧窗口（秒）：单事件延迟 ≤0.3s 可接受（实现计划 Task 6 注明的取舍）
    private static let fsChangeFlushInterval: Double = 0.3

    /// Wave2 P0-4（多窗口）：处理 AppDelegate 进程级 FSEvents 监控广播的文件系统变更通知：
    /// 失效缓存 + 刷新受影响的面板（原 startFileSystemWatcher/handleFileSystemChange 链路，
    /// watcher 上移 AppDelegate 后经通知分发到各窗口）
    @objc private func handleFileSystemDidChangeNotification(_ notification: Notification) {
        let changedPath = (notification.userInfo?["path"] as? String) ?? ""
        guard !changedPath.isEmpty else { return }
        handleFileSystemChange(changedPath: changedPath)
    }

    /// 处理文件系统变更通知：失效缓存 + 刷新受影响的面板
    /// Wave1 P0-1/P1-5：旧实现每个事件在主线程做 2 次 invalidateCache 的
    /// semaphore 往返；现将缓存失效批量移到后台队列，失效完成后回主线程刷新
    /// 受影响面板（保持「先失效、后刷新」的顺序，刷新读到的是已失效缓存）。
    /// watcher 仅在 active 状态回调，启动握手期间不会有事件，事件不丢失。
    /// Wave3 Task 6（P1-5 风暴合帧）：git checkout/解压/网盘同步等风暴期间每秒数百事件，
    /// 逐事件失效+刷新会导致主线程反复往返与重复 loadDirectory——现改为 0.3s 合帧：
    /// 事件路径进去重 Set，到点一次性批量失效 + 每面板至多一次刷新。
    private func handleFileSystemChange(changedPath: String) {
        // 事件路径进去重集合（通知主线程串行回调，集合无需加锁）
        pendingChangedPaths.insert(changedPath)
        // 首个事件起算 0.3s 定时器；窗口期间后续事件只入集合不重置定时器
        // （固定节拍：风暴期间每 0.3s flush 一批，单事件延迟有界、目录扫描频率受控）
        guard fsChangeFlushWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.flushFileSystemChanges()
        }
        fsChangeFlushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fsChangeFlushInterval, execute: item)
    }

    /// Wave3 Task 6: flush 累积的变更事件（主线程）：批量失效 + 每面板至多一次刷新
    private func flushFileSystemChanges() {
        fsChangeFlushWorkItem = nil
        guard !pendingChangedPaths.isEmpty else { return }
        let paths = pendingChangedPaths
        pendingChangedPaths = []

        // 转发去重后的变更路径到内容索引（O(1) 内存 dirty 集合 + 异步 ffiQueue，主线程零等待）
        for path in paths {
            ContentIndexBridge.shared.markDirty(path: path)
        }

        // 检查变更路径是否影响当前面板显示的目录（主线程快照，后台不读 UI 状态）：
        // 变更 = 面板当前目录本身，或其父目录 = 面板当前目录（目录内容变化）
        let leftPath = leftPaneViewModel.currentPath
        let rightPath = rightPaneViewModel.currentPath
        func affects(_ panelPath: String) -> Bool {
            paths.contains { path in
                path == panelPath || (path as NSString).deletingLastPathComponent == panelPath
            }
        }
        let affectsLeft = affects(leftPath)
        let affectsRight = affects(rightPath)

        // 一次后台调用批量失效全部去重路径及其父目录（Wave1 P0-1：主线程无 semaphore 往返）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for path in paths {
                try? CoreBridge.shared.invalidateCache(path: path)
                let parentDir = (path as NSString).deletingLastPathComponent
                if !parentDir.isEmpty && parentDir != path {
                    try? CoreBridge.shared.invalidateCache(path: parentDir)
                }
            }
            // 缓存失效完成后回主线程刷新受影响的面板（每面板至多一次）
            DispatchQueue.main.async { [weak self] in
                if affectsLeft {
                    self?.leftPaneViewModel.refresh()
                }
                if affectsRight {
                    self?.rightPaneViewModel.refresh()
                }
            }
        }
    }

    // MARK: - Keyboard Events

    public override func keyDown(with event: NSEvent) {
        // v0.7.0: Escape 关闭工具浮动面板
        // Wave2 P0-3：以下键位统一经 ShortcutCenter 读取设置（默认值 = 原硬编码行为）。
        // 修饰键判定为「精确匹配」——替换原 contains(.command) 的过松判定（⌘⇧1 不再误触 ⌘1）。

        // QuickLook 预览（默认空格）
        if ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutQuicklook, event: event) {
            handleQuickLook()
            return
        }

        // Bug 5 修复：⌘O / ⌘↓（shortcut_open_file，默认 ⌘O）打开选中项
        // 兜底处理（FileListView 已自行处理，此处主要服务网格视图等无 keyDown 实现的场景）
        if ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutOpenFile, event: event) {
            handleOpenKey()
            return
        }

        // Bug 5 修复：⌘↑（shortcut_go_up）上级目录（Finder 风格）
        if ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutGoUp, event: event) {
            activePaneViewModel.goUp()
            return
        }

        // ⌘1（shortcut_list_view）: 列表视图
        if ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutListView, event: event) {
            activePaneViewModel.setViewMode(.list)
            updateViewMode(side: activePane, mode: .list)
            return
        }

        // ⌘2（shortcut_grid_view）: 网格视图
        if ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutGridView, event: event) {
            activePaneViewModel.setViewMode(.grid)
            updateViewMode(side: activePane, mode: .grid)
            return
        }

        // ⌘D（shortcut_duplicate）: 复制选中项
        if ShortcutCenter.eventMatches(FFUserDefaultsKeys.shortcutDuplicate, event: event) {
            duplicateSelected()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Quick Look

    private func handleQuickLook() {
        let selected = activePaneViewModel.selectedFiles
        FFDebug.log("handleQuickLook selectedCount=\(selected.count)")
        guard !selected.isEmpty else { return }

        // 获取当前面板所有可预览的文件（排除文件夹）
        let previewableFiles = activePaneViewModel.files.filter { !$0.isDirectory }
        let paths = previewableFiles.map { $0.path }
        FFDebug.log("handleQuickLook previewableCount=\(previewableFiles.count) firstSelected=\(selected.first?.path ?? "nil")")

        // 找到当前选中文件的索引
        let currentPath = selected.first?.path
        let currentIndex = paths.firstIndex(of: currentPath ?? "") ?? 0

        FFDebug.log("handleQuickLook -> togglePreview files=\(paths.count) idx=\(currentIndex)")
        QuickLookPreviewPanel.shared.togglePreview(files: paths, currentIndex: currentIndex, targetWindow: self.window)
    }

    // MARK: - Open Key (Cmd+O / Cmd+Down)

    /// Bug 5 修复：Cmd+O / Cmd+Down 打开选中项（替代原 Enter 打开行为，对齐 macOS Finder）
    private func handleOpenKey() {
        guard let entry = activePaneViewModel.selectedFiles.first else { return }
        if entry.isDirectory {
            activePaneViewModel.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    // MARK: - Duplicate

    /// Wave2 P1：改 internal——⌘D 菜单入口 menuDuplicateSelected（MenuActions 扩展）调用
    func duplicateSelected() {
        let selected = activePaneViewModel.selectedFiles
        guard !selected.isEmpty else { return }

        let destPath = activePaneViewModel.currentPath

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var copiedPairs: [(src: String, dst: String)] = []
            for entry in selected {
                let fileName = entry.name
                let ext = (fileName as NSString).pathExtension
                let baseName = (fileName as NSString).deletingPathExtension
                let copyName = ext.isEmpty ? "\(baseName) 副本" : "\(baseName) 副本.\(ext)"
                let dstPath = (destPath as NSString).appendingPathComponent(copyName)

                do {
                    try CoreBridge.shared.copyFile(src: entry.path, dst: dstPath)
                    copiedPairs.append((src: entry.path, dst: dstPath))
                } catch {
                    DispatchQueue.main.async {
                        self?.showError(error: error)
                    }
                    return
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activePaneViewModel.refresh()

                // 注册撤销：删除复制的文件。undoDeleteCopied 会同步注册 redo（redoCopy），
                // 而 redoCopy 处理器内又会注册反向 undo（= undoDeleteCopied），
                // 从而形成无限撤销/重做闭环。
                if !copiedPairs.isEmpty {
                    let pairs = copiedPairs
                    let actionName = "复制 \(pairs.count) 个项目"
                    self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                        ctrl.undoDeleteCopied(pairs: pairs, actionName: actionName)
                    }
                    self.ffUndoManager.setActionName(actionName)
                }
            }
        }
    }

    // MARK: - Wave2 P0-1：keyViewLoop（Tab/⇧Tab 焦点流转）

    /// 构建窗口级 keyViewLoop：
    /// 左面板（搜索框 → 排序 → 分组 → 视图切换 → 当前视图的列表/网格）
    /// → 右面板（同序）→ 回绕到左面板首控件，首尾相接成环。
    /// Tab 沿 nextKeyView 正向流转，⇧Tab 沿 previousKeyView 反向流转；
    /// 列表/网格切换（updateViewMode）后需重建以切换链尾落点。
    private func buildKeyViewLoops() {
        var loop: [NSView] = []
        loop.append(contentsOf: keyViewChain(for: .left))
        loop.append(contentsOf: keyViewChain(for: .right))
        guard loop.count > 1 else { return }
        for (index, view) in loop.enumerated() {
            // 成环：每个视图的 nextKeyView 指向下一个，尾节点指回首节点。
            // previousKeyView 由 AppKit 沿 nextKeyView 环自动推导（只读属性）。
            view.nextKeyView = loop[(index + 1) % loop.count]
        }
    }

    /// 网格默认用户首启焦点须落在当前可见视图（审查 Important 1）。
    /// setupUI 阶段 initialFirstResponder 固定挂在左列表；若「默认视图」设置为 grid，
    /// loadInitialDirectories 切到网格后 initialFirstResponder 仍指向隐藏的列表 tableView，
    /// 键盘焦点会落在不可见视图。keyViewChain 尾节点即当前视图模式对应的焦点落点，
    /// 视图模式初始应用/切换后调用本方法重挂初始焦点。
    private func refreshInitialFirstResponder() {
        window?.initialFirstResponder = keyViewChain(for: .left).last
    }

    /// 单面板的 keyView 链：工具栏控件（搜索/排序/分组/视图切换）+ 当前视图模式的文件视图焦点落点
    private func keyViewChain(for side: PaneSide) -> [NSView] {
        let toolbar = side == .left ? leftPaneToolbar : rightPaneToolbar
        let list = side == .left ? leftFileListView : rightFileListView
        let grid = side == .left ? leftFileGridView : rightFileGridView
        let isGrid = (side == .left ? leftPaneViewModel : rightPaneViewModel).state.viewMode == .grid
        var chain = toolbar?.keyViewControls() ?? []
        // 按当前视图模式取列表/网格的焦点落点（分支取值避免可选类型提升后成员解析失败）
        let focusTarget: NSView?
        if isGrid {
            focusTarget = grid?.keyFocusTarget
        } else {
            focusTarget = list?.keyFocusTarget
        }
        if let focusTarget = focusTarget {
            chain.append(focusTarget)
        }
        return chain
    }

    // MARK: - UI Updates

    private func updatePaneUI(side: PaneSide, state: PaneState) {
        let toolbar = side == .left ? leftPaneToolbar : rightPaneToolbar
        let breadcrumbBar = side == .left ? leftBreadcrumbBar : rightBreadcrumbBar
        let fileListView = side == .left ? leftFileListView : rightFileListView

        breadcrumbBar?.setPath(state.path)
        toolbar?.setCanGoBack(state.historyIndex > 0)
        toolbar?.setCanGoForward(state.historyIndex < state.history.count - 1)
        toolbar?.setViewMode(state.viewMode)

        // 活体验收缺陷修复（列表重复行）触发源：updatePaneUI 由 $state sink 在**每次**
        // 发射时调用（含 isLoading/selectedFiles 等与文件列表无关的字段变化），重赋同一
        // viewModel 实例也会触发 FileListView/FileGridView 的 didSet（取消并重建订阅 +
        // 全量 reloadData）。订阅反复重建会让视图自身 sink 的同步投递被丢弃，
        // lastFilesCount 追加检测基准过期，最终把整表误判为「纯追加」再拼一遍
        // （9 项显示 18 行）。改为仅实例变化时重新绑定；刷新由下方显式 reloadData 负责。
        let paneVM = side == .left ? leftPaneViewModel : rightPaneViewModel
        if fileListView?.viewModel !== paneVM {
            fileListView?.viewModel = paneVM
        }
        fileListView?.reloadData()

        // 更新网格视图
        let grid = side == .left ? leftFileGridView : rightFileGridView
        if grid?.viewModel !== paneVM {
            grid?.viewModel = paneVM
        }
        grid?.reloadData()

        // 视图模式切换
        updateViewMode(side: side, mode: state.viewMode)

        // 问题7修复：刷新状态栏（项目数 + 磁盘可用空间）
        // ExpandableDetailsBar.updateStatus 已实现但此前从未被调用，导致状态栏文字缺失
        let detailsBar = side == .left ? leftDetailsBar : rightDetailsBar
        let itemCount = state.files.count
        let diskFree = getDiskFreeSpace(forPath: state.path)
        // v0.7.4 修订 4：传入当前目录路径（未选中时详情栏显示该文件夹图标）
        detailsBar?.updateStatus(itemCount: itemCount, diskFree: diskFree, currentDirectoryPath: state.path)
        // #7：导航 / 排序 / 筛选变化后同步标签标题与激活态
        syncTabStrip(side: side, state: state)

        // 任务 F11-8: 状态变化时同步侧边栏标签高亮（导航清除 tagFilter / 切换活动面板时高亮需跟随）
        if side == activePane {
            // Wave2 P0-4（多窗口）：通知携带本窗口身份（object），其他窗口的侧边栏据此忽略
            NotificationCenter.default.post(
                name: .paneTagFilterChanged, object: window,
                userInfo: ["tagFilter": state.tagFilter as Any]
            )
            // DESIGN-SPEC §5.2：活动面板目录内的标签计数（后台 + 防抖）
            scheduleTagCountRefresh(side: side)
        }
    }

    // MARK: - 标签计数（DESIGN-SPEC §5.2）

    private var tagCountWorkItem: DispatchWorkItem?
    /// 代次：导航/切换面板期间旧统计可能晚于新统计返回，用它丢弃旧结果
    private var tagCountGeneration = 0

    /// 防抖 300ms 后统计当前活动面板目录内的标签分布并推给侧栏。
    /// 触发源是 updatePaneUI——分页加载、搜索、排序都会多次进入，
    /// 防抖把连续的进入合并成一次 xattr 扫描。
    private func scheduleTagCountRefresh(side: PaneSide) {
        tagCountWorkItem?.cancel()
        tagCountGeneration += 1
        let generation = tagCountGeneration
        let viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
        // 用未过滤列表作基数：筛选某标签时该标签自己的计数不应塌缩为筛后条数
        let paths = viewModel.unfilteredFiles.map { $0.path }
        guard !paths.isEmpty else {
            sidebarView?.updateTagCounts([:])
            return
        }

        let work = DispatchWorkItem { [weak self] in
            TagCountService.shared.count(paths: paths) { counts in
                guard let self, self.tagCountGeneration == generation else { return }
                self.sidebarView?.updateTagCounts(counts)
            }
        }
        tagCountWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    /// 问题7修复：获取指定路径所在卷的可用磁盘空间
    /// - Parameter path: 任意路径（通常为当前面板所在目录）
    /// - Returns: 形如 "42.8 GB 可用" 的描述串；获取失败时返回 nil
    private func getDiskFreeSpace(forPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let freeSize = attrs[.systemFreeSize] as? UInt64 {
                return ByteCountFormatter.string(fromByteCount: Int64(freeSize), countStyle: .file) + " 可用"
            }
        } catch {}
        return nil
    }

    /// 判定点击命中的视图属于哪个操作面板。
    /// 归属范围 = 面板的工具栏（含面包屑/搜索/排序）/ 文件列表 / 网格 / 详情栏，
    /// 命中任一即算操作该面板（与「用户在操作哪一侧」的直觉一致）。
    private func paneSideForHitView(_ hit: NSView) -> PaneSide? {
        let leftOwners: [NSView] = [leftPaneToolbar, leftFileListView, leftFileGridView, leftDetailsBar]
            .compactMap { $0 as NSView? }
        let rightOwners: [NSView] = [rightPaneToolbar, rightFileListView, rightFileGridView, rightDetailsBar]
            .compactMap { $0 as NSView? }
        func belongs(_ owner: NSView) -> Bool {
            hit === owner || hit.isDescendant(of: owner)
        }
        if leftOwners.contains(where: belongs) { return .left }
        if rightOwners.contains(where: belongs) { return .right }
        return nil
    }

    // MARK: - 侧栏显隐（2026-10-19 #10）

    /// 侧栏显隐的窗口级入口：侧栏顶部按钮、⌥⌘S 菜单项、左上角浮层开关都走这里。
    @objc func toggleSidebar(_ sender: Any?) {
        setSidebarVisible(!isSidebarVisible, animated: true)
    }

    @objc private func handleSidebarToggleVisibility(_ notification: Notification) {
        // 多窗口：只响应本窗口侧边栏发出
        if let source = notification.object as? AnyObject,
           !(source === sidebarView), !(source === window) { return }
        toggleSidebar(notification.object)
    }

    /// 显隐侧栏。
    ///
    /// 收起 = 把主分栏分隔线推到 0（不是 removeFromSuperview）：侧栏上挂着工具面板等
    /// 一批跨视图约束，从层级里摘掉会让它们全部失效。动画结束后才 `isHidden = true`，
    /// 免得动画期间侧栏内容被压到 0 宽反复重排。
    func setSidebarVisible(_ visible: Bool, animated: Bool) {
        guard visible != isSidebarVisible,
              let split = mainSplitView, let sidebar = sidebarView else { return }

        // 分隔线归零后 frame 宽度就取不到了，隐藏前先记下来
        if !visible, sidebar.frame.width >= MainWindowController.sidebarMinWidth {
            savedSidebarWidthWhileHidden = sidebar.frame.width
        }

        isSidebarVisible = visible
        UserDefaults.standard.set(!visible, forKey: Self.sidebarHiddenKey)
        sidebarRevealHost?.isHidden = visible
        sidebar.setSidebarVisible(visible)
        applySidebarHiddenToolbarInset()

        // 动画期间放开最小宽度：0 宽是「收起」的合法状态
        sidebarMinWidthOverride = 0
        (mainSplitView as? FFSplitView)?.leadingMinWidth = 0
        if visible { sidebar.isHidden = false }

        let target = visible
            ? max(MainWindowController.sidebarMinWidth,
                  savedSidebarWidthWhileHidden ?? MainWindowController.restoredSidebarWidth())
            : 0

        animateMainDivider(to: target, animated: animated) { [weak self] in
            guard let self else { return }
            if visible {
                self.sidebarMinWidthOverride = nil
                (self.mainSplitView as? FFSplitView)?.leadingMinWidth = MainWindowController.sidebarMinWidth
            } else {
                self.sidebarView?.isHidden = true
                self.mainSplitView?.setPosition(0, ofDividerAt: 0)
                (self.mainSplitView as? FFSplitView)?.leadingMinWidth = 0
            }
        }
    }

    /// 主分栏分隔线动画：60fps 定时器按 ease-in-out 插值，0.18s 收放。
    /// `isAdjustingPaneMode` 全程为真，禁止把动画中间的宽度写进 `sidebar_width`。
    private func animateMainDivider(to target: CGFloat, animated: Bool, completion: @escaping () -> Void) {
        guard let split = mainSplitView else { completion(); return }
        sidebarAnimationTimer?.invalidate()
        sidebarAnimationTimer = nil

        let start = split.arrangedSubviews.first?.frame.width ?? 0
        let duration = animated ? FFMotion.animationDuration(MainWindowController.sidebarAnimationDuration) : 0
        guard duration > 0, abs(target - start) > 0.5 else {
            isAdjustingPaneMode = true
            split.setPosition(target, ofDividerAt: 0)
            isAdjustingPaneMode = false
            completion()
            return
        }

        isAdjustingPaneMode = true
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let split = self.mainSplitView else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - startTime) / duration)
            // easeInOutQuad：两端慢、中间快，和系统侧栏动画的手感一致
            let eased = progress < 0.5
                ? 2 * progress * progress
                : 1 - pow(-2 * progress + 2, 2) / 2
            split.setPosition(start + (target - start) * CGFloat(eased), ofDividerAt: 0)
            if progress >= 1 {
                timer.invalidate()
                self.sidebarAnimationTimer = nil
                split.setPosition(target, ofDividerAt: 0)
                self.isAdjustingPaneMode = false
                completion()
            }
        }
        sidebarAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 标签条按分栏实际位置逐帧对齐。
    ///
    /// 标签条是浮在窗口顶的**窗口级**视图，而分栏（NSSplitView）在下面，
    /// Auto Layout 无法表达「贴着某个 arranged subview 的边缘但浮在它上方」，
    /// 因此这里手动算 frame。
    ///
    /// 2026-10-20 #3：标签条与工具栏**共用同一个避让量**
    /// （`FFInteractionPolicy.titleContentInset`）——侧栏可见时从卡片左缘起，
    /// 侧栏隐藏时从 x=106 起（红绿灯 70 + 浮动开关 96 + 10）。
    /// 以前只有工具栏有避让、标签条没有，隐藏侧栏后第一个标签被红绿灯压住。
    /// 窗口尺寸变化 → 重新对齐标签条
    @objc private func handleWindowLayout() {
        updateTabStripFrames()
        // 窗口尺寸变了，超椭圆遮罩要跟着重算（否则圆角会被拉伸）
        if let window { FFWindowShape.update(on: window) }
    }

    /// 进出全屏时增减遮罩（全屏带遮罩会露黑边）
    @objc private func handleWindowShapeChange() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            FFWindowShape.update(on: window)
        }
    }

    /// 标签条左缘约束（用于避让红绿灯）
    private var leftTabStripLeading: NSLayoutConstraint?
    private var rightTabStripLeading: NSLayoutConstraint?

    /// 刷新标签条状态：可见性与左缘避让量。
    ///
    /// 2026-10-20 #3：标签条与工具栏**共用同一个避让量**
    /// （`FFInteractionPolicy.titleContentInset`）——侧栏可见时从卡片左缘起，
    /// 侧栏隐藏时从 x=106 起（红绿灯 70 + 浮动开关 96 + 10）。
    /// 以前只有工具栏有避让、标签条没有，隐藏侧栏后第一个标签被红绿灯压住。
    func updateTabStripFrames() {
        let inset = FFInteractionPolicy.titleContentInset(sidebarVisible: isSidebarVisible)
        let leftmostIsLeft = !isSinglePaneMode || activePane == .left

        // 最左那一栏的标签条需要让开红绿灯；另一侧贴着卡片左缘即可。
        //
        // 避让量 106 是相对**窗口左边**的绝对值，而约束锚点是 wrapper 左缘
        // （双栏时在侧栏右边 x=280），因此要减去 wrapper 左缘换算成相对偏移。
        // 侧栏可见时 wrapper 左缘 = 280 > 106，offset 归 0（不避让）。
        let wrapperLeading: CGFloat = {
            guard let w = leftmostIsLeft ? leftPaneWrapper : rightPaneWrapper,
                  let sup = w.superview, let cv = mainContainerView else { return 0 }
            return cv.convert(w.frame, from: sup).minX
        }()
        let offset = max(0, inset - wrapperLeading)
        leftTabStripLeading?.constant = leftmostIsLeft ? offset : 0
        rightTabStripLeading?.constant = leftmostIsLeft ? 0 : offset

        // 单栏模式下只显示活动面板那一侧的标签条
        leftTabStrip?.isHidden = isSinglePaneMode && activePane != .left
        rightTabStrip?.isHidden = isSinglePaneMode && activePane != .right

        // 背板颜色 = 面板卡片背景色（两者必须一致，否则接缝处会露出色差）
        let cardColor = operationAreaBackgroundColor()
        leftTabStrip?.setBackdropColor(cardColor)
        rightTabStrip?.setBackdropColor(cardColor)

        // 发光沿「面板 + 活动标签」合并轮廓
        syncGlowTabRects()
    }

    /// 把活动标签的矩形喂给两侧发光视图。
    ///
    /// 标签在标签条坐标系里，发光在包裹视图坐标系里（发光铺满 wrapper）。
    /// 两级坐标系都是左下原点，直接 convert 即可。
    private func syncGlowTabRects() {
        for (strip, glow, wrapper) in [(leftTabStrip, leftActiveBorder, leftPaneWrapper),
                                       (rightTabStrip, rightActiveBorder, rightPaneWrapper)] {
            guard let glow, let wrapper else { continue }
            guard let strip, !strip.isHidden, let tabInStrip = strip.activeTabFrame else {
                glow.tabRect = nil
                continue
            }
            let inWrapper = wrapper.convert(tabInStrip, from: strip)
            glow.tabRect = glow.convert(inWrapper, from: wrapper)
        }
    }

    /// 侧栏收起后，最左那一栏顶到窗口最左边，工具栏要让开红绿灯与「显示侧栏」开关。
    /// 双栏时最左恒为左栏；单栏时要看当前留在哪一侧。
    private func applySidebarHiddenToolbarInset() {
        // 红绿灯到 64pt，浮动开关 72–96，导航按钮从 104 起，互不重叠
        //
        // 2026-10-20 #3：工具栏与标签条共用同一个避让量
        // （`FFInteractionPolicy.titleContentInset`），改一处两处生效。
        let inset = FFInteractionPolicy.titleContentInset(sidebarVisible: isSidebarVisible)
        let leftmostIsLeft = !isSinglePaneMode || activePane == .left
        leftPaneToolbar?.leadingInset = leftmostIsLeft ? inset : 8
        rightPaneToolbar?.leadingInset = leftmostIsLeft ? 8 : inset
        // 标签条是浮层，避让量由 updateTabStripFrames 计算
        updateTabStripFrames()
    }

    // MARK: - 单/双窗口模式（2026-10-18 #3）

    @objc private func handlePaneModeToggle(_ notification: Notification) {
        // 多窗口：只响应本窗口侧边栏发出
        if let source = notification.object as? AnyObject,
           !(source === sidebarView), !(source === window) { return }
        isSinglePaneMode.toggle()
        UserDefaults.standard.set(isSinglePaneMode, forKey: Self.singlePaneModeKey)
        // 2026-10-20 #2：0.36s 弹性过渡（窗口宽度同曲线、contentView 叠淡入淡出）
        let single = isSinglePaneMode
        isAnimatingPaneMode = true
        FFPaneModeAnimator.animate(toSingle: single, window: window) { [weak self] in
            self?.applyPaneMode()
        }
        isAnimatingPaneMode = false
    }

    /// 应用单/双窗口布局：
    /// - 单窗：收起非活动面板（只留活动面板占满操作区），窗口同步收窄被收起那一侧的宽度；
    ///   最小宽度 760（侧栏 160 + 操作区 450 + 两侧留白）
    /// - 双窗：两栏可见，窗口还原到进入单窗前的宽度（不低于 1060，W-07），分隔线回中线
    /// 侧栏切换按钮图标同步更新。
    func applyPaneMode() {
        let single = isSinglePaneMode
        let showLeft = !single || activePane == .left
        let showRight = !single || activePane == .right

        if single {
            // 只有「双 → 单」这次切换才动窗口宽度；单窗内切换活动面板不再重复缩放
            let enteringSingle = (appliedSinglePaneMode != true)
            let hidingWrapper = showLeft ? rightPaneWrapper : leftPaneWrapper
            var hiddenWidth: CGFloat = 0
            if enteringSingle {
                hiddenWidth = max(0, hidingWrapper?.frame.width ?? 0)
                if hiddenWidth < 1 {
                    // 启动即单窗 / 尚未完成布局：按操作区中线估一栏宽度
                    hiddenWidth = max(0, (paneSplitView?.bounds.width ?? 0) / 2)
                }
                if hiddenWidth > 1 { widthBeforeSinglePane = window?.frame.width }
            }

            setPaneVisible(showLeft, wrapper: leftPaneWrapper)
            setPaneVisible(showRight, wrapper: rightPaneWrapper)
            window?.minSize = NSSize(width: 760, height: 700)

            if hiddenWidth > 1, let window = window {
                var frame = window.frame
                // origin 为左下角，X 不变即保持左边缘、向右收窄
                frame.size.width = max(760, frame.width - hiddenWidth)
                resizeWindowKeepingSidebar(frame)
                appliedSinglePaneMode = true
            }
        } else {
            setPaneVisible(true, wrapper: leftPaneWrapper)
            setPaneVisible(true, wrapper: rightPaneWrapper)
            window?.minSize = NSSize(width: 1060, height: 700)
            if let window = window, let saved = widthBeforeSinglePane {
                let target = max(1060, saved)
                if abs(window.frame.width - target) > 1 {
                    var frame = window.frame
                    frame.size.width = target
                    resizeWindowKeepingSidebar(frame)
                }
            }
            widthBeforeSinglePane = nil
            appliedSinglePaneMode = false
            if let split = paneSplitView, split.bounds.width > 0 {
                // 从单窗恢复时把分隔线放回记忆中的左面板宽度
                // （隐藏期间宽度曾被单侧占满；2026-10-20 #8 改为放回记忆值）
                DispatchQueue.main.async {
                    let saved = MainWindowController.restoredPaneLeftWidth()
                    let target = saved > 0 ? saved : split.bounds.width / 2
                    let maxPos = max(FFDividerGlowMath.minPaneWidth,
                                     split.bounds.width - FFDividerGlowMath.minPaneWidth)
                    split.setPosition(min(target, maxPos), ofDividerAt: 0)
                }
            }
        }
        sidebarView?.setSinglePaneMode(single)
        // 侧栏收起时，最左那一栏随单双窗切换而变，工具栏让位要跟着重算（2026-10-19 #10）
        applySidebarHiddenToolbarInset()
        // 2026-10-20 #3：不再有「单栏单标签 → 拖面板退化成拖窗口」这层状态分支。
        // 拖面板只从标签起手，拖窗口只认区域白名单——行为不再随状态变化。
        updateActivePaneVisual()
    }

    /// 切模式时改窗口宽度：**保持侧栏宽度不变**，且不污染 `sidebar_width` 记忆。
    ///
    /// NSSplitView 在窗口变窄时会先挤压持有优先级低的一侧；即便侧栏已设为
    /// .defaultHigh，窗口宽度突变的瞬间仍可能先把侧栏压小，并被
    /// `splitViewDidResizeSubviews` 记进 `sidebar_width`（实测单窗切一次，
    /// 侧栏宽度就从 220 掉到 165）。这里改为：记下切换前的侧栏宽度 →
    /// 改窗口尺寸 → 下一拍把分隔线放回原宽度，全程不写记忆。
    func resizeWindowKeepingSidebar(_ frame: NSRect) {
        guard let window = window else { return }
        // 2026-10-20 #2：切换动画期间走 animator（同一条弹性曲线），否则瞬时跳变
        if isAnimatingPaneMode {
            isAdjustingPaneMode = true
            window.animator().setFrame(frame, display: true)
            DispatchQueue.main.async { [weak self] in
                guard let self, let sidebar = self.sidebarView else { return }
                let saved = max(MainWindowController.sidebarMinWidth, sidebar.frame.width)
                self.mainSplitView?.setPosition(saved, ofDividerAt: 0)
                self.isAdjustingPaneMode = false
            }
            return
        }
        let sidebarWidth = max(MainWindowController.sidebarMinWidth,
                               sidebarView?.frame.width ?? MainWindowController.restoredSidebarWidth())
        isAdjustingPaneMode = true
        window.setFrame(frame, display: true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.mainSplitView?.setPosition(sidebarWidth, ofDividerAt: 0)
            self.isAdjustingPaneMode = false
        }
    }

    private func updateActivePaneVisual() {
        // 1.2 修订：整块面板强调色描边（原 2pt 顶部色条被工具栏完全遮住，从未可见）
        leftActiveBorder?.isHidden = activePane != .left
        rightActiveBorder?.isHidden = activePane != .right
    }

    /// 单窗模式下真正「关掉」一个操作区：把它从分栏里移除（而不是只 isHidden）。
    ///
    /// 2026-10-18 #5：NSSplitView 的 arranged subview 只设 isHidden 时，本工程里
    /// 并没有被折叠——用户看到的是「两个操作区都在，窗口也没变小」。
    /// 移除 subview 是确定性的做法：不在分栏里就不可能占宽度。
    /// 重新显示时按左右顺序插回，并重建 holding priority。
    private func setPaneVisible(_ visible: Bool, wrapper: NSView?) {
        guard let wrapper = wrapper, let split = paneSplitView else { return }
        if visible {
            guard wrapper.superview == nil else { return }
            wrapper.isHidden = false
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            if wrapper === leftPaneWrapper {
                split.insertArrangedSubview(wrapper, at: 0)
            } else {
                split.addArrangedSubview(wrapper)
            }
            // holding priority 按 subview 序号保存，重排后需重新设置
            for (index, subview) in split.arrangedSubviews.enumerated() {
                split.setHoldingPriority(index == 0 && split.arrangedSubviews.count > 1 ? .defaultLow : .defaultHigh,
                                         forSubviewAt: index)
            }
        } else {
            guard wrapper.superview != nil else { return }
            split.removeArrangedSubview(wrapper)
            wrapper.removeFromSuperview()
        }
    }

    func updateViewMode(side: PaneSide, mode: ViewMode) {
        let listView = side == .left ? leftFileListView : rightFileListView
        let gridView = side == .left ? leftFileGridView : rightFileGridView

        switch mode {
        case .list:
            // 活体验收缺陷修复（⌘2 焦点漂移）：先显示新视图，再把焦点从旧视图移出，
            // 最后才隐藏旧视图——顺序不可颠倒。若直接隐藏 firstResponder 所在的旧视图，
            // AppKit 会沿 keyViewLoop 把焦点漂移到「下一个」可见控件：左面板列表的
            // nextKeyView 是右面板搜索框（buildKeyViewLoops 链序），⌘2 切网格后焦点
            // 即落到右面板搜索框（蓝圈），键盘/视图操作从此打到另一面板。
            listView?.isHidden = false
            Self.moveFocusOff(window: window, from: gridView, to: listView?.keyFocusTarget)
            gridView?.isHidden = true
            listView?.reloadData()
        case .grid:
            gridView?.isHidden = false
            Self.moveFocusOff(window: window, from: listView, to: gridView?.keyFocusTarget)
            listView?.isHidden = true
            gridView?.reloadData()
        }
        // Wave2 P0-1：视图模式切换后重建 keyViewLoop（链尾落点在列表/网格间切换）
        buildKeyViewLoops()
        // 网格默认用户首启焦点须落在当前可见视图（审查 Important 1）
        refreshInitialFirstResponder()
    }

    /// 活体验收缺陷修复（⌘2 焦点漂移）：视图模式切换时把键盘焦点保持在原面板。
    /// 若键盘焦点在即将隐藏的旧文件视图（或其子视图）内，先转移到同面板新视图的
    /// 焦点落点，避免 AppKit 因 firstResponder 被隐藏而沿 keyViewLoop 漂移到另一面板
    /// 的首控件（右面板搜索框）。文本编辑中（field editor NSTextView）不打断。
    static func moveFocusOff(window: NSWindow?, from oldView: NSView?, to newTarget: NSView?) {
        guard let window = window, let oldView = oldView, let newTarget = newTarget else { return }
        guard shouldTransferFocus(firstResponder: window.firstResponder, from: oldView) else { return }
        window.makeFirstResponder(newTarget)
    }

    /// 焦点转移判定（纯函数，internal 供单元测试）：firstResponder 在旧视图（或其子视图）
    /// 内且非文本编辑中（field editor NSTextView）时需要转移。
    static func shouldTransferFocus(firstResponder: Any?, from oldView: NSView?) -> Bool {
        guard let oldView = oldView, let frView = firstResponder as? NSView else { return false }
        if firstResponder is NSTextView { return false }  // 文本编辑中（field editor）不转移
        return frView === oldView || frView.isDescendant(of: oldView)
    }

    private func loadInitialDirectories() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        // 接线设置项「启动时打开」（UserDefaults key "startup_location"）：
        // 0 = 上次打开的位置（已实现持久化）/ 1 = 主目录 / 2 = 桌面
        //
        // J1 兜底：路径必须真实存在才交给面板，否则首开是一屏「无法加载此文件夹」。
        // 原实现把 ~/Desktop 硬编码进去且不校验，设置项「上次位置」也只是注释里的
        // 「暂回退到桌面」。现在候选序列 = 设置 → 上次位置 → 桌面 → 主目录。
        let startupChoice = UserDefaults.standard.integer(forKey: "startup_location")
        let leftStart = FFStartupPath.resolve(
            choice: startupChoice,
            lastLocation: UserDefaults.standard.string(forKey: FFStartupPath.lastLeftKey),
            home: homePath,
            isDirectory: FFStartupPath.isDirectoryOnDisk
        )
        let rightStart = FFStartupPath.resolveSecondary(
            lastLocation: UserDefaults.standard.string(forKey: FFStartupPath.lastRightKey),
            home: homePath,
            subdirectory: "Documents",
            isDirectory: FFStartupPath.isDirectoryOnDisk
        )

        leftPaneViewModel.state.path = leftStart
        leftPaneViewModel.state.history = [leftStart]
        leftPaneViewModel.state.historyIndex = 0

        rightPaneViewModel.state.path = rightStart
        rightPaneViewModel.state.history = [rightStart]
        rightPaneViewModel.state.historyIndex = 0

        // 记住两侧当前目录，供下次启动还原
        for (vm, key) in [(leftPaneViewModel, FFStartupPath.lastLeftKey),
                          (rightPaneViewModel, FFStartupPath.lastRightKey)] {
            vm.$state.map(\.path).removeDuplicates().sink { path in
                guard !path.isEmpty else { return }
                UserDefaults.standard.set(path, forKey: key)
            }.store(in: &cancellables)
        }

        // 接线设置项「默认视图」（UserDefaults key "default_view_mode"）：
        // "list"（默认）= 列表；"grid" = 网格。启动时按设置初始化左右面板视图模式。
        let viewModeStr = UserDefaults.standard.string(forKey: "default_view_mode") ?? "list"
        let initialMode: ViewMode = (viewModeStr == "grid") ? .grid : .list
        leftPaneViewModel.setViewMode(initialMode)
        rightPaneViewModel.setViewMode(initialMode)
        updateViewMode(side: .left, mode: initialMode)
        updateViewMode(side: .right, mode: initialMode)
        // 网格默认用户首启焦点须落在当前可见视图（审查 Important 1）：
        // 首启按「默认视图」设置切到网格时，初始焦点改挂当前可见视图的落点
        refreshInitialFirstResponder()

        // 权限集中请求完成后再刷新两侧面板：
        // 直接 refresh 会让目录列举撞上 TCC 授权对话框（系统调用阻塞 → 10s 后误报超时），
        // 而且用户体感是「每打开一个文件夹被问一次」。
        FFPermissionGate.shared.prepareBeforeInitialLoad(window: window) { [weak self] in
            guard let self = self else { return }
            self.leftPaneViewModel.refresh()
            self.rightPaneViewModel.refresh()
        }
    }

    // MARK: - Actions

    private func handleDoubleClick(_ entry: FileEntry, side: PaneSide) {
        if entry.isDirectory {
            let vm = side == .left ? leftPaneViewModel : rightPaneViewModel
            vm.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    /// v0.7.4 修复 4：文件内容变更（重命名等）后刷新详情栏。
    /// 详情栏显示选中文件的名称/路径，重命名后若不刷新会残留旧名字。
    /// 通知携带目录路径，据此确定受影响的面板，用其 viewModel.selectedFiles 首项刷新详情栏。
    @objc private func handleFileContentChanged(_ notification: Notification) {
        let changedPath = (notification.userInfo?["path"] as? String) ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 更新受影响面板（左/右）的详情栏。目录匹配的面板数据已刷新（refresh 或重载），
            // selectedFiles 中旧路径条目已在 renameFile 中更新为新路径（修复 2）。
            if changedPath == self.leftPaneViewModel.currentPath {
                self.leftDetailsBar?.update(with: self.leftPaneViewModel.selectedFiles)
            }
            if changedPath == self.rightPaneViewModel.currentPath {
                self.rightDetailsBar?.update(with: self.rightPaneViewModel.selectedFiles)
            }
        }
    }

    private func handleSelectionChanged(side: PaneSide, files: [FileEntry]) {
        // v0.7.4 修订: 同步"新建文件夹"按钮的选中数量（行为与悬停提示跟随变化）
        let toolbar = side == .left ? leftPaneToolbar : rightPaneToolbar
        toolbar?.setFolderSelectionCount(files.count)

        // 防抖: 取消上一次未完成的选中变更 UI 更新，防止快速连续点击不同文件时
        // 多次 layout 触发窗口跳动。将详情栏更新推迟到下一个 runloop，确保
        // NSTableView 的选中态渲染完成后再更新详情栏，避免布局冲突。
        selectionChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let detailsBar = side == .left ? self.leftDetailsBar : self.rightDetailsBar else { return }
            // v0.7.4 修订: 传入完整选中数组，详情栏自行区分单选/多选/未选
            detailsBar.update(with: files)
        }
        selectionChangeWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func activatePane(_ side: PaneSide) {
        activePane = side
        updateActivePaneVisual()
        // 单窗模式下切换活动面板 = 切换可见侧
        if isSinglePaneMode { applyPaneMode() }
        // Wave2 P0-2：激活面板时同步键盘焦点到对应面板的列表/网格，消除
        // 「焦点面板 ≠ activePane」双真值源（menu 审计 §15：菜单操作按 activePane 执行，
        // 键盘按 firstResponder 分派，二者不一致时操作打到另一面板）
        syncKeyboardFocusWithActivePane(side)
        // Wave2 P0-4（多窗口）：通知携带本窗口身份（object），其他窗口的侧边栏据此忽略
        NotificationCenter.default.post(name: .paneDidActivate, object: window, userInfo: ["side": side == .left ? "left" : "right"])
        // 任务 F11-8: 切换活动面板时同步侧边栏标签高亮（显示新活动面板的 tagFilter）
        let vm = side == .left ? leftPaneViewModel : rightPaneViewModel
        NotificationCenter.default.post(
            name: .paneTagFilterChanged, object: window,
            userInfo: ["tagFilter": vm.state.tagFilter as Any]
        )
    }

    /// Wave2 P0-2：把键盘焦点同步到指定面板的列表/网格（按当前视图模式）。
    /// - 文本编辑中（field editor / 可编辑文本框）不打断——搜索框输入、内联重命名不受点击影响；
    /// - 焦点已属于目标面板的文件视图时不动（避免无谓的 firstResponder 抖动）；
    /// - 其余情况（焦点在另一面板/侧边栏/窗口本身）转移到目标面板，保证「点哪面板，⌘C 等文件
    ///   操作作用于哪面板」。
    private func syncKeyboardFocusWithActivePane(_ side: PaneSide) {
        guard let window = window else { return }
        let fr = window.firstResponder
        if fr is NSTextView { return }  // 文本编辑中（field editor）
        if let tf = fr as? NSTextField, tf.isEditable { return }
        // 目标面板当前视图模式的焦点落点（分支取值避免可选类型提升后成员解析失败）
        let isGrid = (side == .left ? leftPaneViewModel : rightPaneViewModel).state.viewMode == .grid
        let target: NSView?
        let currentPane: NSView?
        if isGrid {
            target = (side == .left ? leftFileGridView : rightFileGridView)?.keyFocusTarget
            currentPane = side == .left ? leftFileGridView : rightFileGridView
        } else {
            target = (side == .left ? leftFileListView : rightFileListView)?.keyFocusTarget
            currentPane = side == .left ? leftFileListView : rightFileListView
        }
        guard let target = target else { return }
        // 焦点已在目标面板的文件视图（或其子视图）内则无需转移
        if let frView = fr as? NSView,
           let focusedPane = filePaneView(for: frView),
           focusedPane === currentPane {
            return
        }
        window.makeFirstResponder(target)
    }

    /// 判断侧边栏通知发送者是否属于本窗口（活体缺陷：发送者是侧边栏内部
    /// 数据源/outlineView 视图——数据源对象非 NSView 无法走视图树判定；
    /// 设备浮层 outlineView 挂在 mainContainer 也不在 sidebarView 子树内。
    /// 归属判定以「发送者所属 NSWindow === 本窗口」为准，未挂窗时退回视图树判定）
    private func isOwnSidebarNotification(_ notification: Notification) -> Bool {
        guard let source = notification.object as? NSView else {
            return notification.object == nil // 旧 poster 兼容
        }
        if source === sidebarView { return true }
        if let sourceWindow = source.window {
            return sourceWindow === window
        }
        var current: NSView? = source
        while let view = current {
            if view === sidebarView { return true }
            current = view.superview
        }
        return false
    }

    /// 强调色变更 → 三处选中态即时重绘（列表 / 网格 / 侧栏统一取 FFAccent）
    @objc private func handleAccentColorChanged(_ notification: Notification) {
        sidebarView?.needsDisplay = true
        sidebarView?.refreshSelectionAppearance()
        leftFileListView?.refreshAppearance()
        rightFileListView?.refreshAppearance()
        leftFileGridView?.refreshAppearance()
        rightFileGridView?.refreshAppearance()
        // 活动面板描边跟随强调色（DESIGN-SPEC C-04）
        leftActiveBorder?.ringColor = FFAccent.current
        rightActiveBorder?.ringColor = FFAccent.current
    }

    @objc private func handleSidebarDirectorySelected(_ notification: Notification) {
        // Wave2 P0-4（多窗口）：仅响应本窗口侧边栏发出的选择。发送者可能是
        // SidebarView 自身或其内部数据源（收藏/设备 outlineView 的 dataSource），
        // 用视图树归属判定（isOwnSidebarNotification），避免误杀本窗口导航
        guard isOwnSidebarNotification(notification) else { return }
        guard let entry = (notification.userInfo?["entry"] as? FileEntry) ?? (notification.object as? FileEntry) else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: entry.path)
    }

    // MARK: - v0.8.0 P1：收藏右键菜单的窗口级动作

    /// 在新标签页中打开收藏目录
    @objc private func handleSidebarOpenInNewTab(_ notification: Notification) {
        guard isOwnSidebarNotification(notification),
              let path = notification.userInfo?["path"] as? String else { return }
        openDirectoryInNewWindow(path: path, asTab: true)
    }

    /// 在新窗口中打开收藏目录
    @objc private func handleSidebarOpenInNewWindow(_ notification: Notification) {
        guard isOwnSidebarNotification(notification),
              let path = notification.userInfo?["path"] as? String else { return }
        openDirectoryInNewWindow(path: path, asTab: false)
    }

    /// 显示收藏目录的「简介」窗口
    @objc private func handleSidebarShowFavoriteInfo(_ notification: Notification) {
        guard isOwnSidebarNotification(notification),
              let path = notification.userInfo?["path"] as? String else { return }
        showFileInfo(forPath: path)
    }

    /// 新建窗口并在左面板导航到指定目录；`asTab` 为真时并入当前窗口的标签页。
    ///
    /// 窗口创建/持有归 MainWindowController（AppDelegate.extras 强引用），
    /// SidebarView 仅发意图通知，不直接建窗——保持多窗口簿记单点。
    private func openDirectoryInNewWindow(path: String, asTab: Bool) {
        // #7：新标签页 = 当前活动面板新增一个标签，不再使用系统窗口标签
        if asTab {
            newTab(in: activePane, path: path)
            return
        }
        let controller = MainWindowController()
        if let reference = window {
            let origin = reference.frame.origin
            controller.window?.setFrameOrigin(NSPoint(x: origin.x + 28, y: origin.y - 28))
        }
        (NSApp.delegate as? AppDelegate)?.registerWindowController(controller)
        controller.showWindow(nil)
        controller.leftPaneViewModel.navigate(to: path)

        guard asTab, let host = window, host.tabbingMode != .disallowed,
              let newWindow = controller.window else { return }
        // 标签页合并要求两窗口 tabbingIdentifier 一致
        if host.tabbingIdentifier.isEmpty {
            host.tabbingIdentifier = "FlowFinderMain"
        }
        newWindow.tabbingIdentifier = host.tabbingIdentifier
        host.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    /// 任务 F11-8: 处理侧边栏标签点击，设置当前活动面板的标签筛选（问题3）。
    /// - 点击标签 -> 筛选当前面板，仅显示含该标签的文件
    /// - 再次点击同一标签 -> 取消筛选（setTagFilter 内部判断）
    /// 筛选状态变化后发布 paneTagFilterChanged 通知，侧边栏据此高亮对应标签
    @objc private func handleSidebarTagSelected(_ notification: Notification) {
        // Wave2 P0-4（多窗口）：仅响应本窗口侧边栏发出的标签点击（object=SidebarView 实例；
        // object 为 nil 时兼容旧 poster）。避免 A 窗口点击标签筛选 B 窗口面板。
        guard isOwnSidebarNotification(notification) || (notification.object is Tag) else { return }
        guard let tag = (notification.userInfo?["tag"] as? Tag) ?? (notification.object as? Tag) else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.setTagFilter(tag)
        // 发布通知让侧边栏更新标签高亮。观察方（SidebarView）按 object as? NSWindow
        // 过滤他窗口，必须携带本窗口对象（round-2 复核：object: self 对 NSWindow
        // 转型失败会被观察方跳过过滤，跨窗口高亮串扰依旧）
        NotificationCenter.default.post(
            name: .paneTagFilterChanged, object: window,
            userInfo: ["tagFilter": vm.state.tagFilter as Any]
        )
    }
}

// MARK: - PaneToolbarDelegate

extension MainWindowController: PaneToolbarDelegate {
    func paneToolbarDidClickBack(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        _ = vm.goBack()
    }

    func paneToolbarDidClickForward(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        _ = vm.goForward()
    }

    func paneToolbarDidClickUp(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.goUp()
    }

    func paneToolbarDidClickRefresh(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.refresh()
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeSearchQuery query: String) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setSearchQuery(query)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeSortField field: SortField, ascending: Bool) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setSortField(field, ascending: ascending)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeGroupBy groupBy: String) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setGroupBy(groupBy)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeViewMode mode: ViewMode) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setViewMode(mode)
    }

    // MARK: - 核心旅程 J3：⌘F → ↑↓ → Enter

    /// 搜索框 ↓/↑：焦点交给本面板当前视图并选中首 / 末项
    func paneToolbarDidRequestMoveToResults(_ toolbar: PaneToolbar, toLast: Bool) {
        let isLeft = toolbar == leftPaneToolbar
        let vm = isLeft ? leftPaneViewModel : rightPaneViewModel
        activatePane(isLeft ? .left : .right)
        switch vm.state.viewMode {
        case .list:
            (isLeft ? leftFileListView : rightFileListView)?.focusFirstSelectableRow(toLast: toLast)
        case .grid:
            (isLeft ? leftFileGridView : rightFileGridView)?.focusFirstSelectableItem(toLast: toLast)
        }
    }

    /// 搜索框 Enter：打开结果。无选中时先落到第一项再打开，避免「回车没反应」
    func paneToolbarDidRequestOpenResult(_ toolbar: PaneToolbar) {
        let isLeft = toolbar == leftPaneToolbar
        let vm = isLeft ? leftPaneViewModel : rightPaneViewModel
        activatePane(isLeft ? .left : .right)
        if vm.selectedFiles.isEmpty {
            paneToolbarDidRequestMoveToResults(toolbar, toLast: false)
        }
        // 让步一帧：选中 → selectedFiles 是同步的，但视图选中态需先落地再打开
        DispatchQueue.main.async { [weak self] in
            self?.menuOpen(nil)
        }
    }

    func paneToolbar(_ toolbar: PaneToolbar, didClickPath path: String) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: path)
    }

    // 任务 F10-10: 补实现查重/批量重命名回调（v0.6.6）
    // 修复问题17：PaneToolbarDelegate 协议提供了默认空实现，MainWindowController 未覆写，
    // 导致工具按钮点击查重扫描/批量重命名时无任何响应（菜单栏菜单可用，工具栏按钮不可用）
    func paneToolbarDidClickDedupScan(_ toolbar: PaneToolbar) {
        DuplicateScanWindowController.shared.showWindow()
    }

    func paneToolbarDidClickBatchRename(_ toolbar: PaneToolbar) {
        // 转发到现有 menuBatchRename 逻辑：需至少选中 2 个文件
        let selected = activePaneViewModel.selectedFiles
        guard selected.count >= 2 else {
            // 选中不足 2 个时提示用户（与 menuBatchRename 的 validateMenuItem 行为一致）
            let alert = NSAlert()
            alert.messageText = "批量重命名"
            alert.informativeText = "请至少选中 2 个文件后再使用批量重命名。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }
        menuBatchRename(nil)
    }

    // v0.6.9: 文件夹配置菜单"新建文件夹"回调（v0.7.4 修订：合并行为，携带选中数量）
    func paneToolbarDidClickNewFolder(_ toolbar: PaneToolbar, selectedCount: Int) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        if selectedCount >= 2 {
            // 选中 2 个及以上：用所选项目新建文件夹
            _ = vm.createFolderFromSelection(window: window)
        } else {
            // 未选中（或单选）：创建空文件夹
            vm.createDirectory()
        }
    }
}

// MARK: - BreadcrumbBarDelegate

extension MainWindowController: BreadcrumbBarDelegate {
    func breadcrumbBar(_ bar: BreadcrumbBar, didSelectPath path: String) {
        let vm = bar == leftBreadcrumbBar ? leftPaneViewModel : rightPaneViewModel
        // BreadcrumbBar 按路径分隔符拆分后重组路径会丢失前导 "/"，
        // 此处补回前导斜杠以确保绝对路径正确
        let absolutePath = path.hasPrefix("/") ? path : "/" + path
        vm.navigate(to: absolutePath)
    }
}

// MARK: - NSSplitViewDelegate

extension MainWindowController: NSSplitViewDelegate {
    /// 限制每个面板的最小坐标，防止工具栏元素重叠
    public func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 主 split view（sidebar + panes）：sidebar 最小 160（DESIGN-SPEC B-01）
        // 侧栏收起时放开到 0，否则分隔线推不到底（2026-10-19 #10）
        if splitView === mainSplitView {
            return sidebarMinWidthOverride ?? MainWindowController.sidebarMinWidth
        }
        // pane split view（left + right panes）：每个面板最小 450
        if splitView === paneSplitView {
            return 450
        }
        return proposedMinimumPosition
    }

    /// 限制每个面板的最大坐标，防止一个面板占据过多空间
    public func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 主 split view：sidebar 最大 280（DESIGN-SPEC B-01）
        if splitView === mainSplitView {
            return MainWindowController.sidebarMaxWidth
        }
        // pane split view：留出至少 450 给另一个面板
        if splitView === paneSplitView {
            let totalWidth = splitView.bounds.width
            return max(totalWidth - 450, 450)
        }
        return proposedMaximumPosition
    }

    /// 拖动时实时更新布局 + 记忆侧栏宽度
    public func splitViewDidResizeSubviews(_ notification: Notification) {
        // 触发布局更新
        if let splitView = notification.object as? NSSplitView {
            splitView.window?.layoutIfNeeded()
            // DESIGN-SPEC B-01：侧栏宽度记忆（下一窗口/下次启动沿用）
            // 切模式期间的分隔线变更不算用户拖拽，不写记忆（2026-10-18 #5）
            if splitView === mainSplitView, !isAdjustingPaneMode, let sidebar = splitView.subviews.first {
                let width = sidebar.frame.width
                if width >= MainWindowController.sidebarMinWidth,
                   width <= MainWindowController.sidebarMaxWidth {
                    UserDefaults.standard.set(Double(width), forKey: MainWindowController.sidebarWidthKey)
                }
            }
            // 2026-10-20 #8：左操作面板宽度记忆（中缝拖动后沿用）
            if splitView === paneSplitView, !isAdjustingPaneMode, let left = splitView.subviews.first {
                let width = left.frame.width
                if width >= FFDividerGlowMath.minPaneWidth {
                    UserDefaults.standard.set(Double(width), forKey: MainWindowController.paneLeftWidthKey)
                }
            }
        }
    }
}

// MARK: - PaneSide

enum PaneSide {
    case left
    case right
}

// MARK: - NSWindowDelegate

// 任务 F10-1: 显式声明 NSWindowDelegate 协议遵循（v0.6.6）
// NSWindowController 父类虽在 ObjC 层声明 <NSWindowDelegate>，但 Swift 编译器要求
// 显式遵循才能将 MainWindowController 实例赋值给 window.delegate。
// windowDidBecomeKey/ResignKey/BecomeMain/ResignMain 等回调已在类内实现（见类内 MARK 区）。
extension MainWindowController: NSWindowDelegate {}

// MARK: - QLPreviewPanelController（常驻 responder，问题 8 修复）

/// 常驻实现 QLPreviewPanelController informal protocol：
/// MainWindowController 位于 window 的 responder chain（window → windowController），
/// QLPreviewPanel 显示时沿链自动找到本控制器，无需临时插入/移除 responder。
extension MainWindowController {
    public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookPreviewPanel.shared
        panel.delegate = QuickLookPreviewPanel.shared
        panel.currentPreviewItemIndex = QuickLookPreviewPanel.shared.currentIndex
    }

    public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
