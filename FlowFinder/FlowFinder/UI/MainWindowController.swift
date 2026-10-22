import Cocoa
import Combine
import QuickLook
import Quartz

/// 自定义 NSSplitView 子类：任务 R5 — divider 悬停高亮
/// v0.7.6 发布后修复轮：亮点跟随鼠标 Y（上下各 60pt 渐隐）+ 拖动绝对跟随（禁隐式动画消迟滞）。
/// 2026-10-20 #8：分隔发光条与 hover 高亮**全部移除**，把手改到「面板卡片的边缘」，
/// 用户直接拖卡片外沿调宽，不必瞄准缝隙正中那条看不见的线。
/// 拖动调宽时跟随鼠标的宽度浮标；只显示，不参与命中。
private final class FFDividerBadgeLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

class FFSplitView: NSSplitView {

    /// 手动拖拽状态（dividerThickness=0 时 NSSplitView 内置拖拽不生效）
    /// internal：拖动期间控制器要跳过宽度写盘，松手后由 onResizeDragEnded 补写
    internal private(set) var isDragging = false

    /// 双面板分栏：最小宽度按窗口宽度软降到 360；侧栏分栏保持固定 min/max。
    var adaptivePaneMinimum = false

    /// 双面板分栏允许双击 50/50 与 25/50/75 吸附。
    var allowsRatioGestures = false

    /// 一次手动调宽结束（松手）。控制器在此补写宽度记忆。
    var onResizeDragEnded: (() -> Void)?

    /// 双击分栏（仅双面板）。
    var onDoubleClickDivider: (() -> Void)?

    /// 拖动时回调宽度浮标（text=nil 表示隐藏；rect 为分栏坐标系）。
    var onWidthBadgeChanged: ((_ text: String?, _ rectInSplit: NSRect?) -> Void)?

    /// 鼠标按下瞬间与分隔线的水平偏移。
    /// 把手在卡片外沿、与分隔线差 8pt；不记这个偏移的话，按下瞬间卡片会跳 8pt。
    private var grabOffset: CGFloat = 0

    /// 当前可见子视图数。单窗口模式下另一侧 isHidden，此时不应响应分隔线拖拽
    /// （否则可以把隐藏面板拖出来，与单窗状态冲突）
    private var visibleSubviewCount: Int { arrangedSubviews.filter { !$0.isHidden }.count }

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

    /// 左侧子视图最小宽度。侧栏分隔用 180，双操作区用 400。
    /// 分隔线厚度为 0 时系统不接管拖拽，最小/最大值只能由本类自行 clamp。
    var leadingMinWidth: CGFloat = FFDividerGlowMath.minPaneWidth

    /// 右侧子视图最小宽度（双操作区两侧各 400；侧栏分隔右侧为操作区，同样按 400 保底）
    var trailingMinWidth: CGFloat = FFDividerGlowMath.minPaneWidth

    /// 左侧子视图最大宽度（侧栏 280；双操作区不限）
    var leadingMaxWidth: CGFloat?

    /// 当前把手 X 列表
    private var handlePositions: [CGFloat] { handlePositionsProvider?() ?? [] }

    /// 把手 X 列表（自检用）
    var handleXPositions: [CGFloat] { handlePositions }

    /// 分隔线当前 X（左子视图右边缘）。仅限静止状态回读；
    /// 拖动中必须使用 applyDividerPosition 返回的计算值（布局可能滞后一拍）。
    private var currentDividerX: CGFloat {
        return arrangedSubviews.count >= 2 ? arrangedSubviews[0].frame.maxX : 0
    }

    /// 鼠标是否落在某个把手上
    /// internal：决策表要在 mouseDown 之前判定「这个点是不是把手」
    ///
    /// 2026-10-21 C2：标签条已提升为窗口级顶栏，分栏内部不再有标题带遮挡；
    /// 热区按 X 判定（±6pt = 12pt），但必须落在分栏自身高度内，
    /// 否则点到顶栏标签的缝隙 X 也会被误判成调宽。
    func handleHit(atX x: CGFloat, y: CGFloat) -> Bool {
        guard bounds.contains(NSPoint(x: x, y: y)) else { return false }
        return handlePositions.contains { abs(x - $0) <= FFDividerGlowMath.hotZoneRadius }
    }

    /// 窗口坐标点是否命中本 split 的某个把手
    func handleHit(windowPoint point: NSPoint) -> Bool {
        let local = convert(point, from: nil)
        return handleHit(atX: local.x, y: local.y)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard visibleSubviewCount >= 2 else {
            NSCursor.arrow.set()
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        if handleHit(atX: loc.x, y: loc.y) {
            handleCursor.set()
        } else if !isDragging {
            NSCursor.arrow.set()
        }
    }

    /// 绝对跟随：分隔线目标位置一律取 clamp(鼠标X + 偏移)，返回实际生效的位置。
    /// 按下瞬间即对齐鼠标正下方（跳动 ≤ 热区半径 6pt）。
    @discardableResult
    private func applyDividerPosition(mouseX: CGFloat, mouseY: CGFloat) -> CGFloat {
        let raw: CGFloat
        if adaptivePaneMinimum, bounds.width > 1 {
            let ratio = FFPaneWidthMath.snappedRatio(mouseX / bounds.width, total: bounds.width)
            raw = FFPaneWidthMath.clampLeft(ratio * bounds.width, total: bounds.width)
        } else {
            raw = FFDividerGlowMath.clampedDividerPosition(
                mouseX: mouseX,
                boundsWidth: bounds.width,
                leadingMin: leadingMinWidth,
                trailingMin: trailingMinWidth
            )
        }
        let clamped = leadingMaxWidth.map { min(raw, $0) } ?? raw
        setPosition(clamped, ofDividerAt: 0)
        showWidthBadge(position: clamped, mouseY: mouseY)
        return clamped
    }

    /// 命中把手（±6pt）：按下即对齐并进入拖拽；未命中：交给系统处理
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard visibleSubviewCount >= 2, handleHit(atX: point.x, y: point.y) else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2, allowsRatioGestures, bounds.width > 1 {
            setPosition(FFPaneWidthMath.doubleClickLeft(total: bounds.width), ofDividerAt: 0)
            onDoubleClickDivider?()
            return
        }
        isDragging = true
        // 记住「鼠标 ↔ 分隔线」的偏移：把手在卡片外沿，与分隔线相差一个卡片留白
        grabOffset = currentDividerX - point.x
        _ = applyDividerPosition(mouseX: point.x + grabOffset, mouseY: point.y)
        handleCursor.set()
    }

