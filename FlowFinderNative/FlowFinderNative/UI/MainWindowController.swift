import Cocoa
import Combine
import QuickLook

/// 自定义 NSSplitView 子类：任务 R5 — divider 悬停高亮
/// 悬停时左右卡片边缘显示 1pt accent 色边框，提示可拖动调整操作区横向大小
private class FFSplitView: NSSplitView {
    private var dividerTrackingArea: NSTrackingArea?
    /// 悬停时是否高亮（由 mouseMoved 判断鼠标位置是否在 divider 附近 ±4pt）
    private var isHoveringDivider = false {
        didSet {
            if isHoveringDivider != oldValue {
                updateSubviewBorderHighlight()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = dividerTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        dividerTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let loc = convert(event.locationInWindow, from: nil)
        let dividerX = subviews.count >= 2 ? subviews[0].frame.maxX : 0
        isHoveringDivider = abs(loc.x - dividerX) <= 4
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // 鼠标进入后，mouseMoved 会判断是否在 divider 附近
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHoveringDivider = false
    }

    /// 更新子视图边框高亮
    private func updateSubviewBorderHighlight() {
        if isHoveringDivider {
            for subview in subviews {
                subview.layer?.borderWidth = 1
                subview.layer?.borderColor = NSColor.controlAccentColor.cgColor
            }
            // 鼠标变为双箭头调整光标
            NSCursor.resizeLeftRight.set()
        } else {
            for subview in subviews {
                subview.layer?.borderWidth = 0
            }
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
/// NSVisualEffectView 之所以能正常工作，是因为它重写了 isOpaque 返回 true。
/// 此处对 containerView 做同样处理，让窗口服务器捕获鼠标事件，同时不影响玻璃视觉效果
/// （玻璃效果由 NSGlassEffectView 子视图绘制，containerView 仅作为事件接收容器）。
private class OpaqueContainerView: NSView {
    override var isOpaque: Bool {
        return true
    }
}

// MARK: - MainWindowController

public class MainWindowController: NSWindowController {

    // MARK: - Properties

    private let leftPaneViewModel = PaneViewModel()
    private let rightPaneViewModel = PaneViewModel()
    private var activePane: PaneSide = .left
    private var cancellables = Set<AnyCancellable>()

    /// 全局撤销/重做栈（per-window）。通过覆盖 undoManager 计算属性让响应链使用它，
    /// Edit 菜单的 undo:/redo: 通过响应链自动路由到此 UndoManager。
    private let ffUndoManager = UndoManager()

    /// 覆盖 NSResponder 的 undoManager，让响应链返回自定义的 UndoManager。
    override public var undoManager: UndoManager? {
        ffUndoManager
    }

    private var sidebarView: SidebarView!
    private var leftPaneContainer: NSView!
    private var rightPaneContainer: NSView!
    /// 任务 F10-3: 设备浮层（浮动在窗口左下角独立区域，v0.6.6）
    /// 与侧边栏收藏夹/标签模块视觉分离，展开时显示所有设备不需滚动条
    private var devicePanel: NSView!
    /// 任务 F10-3: 设备浮层头部（汇总信息 + 折叠箭头）
    private var devicePanelHeader: DeviceHeaderView!
    /// 任务 F10-3: 设备浮层内容 stack（设备行纵向排列，高度自适应）
    private var devicePanelStack: NSStackView!
    /// 任务 F10-3: 设备数据源（迁移自 SidebarView，负责 statfs 读取磁盘容量、过滤隐藏卷）
    private let deviceDataSource = DeviceSidebarDataSource()
    /// 任务 F10-3: 设备浮层折叠状态（默认折叠，仅显示汇总头部）
    private var isDevicePanelCollapsed = true
    /// 任务 F10-3: 设备浮层折叠态高度（头部 32pt + 上下 padding 8pt = 48pt）
    private let devicePanelCollapsedHeight: CGFloat = 48
    /// 任务 F10-3: 设备行单行高度
    private let devicePanelRowHeight: CGFloat = 28
    /// 任务 F10-3: 设备浮层宽度（贴窗口左下角，固定 200pt）
    private let devicePanelWidth: CGFloat = 200
    /// 任务 F10-3: 设备浮层高度约束（折叠/展开时调整）
    private var devicePanelHeightConstraint: NSLayoutConstraint!
    /// 1.2 活动面板顶部 accent 色条（替代 borderWidth 方案）
    private var leftAccentBar: NSView!
    private var rightAccentBar: NSView!
    private var leftDetailsBar: ExpandableDetailsBar!
    private var rightDetailsBar: ExpandableDetailsBar!
    private var taskProgressBar: TaskProgressBar!
    private var mainSplitView: NSSplitView!
    private var paneSplitView: NSSplitView!
    /// 主内容容器引用（ThemeManager 需设置 appearance 以确保选中高亮可见）
    private var mainContainerView: NSView!
    /// 诊断：鼠标事件监听器（必须强引用，否则会被立即释放）
    private var mouseEventMonitor: Any?

    private var leftPaneToolbar: PaneToolbar!
    private var rightPaneToolbar: PaneToolbar!
    private var leftBreadcrumbBar: BreadcrumbBar!
    private var rightBreadcrumbBar: BreadcrumbBar!
    private var leftFileListView: FileListView!
    private var rightFileListView: FileListView!
    private var leftFileGridView: FileGridView!
    private var rightFileGridView: FileGridView!

    // Clipboard support (must be in main class, not extension)
    private var clipboardItems: [String] = []
    private var clipboardOperation: ClipboardOperation?

    /// F9-C: 「显示简介」独立窗口控制器（强引用，避免窗口被立即释放）。
    /// 每次显示时复用同一控制器并切换文件路径（仿访达可切换内容的 Get Info 窗口）。
    private var fileInfoWindowController: FileInfoWindowController?

    private enum ClipboardOperation {
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
        window.minSize = NSSize(width: 1000, height: 700)
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

        // 窗口距顶部保留 8pt 间距
        var frame = window.frame
        let screenHeight = NSScreen.main?.frame.height ?? 900
        let topGap: CGFloat = 8
        frame.origin.y = screenHeight - frame.size.height - topGap
        window.setFrame(frame, display: true)

        setupBindings()
        setupNotifications()
        loadInitialDirectories()

        // setupUI 完成后再显示窗口（此时透明设置已就绪）
        window.makeKeyAndOrderFront(nil)
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

    public func windowDidResignKey(_ notification: Notification) {
        FFDebug.log("windowDidResignKey: window lost key status")
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        FFDebug.log("windowDidBecomeMain: window is now main window")
    }

    public func windowDidResignMain(_ notification: Notification) {
        FFDebug.log("windowDidResignMain: window lost main status")
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
        window.title = "FlowFinder"

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
        paneSplitView.addArrangedSubview(leftPaneContainer)
        paneSplitView.addArrangedSubview(rightPaneContainer)

        // Main Split View（侧边栏 + 操作区）
        mainSplitView = NSSplitView()
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false
        mainSplitView.delegate = self
        mainSplitView.wantsLayer = true
        mainSplitView.layer?.backgroundColor = NSColor.clear.cgColor
        mainSplitView.addArrangedSubview(sidebarView)
        mainSplitView.addArrangedSubview(paneSplitView)

        // Task Progress Bar
        taskProgressBar = TaskProgressBar()
        taskProgressBar.translatesAutoresizingMaskIntoConstraints = false

        // 任务 F7: 使用 OpaqueContainerView 修复鼠标穿透与选中渲染（v0.6.5）
        // mainContainer（透明背景以透出玻璃效果）
        let mainContainer = OpaqueContainerView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        mainContainer.layer?.backgroundColor = NSColor.clear.cgColor
        mainContainer.addSubview(mainSplitView)
        mainContainer.addSubview(taskProgressBar)
        taskProgressBar.isHidden = true

        // 任务 F10-1: 移除 titlebarView 占位，mainSplitView 顶到顶部（v0.6.6）
        // 红绿灯由系统自动浮在侧边栏顶部上方（titlebarAppearsTransparent=true）
        // 侧边栏内部顶部留出红绿灯安全区（由 SidebarView 处理）
        // mainSplitView 的 divider 提供 1pt 发丝线（dividerStyle=.thin）
        NSLayoutConstraint.activate([
            // mainSplitView 顶到 mainContainer 顶部（红绿灯浮在上方）
            mainSplitView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            mainSplitView.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),

            taskProgressBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            taskProgressBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            taskProgressBar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            taskProgressBar.heightAnchor.constraint(equalToConstant: 0),
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

        // 任务 F10-3: 创建设备浮层并浮动到窗口左下角（v0.6.6）
        // 设备区域从侧边栏内部移出，改为独立卡片样式，与收藏夹/标签模块视觉分离
        devicePanel = createDevicePanel()
        mainContainer.addSubview(devicePanel)
        devicePanelHeightConstraint = devicePanel.heightAnchor.constraint(equalToConstant: devicePanelCollapsedHeight)
        devicePanelHeightConstraint.priority = .required
        NSLayoutConstraint.activate([
            // 贴 mainContainer 左下角：leading +8pt，bottom -8pt，宽度 200pt
            devicePanel.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor, constant: 8),
            devicePanel.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor, constant: -8),
            devicePanel.widthAnchor.constraint(equalToConstant: devicePanelWidth),
            devicePanelHeightConstraint,
        ])

        // 任务 F10-3: 监听卷挂载/卸载通知，刷新设备浮层（迁移自 SidebarView）
        let workspaceNC = NSWorkspace.shared.notificationCenter
        workspaceNC.addObserver(self, selector: #selector(handleVolumeMount(_:)),
                                name: NSWorkspace.didMountNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(handleVolumeUnmount(_:)),
                                name: NSWorkspace.didUnmountNotification, object: nil)

        window.contentView = visualEffectView

        // 确保玻璃效果不被 ThemeManager 覆盖
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.appearance = nil
            self.mainContainerView?.appearance = NSApp.effectiveAppearance
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

        // 诊断：监听所有鼠标按下事件
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let winTitle = event.window?.title ?? "nil"
            let loc = event.locationInWindow
            let hitView = event.window?.contentView?.hitTest(loc).map { String(describing: type(of: $0)) } ?? "nil"
            FFDebug.log("EVENT leftMouseDown window=\(winTitle) loc=\(loc) hitView=\(hitView)")
            return event
        }
        FFDebug.log("NSEvent monitor installed: \(mouseEventMonitor != nil)")

        // Holding priorities
        mainSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        mainSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        updateActivePaneVisual()

        // 注入 UndoManager 到各 PaneViewModel
        leftPaneViewModel.undoManager = undoManager
        rightPaneViewModel.undoManager = undoManager

        // I1: 注入对侧 ViewModel
        leftFileListView.counterpartViewModel = rightPaneViewModel
        rightFileListView.counterpartViewModel = leftPaneViewModel
        leftFileGridView.counterpartViewModel = rightPaneViewModel
        rightFileGridView.counterpartViewModel = leftPaneViewModel

        // 初始 divider 位置
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.mainSplitView.setPosition(220, ofDividerAt: 0)
            let totalWidth = self.paneSplitView.bounds.width
            if totalWidth > 0 {
                self.paneSplitView.setPosition(totalWidth / 2, ofDividerAt: 0)
            }
            // 任务 F10-3: 初始化设备浮层内容（构建设备行 + 更新汇总头部）
            self.rebuildDevicePanelRows()
            self.updateDevicePanelSummary()
        }

        TaskSchedulerManager.shared.startPolling()
    }

    /// 创建面板容器（工具栏 + 文件列表/网格 + DetailsBar）
    /// 任务 F2: 操作区撑满（仿访达），无圆角（v0.6.5）
    /// 任务 F11-1: 操作区改为实体背景（日间#F5F5F5/夜间#2D2D2D），不再透明透出玻璃材质（v0.6.7）
    private func createPaneContainer(side: PaneSide) -> NSView {
        FFDebug.log("createPaneContainer: side=\(side)")
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        // 任务 F11-1: 操作区实体背景（v0.6.7）
        // 日间 #F5F5F5（访达浅灰白），夜间 #2D2D2D（访达深灰黑）
        // 实体背景上选中蓝色清晰可见（解决 v0.6.6 问题14 的最终方案）
        container.layer?.backgroundColor = operationAreaBackgroundColor().cgColor
        // 任务 F2: 移除圆角卡片，仿访达撑满（v0.6.5）
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = false

        // 1.2 活动面板顶部 accent 色条（2pt 高，初始隐藏，由 updateActivePaneVisual 切换）
        let accentBar = NSView()
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.isHidden = true  // 初始隐藏，仅活动面板显示
        container.addSubview(accentBar)

        // 任务 F3: 双行工具栏布局（v0.6.5）
        // Row1（32pt）= 后退/前进/上一级/刷新 + BreadcrumbBar（紧贴刷新）
        // Row2（32pt）= 搜索/排序/分组/视图/工具
        // PaneToolbar 总高 72pt

        // 工具栏（内含双行 + BreadcrumbBar）
        let toolbar = PaneToolbar()
        toolbar.delegate = self
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
        let detailsBar = ExpandableDetailsBar()
        detailsBar.translatesAutoresizingMaskIntoConstraints = false

        // 添加到容器
        container.addSubview(toolbar)
        container.addSubview(listView)
        container.addSubview(gridView)
        container.addSubview(detailsBar)

        NSLayoutConstraint.activate([
            // accentBar 贴顶部（任务 F2：无圆角，不再裁剪）
            accentBar.topAnchor.constraint(equalTo: container.topAnchor),
            accentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            accentBar.heightAnchor.constraint(equalToConstant: 2),

            // 任务 F3: toolbar 占顶部 72pt（双行）
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            listView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: detailsBar.topAnchor),

            gridView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: detailsBar.topAnchor),

            detailsBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailsBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailsBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 高度由 ExpandableDetailsBar 内部 heightConstraint 控制（收起 28 / 展开 120）
        ])

        // 保存引用
        switch side {
        case .left:
            leftPaneToolbar = toolbar
            leftBreadcrumbBar = breadcrumbBar
            leftFileListView = listView
            leftFileGridView = gridView
            leftDetailsBar = detailsBar
            leftAccentBar = accentBar
        case .right:
            rightPaneToolbar = toolbar
            rightBreadcrumbBar = breadcrumbBar
            rightFileListView = listView
            rightFileGridView = gridView
            rightDetailsBar = detailsBar
            rightAccentBar = accentBar
        }

        return container
    }

    // MARK: - 任务 F10-3: 设备浮层（浮动在窗口左下角独立区域，v0.6.6）

    /// 任务 F11-1: 操作区实体背景色（v0.6.7）
    /// 日间 #F5F5F5（访达浅灰白），夜间 #2D2D2D（访达深灰黑）
    /// 供 createPaneContainer 初始设置与主题切换刷新共用
    private func operationAreaBackgroundColor() -> NSColor {
        let isDark = ThemeManager.shared.resolvedIsDark
        return isDark
            ? NSColor(srgbRed: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D
            : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)  // #F5F5F5
    }

    /// 任务 F11-1: 刷新左右操作区容器背景色（主题切换时调用，v0.6.7）
    private func refreshOperationAreaBackgrounds() {
        let color = operationAreaBackgroundColor().cgColor
        leftPaneContainer?.layer?.backgroundColor = color
        rightPaneContainer?.layer?.backgroundColor = color
        // 任务 F11-1: 设备栏浮层同步改为实体背景（与操作区一致）
        refreshDevicePanelBackground()
    }

    /// 任务 F11-1: 创建设备浮层
    /// - 浮动在窗口左下角，与侧边栏收藏夹/标签模块视觉分离（独立卡片样式）
    /// - 折叠时仅显示汇总头部；展开时显示所有设备，高度自适应，不需滚动条
    /// - 设备数据获取逻辑（statfs 读取磁盘容量、过滤隐藏卷）迁移自 SidebarView.DeviceSidebarDataSource
    private func createDevicePanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        // 任务 F11-1: 设备栏浮层改为实体背景（与操作区一致，v0.6.7）
        // 此前为半透明 controlBackgroundColor(0.8)，现统一为操作区实体色，保留 8pt 圆角卡片样式
        panel.layer?.backgroundColor = operationAreaBackgroundColor().cgColor
        panel.layer?.cornerRadius = 8
        panel.layer?.masksToBounds = true

        // 设备栏头部（汇总信息 + 折叠箭头，复用 SidebarView 的 DeviceHeaderView）
        devicePanelHeader = DeviceHeaderView()
        devicePanelHeader.translatesAutoresizingMaskIntoConstraints = false
        // 点击头部切换折叠/展开
        let headerClick = NSClickGestureRecognizer(target: self, action: #selector(toggleDevicePanelExpanded))
        devicePanelHeader.addGestureRecognizer(headerClick)
        panel.addSubview(devicePanelHeader)

        // 设备列表（纵向 stack，根据设备数量自适应高度，不需滚动条）
        devicePanelStack = NSStackView()
        devicePanelStack.orientation = .vertical
        devicePanelStack.alignment = .leading
        devicePanelStack.spacing = 0
        devicePanelStack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(devicePanelStack)

        NSLayoutConstraint.activate([
            // 头部固定在 panel 顶部（高度 32pt，左右内边距 8pt）
            devicePanelHeader.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            devicePanelHeader.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            devicePanelHeader.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            devicePanelHeader.heightAnchor.constraint(equalToConstant: 32),

            // 设备 stack 位于头部下方，填满剩余空间
            // 折叠时 panel 高度=48，stack 高度自动为 0（被 masksToBounds 裁剪）
            devicePanelStack.topAnchor.constraint(equalTo: devicePanelHeader.bottomAnchor, constant: 0),
            devicePanelStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            devicePanelStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            devicePanelStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
        ])

        return panel
    }

    /// 任务 F10-3: 重建设备浮层的所有设备行
    /// 迁移自 SidebarView.DeviceSidebarDataSource.outlineView(_:viewFor:) 的 DeviceCellView 构建逻辑
    /// 每个设备行：图标 + 名称 + "X GB 可用"（复用 DeviceCellView，含悬停气泡）
    private func rebuildDevicePanelRows() {
        // 清空旧设备行
        devicePanelStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 遍历设备数据源，为每个设备创建一行
        for dev in deviceDataSource.devices {
            let row = makeDeviceRow(dev: dev)
            devicePanelStack.addArrangedSubview(row)
            // 让行撑满 stack 宽度
            row.leadingAnchor.constraint(equalTo: devicePanelStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: devicePanelStack.trailingAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: devicePanelRowHeight).isActive = true
        }
    }

    /// 任务 F10-3: 创建单个设备行视图（复用 DeviceCellView，附带点击导航）
    /// 迁移自 SidebarView.DeviceSidebarDataSource 的 DeviceCellView 配置逻辑
    private func makeDeviceRow(dev: DeviceItem) -> NSView {
        // 复用 SidebarView 的 DeviceCellView（含图标 + 名称 + 可用空间 + 悬停气泡）
        let cell = DeviceCellView()
        let extInfo = deviceDataSource.deviceExtendedInfo[dev.path]
        cell.configure(dev: dev, extInfo: extInfo)

        // 点击设备行切换到该卷（保留设备点击导航功能）
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleDeviceRowClick(_:)))
        cell.identifier = NSUserInterfaceItemIdentifier(dev.path)
        cell.addGestureRecognizer(click)
        return cell
    }

    /// 任务 F10-3: 点击设备行 -> 切换活动面板到该卷路径
    @objc private func handleDeviceRowClick(_ sender: NSClickGestureRecognizer) {
        guard let path = sender.view?.identifier?.rawValue else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: path)
    }

    /// 任务 F10-3: 切换设备浮层折叠/展开状态（带 200ms 动画）
    /// 迁移自 SidebarView.toggleDeviceExpanded
    @objc private func toggleDevicePanelExpanded() {
        isDevicePanelCollapsed.toggle()
        let targetHeight: CGFloat
        if isDevicePanelCollapsed {
            targetHeight = devicePanelCollapsedHeight
        } else {
            // 展开态：折叠高度 + 设备数量 * 行高（高度自适应，不需滚动条）
            targetHeight = devicePanelCollapsedHeight + CGFloat(deviceDataSource.deviceCount) * devicePanelRowHeight
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            devicePanelHeightConstraint.animator().constant = targetHeight
            devicePanel.layoutSubtreeIfNeeded()
        }, completionHandler: nil)

        // 更新箭头方向
        devicePanelHeader.updateArrow(isCollapsed: isDevicePanelCollapsed)
    }

    /// 任务 F10-3: 更新设备浮层头部汇总信息（所有设备的可用空间和总容量之和）
    /// 迁移自 SidebarView.updateDeviceHeaderSummary
    private func updateDevicePanelSummary() {
        let (totalFree, totalTotal) = deviceDataSource.totalSpaceSummary()
        devicePanelHeader.updateSummary(free: totalFree, total: totalTotal, isCollapsed: isDevicePanelCollapsed)
    }

    /// 任务 F10-3: 卷挂载通知 -> 刷新设备浮层
    /// 迁移自 SidebarView.handleVolumeMount
    @objc private func handleVolumeMount(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDevicePanel()
        }
    }

    /// 任务 F10-3: 卷卸载通知 -> 刷新设备浮层
    /// 迁移自 SidebarView.handleVolumeUnmount
    @objc private func handleVolumeUnmount(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDevicePanel()
        }
    }

    /// 任务 F10-3: 刷新设备浮层（重新加载设备数据 + 重建行 + 更新汇总 + 调整高度）
    /// 迁移自 SidebarView.refreshDevices
    private func refreshDevicePanel() {
        deviceDataSource.loadDevices()
        rebuildDevicePanelRows()
        updateDevicePanelSummary()
        // 若当前展开态，根据新设备数量调整高度（高度自适应，不需滚动条）
        if !isDevicePanelCollapsed {
            let targetHeight = devicePanelCollapsedHeight + CGFloat(deviceDataSource.deviceCount) * devicePanelRowHeight
            devicePanelHeightConstraint.constant = targetHeight
        }
    }

    /// 任务 F11-1: 刷新设备栏浮层背景色（主题切换时调用，v0.6.7）
    private func refreshDevicePanelBackground() {
        devicePanel?.layer?.backgroundColor = operationAreaBackgroundColor().cgColor
    }

    deinit {
        // Bug 6 修复：移除所有 NotificationCenter observer，防止悬空回调
        NotificationCenter.default.removeObserver(self)
        // 任务 F10-3: 移除卷挂载/卸载通知监听（迁移自 SidebarView deinit）
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarDirectorySelected(_:)),
            name: .sidebarDidSelectDirectory, object: nil
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
            name: NSNotification.Name("FileListAddTag"), object: nil
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
            name: NSNotification.Name("OpenSettings"), object: nil
        )
    }

    /// 任务 F10-10: 处理 OpenSettings 通知，弹出设置窗口（修复问题3）
    @objc private func handleOpenSettings(_ notification: Notification) {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func handleFileListAddTag(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String else { return }
        let currentTags = TagBridge.shared.getTags(path: path)
        let dialog = TagSelectorDialog(filePath: path, currentTags: currentTags)
        if let window = window {
            dialog.beginSheetModal(for: window)
        }
    }

    /// F9-C: 处理「显示简介」请求，弹出独立 FileInfoWindow（仿访达 Get Info）。
    /// 若通知携带有效路径则显示该文件信息；否则回退到当前活动面板选中项的第一项。
    @objc private func handleFileListShowInfo(_ notification: Notification) {
        var path = (notification.userInfo?["path"] as? String) ?? ""
        if path.isEmpty {
            path = activePaneViewModel.selectedFiles.first?.path ?? ""
        }
        guard !path.isEmpty else { return }
        showFileInfo(forPath: path)
    }

    @objc private func handleQuickLookRequest(_ notification: Notification) {
        // 切换到请求的面板
        if let side = notification.userInfo?["side"] as? String {
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
    private func refreshPane(_ side: PaneSide) {
        let vm = side == .left ? leftPaneViewModel : rightPaneViewModel
        vm.refresh()
    }

    // MARK: - Keyboard Events

    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // 仅 Cmd 修饰（不含 Shift/Option/Control）
        let isPureCommand = modifiers.contains(.command)
            && !modifiers.contains(.shift)
            && !modifiers.contains(.option)
            && !modifiers.contains(.control)

        // Space: QuickLook 预览
        if event.keyCode == 49 && modifiers.isEmpty {
            handleQuickLook()
            return
        }

        // Bug 5 修复：移除 Enter 打开文件的行为。
        // macOS Finder 风格：Enter=重命名（由 FileListView 内联处理），Cmd+O/Cmd+Down=打开。
        // 此处不再处理 Enter，避免响应链回退时把 Enter 当作打开。

        // Bug 5 修复：Cmd+Down (keyCode 125) / Cmd+O (keyCode 31) 打开选中项
        // 兜底处理（FileListView 已自行处理，此处主要服务网格视图等无 keyDown 实现的场景）
        if isPureCommand && (event.keyCode == 125 || event.keyCode == 31) {
            handleOpenKey()
            return
        }

        // Bug 5 修复：Cmd+Up (keyCode 126) 上级目录（Finder 风格）
        if isPureCommand && event.keyCode == 126 {
            activePaneViewModel.goUp()
            return
        }

        // ⌘1: 列表视图
        if event.keyCode == 18 && modifiers.contains(.command) {
            activePaneViewModel.setViewMode(.list)
            updateViewMode(side: activePane, mode: .list)
            return
        }

        // ⌘2: 网格视图
        if event.keyCode == 19 && modifiers.contains(.command) {
            activePaneViewModel.setViewMode(.grid)
            updateViewMode(side: activePane, mode: .grid)
            return
        }

        // ⌘D: 复制选中项
        if event.keyCode == 2 && modifiers.contains(.command) {
            duplicateSelected()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Quick Look

    private func handleQuickLook() {
        let selected = activePaneViewModel.selectedFiles
        guard !selected.isEmpty else { return }

        // 获取当前面板所有可预览的文件（排除文件夹）
        let previewableFiles = activePaneViewModel.files.filter { !$0.isDirectory }
        let paths = previewableFiles.map { $0.path }

        // 找到当前选中文件的索引
        let currentPath = selected.first?.path
        let currentIndex = paths.firstIndex(of: currentPath ?? "") ?? 0

        QuickLookPreviewPanel.shared.togglePreview(files: paths, currentIndex: currentIndex)
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

    private func duplicateSelected() {
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

                // 注册撤销：删除复制的文件
                if !copiedPairs.isEmpty {
                    let pairs = copiedPairs
                    let activeSide = self.activePane
                    self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                        // undo: 删除复制的文件
                        for (_, dst) in pairs {
                            try? CoreBridge.shared.deleteFile(path: dst)
                        }
                        // 注册 redo：重新复制
                        ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                            for (src, dst) in pairs {
                                try? CoreBridge.shared.copyFile(src: src, dst: dst)
                            }
                            ctrl2.refreshPane(activeSide)
                        }
                        ctrl.undoManager?.setActionName("复制 \(pairs.count) 个项目")
                        ctrl.refreshPane(activeSide)
                    }
                    self.ffUndoManager.setActionName("复制 \(pairs.count) 个项目")
                }
            }
        }
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

        fileListView?.viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
        fileListView?.reloadData()

        // 更新网格视图
        let grid = side == .left ? leftFileGridView : rightFileGridView
        grid?.viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
        grid?.reloadData()

        // 视图模式切换
        updateViewMode(side: side, mode: state.viewMode)
    }

    private func updateActivePaneVisual() {
        // 1.2 新设计：顶部 2pt accent 色条（替代 borderWidth 方案）
        // 注意：不覆盖 container 基础背景色（windowBackgroundColor），避免破坏面板底色
        leftAccentBar?.isHidden = activePane != .left
        rightAccentBar?.isHidden = activePane != .right
    }

    private func updateViewMode(side: PaneSide, mode: ViewMode) {
        let listView = side == .left ? leftFileListView : rightFileListView
        let gridView = side == .left ? leftFileGridView : rightFileGridView

        switch mode {
        case .list:
            listView?.isHidden = false
            gridView?.isHidden = true
            listView?.reloadData()
        case .grid:
            listView?.isHidden = true
            gridView?.isHidden = false
            gridView?.reloadData()
        }
    }

    private func loadInitialDirectories() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let desktopPath = (homePath as NSString).appendingPathComponent("Desktop")
        let documentsPath = (homePath as NSString).appendingPathComponent("Documents")

        leftPaneViewModel.state.path = desktopPath
        leftPaneViewModel.state.history = [desktopPath]
        leftPaneViewModel.state.historyIndex = 0

        rightPaneViewModel.state.path = documentsPath
        rightPaneViewModel.state.history = [documentsPath]
        rightPaneViewModel.state.historyIndex = 0

        leftPaneViewModel.refresh()
        rightPaneViewModel.refresh()
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

    private func handleSelectionChanged(side: PaneSide, files: [FileEntry]) {
        guard let detailsBar = side == .left ? leftDetailsBar : rightDetailsBar else { return }
        if let first = files.first {
            detailsBar.update(with: first)
            detailsBar.setSelectedCount(files.count)
            // 选中文件时自动展开详情面板（用户偏好：选中即显示详情）
            detailsBar.isExpanded = true
        } else {
            detailsBar.update(with: nil)
            detailsBar.setSelectedCount(0)
            // 取消选中时自动收起
            detailsBar.isExpanded = false
        }
    }

    func activatePane(_ side: PaneSide) {
        activePane = side
        updateActivePaneVisual()
        NotificationCenter.default.post(name: .paneDidActivate, object: nil, userInfo: ["side": side == .left ? "left" : "right"])
    }

    @objc private func handleSidebarDirectorySelected(_ notification: Notification) {
        guard let entry = notification.object as? FileEntry else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: entry.path)
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

// MARK: - Menu Actions

extension MainWindowController {
    @objc func menuNewFolder(_ sender: Any?) {
        activePaneViewModel.createDirectory()
    }

    @objc func menuOpen(_ sender: Any?) {
        guard let entry = activePaneViewModel.selectedFiles.first else { return }
        if entry.isDirectory {
            activePaneViewModel.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    @objc func menuMoveToTrash(_ sender: Any?) {
        let selectedFiles = activePaneViewModel.selectedFiles
        let disabled = UserDefaults.standard.bool(forKey: "delete_confirm_disabled")
        if disabled || selectedFiles.isEmpty {
            activePaneViewModel.deleteSelected()
            return
        }
        let dialog = DeleteConfirmDialog(fileCount: selectedFiles.count) { [weak self] in
            self?.activePaneViewModel.deleteSelected()
        }
        if let window = window {
            dialog.beginSheetModal(for: window)
        }
    }

    @objc func menuAddTag(_ sender: Any?) {
        let selectedFiles = activePaneViewModel.selectedFiles
        guard let firstFile = selectedFiles.first else { return }
        // 获取当前文件的标签（allTags 留空，由 TagSelectorDialog 使用默认预设）
        let currentTags = TagBridge.shared.getTags(path: firstFile.path)
        let dialog = TagSelectorDialog(filePath: firstFile.path, currentTags: currentTags)
        if let window = window {
            dialog.beginSheetModal(for: window)
        }
    }

    @objc func menuGetInfo(_ sender: Any?) {
        // F9-C: 弹出独立 FileInfoWindow（仿访达 Get Info）。
        // 访达行为：显示选中项的第一个文件信息；无选中则不弹窗。
        guard let path = activePaneViewModel.selectedFiles.first?.path else { return }
        showFileInfo(forPath: path)
    }

    /// F9-C: 显示独立 FileInfoWindow（仿访达 Get Info）。
    /// 复用已有控制器并切换文件路径；窗口关闭后由 ARC 释放。
    /// - Parameter path: 文件绝对路径
    private func showFileInfo(forPath path: String) {
        if let controller = fileInfoWindowController, controller.window != nil {
            controller.showInfoWindow(filePath: path)
        } else {
            let controller = FileInfoWindowController(filePath: path)
            fileInfoWindowController = controller
            controller.showWindow(nil)
        }
    }

    @objc func menuCopy(_ sender: Any?) {
        clipboardItems = activePaneViewModel.selectedFiles.map { $0.path }
        clipboardOperation = .copy
    }

    @objc func menuCut(_ sender: Any?) {
        clipboardItems = activePaneViewModel.selectedFiles.map { $0.path }
        clipboardOperation = .cut
    }

    @objc func menuPaste(_ sender: Any?) {
        guard !clipboardItems.isEmpty,
              let operation = clipboardOperation else { return }
        let destPath = activePaneViewModel.currentPath
        let srcs = clipboardItems

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let total = srcs.count
                let success: Int
                let isMove: Bool
                switch operation {
                case .copy:
                    isMove = false
                    success = try CoreBridge.shared.parallelCopy(srcs: srcs, dstDir: destPath)
                case .cut:
                    isMove = true
                    success = try CoreBridge.shared.parallelMove(srcs: srcs, dstDir: destPath)
                }

                // I2: invalidate cache so the refresh sees the new state.
                // Destination always changes; for a move each source parent
                // directory also changes (items left those dirs). Best-effort.
                try? CoreBridge.shared.invalidateCache(path: destPath)
                if isMove {
                    let sourceDirs = Set(srcs.map { ($0 as NSString).deletingLastPathComponent })
                    for dir in sourceDirs where !dir.isEmpty {
                        try? CoreBridge.shared.invalidateCache(path: dir)
                    }
                }

                // I3: capture the detailed partial-failure message now
                // (getLastError is read-once) before the async UI refresh —
                // refresh → listDirectory would otherwise consume it on its
                // own failure path. Appended to the user-facing alert.
                let partialDetail = (success < total) ? CoreBridge.shared.getLastError() : ""

                // 计算 dst 路径用于撤销注册（best-effort：假设 srcs 都成功）
                let dstPaths = srcs.map { src -> String in
                    let name = (src as NSString).lastPathComponent
                    return (destPath as NSString).appendingPathComponent(name)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.activePaneViewModel.refresh()

                    // 注册撤销（仅当至少一个成功；best-effort）
                    if success > 0 {
                        if isMove {
                            let pairs = zip(srcs, dstPaths).map { (src: $0, dst: $1) }
                            self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                                // undo: 移回原位
                                for (src, dst) in pairs {
                                    try? CoreBridge.shared.moveFile(src: dst, dst: src)
                                }
                                // 注册 redo：再次移动
                                ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                                    for (src, dst) in pairs {
                                        try? CoreBridge.shared.moveFile(src: src, dst: dst)
                                    }
                                    ctrl2.refreshPane(.left)
                                    ctrl2.refreshPane(.right)
                                }
                                ctrl.undoManager?.setActionName("移动 \(success) 个项目")
                                ctrl.refreshPane(.left)
                                ctrl.refreshPane(.right)
                            }
                            self.ffUndoManager.setActionName("移动 \(success) 个项目")
                        } else {
                            let pairs = zip(srcs, dstPaths).map { (src: $0, dst: $1) }
                            self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                                // undo: 删除复制项
                                for (_, dst) in pairs {
                                    try? CoreBridge.shared.deleteFile(path: dst)
                                }
                                // 注册 redo：重新复制
                                ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                                    for (src, dst) in pairs {
                                        try? CoreBridge.shared.copyFile(src: src, dst: dst)
                                    }
                                    ctrl2.refreshPane(.left)
                                    ctrl2.refreshPane(.right)
                                }
                                ctrl.undoManager?.setActionName("复制 \(success) 个项目")
                                ctrl.refreshPane(.left)
                                ctrl.refreshPane(.right)
                            }
                            self.ffUndoManager.setActionName("复制 \(success) 个项目")
                        }
                    }

                    if success < total {
                        self.showError(error: NSError(
                            domain: "FlowFinder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "\(total - success) 个项目粘贴失败：\(partialDetail)"])
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error: error)
                }
            }
        }
    }

    // MARK: - FileListView 右键菜单通知处理

    @objc private func handleFileListCopy(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        let vm = side == "left" ? leftPaneViewModel : rightPaneViewModel
        clipboardItems = vm.selectedFiles.map { $0.path }
        clipboardOperation = .copy
        activatePane(side == "left" ? .left : .right)
    }

    @objc private func handleFileListCut(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        let vm = side == "left" ? leftPaneViewModel : rightPaneViewModel
        clipboardItems = vm.selectedFiles.map { $0.path }
        clipboardOperation = .cut
        activatePane(side == "left" ? .left : .right)
    }

    @objc private func handleFileListPaste(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        activatePane(side == "left" ? .left : .right)
        menuPaste(self)
    }

    @objc private func handleFileListAddFavorite(_ notification: Notification) {
        guard let name = notification.userInfo?["name"] as? String,
              let path = notification.userInfo?["path"] as? String else { return }
        sidebarView.addFavorite(name: name, path: path)
    }

    // MARK: - Cross-Pane Operations

    @objc private func handleFileListCopyToOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        performCrossPaneOperation(side: side, isMove: false)
    }

    @objc private func handleFileListMoveToOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        performCrossPaneOperation(side: side, isMove: true)
    }

    @objc private func handleFileListOpenInOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String,
              let path = notification.userInfo?["path"] as? String else { return }
        let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
        destVM.navigate(to: path)
        let destSide: PaneSide = side == "left" ? .right : .left
        activatePane(destSide)
    }

    /// 执行跨面板复制/移动操作
    private func performCrossPaneOperation(side: String, isMove: Bool) {
        let sourceVM: PaneViewModel = side == "left" ? leftPaneViewModel : rightPaneViewModel
        let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
        let destPath = destVM.currentPath

        let selectedFiles = sourceVM.selectedFiles
        guard !selectedFiles.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var successCount = 0
            var failedFiles: [(String, Error)] = []
            // 记录每个成功操作的 (src, dst) 用于撤销注册
            var movedOrCopied: [(src: String, dst: String)] = []

            for entry in selectedFiles {
                let srcPath = entry.path
                let fileName = entry.name
                var dstPath = (destPath as NSString).appendingPathComponent(fileName)

                // 重名冲突检测 - 添加 "副本" 后缀
                if FileManager.default.fileExists(atPath: dstPath) {
                    let ext = (fileName as NSString).pathExtension
                    let nameWithoutExt = (fileName as NSString).deletingPathExtension
                    var counter = 1
                    repeat {
                        let suffixName = ext.isEmpty ? "\(nameWithoutExt) 副本 \(counter)" : "\(nameWithoutExt) 副本 \(counter).\(ext)"
                        dstPath = (destPath as NSString).appendingPathComponent(suffixName)
                        counter += 1
                    } while FileManager.default.fileExists(atPath: dstPath)
                }

                do {
                    if isMove {
                        try CoreBridge.shared.moveFile(src: srcPath, dst: dstPath)
                    } else {
                        try CoreBridge.shared.copyFile(src: srcPath, dst: dstPath)
                    }
                    movedOrCopied.append((src: srcPath, dst: dstPath))
                    successCount += 1
                } catch {
                    failedFiles.append((fileName, error))
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 刷新双方面板
                sourceVM.refresh()
                destVM.refresh()

                // 注册撤销（仅对成功的操作）
                if !movedOrCopied.isEmpty {
                    let sourceSide: PaneSide = side == "left" ? .left : .right
                    let destSide: PaneSide = side == "left" ? .right : .left
                    let items = movedOrCopied
                    if isMove {
                        self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                            // undo: 移回原位
                            for (src, dst) in items {
                                try? CoreBridge.shared.moveFile(src: dst, dst: src)
                            }
                            // 注册 redo：再次移动
                            ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                                for (src, dst) in items {
                                    try? CoreBridge.shared.moveFile(src: src, dst: dst)
                                }
                                ctrl2.refreshPane(sourceSide)
                                ctrl2.refreshPane(destSide)
                            }
                            ctrl.undoManager?.setActionName("移动 \(items.count) 个项目")
                            ctrl.refreshPane(sourceSide)
                            ctrl.refreshPane(destSide)
                        }
                        self.ffUndoManager.setActionName("移动 \(items.count) 个项目")
                    } else {
                        self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                            // undo: 删除复制项
                            for (_, dst) in items {
                                try? CoreBridge.shared.deleteFile(path: dst)
                            }
                            // 注册 redo：重新复制
                            ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                                for (src, dst) in items {
                                    try? CoreBridge.shared.copyFile(src: src, dst: dst)
                                }
                                ctrl2.refreshPane(destSide)
                            }
                            ctrl.undoManager?.setActionName("复制 \(items.count) 个项目")
                            ctrl.refreshPane(destSide)
                        }
                        self.ffUndoManager.setActionName("复制 \(items.count) 个项目")
                    }
                }

                // 显示错误（如果有）
                if !failedFiles.isEmpty {
                    let fileNames = failedFiles.map { $0.0 }.joined(separator: ", ")
                    self.showError(error: NSError(domain: "FlowFinder", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "\(failedFiles.count) 个文件操作失败: \(fileNames)"]))
                }
            }
        }
    }

    // MARK: - Menu Bar Cross-Pane Actions

    @objc func menuCopyToOther(_ sender: Any?) {
        let side = activePane == .left ? "left" : "right"
        performCrossPaneOperation(side: side, isMove: false)
    }

    @objc func menuMoveToOther(_ sender: Any?) {
        let side = activePane == .left ? "left" : "right"
        performCrossPaneOperation(side: side, isMove: true)
    }

    @objc func menuOpenInOther(_ sender: Any?) {
        guard let entry = activePaneViewModel.selectedFiles.first,
              entry.isDirectory else { return }
        let destVM: PaneViewModel = activePane == .left ? rightPaneViewModel : leftPaneViewModel
        destVM.navigate(to: entry.path)
        activatePane(activePane == .left ? .right : .left)
    }

    @objc func menuSelectAll(_ sender: Any?) {
        activePaneViewModel.selectAll()
    }

    @objc func menuRename(_ sender: Any?) {
        guard let entry = activePaneViewModel.selectedFiles.first else { return }
        let alert = NSAlert()
        alert.messageText = "重命名 \"\(entry.name)\""
        alert.informativeText = "输入新名称："
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = entry.name
        alert.accessoryView = textField
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !newName.isEmpty, newName != entry.name else { return }
                self?.activePaneViewModel.renameFile(entry.path, to: newName)
            }
        }
    }

    @objc func menuBatchRename(_ sender: Any?) {
        let selected = activePaneViewModel.selectedFiles
        guard selected.count >= 2 else { return }
        BatchRenameWindowController.shared.showWindow(selectedFiles: selected, paneViewModel: activePaneViewModel)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Bug 8 修复：先 guard action 非 nil（separator 等无 action 项不会进入此回调，
        // 但仍做防御性检查），避免后续比较中误访问
        guard let action = item.action else { return false }

        let hasSelection = !activePaneViewModel.selectedFiles.isEmpty

        switch action {
        case #selector(menuBatchRename(_:)):
            return activePaneViewModel.selectedFiles.count >= 2
        // Bug 8 修复：对需要选中文本才能生效的菜单项做防御性校验，避免无选中时误触导致后续 nil 访问
        case #selector(menuOpen(_:)),
             #selector(menuMoveToTrash(_:)),
             #selector(menuCopy(_:)),
             #selector(menuCut(_:)),
             #selector(menuRename(_:)),
             #selector(menuCopyToOther(_:)),
             #selector(menuMoveToOther(_:)):
            return hasSelection
        case #selector(menuOpenInOther(_:)):
            // 仅当选中项为目录时可用
            return activePaneViewModel.selectedFiles.first?.isDirectory ?? false
        default:
            return true
        }
    }

    @objc func menuListView(_ sender: Any?) {
        activePaneViewModel.setViewMode(.list)
        updateViewMode(side: activePane, mode: .list)
    }

    @objc func menuGridView(_ sender: Any?) {
        activePaneViewModel.setViewMode(.grid)
        updateViewMode(side: activePane, mode: .grid)
    }

    @objc func menuToggleHiddenFiles(_ sender: Any?) {
        // Phase 4 实现
    }

    @objc func menuRefresh(_ sender: Any?) {
        activePaneViewModel.refresh()
    }

    @objc func menuGoBack(_ sender: Any?) {
        _ = activePaneViewModel.goBack()
    }

    @objc func menuGoForward(_ sender: Any?) {
        _ = activePaneViewModel.goForward()
    }

    @objc func menuGoUp(_ sender: Any?) {
        activePaneViewModel.goUp()
    }

    @objc func menuGoDesktop(_ sender: Any?) {
        let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop")
        activePaneViewModel.navigate(to: path)
    }

    @objc func menuGoDocuments(_ sender: Any?) {
        let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Documents")
        activePaneViewModel.navigate(to: path)
    }

    @objc func menuGoDownloads(_ sender: Any?) {
        let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
        activePaneViewModel.navigate(to: path)
    }

    @objc func menuGoHome(_ sender: Any?) {
        activePaneViewModel.navigate(to: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @objc func menuConnectServer(_ sender: Any?) {
        guard let window = window else { return }
        let dialog = ConnectServerDialog { result in
            guard let url = result.smbURL() else { return }
            SMBBridge.shared.mount(url: url.absoluteString) { mountResult in
                DispatchQueue.main.async {
                    switch mountResult {
                    case .success:
                        break
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "连接失败"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "好")
                        alert.runModal()
                    }
                }
            }
        }
        dialog.beginSheetModal(for: window)
    }

    @objc func menuSearch(_ sender: Any?) {
        let path = activePaneViewModel.currentPath
        SearchPanelController.shared.onNavigateToPath = { [weak self] resultPath in
            self?.activePaneViewModel.navigate(to: (resultPath as NSString).deletingLastPathComponent)
        }
        SearchPanelController.shared.showPanel(initialQuery: "", searchPath: path)
    }

    @objc func menuDuplicateScan(_ sender: Any?) {
        DuplicateScanWindowController.shared.showWindow()
    }

    @objc func menuTaskPanel(_ sender: Any?) {
        TaskPanelWindowController.shared.showWindow()
    }

    @objc func menuSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow()
    }

    // MARK: - Helpers

    private var activePaneViewModel: PaneViewModel {
        activePane == .left ? leftPaneViewModel : rightPaneViewModel
    }

    private func showError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        if let window = window { alert.beginSheetModal(for: window) { _ in } }
    }
}

// MARK: - NSSplitViewDelegate

extension MainWindowController: NSSplitViewDelegate {
    /// 限制每个面板的最小坐标，防止工具栏元素重叠
    public func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 主 split view（sidebar + panes）：sidebar 最小 180
        if splitView === mainSplitView {
            return 180
        }
        // pane split view（left + right panes）：每个面板最小 450
        if splitView === paneSplitView {
            return 450
        }
        return proposedMinimumPosition
    }

    /// 限制每个面板的最大坐标，防止一个面板占据过多空间
    public func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 主 split view：sidebar 最大 280
        if splitView === mainSplitView {
            return 280
        }
        // pane split view：留出至少 450 给另一个面板
        if splitView === paneSplitView {
            let totalWidth = splitView.bounds.width
            return max(totalWidth - 450, 450)
        }
        return proposedMaximumPosition
    }

    /// 拖动时实时更新布局
    public func splitViewDidResizeSubviews(_ notification: Notification) {
        // 触发布局更新
        if let splitView = notification.object as? NSSplitView {
            splitView.window?.layoutIfNeeded()
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