    /// 拖拽全程 1:1 跟随鼠标 X（绝对模型 + 起始偏移，无起点记账）
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, visibleSubviewCount >= 2 else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        applyDividerPosition(mouseX: point.x + grabOffset, mouseY: point.y)
    }

    /// 拖拽结束
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onWidthBadgeChanged?(nil, nil)
            onResizeDragEnded?()
        } else {
            super.mouseUp(with: event)
        }
        let loc = convert(event.locationInWindow, from: nil)
        if !handleHit(atX: loc.x, y: loc.y) {
            NSCursor.arrow.set()
        }
    }

    private func showWidthBadge(position: CGFloat, mouseY: CGFloat) {
        let text = "\(Int(position.rounded())) pt"
        let y = isFlipped ? mouseY + 10 : bounds.height - mouseY + 10
        onWidthBadgeChanged?(text, NSRect(x: position - 40, y: y, width: 80, height: 22))
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
    static let sidebarMinWidth: CGFloat = 180
    /// 侧栏可拖最大宽度
    static let sidebarMaxWidth: CGFloat = 280
    /// 只有拖侧栏缝才写侧栏宽度（窗口缩放/单双切换不写）。
    fileprivate func saveSidebarWidthOnly() {
        guard !isAdjustingPaneMode, let sidebar = mainSplitView?.arrangedSubviews.first else { return }
        let width = sidebar.frame.width
        guard width >= MainWindowController.sidebarMinWidth,
              width <= MainWindowController.sidebarMaxWidth else { return }
        sidebarWidthPreference = width
        UserDefaults.standard.set(Double(width), forKey: MainWindowController.sidebarWidthKey)
    }

    /// 只有拖双面板中缝/双击才写面板宽度与比例。
    fileprivate func savePaneWidthAndRatio() {
        guard !isAdjustingPaneMode,
              let split = paneSplitView,
              split.arrangedSubviews.count == 2,
              split.bounds.width > 1 else { return }
        let leftWidth = split.arrangedSubviews[0].frame.width
        guard leftWidth >= FFPaneWidthMath.effectiveMin(total: split.bounds.width) - 1 else { return }
        UserDefaults.standard.set(Double(leftWidth), forKey: MainWindowController.paneLeftWidthKey)
        paneWidthRatio = min(max(leftWidth / split.bounds.width, 0.01), 0.99)
    }

    private func updatePaneWidthRatioFromSplit() {
        guard let split = paneSplitView,
              split.arrangedSubviews.count == 2,
              split.bounds.width > 1 else { return }
        paneWidthRatio = min(max(split.arrangedSubviews[0].frame.width / split.bounds.width, 0.01), 0.99)
    }

    /// 窗口尺寸变化后：先把侧栏钉回偏好宽度，再让两栏按比例伸缩。
    private func enforceWindowResizeLayout() {
        guard !isAdjustingPaneMode, !isAnimatingPaneMode,
              let window, let main = mainSplitView else { return }
        if isSidebarVisible, let preferred = sidebarWidthPreference, !main.isDragging {
            window.contentView?.layoutSubtreeIfNeeded()
            main.setPosition(preferred, ofDividerAt: 0)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        applyProportionalPaneWidths()
    }

    /// 窗口缩放时两栏按记忆比例伸缩；侧栏宽度由偏好值保持。
    func applyProportionalPaneWidths() {
        guard !isApplyingProportionalPanes,
              !isAdjustingPaneMode,
              !isSinglePaneMode,
              let split = paneSplitView,
              !split.isDragging,
              split.arrangedSubviews.count == 2,
              split.bounds.width > 1 else { return }
        let total = split.bounds.width
        let target = FFPaneWidthMath.clampLeft(total * paneWidthRatio, total: total)
        let current = split.arrangedSubviews[0].frame.width
        guard abs(current - target) > 1 else { return }
        isApplyingProportionalPanes = true
        split.setPosition(target, ofDividerAt: 0)
        split.adjustSubviews()
        isApplyingProportionalPanes = false
    }

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
    /// Task 9：面板单一真值/焦点/工具/任务所有权迁移到 coordinator，
    /// MainWindowController 通过计算属性转发，保持既有调用点不变。
    lazy var paneCoordinator = PaneCoordinator(leftState: leftPaneViewModel.state,
                                               rightState: rightPaneViewModel.state)
    lazy var sidebarCoordinator = SidebarCoordinator()
    lazy var toolCoordinator = ToolCoordinator()
    lazy var taskCoordinator = TaskCoordinator()
    lazy var shellCoordinator = WindowShellCoordinator(window: window,
                                                      panes: paneCoordinator,
                                                      sidebar: sidebarCoordinator,
                                                      tools: toolCoordinator,
                                                      tasks: taskCoordinator)

    /// XCTest 注入到宿主 App 时不得写用户级设置（启动路径/窗口状态）。
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["FF_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// 2026-10-21：窗口内唯一活动面板真值（点击/Tab/⌘1/⌘2/侧栏/菜单都写它）。
    var focus: WindowFocusModel { paneCoordinator.focus }
    /// 迁移期：每面板单一真值，视图仍通过 PaneViewModel 加载。
    var leftPaneStore: PaneStore { paneCoordinator.leftStore }
    var rightPaneStore: PaneStore { paneCoordinator.rightStore }
    var activePane: PaneSide {
        get { focus.activePane }
        set { focus.activate(newValue) }
    }
    /// 防抖: 选中变更工作项，用于取消上一次未完成的 UI 更新，防止快速点击时窗口跳动
    private var selectionChangeWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    /// 上一次真正刷新过列表的状态；选中变化不再触发整表 reload。
    private var lastRenderedState: [PaneSide: PaneState] = [:]
    /// 已应用的视图模式；同一模式不再 reload / 重建 key loop。
    private var lastAppliedViewMode: [PaneSide: ViewMode] = [:]
    /// 磁盘可用空间缓存与在途请求（避免每次状态发射都同步 statfs）。
    private var diskFreeCache: [String: String] = [:]
    private var diskFreePending: Set<String> = []

    /// 全局撤销/重做栈（per-window）。通过覆盖 undoManager 计算属性让响应链使用它，
    /// Edit 菜单的 undo:/redo: 通过响应链自动路由到此 UndoManager。
    let ffUndoManager = UndoManager()

    /// 覆盖 NSResponder 的 undoManager，让响应链返回自定义的 UndoManager。
    override public var undoManager: UndoManager? {
        ffUndoManager
    }

    var sidebarView: SidebarView { sidebarCoordinator.view }
    internal var leftPaneContainer: NSView!
    private var rightPaneContainer: NSView!
    /// #3：分栏两端的卡片包装视图（单窗模式靠 isHidden 收起一侧）
    var leftPaneWrapper: NSView!
    var rightPaneWrapper: NSView!
    /// #3：当前是否单窗口模式（持久化到 single_pane_mode）
    var isSinglePaneMode = false
    /// 批次 1 B1-07：SMB 断线/重连的底部提示
    private var smbStatusToast: NSView?
    private var smbStatusLabel: NSTextField?
    private var smbStatusHideWork: DispatchWorkItem?
    /// #7：每个操作区顶部标签条与标签集合
    var leftTabStrip: PaneTabStripView?
    var rightTabStrip: PaneTabStripView?
    var leftTabsStore: PaneTabsStore?
    var rightTabsStore: PaneTabsStore?
    /// 2026-10-21 C2：窗口级全局顶栏（工具/侧栏/标签组/主题/单双栏）
    internal var globalTopBar: FFGlobalTopBar!
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
    /// 双面板左栏占比（窗口缩放时按此比例伸缩）
    private var paneWidthRatio: CGFloat = 0.5
    private var isApplyingProportionalPanes = false
    /// 侧栏目标宽度；窗口缩放时按此值钉住，而不是取可能被挤压后的 frame
    private var sidebarWidthPreference: CGFloat?

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
    /// 拖动分栏时显示的宽度浮标（挂在 mainContainer，不能放进 NSSplitView）
    private var dividerWidthBadge: FFDividerBadgeLabel!
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
    /// ⌘I 已改走按需详情浮层；此窗口仍供侧栏收藏等入口使用。
    var fileInfoWindowController: FileInfoWindowController?

    func detailsBar(for side: PaneSide) -> ExpandableDetailsBar? {
        side == .left ? leftDetailsBar : rightDetailsBar
    }

    enum ClipboardOperation {
        case copy
        case cut
    }

    // MARK: - Initialization

    /// - Parameters:
    ///   - startsWithSinglePane: 显式指定初始单/双栏；nil = 读用户上次的选择。
    ///     拖标签生成的新窗口必须传 true，不能继承源窗口的双栏状态。
    ///   - showImmediately: false = 先完成标签注入与定位，再由调用方显示，
    ///     避免新窗口在默认位置用默认内容闪一下。
    ///   - runsSelfTests: 拖拽自检会再创建窗口；派生窗口必须关掉，避免递归。
    public init(startsWithSinglePane: Bool? = nil,
                showImmediately: Bool = true,
                runsSelfTests: Bool = true) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FlowFinder"
        // #7：改用应用内标签条，关闭系统窗口标签，避免两套标签并存
        window.tabbingMode = .disallowed
        // 最小尺寸 1060×700：侧栏最小 180 + 两个操作区各 400 + 留白/分隔线，
        // 合计约 1012，1060 仍有可用余量。面板最小宽不再与窗口最小宽冲突。
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
        isSinglePaneMode = startsWithSinglePane
            ?? UserDefaults.standard.bool(forKey: Self.singlePaneModeKey)
        applyPaneMode()
        // 显示前完成侧栏/分栏初始定位，避免首帧 50/50 闪一下。
        applyInitialSplitPositions()

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
            self?.alignTrafficLightsToTopBar()
            // 批次 1 B1-03：选择「上次打开的位置」时恢复最后的活动面板
            if UserDefaults.standard.integer(forKey: FFUserDefaultsKeys.startupLocation) == FFStartupPath.Choice.lastLocation.rawValue,
               let restored = FFStartupPath.activePane(
                   from: UserDefaults.standard.string(forKey: FFStartupPath.lastActivePaneKey),
                   singlePane: self?.isSinglePaneMode ?? true) {
                self?.activatePane(restored)
            }
            self?.logPaneGeometry(" 启动")
        }

        // Wave2 P0-4（多窗口）：FSEvents 文件系统监控已上移至 AppDelegate 进程级单实例
        // （CoreBridge 的 watcher 重复 start 会顶掉旧 watcher），本窗口经
        // .fileSystemDidChange 通知接收变更并刷新受影响面板（setupNotifications 注册）。

        // setupUI 完成后再显示窗口（此时透明设置已就绪）
        if showImmediately {
            window.makeKeyAndOrderFront(nil)
        }

        #if DEBUG
        // 拖放落点自检：仅当以 FF_SELFTEST=1 启动时运行，结果写入 /tmp/ff-debug.log
        if runsSelfTests, ProcessInfo.processInfo.environment["FF_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                // 自检里的侧栏/区域断言假定侧栏可见；结束后恢复用户原状态。
                let wasSidebarVisible = self.isSidebarVisible
                if !wasSidebarVisible {
                    self.setSidebarVisible(true, animated: false)
                }
                self.runDragSelfTest()
                self.runInteractionPolicySelfTest()
                self.runRegionResolveSelfTest()
                self.runDragBehaviorSelfTest()
                self.runTabWeldSelfTest()
                self.runSidebarAvoidanceSelfTest()
                self.runPaneWidthSelfTest()
                self.runListShellSelfTest()
                self.runLayoutStressSelfTest()
                if !wasSidebarVisible {
                    self.setSidebarVisible(false, animated: false)
                }
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
        // AppKit 可能在激活时重排标题栏按钮；下一拍再对齐一次。
        DispatchQueue.main.async { [weak self] in
            self?.alignTrafficLightsToTopBar()
        }
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
        // 批次 1 B1-03：完整浏览会话——记录最后关闭窗口的活动面板
        if !MainWindowController.isRunningTests {
            UserDefaults.standard.set(activePane == .right ? "right" : "left",
                                      forKey: FFStartupPath.lastActivePaneKey)
        }
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
        updateGlobalTopBarLayout()
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
        updateGlobalTopBarLayout()
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
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarCoordinator.bindToolContext { [weak self] in self?.toolContext() }
        // 批次 1 B1-10：工具页进出后重建 keyViewLoop（含胶囊与 5 个工具行）
        sidebarCoordinator.view.onToolPageVisibilityChanged = { [weak self] in
            self?.buildKeyViewLoops()
        }

        // 左面板（工具栏 + 文件列表 + DetailsBar）—— 任务 R4: 操作区背景色
        leftPaneContainer = createPaneContainer(side: .left)
        rightPaneContainer = createPaneContainer(side: .right)

        // Pane Split View（左右操作区）— 任务 R5: 使用 FFSplitView 实现 divider 悬停高亮
        paneSplitView = FFSplitView()
        paneSplitView.isVertical = true
        paneSplitView.dividerStyle = .thin
        paneSplitView.adaptivePaneMinimum = true
        paneSplitView.allowsRatioGestures = true
        paneSplitView.leadingMinWidth = FFPaneWidthMath.hardMin
        paneSplitView.trailingMinWidth = FFPaneWidthMath.hardMin
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

        // 2026-10-21 C2：窗口级全局顶栏。标签组是顶栏的子视图，
        // 按左右面板的实际位置手动对齐（见 updateTabStripFrames）。
        let topBar = FFGlobalTopBar()
        globalTopBar = topBar
        leftTabStrip = topBar.leftTabStrip
        rightTabStrip = topBar.rightTabStrip
        leftTabStrip?.side = .left
        rightTabStrip?.side = .right
        leftTabStrip?.delegate = self
        rightTabStrip?.delegate = self
        topBar.setSidebarVisible(true)
        topBar.setSinglePaneMode(isSinglePaneMode)
        topBar.setThemeIcon(for: ThemeManager.shared.currentMode)
        topBar.onSidebarToggle = { [weak self] in
            guard let self else { return }
            self.setSidebarVisible(!self.isSidebarVisible, animated: true)
        }
        topBar.onThemeToggle = { [weak self] in
            self?.toggleThemeFromTopBar()
        }
        topBar.onPaneModeToggle = { [weak self] in
            self?.togglePaneMode()
        }
        mainContainer.addSubview(topBar)

        // 2026-10-20 #3：标签条已提升到全局顶栏。
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
            topBar.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: FFTopBarMetrics.height),

            // 内容区从全局顶栏下方开始；活动标签底边焊在顶栏底边。
            mainSplitView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            // 双操作区直接贴到底部进度栏；无全局状态栏。详情回到每侧操作区。
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

        let badge = FFDividerBadgeLabel(frame: .zero)
        badge.isEditable = false
        badge.isSelectable = false
        badge.isBordered = false
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94)
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        badge.alignment = .center
        badge.textColor = .labelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        badge.layer?.masksToBounds = true
        badge.isHidden = true
        mainContainer.addSubview(badge)
        dividerWidthBadge = badge

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
        // 2026-10-21 Phase 3：侧栏宽度只由侧栏缝写；面板宽度只由中缝写。
        mainSplitView.onResizeDragEnded = { [weak self] in
            self?.saveSidebarWidthOnly()
        }
        paneSplitView.onResizeDragEnded = { [weak self] in
            self?.savePaneWidthAndRatio()
        }
        paneSplitView.onDoubleClickDivider = { [weak self] in
            self?.savePaneWidthAndRatio()
        }
        for split in [mainSplitView, paneSplitView] {
            split?.onWidthBadgeChanged = { [weak self, weak split] text, rect in
                self?.updateDividerWidthBadge(text: text, rect: rect, in: split)
            }
        }

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
                self?.globalTopBar?.setThemeIcon(for: mode)
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

        // 初始 divider 位置已在 init 的 applyInitialSplitPositions() 中完成。

        // #7：两侧面板就绪后建立初始标签
        installTabStrips()

        taskCoordinator.start()
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

        // 2026-10-21 C2：标签条已提升到窗口级全局顶栏；卡片顶边直接焊到顶栏底边，
        // 根部内凹由顶栏标签条背板绘制，wrapper 不再承担标题带。
        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: wrapper.topAnchor),
            glow.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            glow.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: FFActivePaneBorderView.edgeOutset),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -FFActivePaneBorderView.edgeOutset),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -FFActivePaneBorderView.edgeOutset),
        ])
        if let strip = side == .left ? leftTabStrip : rightTabStrip {
            strip.onActiveTabFrameChanged = { [weak self] in
                self?.syncGlowTabRects()
            }
        }

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
        let container = SquircleView(cornerRadius: FFVisualTokens.Radius.panel, squircleFactor: 5.0, autoUpdateMask: true)
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
        detailsBar.metadataProvider = FFMetadataService()

        // 2026-10-21 C2：标签条提升到窗口级全局顶栏，由 setupUI 统一创建。

        // 内容裁切层：外层 SquircleView 保留背景与微光阴影，内层裁切工具栏/列表，
        // 让四个顶角都露出卡片的 12pt 连续曲率，而不是被整幅工具栏背景盖成直角。
        let contentClip = FFPaneContentClipView(cornerRadius: FFVisualTokens.Radius.panel)
        contentClip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentClip)

        // 添加到裁切层
        contentClip.addSubview(toolbar)
        contentClip.addSubview(listView)
        contentClip.addSubview(gridView)
        // v0.6.9: detailsBar 最后添加到容器（视觉最上层），作为浮层覆盖；不参与卡片裁切
        container.addSubview(detailsBar)
        // 2026-10-21：统一状态栏上线；常驻详情浮层退役（Task 5 改 ⌘I 按需浮层）。
        detailsBar.isHidden = false

        NSLayoutConstraint.activate([
            // 裁切层填满卡片；圆角由 FFPaneContentClipView 负责
            contentClip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentClip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentClip.topAnchor.constraint(equalTo: container.topAnchor),
            contentClip.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // 2026-10-20 #3：标签条已浮到窗口顶，工具栏直接顶到裁切层顶部
            toolbar.topAnchor.constraint(equalTo: contentClip.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentClip.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentClip.trailingAnchor),

            // v0.6.9: 文件列表底部锚定裁切层底部（不再锚定 detailsBar.topAnchor）
            // 文件列表始终占满操作区全高，详情栏以浮层形式覆盖在上方
            listView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: contentClip.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: contentClip.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: contentClip.bottomAnchor),

            gridView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: contentClip.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: contentClip.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: contentClip.bottomAnchor),

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
            // FileListView 内部会补上浮层距底部的 8pt。
            listView?.setBottomOverlayInset(height)
            gridView?.setBottomOverlayInset(height)
        }
        // 初始同步：收起态 54pt。
        listView.setBottomOverlayInset(detailsBar.currentHeight)
        gridView.setBottomOverlayInset(detailsBar.currentHeight)

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

    // MARK: - 调宽把手判定（2026-10-20 第五轮）

    /// 窗口坐标点是否命中调宽把手（中缝 / 侧栏缝的卡片外沿热区）
    func isPointOnResizeHandle(windowPoint point: NSPoint) -> Bool {
        mainSplitView?.handleHit(windowPoint: point) == true
            || paneSplitView?.handleHit(windowPoint: point) == true
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

    /// 命中视图属于哪一侧面板（按压反馈用）
    func paneSide(containing view: NSView) -> PaneSide? {
        if let left = leftPaneWrapper, view === left || view.isDescendant(of: left) {
            return .left
        }
        if let right = rightPaneWrapper, view === right || view.isDescendant(of: right) {
            return .right
        }
        return nil
    }

    /// 当前窗口参与标签落点判定的几何（屏幕坐标）。
    /// 拖动开始时缓存一次，拖动中只做矩形判定。
    func dragGeometry() -> FFWindowDropGeometry? {
        guard let window, let contentView = window.contentView else { return nil }

        func screenRect(_ view: NSView) -> CGRect {
            let inWindow = view.convert(view.bounds, to: nil)
            return window.convertToScreen(inWindow)
        }
        func screenRect(_ rect: NSRect, in view: NSView) -> CGRect {
            let inWindow = view.convert(rect, to: nil)
            return window.convertToScreen(inWindow)
        }

        var tabStrips: [PaneSide: FFTabStripGeometry] = [:]
        var paneContents: [PaneSide: FFPaneGeometry] = [:]
        var invalidRects: [CGRect] = []

        if isSidebarVisible {
            invalidRects.append(screenRect(sidebarView))
        }
        // 侧栏隐藏时红绿灯浮在内容上；无论侧栏是否可见都加一条交通灯无效带。
        let traffic = NSRect(x: 0, y: contentView.bounds.height - 36, width: 90, height: 36)
        invalidRects.append(screenRect(traffic, in: contentView))

        for side in PaneSide.allCases {
            guard let strip = tabStrip(for: side), !strip.isHidden else { continue }
            tabStrips[side] = FFTabStripGeometry(
                rect: screenRect(strip),
                tabRects: strip.allTabItems().map(screenRect)
            )
            if let addButtonRect = strip.addButtonFrame {
                invalidRects.append(screenRect(addButtonRect, in: strip))
            }
            guard let wrapper = paneWrapper(for: side), !wrapper.isHidden else { continue }
            let realCount = tabsStore(for: side)?.tabs.filter { !$0.isPlaceholder }.count ?? 0
            paneContents[side] = FFPaneGeometry(rect: screenRect(wrapper), realTabCount: realCount)
        }

        return FFWindowDropGeometry(
            windowID: ObjectIdentifier(self),
            frame: window.frame,
            isSinglePane: isSinglePaneMode,
            activePane: activePane,
            tabStrips: tabStrips,
            paneContents: paneContents,
            invalidRects: invalidRects
        )
    }

    /// 窗口坐标点落在操作区的哪一侧。
    ///
    /// 双栏：按操作区中线分左右面板。
    /// 单栏：同样按中线分左右半区——返回的是**落点半区**（新面板将出现的一侧），
    /// 不是活动面板。旧实现单栏直接返回 `activePane`，导致拖到右半区仍出在左边。
    func operationSide(near point: NSPoint) -> PaneSide? {
        guard let cv = window?.contentView else { return nil }
        let localX = cv.convert(NSPoint(x: point.x, y: 0), from: nil).x
        let sidebarRight = sidebarView.superview.map {
            cv.convert(sidebarView.frame, from: $0).maxX
        } ?? 0
        let midX = (sidebarRight + cv.bounds.maxX) / 2
        return localX < midX ? .left : .right
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
        if let mouseEventMonitor {
            NSEvent.removeMonitor(mouseEventMonitor)
            self.mouseEventMonitor = nil
        }
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        FFPaneDragController.shared.unregister(owner: self)
        // Bug 6 修复：移除所有 NotificationCenter observer，防止悬空回调
        NotificationCenter.default.removeObserver(self)
        // 任务 F10-3: 移除卷挂载/卸载通知监听（迁移自 SidebarView deinit）
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        // Wave3 Task 6: 取消挂起的 FSEvents 合帧 flush
        fsChangeFlushWorkItem?.cancel()
        taskCoordinator.stop()
    }

    private func setupBindings() {
        leftPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.leftPaneStore.apply(state: state)
                self.leftPaneStore.syncSelection(from: state.selectedFiles)
                self.updatePaneUI(side: .left, state: state)
            }
            .store(in: &cancellables)

        rightPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.rightPaneStore.apply(state: state)
                self.rightPaneStore.syncSelection(from: state.selectedFiles)
                self.updatePaneUI(side: .right, state: state)
            }
            .store(in: &cancellables)

        focus.$activePane
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateActivePaneVisual()
                // 切换活动面板时强制统计一次；此前该面板可能在后台加载完成。
                let side = self.focus.activePane
                let state = (side == .left ? self.leftPaneViewModel : self.rightPaneViewModel).state
                self.lastTagCountSignature[side] = FFPerformancePolicy.tagCountSignature(state)
                self.scheduleTagCountRefresh(side: side)
            }
            .store(in: &cancellables)
    }

    // MARK: - 批次 1 B1-07：SMB 状态提示

    @objc private func handleSortPreferencesChanged() {
        leftPaneViewModel.refresh()
        rightPaneViewModel.refresh()
    }

    @objc private func handleSMBDisconnected(_ note: Notification) {
        let volume = note.userInfo?["volumeName"] as? String ?? "网络卷"
        showSMBStatus(FFSMBStatusText.reconnecting(volume: volume, attempt: 1, max: 3))
    }

    @objc private func handleSMBReconnected(_ note: Notification) {
        let volume = note.userInfo?["volumeName"] as? String ?? "网络卷"
        showSMBStatus(FFSMBStatusText.reconnected(volume: volume))
    }

    @objc private func handleSMBReconnectFailed(_ note: Notification) {
        let volume = note.userInfo?["volumeName"] as? String ?? "网络卷"
        showSMBStatus(FFSMBStatusText.failed(volume: volume), showsRetry: true)
    }

    @objc private func retrySMBReconnect() {
        SMBBridge.shared.reconnectSavedConnections()
    }

    private func showSMBStatus(_ text: String, showsRetry: Bool = false) {
        guard let content = window?.contentView else { return }
        smbStatusHideWork?.cancel()

        let toast: NSView
        if let existing = smbStatusToast {
            toast = existing
        } else {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor
            container.layer?.cornerRadius = 10
            container.layer?.borderWidth = 0.5
            container.layer?.borderColor = NSColor.separatorColor.cgColor

            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.heightAnchor.constraint(equalToConstant: 32),
            ])
            content.addSubview(container)
            NSLayoutConstraint.activate([
                container.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                container.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -56),
            ])
            smbStatusToast = container
            smbStatusLabel = label
            toast = container
        }

        if let label = smbStatusLabel {
            label.stringValue = text
        }
        // 重试按钮：复用右侧约束，仅失败时添加
        if showsRetry, let container = toast as? NSView,
           let label = smbStatusLabel {
            if container.viewWithTag(8801) == nil {
                let button = NSButton(title: "重试", target: self, action: #selector(retrySMBReconnect))
                button.bezelStyle = .inline
                button.controlSize = .small
                button.tag = 8801
                button.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(button)
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
                    button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                    button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                ])
            }
        } else {
            toast.viewWithTag(8801)?.removeFromSuperview()
        }
        toast.isHidden = false
        toast.alphaValue = 1

        let work = DispatchWorkItem { [weak self] in
            self?.smbStatusToast?.isHidden = true
        }
        smbStatusHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleSortPreferencesChanged),
                                               name: .sortPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSMBDisconnected(_:)),
                                               name: .smbVolumeDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSMBReconnected(_:)),
                                               name: .smbVolumeReconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSMBReconnectFailed(_:)),
                                               name: .smbVolumeReconnectFailed, object: nil)
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
        switch notification.userInfo?["section"] as? String {
        case "about":
            SettingsWindowController.shared.showAboutSection()
        case "tagManage":
            SettingsWindowController.shared.showTagManagementSection()
        default:
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
    /// 测试用：返回当前窗口的 keyViewLoop 组成（顺序与 Tab 一致）。
    func keyViewLoopForTesting() -> [NSView] {
        buildKeyViewLoops()
        var loop: [NSView] = []
        if isSidebarVisible {
            let sidebar = sidebarView
            loop.append(sidebar.sidebarFocusableView)
            loop.append(sidebar.toolPillFocusView)
            if let page = sidebar.toolPageForTesting {
                loop.append(contentsOf: page.focusableViewsForTesting())
            }
        }
        loop.append(contentsOf: keyViewChain(for: .left))
        loop.append(contentsOf: keyViewChain(for: .right))
        return loop
    }

    private func buildKeyViewLoops() {
        var loop: [NSView] = []
        // 批次 1 B1-10：侧栏工具胶囊与工具页行排在面板之前
        if isSidebarVisible {
            let sidebar = sidebarView
            loop.append(sidebar.sidebarFocusableView)
            loop.append(sidebar.toolPillFocusView)
            if let page = sidebar.toolPageForTesting {
                loop.append(contentsOf: page.focusableViewsForTesting())
            }
        }
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

        // 更新网格视图
        let grid = side == .left ? leftFileGridView : rightFileGridView
        if grid?.viewModel !== paneVM {
            grid?.viewModel = paneVM
        }

        let shouldReload = FFPaneReloadPolicy.shouldReloadList(
            previous: lastRenderedState[side],
            current: state
        )
        lastRenderedState[side] = state
        if shouldReload {
            fileListView?.reloadData()
            grid?.reloadData()
            // #7：导航 / 排序 / 筛选变化后同步标签标题与激活态
            syncTabStrip(side: side, state: state)
        } else {
            // 选中变化不需要重建标签条；只把状态写回活动标签。
            tabsStore(for: side)?.updateActiveState(state)
        }

        // 视图模式切换：只有真正变化才 reload / 重建 key loop。
        if FFViewModePolicy.shouldApply(previous: lastAppliedViewMode[side],
                                        current: state.viewMode) {
            lastAppliedViewMode[side] = state.viewMode
            updateViewMode(side: side, mode: state.viewMode)
        }

        // 问题7修复：刷新状态栏（项目数 + 磁盘可用空间）
        // 磁盘空间走缓存 + 后台读取，不在每次状态发射时同步 statfs。
        let detailsBar = side == .left ? leftDetailsBar : rightDetailsBar
        let itemCount = state.files.count
        let diskFree = diskFreeText(for: state.path)
        // v0.7.4 修订 4：传入当前目录路径（未选中时详情栏显示该文件夹图标）
        detailsBar?.updateStatus(itemCount: itemCount, diskFree: diskFree, currentDirectoryPath: state.path)

        // 任务 F11-8: 状态变化时同步侧边栏标签高亮（导航清除 tagFilter / 切换活动面板时高亮需跟随）
        if side == activePane {
            // Wave2 P0-4（多窗口）：通知携带本窗口身份（object），其他窗口的侧边栏据此忽略
            NotificationCenter.default.post(
                name: .paneTagFilterChanged, object: window,
                userInfo: ["tagFilter": state.tagFilter as Any,
                           "tagFilters": state.tagFilters]
            )
            // DESIGN-SPEC §5.2：仅在目录/文件集合变化时统计标签（选中不触发）。
            let signature = FFPerformancePolicy.tagCountSignature(state)
            if lastTagCountSignature[side] != signature {
                lastTagCountSignature[side] = signature
                scheduleTagCountRefresh(side: side)
            }
        }
    }

    /// 工具组上下文：读取活动面板与选择，不触碰视图内部状态。
    func toolContext() -> FFToolContext {
        let viewModel = activePaneViewModel
        return toolCoordinator.context(activePane: activePane,
                                       currentPath: viewModel.state.path,
                                       selection: viewModel.selectedFiles,
                                       window: self)
    }

    /// ⌘I：展开当前活动面板的操作区内详情栏；不再创建独立浮层。
    func showDetailsForActiveSelection() {
        let side = activePane
        let viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
        guard let bar = detailsBar(for: side) else { return }
        bar.expand()
        bar.update(with: viewModel.selectedFiles)
    }

    // MARK: - 标签计数（DESIGN-SPEC §5.2）

    private var tagCountWorkItem: DispatchWorkItem?
    /// 代次：导航/切换面板期间旧统计可能晚于新统计返回，用它丢弃旧结果
    private var tagCountGeneration = 0
    /// 上次统计对应的廉价签名；选中/加载状态发射不再重复触发 xattr 扫描。
    private var lastTagCountSignature: [PaneSide: String] = [:]

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
            sidebarView.updateTagCounts([:])
            return
        }

        let work = DispatchWorkItem { [weak self] in
            TagCountService.shared.count(paths: paths) { counts in
                guard let self, self.tagCountGeneration == generation else { return }
                self.sidebarView.updateTagCounts(counts)
            }
        }
        tagCountWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    /// 问题7修复：获取指定路径所在卷的可用磁盘空间。
    /// 后台读取 + 按路径缓存，主线程先拿到 nil（或旧值），不阻塞状态刷新。
    private func diskFreeText(for path: String) -> String? {
        guard !path.isEmpty else { return nil }
        if let cached = diskFreeCache[path] { return cached }
        guard !diskFreePending.contains(path) else { return nil }
        diskFreePending.insert(path)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text = Self.readDiskFreeSpace(path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.diskFreePending.remove(path)
                if let text {
                    self.diskFreeCache[path] = text
                }
                self.refreshStatusBars(for: path)
            }
        }
        return nil
    }

    private static func readDiskFreeSpace(_ path: String) -> String? {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let freeSize = attrs[.systemFreeSize] as? UInt64 {
                return ByteCountFormatter.string(fromByteCount: Int64(freeSize), countStyle: .file) + " 可用"
            }
        } catch {}
        return nil
    }

    private func refreshStatusBars(for path: String) {
        let text = diskFreeCache[path]
        if leftPaneViewModel.state.path == path {
            leftDetailsBar?.updateStatus(itemCount: leftPaneViewModel.state.files.count,
                                         diskFree: text,
                                         currentDirectoryPath: path)
        }
        if rightPaneViewModel.state.path == path {
            rightDetailsBar?.updateStatus(itemCount: rightPaneViewModel.state.files.count,
                                          diskFree: text,
                                          currentDirectoryPath: path)
        }
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
              let split = mainSplitView else { return }
        let sidebar = sidebarView

        // 分隔线归零后 frame 宽度就取不到了，隐藏前先记下来
        if !visible, sidebar.frame.width >= MainWindowController.sidebarMinWidth {
            savedSidebarWidthWhileHidden = sidebar.frame.width
        }

        isSidebarVisible = visible
        UserDefaults.standard.set(!visible, forKey: Self.sidebarHiddenKey)
        // 顶栏侧栏键常驻；旧的浮动开关退役，避免与顶栏按钮重叠。
        sidebarRevealHost?.isHidden = true
        globalTopBar?.setSidebarVisible(visible)
        applySidebarHiddenToolbarInset()

        // 动画期间放开最小宽度：0 宽是「收起」的合法状态
        sidebarMinWidthOverride = 0
        (mainSplitView as? FFSplitView)?.leadingMinWidth = 0
        if visible { sidebar.isHidden = false }

        let target = visible
            ? max(MainWindowController.sidebarMinWidth,
                  savedSidebarWidthWhileHidden ?? sidebarWidthPreference ?? MainWindowController.restoredSidebarWidth())
            : 0
        if visible {
            sidebarWidthPreference = target
        }

        animateMainDivider(to: target, animated: animated) { [weak self] in
            guard let self else { return }
            if visible {
                self.sidebarMinWidthOverride = nil
                (self.mainSplitView as? FFSplitView)?.leadingMinWidth = MainWindowController.sidebarMinWidth
            } else {
                self.sidebarView.isHidden = true
                self.mainSplitView?.setPosition(0, ofDividerAt: 0)
                (self.mainSplitView as? FFSplitView)?.leadingMinWidth = 0
            }
            // 侧栏动画结束后 wrapperLeading 才变成最终值；必须再算一次标签条左缘，
            // 否则 offset 仍停留在动画前的 0，标签条会压在红绿灯上。
            self.updateTabStripFrames()
            FFLayoutDiagnostics.logTransition("侧栏\(visible ? "显示" : "隐藏")完成", self)
            FFLayoutDiagnostics.logNextRunLoop("侧栏\(visible ? "显示" : "隐藏")下一拍", self)
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
        enforceWindowResizeLayout()
        updateTabStripFrames()
        alignTrafficLightsToTopBar()
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

    /// 刷新全局顶栏：面板矩形、标签组可见性、卡片同色背板、发光轮廓。
    ///
    /// 标签组挂在窗口级顶栏里，不在分栏层级内；跨 NSSplitView 的 Auto Layout
    /// 不可靠（实测 width 恒为 0），因此按 wrapper 的实际 frame 手动换算。
    func updateTabStripFrames() {
        guard let bar = globalTopBar else { return }
        let barHeight = bar.bounds.height > 1 ? bar.bounds.height : FFTopBarMetrics.height

        func paneRect(_ wrapper: NSView?) -> NSRect? {
            guard let wrapper, let superview = wrapper.superview,
                  wrapper.frame.width > 1 else { return nil }
            let rect = bar.convert(wrapper.frame, from: superview)
            return NSRect(x: rect.minX, y: 0, width: rect.width, height: barHeight)
        }

        bar.update(paneFrames: (paneRect(leftPaneWrapper), paneRect(rightPaneWrapper)),
                   isSinglePane: isSinglePaneMode,
                   activePane: activePane,
                   sidebarVisible: isSidebarVisible)
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()

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
        // 2026-10-21 C2：顶栏独立占 44pt，红绿灯/侧栏开关不再压住面板工具栏；
        // 两侧工具栏始终保留 8pt 缩进（修复隐藏侧栏后面包屑/搜索被推到 112）。
        leftPaneToolbar?.leadingInset = 8
        rightPaneToolbar?.leadingInset = 8
        updateTabStripFrames()
    }

    // MARK: - 单/双窗口模式（2026-10-18 #3）

    @objc private func handlePaneModeToggle(_ notification: Notification) {
        // 多窗口：只响应本窗口侧边栏/窗口发出
        if let source = notification.object as? AnyObject,
           !(source === sidebarView), !(source === window) { return }
        togglePaneMode()
    }

    /// 顶栏单双栏键入口。
    func togglePaneMode() {
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

    /// 顶栏主题键入口。
    func toggleThemeFromTopBar() {
        let newMode = ThemeManager.shared.currentMode.toggled
        ThemeManager.shared.applyMode(newMode)
        globalTopBar?.setThemeIcon(for: newMode)
    }

    private func updateDividerWidthBadge(text: String?, rect: NSRect?, in split: FFSplitView?) {
        guard let badge = dividerWidthBadge, let container = mainContainerView else { return }
        guard let text, let rect, let split, split.window != nil else {
            badge.isHidden = true
            return
        }
        badge.stringValue = text
        let content = badge.intrinsicContentSize
        let size = NSSize(width: max(52, content.width + 16), height: 22)
        let converted = container.convert(rect, from: split)
        let x = min(max(converted.midX - size.width / 2, 4),
                    max(4, container.bounds.width - size.width - 4))
        let y = min(max(converted.minY, 4),
                    max(4, container.bounds.height - size.height - 4))
        badge.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        container.addSubview(badge, positioned: .above, relativeTo: nil)
        badge.isHidden = false
    }

    /// 供布局测试/窗口事件调用的统一入口。
    func updateGlobalTopBarLayout() {
        updateTabStripFrames()
        globalTopBar?.needsLayout = true
        globalTopBar?.layoutSubtreeIfNeeded()
        alignTrafficLightsToTopBar()
    }

    /// 把系统红绿灯的垂直中心移到顶栏共用中线（水平位置保持系统默认）。
    func alignTrafficLightsToTopBar() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let content = window.contentView else { return }
        let contentTopInWindow = content.convert(
            NSPoint(x: 0, y: content.bounds.height), to: nil).y
        let targetCenterY = contentTopInWindow - FFTopBarMetrics.centerline
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type),
                  let superview = button.superview else { continue }
            var frame = button.frame
            let targetCenter = superview.convert(
                NSPoint(x: frame.midX, y: targetCenterY), from: nil)
            let newY = targetCenter.y - frame.height / 2
            guard abs(frame.origin.y - newY) > 0.5 else { continue }
            frame.origin.y = newY
            button.frame = frame
        }
    }

    /// 显示前完成侧栏/分栏初始定位（主窗口与拖出的新窗口共用）。
    private func applyInitialSplitPositions() {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let preferredSidebar = max(MainWindowController.sidebarMinWidth,
                                   MainWindowController.restoredSidebarWidth())
        sidebarWidthPreference = preferredSidebar
        let sidebarWidth = UserDefaults.standard.bool(forKey: Self.sidebarHiddenKey)
            ? 0
            : preferredSidebar
        mainSplitView?.setPosition(sidebarWidth, ofDividerAt: 0)
        if let split = paneSplitView, split.bounds.width > 1, !isSinglePaneMode {
            split.adjustSubviews()
            split.layoutSubtreeIfNeeded()
            let saved = MainWindowController.restoredPaneLeftWidth()
            let target = saved > 0 ? saved : split.bounds.width / 2
            let minWidth = FFPaneWidthMath.effectiveMin(total: split.bounds.width)
            let maxPos = max(minWidth, split.bounds.width - minWidth)
            split.setPosition(min(max(target, minWidth), maxPos), ofDividerAt: 0)
            split.adjustSubviews()
            split.layoutSubtreeIfNeeded()
            updatePaneWidthRatioFromSplit()
        }
        if UserDefaults.standard.bool(forKey: Self.sidebarHiddenKey) {
            setSidebarVisible(false, animated: false)
        }
        updateGlobalTopBarLayout()
    }

    /// 拖标签生成的新窗口在显示前调用。
    func prepareForInitialDisplay() {
        applyInitialSplitPositions()
    }

    /// 应用单/双窗口布局：
    /// - 单窗：收起非活动面板（只留活动面板占满操作区），窗口同步收窄被收起那一侧的宽度；
    ///   最小宽度 760（侧栏 180 + 操作区 400 + 两侧留白）
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
                // 从单窗恢复时先强制布局，再把分隔线放回记忆中的左面板宽度。
                // 仅靠异步 setPosition 在「刚插回第二个 arranged subview」时会被
                // NSSplitView 的旧布局覆盖，表现是另一侧宽度恒为 0（看起来仍像单栏）。
                split.adjustSubviews()
                split.layoutSubtreeIfNeeded()
                let saved = MainWindowController.restoredPaneLeftWidth()
                let target = saved > 0 ? saved : split.bounds.width / 2
                let maxPos = max(FFDividerGlowMath.minPaneWidth,
                                 split.bounds.width - FFDividerGlowMath.minPaneWidth)
                split.setPosition(min(target, maxPos), ofDividerAt: 0)
                split.adjustSubviews()
                split.layoutSubtreeIfNeeded()
                updatePaneWidthRatioFromSplit()
                FFDebug.log("[PANEMODE] dual split=\(split.bounds) frames=\(split.arrangedSubviews.map { $0.frame })")
            }
        }
        globalTopBar?.setSinglePaneMode(single)
        // 单双栏切换后标签组/工具栏位置重算
        applySidebarHiddenToolbarInset()
        // 2026-10-20 #3：不再有「单栏单标签 → 拖面板退化成拖窗口」这层状态分支。
        // 拖面板只从标签起手，拖窗口只认区域白名单——行为不再随状态变化。
        updateActivePaneVisual()
        FFLayoutDiagnostics.logTransition("单双栏应用 single=\(single) active=\(activePane)", self)
        FFLayoutDiagnostics.logNextRunLoop("单双栏下一拍 single=\(single) active=\(activePane)", self)
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
                guard let self else { return }
                let saved = self.sidebarWidthPreference
                    ?? max(MainWindowController.sidebarMinWidth, self.sidebarView.frame.width)
                self.mainSplitView?.setPosition(saved, ofDividerAt: 0)
                self.isAdjustingPaneMode = false
            }
            return
        }
        let sidebarWidth = sidebarWidthPreference
            ?? max(MainWindowController.sidebarMinWidth, sidebarView.frame.width)
        isAdjustingPaneMode = true
        window.setFrame(frame, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        mainSplitView?.setPosition(sidebarWidth, ofDividerAt: 0)
        isAdjustingPaneMode = false
    }

    private func updateActivePaneVisual() {
        leftActiveBorder?.isHidden = activePane != .left
        rightActiveBorder?.isHidden = activePane != .right
        FFPaneGlow.apply(to: leftPaneContainer, active: activePane == .left)
        FFPaneGlow.apply(to: rightPaneContainer, active: activePane == .right)
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
            wrapper.isHidden = false
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            if !split.arrangedSubviews.contains(wrapper) {
                // 可能残留在 split.subviews 但不参与排列；先彻底摘掉再按左右序插回。
                if wrapper.superview != nil {
                    split.removeArrangedSubview(wrapper)
                    wrapper.removeFromSuperview()
                }
                if wrapper === leftPaneWrapper {
                    split.insertArrangedSubview(wrapper, at: 0)
                } else {
                    split.addArrangedSubview(wrapper)
                }
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

        // 记住两侧当前目录，供下次启动还原。
        // XCTest 会创建真实 MainWindowController，测试专用环境不得污染用户的首启路径。
        if !MainWindowController.isRunningTests {
            for (vm, key) in [(leftPaneViewModel, FFStartupPath.lastLeftKey),
                              (rightPaneViewModel, FFStartupPath.lastRightKey)] {
                vm.$state.map(\.path).removeDuplicates().sink { path in
                    guard !path.isEmpty else { return }
                    UserDefaults.standard.set(path, forKey: key)
                }.store(in: &cancellables)
            }
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
            userInfo: ["tagFilter": vm.state.tagFilter as Any,
                       "tagFilters": vm.state.tagFilters]
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
        sidebarView.needsDisplay = true
        sidebarView.refreshSelectionAppearance()
        leftFileListView?.refreshAppearance()
        rightFileListView?.refreshAppearance()
        leftFileGridView?.refreshAppearance()
        rightFileGridView?.refreshAppearance()
        // 活动面板微光跟随统一强调色。
        leftActiveBorder?.ringColor = FFAccent.current
        rightActiveBorder?.ringColor = FFAccent.current
        updateActivePaneVisual()
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
        let additive = notification.userInfo?["additive"] as? Bool ?? false
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.toggleTagFilter(tag, additive: additive)
        // 发布通知让侧边栏更新标签高亮。观察方（SidebarView）按 object as? NSWindow
        // 过滤他窗口，必须携带本窗口对象（round-2 复核：object: self 对 NSWindow
        // 转型失败会被观察方跳过过滤，跨窗口高亮串扰依旧）
        NotificationCenter.default.post(
            name: .paneTagFilterChanged, object: window,
            userInfo: ["tagFilter": vm.state.tagFilter as Any,
                       "tagFilters": vm.state.tagFilters]
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
        // pane split view（left + right panes）：首选 400，窗口窄时软降到 360
        if splitView === paneSplitView {
            return FFPaneWidthMath.effectiveMin(total: splitView.bounds.width)
        }
        return proposedMinimumPosition
    }

    /// 限制每个面板的最大坐标，防止一个面板占据过多空间
    public func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 主 split view：sidebar 最大 280（DESIGN-SPEC B-01）
        if splitView === mainSplitView {
            return MainWindowController.sidebarMaxWidth
        }
        // pane split view：留出同样的最小宽度给另一个面板
        if splitView === paneSplitView {
            let totalWidth = splitView.bounds.width
            let minPane = FFPaneWidthMath.effectiveMin(total: totalWidth)
            return max(totalWidth - minPane, minPane)
        }
        return proposedMaximumPosition
    }

    /// 拖动时实时更新布局 + 记忆侧栏宽度
    public func splitViewDidResizeSubviews(_ notification: Notification) {
        // 触发布局更新
        if let splitView = notification.object as? NSSplitView {
            splitView.window?.layoutIfNeeded()
            // 分栏位置变化会改变标签组位置，实时重算。
            updateTabStripFrames()
            // Phase 3：宽度记忆只在用户拖拽松手时写（onResizeDragEnded），
            // 窗口缩放/单双切换/程序化 setPosition 都不写。
        }
    }
}

// MARK: - PaneSide

enum FFViewModePolicy {
    static func shouldApply(previous: ViewMode?, current: ViewMode) -> Bool {
        previous != current
    }
}

/// 只有影响列表内容的字段变化才整表 reload；选中变化交给列表自己处理。
enum FFPaneReloadPolicy {
    static func shouldReloadList(previous: PaneState?, current: PaneState) -> Bool {
        guard let previous else { return true }
        return previous.path != current.path
            || previous.files != current.files
            || previous.viewMode != current.viewMode
            || previous.searchQuery != current.searchQuery
            || previous.tagFilter != current.tagFilter
            || previous.sortField != current.sortField
            || previous.sortAscending != current.sortAscending
            || previous.groupBy != current.groupBy
    }
}

enum PaneSide: Hashable, CaseIterable {
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
