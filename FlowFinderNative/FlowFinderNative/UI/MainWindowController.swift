import Cocoa
import Combine
import QuickLook

/// v0.6.9: 无分割线 NSSplitView 子类（用于侧边栏与操作区之间，divider 厚度为 0）
private class FFNoDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        return 0
    }
}

/// 自定义 NSSplitView 子类：任务 R5 — divider 悬停高亮
/// v0.6.9: divider 厚度设为 0（移除可见分割线），拖动时显示渐变亮线
private class FFSplitView: NSSplitView {
    private var dividerTrackingArea: NSTrackingArea?
    /// 悬停时是否高亮（由 mouseMoved 判断鼠标位置是否在 divider 附近 ±4pt）
    private var isHoveringDivider = false {
        didSet {
            if isHoveringDivider != oldValue {
                updateDividerLine()
            }
        }
    }

    /// 渐变亮线 layer（拖动时显示，复用避免重复创建）
    private var gradientLineLayer: CAGradientLayer?

    /// v0.6.9: divider 厚度为 0（移除可见分割线，保留拖拽功能）
    override var dividerThickness: CGFloat {
        return 0
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

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHoveringDivider = false
    }

    /// v0.6.9: 拖动时显示从鼠标位置向上下渐变的亮线，移除操作区蓝色边框
    private func updateDividerLine() {
        if isHoveringDivider {
            // 复用 gradientLineLayer，仅更新 frame，避免每次拖动重建 layer
            if gradientLineLayer == nil {
                let gradientLayer = CAGradientLayer()
                gradientLayer.colors = [
                    NSColor.clear.cgColor,
                    NSColor.controlAccentColor.cgColor,
                    NSColor.clear.cgColor
                ]
                gradientLayer.locations = [0, 0.5, 1]
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
                self.layer?.addSublayer(gradientLayer)
                gradientLineLayer = gradientLayer
            }
            // 亮线位置：跟随 divider 实时位置，宽度 2pt，高度为 splitView 全高
            let dividerX = subviews.count >= 2 ? subviews[0].frame.maxX : 0
            gradientLineLayer?.frame = CGRect(x: dividerX - 1, y: 0, width: 2, height: self.bounds.height)
            gradientLineLayer?.isHidden = false

            // 鼠标变为双箭头调整光标
            NSCursor.resizeLeftRight.set()
        } else {
            // 隐藏亮线
            gradientLineLayer?.isHidden = true
            NSCursor.arrow.set()
        }
    }

    /// 拖动开始时确保亮线显示
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateDividerLine()
    }

    /// v0.6.9 fix: 拖动过程中实时更新亮线位置（跟随 divider 移动）
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        // 拖动时 divider 位置实时变化，更新亮线位置
        if isHoveringDivider || gradientLineLayer?.isHidden == false {
            let dividerX = subviews.count >= 2 ? subviews[0].frame.maxX : 0
            gradientLineLayer?.frame = CGRect(x: dividerX - 1, y: 0, width: 2, height: self.bounds.height)
        }
    }

    /// 拖动结束后隐藏亮线
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // 拖动结束后检查鼠标是否仍在 divider 附近，否则隐藏亮线
        let loc = convert(event.locationInWindow, from: nil)
        let dividerX = subviews.count >= 2 ? subviews[0].frame.maxX : 0
        if abs(loc.x - dividerX) > 4 {
            isHoveringDivider = false
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

// MARK: - MainWindowController

public class MainWindowController: NSWindowController {

    // MARK: - Properties

    private let leftPaneViewModel = PaneViewModel()
    private let rightPaneViewModel = PaneViewModel()
    private var activePane: PaneSide = .left
    /// 防抖: 选中变更工作项，用于取消上一次未完成的 UI 更新，防止快速点击时窗口跳动
    private var selectionChangeWorkItem: DispatchWorkItem?
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
    /// v0.6.9: 工具选择覆盖页（点击侧边栏工具按钮后在操作区显示）
    private var toolOverlayView: ToolOverlayView?
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
    /// 任务 F11-9：底部进度栏高度约束（0=收起 / 28=展开，复制/移动/粘贴时动态切换）
    private var taskProgressBarHeightConstraint: NSLayoutConstraint!
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

        // 启动 FSEvents 文件系统监控：当外部程序（如访达）修改/删除/创建文件时，
        // 自动失效缓存并刷新对应面板，确保操作区显示最新文件系统状态
        startFileSystemWatcher()

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
        // 问题13修复：左右操作区用圆角卡片包裹，四周留 8pt 边距使圆角在所有边可见
        paneSplitView.addArrangedSubview(makeCardWrapper(for: leftPaneContainer))
        paneSplitView.addArrangedSubview(makeCardWrapper(for: rightPaneContainer))

        // Main Split View（侧边栏 + 操作区）
        // v0.6.9: 使用无分割线子类，移除侧边栏与操作区之间的可见分割线
        mainSplitView = FFNoDividerSplitView()
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
        let mainContainer = FFOpaqueContainerView()
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

        // 任务 F10-3: 创建设备浮层并浮动到窗口左下角（v0.6.6）
        // 设备区域从侧边栏内部移出，改为独立卡片样式，与收藏夹/标签模块视觉分离
        devicePanel = createDevicePanel()
        mainContainer.addSubview(devicePanel)
        devicePanelHeightConstraint = devicePanel.heightAnchor.constraint(equalToConstant: devicePanelCollapsedHeight)
        devicePanelHeightConstraint.priority = .required
        NSLayoutConstraint.activate([
            // 贴 mainContainer 左下角：leading +8pt
            // 底部上移 36pt，为工具栏按钮（主题/设置/工具）留出空间
            devicePanel.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor, constant: 8),
            devicePanel.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor, constant: -44),
            devicePanel.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -8),
            devicePanelHeightConstraint,
        ])

        // 任务 F10-3: 监听卷挂载/卸载通知，刷新设备浮层（迁移自 SidebarView）
        let workspaceNC = NSWorkspace.shared.notificationCenter
        workspaceNC.addObserver(self, selector: #selector(handleVolumeMount(_:)),
                                name: NSWorkspace.didMountNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(handleVolumeUnmount(_:)),
                                name: NSWorkspace.didUnmountNotification, object: nil)

        window.contentView = visualEffectView

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

    /// 问题13修复：为操作区创建带 8pt 边距的透明包裹视图
    /// createPaneContainer 已设置 cornerRadius=8 + masksToBounds + 实体背景色，
    /// 但此前容器直接铺满 split view，圆角紧贴窗口边缘不可见。
    /// 此包裹视图在容器四周留出 8pt 透明边距，使圆角矩形在四个边均可见，形成独立卡片效果。
    /// 两个卡片之间经 split divider 分隔，视觉上呈现为左右两张独立圆角卡片。
    private func makeCardWrapper(for content: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),
        ])
        return wrapper
    }

    /// 创建面板容器（工具栏 + 文件列表/网格 + DetailsBar）
    /// v0.6.9: 超椭圆圆角 16pt + 1px 边框 + 实体背景覆盖工具栏
    private func createPaneContainer(side: PaneSide) -> NSView {
        FFDebug.log("createPaneContainer: side=\(side)")
        let container = SquircleView(cornerRadius: 16, squircleFactor: 5.0, autoUpdateMask: true)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        // v0.6.9: 操作区实体背景（日间#F5F5F5/夜间#2D2D2D）
        container.layer?.backgroundColor = operationAreaBackgroundColor().cgColor
        // v0.6.9: 1px 边框（日间浅灰/夜间深灰）
        container.layer?.borderWidth = 1
        container.layer?.borderColor = operationAreaBorderColor().cgColor

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
        // v0.6.9: 详情栏改为液态玻璃浮层，覆盖在文件列表上方（不再占据容器底部空间）
        let detailsBar = ExpandableDetailsBar()
        detailsBar.translatesAutoresizingMaskIntoConstraints = false

        // 添加到容器
        container.addSubview(toolbar)
        container.addSubview(listView)
        container.addSubview(gridView)
        // v0.6.9: detailsBar 最后添加（视觉最上层），作为浮层覆盖
        container.addSubview(detailsBar)

        NSLayoutConstraint.activate([
            // accentBar 贴顶部
            accentBar.topAnchor.constraint(equalTo: container.topAnchor),
            accentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            accentBar.heightAnchor.constraint(equalToConstant: 2),

            // toolbar 占顶部
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

        // v0.6.9: 详情栏浮层添加阴影强化浮动层次
        detailsBar.wantsLayer = true
        detailsBar.layer?.shadowOpacity = 0.15
        detailsBar.layer?.shadowRadius = 8
        detailsBar.layer?.shadowOffset = CGSize(width: 0, height: -2)
        detailsBar.layer?.shadowColor = NSColor.black.cgColor

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

    /// v0.6.9: 操作区边框颜色（日间浅灰/夜间深灰）
    private func operationAreaBorderColor() -> NSColor {
        let isDark = ThemeManager.shared.resolvedIsDark
        return isDark
            ? NSColor(srgbRed: 0.227, green: 0.227, blue: 0.227, alpha: 1.0)  // #3A3A3A
            : NSColor.separatorColor  // 系统分隔线色（约 #E5E5E5）
    }

    /// v0.6.9: 刷新左右操作区容器背景色和边框色（主题切换时调用）
    private func refreshOperationAreaBackgrounds() {
        let bgColor = operationAreaBackgroundColor().cgColor
        let borderColor = operationAreaBorderColor().cgColor
        leftPaneContainer?.layer?.backgroundColor = bgColor
        rightPaneContainer?.layer?.backgroundColor = bgColor
        // v0.6.9: 同步刷新边框颜色
        leftPaneContainer?.layer?.borderColor = borderColor
        rightPaneContainer?.layer?.borderColor = borderColor
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
        // 问题3续修复：监听侧边栏工具面板展开/收起，联动设备浮层显隐
        // SidebarView 已发送 SidebarToolPanelDidToggle 通知，但此前无观察者，导致设备浮层不隐藏
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToolPanelToggle(_:)),
            name: NSNotification.Name("SidebarToolPanelDidToggle"), object: nil
        )
        // v0.6.9: 文件夹显示配置变更通知
        // 隐藏文件 / 系统文件切换需重新过滤文件列表（数据层）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRefreshHiddenFiles),
            name: .refreshHiddenFiles, object: nil
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
    }

    /// 任务 F10-10: 处理 OpenSettings 通知，弹出设置窗口（修复问题3）
    @objc private func handleOpenSettings(_ notification: Notification) {
        SettingsWindowController.shared.showWindow()
    }

    /// 问题3续修复：工具面板展开时隐藏设备浮层，收起时恢复
    /// 工具面板与设备浮层同处侧边栏左下角区域，展开工具面板会覆盖设备浮层，需联动隐藏避免视觉重叠
    @objc private func handleToolPanelToggle(_ notification: Notification) {
        guard let isExpanded = notification.userInfo?["isExpanded"] as? Bool else { return }
        // 工具展开时隐藏设备浮层，收起时恢复显示
        devicePanel?.isHidden = isExpanded
        // v0.6.9: 工具展开时在激活操作区显示工具选择覆盖页，收起时移除
        if isExpanded {
            showToolOverlay()
        } else {
            hideToolOverlay()
        }
    }

    // MARK: - v0.6.9: 工具选择覆盖页

    /// 在当前激活的操作区容器上覆盖显示工具选择页
    private func showToolOverlay() {
        // 若已存在则先移除
        hideToolOverlay()

        let tools: [ToolOverlayView.ToolItem] = [
            ToolOverlayView.ToolItem(
                icon: "rectangle.dashed",
                title: "查重扫描",
                description: "扫描当前目录中的重复文件",
                isEnabled: true,
                action: { [weak self] in
                    self?.hideToolOverlay()
                    DuplicateScanWindowController.shared.showWindow()
                }
            ),
            ToolOverlayView.ToolItem(
                icon: "pencil.line",
                title: "批量重命名",
                description: "批量重命名选中文件",
                isEnabled: true,
                action: { [weak self] in
                    self?.hideToolOverlay()
                    self?.menuBatchRename(nil)
                }
            ),
            ToolOverlayView.ToolItem(
                icon: "sparkles",
                title: "AI 打标 Beta",
                description: "自动为文件生成标签",
                isEnabled: false,
                action: nil
            ),
            ToolOverlayView.ToolItem(
                icon: "tray.full",
                title: "AI 整理 Beta",
                description: "自动整理文件到子文件夹",
                isEnabled: false,
                action: nil
            ),
        ]

        let overlay = ToolOverlayView(tools: tools)
        overlay.onClose = { [weak self] in
            self?.hideToolOverlay()
            // 同步复位侧边栏工具按钮状态
            NotificationCenter.default.post(
                name: NSNotification.Name("SidebarToolPanelDidToggle"),
                object: nil,
                userInfo: ["isExpanded": false]
            )
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = operationAreaBackgroundColor().cgColor

        let activeContainer = (activePane == .left ? leftPaneContainer : rightPaneContainer)!
        activeContainer.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: activeContainer.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: activeContainer.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: activeContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: activeContainer.trailingAnchor),
        ])
        toolOverlayView = overlay
    }

    /// 移除工具选择覆盖页
    private func hideToolOverlay() {
        toolOverlayView?.removeFromSuperview()
        toolOverlayView = nil
    }

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

    // MARK: - FSEvents 文件系统监控

    /// 启动 FSEvents 文件系统变更监控
    /// 监控用户主目录，当文件被外部程序（如访达）创建/删除/修改时，
    /// 自动失效对应目录缓存并刷新受影响的面板
    private func startFileSystemWatcher() {
        let homeDir = NSHomeDirectory()
        do {
            try CoreBridge.shared.startFSEventsWatcher(path: homeDir) { [weak self] changedPath in
                DispatchQueue.main.async { [weak self] in
                    self?.handleFileSystemChange(changedPath: changedPath)
                }
            }
            FFDebug.log("FSEvents 文件系统监控已启动，监控路径: \(homeDir)")
        } catch {
            FFLog.error("FSEvents 监控启动失败: \(error.localizedDescription)", log: FFLog.bridge)
        }
    }

    /// 处理文件系统变更通知：失效缓存 + 刷新受影响的面板
    private func handleFileSystemChange(changedPath: String) {
        // 失效变更路径及其父目录的缓存
        let parentDir = (changedPath as NSString).deletingLastPathComponent
        try? CoreBridge.shared.invalidateCache(path: changedPath)
        if !parentDir.isEmpty && parentDir != changedPath {
            try? CoreBridge.shared.invalidateCache(path: parentDir)
        }

        // 检查变更路径是否影响当前面板显示的目录
        let leftPath = leftPaneViewModel.currentPath
        let rightPath = rightPaneViewModel.currentPath

        // 如果变更发生在当前显示的目录内，或变更的就是当前目录本身
        if changedPath == leftPath || parentDir == leftPath {
            leftPaneViewModel.refresh()
        }
        if changedPath == rightPath || parentDir == rightPath {
            rightPaneViewModel.refresh()
        }
    }

    // MARK: - Keyboard Events

    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // v0.6.9: Escape 关闭工具选择覆盖页
        if event.keyCode == 53 && toolOverlayView != nil {
            hideToolOverlay()
            NotificationCenter.default.post(
                name: NSNotification.Name("SidebarToolPanelDidToggle"),
                object: nil,
                userInfo: ["isExpanded": false]
            )
            return
        }

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

        // 问题7修复：刷新状态栏（项目数 + 磁盘可用空间）
        // ExpandableDetailsBar.updateStatus 已实现但此前从未被调用，导致状态栏文字缺失
        let detailsBar = side == .left ? leftDetailsBar : rightDetailsBar
        let itemCount = state.files.count
        let diskFree = getDiskFreeSpace(forPath: state.path)
        detailsBar?.updateStatus(itemCount: itemCount, diskFree: diskFree)

        // 任务 F11-8: 状态变化时同步侧边栏标签高亮（导航清除 tagFilter / 切换活动面板时高亮需跟随）
        if side == activePane {
            NotificationCenter.default.post(
                name: .paneTagFilterChanged, object: nil,
                userInfo: ["tagFilter": state.tagFilter as Any]
            )
        }
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
        // 防抖: 取消上一次未完成的选中变更 UI 更新，防止快速连续点击不同文件时
        // 多次 layout 触发窗口跳动。将详情栏更新推迟到下一个 runloop，确保
        // NSTableView 的选中态渲染完成后再更新详情栏，避免布局冲突。
        selectionChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let detailsBar = side == .left ? self.leftDetailsBar : self.rightDetailsBar else { return }
            if let first = files.first {
                detailsBar.update(with: first)
                detailsBar.setSelectedCount(files.count)
            } else {
                detailsBar.update(with: nil)
                detailsBar.setSelectedCount(0)
            }
        }
        selectionChangeWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func activatePane(_ side: PaneSide) {
        activePane = side
        updateActivePaneVisual()
        NotificationCenter.default.post(name: .paneDidActivate, object: nil, userInfo: ["side": side == .left ? "left" : "right"])
        // 任务 F11-8: 切换活动面板时同步侧边栏标签高亮（显示新活动面板的 tagFilter）
        let vm = side == .left ? leftPaneViewModel : rightPaneViewModel
        NotificationCenter.default.post(
            name: .paneTagFilterChanged, object: nil,
            userInfo: ["tagFilter": vm.state.tagFilter as Any]
        )
    }

    @objc private func handleSidebarDirectorySelected(_ notification: Notification) {
        guard let entry = notification.object as? FileEntry else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: entry.path)
    }

    /// 任务 F11-8: 处理侧边栏标签点击，设置当前活动面板的标签筛选（问题3）。
    /// - 点击标签 -> 筛选当前面板，仅显示含该标签的文件
    /// - 再次点击同一标签 -> 取消筛选（setTagFilter 内部判断）
    /// 筛选状态变化后发布 paneTagFilterChanged 通知，侧边栏据此高亮对应标签
    @objc private func handleSidebarTagSelected(_ notification: Notification) {
        guard let tag = notification.object as? Tag else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.setTagFilter(tag)
        // 发布通知让侧边栏更新标签高亮
        NotificationCenter.default.post(
            name: .paneTagFilterChanged, object: nil,
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

    // v0.6.9: 文件夹配置菜单"新建文件夹"回调
    func paneToolbarDidClickNewFolder(_ toolbar: PaneToolbar) {
        menuNewFolder(nil)
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
        // 获取当前文件的标签，并传入侧边栏标签供选择
        let currentTags = TagBridge.shared.getTags(path: firstFile.path)
        let allTags = sidebarView.allSidebarTags()
        let dialog = TagSelectorDialog(filePath: firstFile.path, currentTags: currentTags, allTags: allTags)
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

        // 任务 F11-9：粘贴也属于复制/移动操作，展示底部进度栏反馈
        let operationName: String
        switch operation {
        case .copy: operationName = "复制"
        case .cut: operationName = "移动"
        }
        let totalCount = srcs.count
        taskProgressBar.startDirectProgress(operation: operationName, totalCount: totalCount)
        showProgressBar(animated: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let total = srcs.count
                let success: Int
                let isMove: Bool
                switch operation {
                case .copy:
                    isMove = false
                    // 任务 F11-9：传入 progress 回调，实时更新底部进度栏
                    success = try CoreBridge.shared.parallelCopy(srcs: srcs, dstDir: destPath) { completed, total in
                        let opName = operationName
                        DispatchQueue.main.async { [weak self] in
                            self?.taskProgressBar.updateDirectProgress(
                                operation: opName,
                                currentFileName: nil,
                                completed: completed,
                                total: total
                            )
                        }
                    }
                case .cut:
                    isMove = true
                    success = try CoreBridge.shared.parallelMove(srcs: srcs, dstDir: destPath) { completed, total in
                        let opName = operationName
                        DispatchQueue.main.async { [weak self] in
                            self?.taskProgressBar.updateDirectProgress(
                                operation: opName,
                                currentFileName: nil,
                                completed: completed,
                                total: total
                            )
                        }
                    }
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
                // (getLastError is read-once) before the async UI refresh -
                // refresh -> listDirectory would otherwise consume it on its
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

                    // 任务 F11-9：标记粘贴进度完成，2 秒后淡出收起
                    self.taskProgressBar.completeDirectProgress(operation: operationName, count: success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                        self?.hideProgressBar(animated: true)
                    }

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
                DispatchQueue.main.async { [weak self] in
                    self?.showError(error: error)
                    // 任务 F11-9：失败时也收起进度栏
                    self?.taskProgressBar.hide()
                    self?.hideProgressBar(animated: true)
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
        // 问题12修复：取出右键点击文件路径，传入操作方法做空选兜底
        let clickedPath = notification.userInfo?["clickedPath"] as? String
        performCrossPaneOperation(side: side, isMove: false, clickedPath: clickedPath)
    }

    @objc private func handleFileListMoveToOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        // 问题12修复：取出右键点击文件路径，传入操作方法做空选兜底
        let clickedPath = notification.userInfo?["clickedPath"] as? String
        performCrossPaneOperation(side: side, isMove: true, clickedPath: clickedPath)
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
    /// 任务 F11-9（问题1）：增加底部进度栏反馈，避免大文件复制/移动时"无提示"误以为不生效
    /// 问题12修复：
    ///   1. 空选兜底——无选中时使用右键点击的文件（clickedPath）作为操作对象，不再静默返回
    ///   2. 同目录保护——源与目标为同一目录时提示并返回
    ///   3. 改用 parallelMove/parallelCopy 批量接口，解决跨卷 move 失败问题
    ///      （parallelMove 内部对跨卷移动自动回退为复制+删除）
    private func performCrossPaneOperation(side: String, isMove: Bool, clickedPath: String? = nil) {
        let sourceVM: PaneViewModel = side == "left" ? leftPaneViewModel : rightPaneViewModel
        let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
        let destPath = destVM.currentPath

        // 问题12修复：同目录保护——源与目标为同一目录，操作无意义
        if sourceVM.currentPath == destPath {
            let alert = NSAlert()
            alert.messageText = "无法操作"
            alert.informativeText = "目标目录与源目录相同，请先切换对侧面板到其他目录。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }

        // 问题12修复：空选兜底——无选中文件时使用右键点击的文件作为操作对象
        var selectedFiles = sourceVM.selectedFiles
        if selectedFiles.isEmpty, let path = clickedPath, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            let isDir = (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory
            selectedFiles = [FileEntry(path: path, name: name, isDirectory: isDir, isFile: !isDir)]
        }
        guard !selectedFiles.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无选中文件"
            alert.informativeText = "请先选择要\(isMove ? "移动" : "复制")的文件，或在文件上右键选择操作。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }

        // 任务 F11-9：进入"直接进度"模式，展开底部进度栏
        let operationName = isMove ? "移动" : "复制"
        let totalCount = selectedFiles.count
        taskProgressBar.startDirectProgress(operation: operationName, totalCount: totalCount)
        showProgressBar(animated: true)

        // 预计算每个文件的目标名：重名冲突时追加 "副本" 后缀。
        // 无冲突文件（dstName == 原名）走批量 parallel 接口；冲突文件单独处理以保留重命名。
        // parallel 接口将文件放入 dstDir 并保留原名，因此无冲突文件的 dst = dstDir/原名。
        struct OpItem {
            let src: String
            let name: String
            let dstName: String
        }
        var items: [OpItem] = []
        for entry in selectedFiles {
            let fileName = entry.name
            var dstName = fileName
            let baseDst = (destPath as NSString).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: baseDst) {
                let ext = (fileName as NSString).pathExtension
                let nameWithoutExt = (fileName as NSString).deletingPathExtension
                var counter = 1
                repeat {
                    let suffixName = ext.isEmpty ? "\(nameWithoutExt) 副本 \(counter)" : "\(nameWithoutExt) 副本 \(counter).\(ext)"
                    dstName = suffixName
                    counter += 1
                } while FileManager.default.fileExists(atPath: (destPath as NSString).appendingPathComponent(dstName))
            }
            items.append(OpItem(src: entry.path, name: fileName, dstName: dstName))
        }

        let batchItems = items.filter { $0.dstName == $0.name }
        let conflictItems = items.filter { $0.dstName != $0.name }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var successCount = 0
            var failedFiles: [(String, Error)] = []
            // 记录每个成功操作的 (src, dst) 用于撤销注册
            var movedOrCopied: [(src: String, dst: String)] = []
            var completed = 0

            // 跨卷安全移动：moveFile 跨卷会失败，失败时回退 copyFile + deleteFile
            func safeMove(src: String, dst: String) throws {
                do {
                    try CoreBridge.shared.moveFile(src: src, dst: dst)
                } catch {
                    try CoreBridge.shared.copyFile(src: src, dst: dst)
                    try CoreBridge.shared.deleteFile(path: src)
                }
            }

            // 1) 批量处理无冲突文件（parallel 接口，跨卷移动自动回退复制+删除）
            if !batchItems.isEmpty {
                let batchSrcs = batchItems.map { $0.src }
                let batchCount = batchItems.count
                let progressHandler: ((Int, Int) -> Void)? = { done, _ in
                    let displayDone = done
                    DispatchQueue.main.async { [weak self] in
                        self?.taskProgressBar.updateDirectProgress(
                            operation: operationName,
                            currentFileName: "正在\(operationName)…",
                            completed: displayDone,
                            total: totalCount
                        )
                    }
                }
                do {
                    let ok = isMove
                        ? try CoreBridge.shared.parallelMove(srcs: batchSrcs, dstDir: destPath, progress: progressHandler)
                        : try CoreBridge.shared.parallelCopy(srcs: batchSrcs, dstDir: destPath, progress: progressHandler)
                    successCount += ok
                    for it in batchItems {
                        movedOrCopied.append((src: it.src, dst: (destPath as NSString).appendingPathComponent(it.name)))
                    }
                } catch {
                    // 批量失败：将每个文件记为失败
                    for it in batchItems {
                        failedFiles.append((it.name, error))
                    }
                }
                completed += batchCount
                let c = completed
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressBar.updateDirectProgress(
                        operation: operationName,
                        currentFileName: "正在\(operationName)…",
                        completed: min(c, totalCount),
                        total: totalCount
                    )
                }
            }

            // 2) 逐个处理冲突文件（保留 "副本" 重命名）
            for it in conflictItems {
                let dstPath = (destPath as NSString).appendingPathComponent(it.dstName)
                let preCompleted = completed
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressBar.updateDirectProgress(
                        operation: operationName,
                        currentFileName: it.dstName,
                        completed: preCompleted,
                        total: totalCount
                    )
                }
                do {
                    if isMove {
                        try safeMove(src: it.src, dst: dstPath)
                    } else {
                        try CoreBridge.shared.copyFile(src: it.src, dst: dstPath)
                    }
                    movedOrCopied.append((src: it.src, dst: dstPath))
                    successCount += 1
                } catch {
                    failedFiles.append((it.dstName, error))
                }
                completed += 1
                let c = completed
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressBar.updateDirectProgress(
                        operation: operationName,
                        currentFileName: it.dstName,
                        completed: min(c, totalCount),
                        total: totalCount
                    )
                }
            }

            // 失效缓存：跨面板操作改变了源目录和目标目录的文件列表，
            // 必须在 refresh 之前失效缓存，否则 refresh 会命中过期缓存
            try? CoreBridge.shared.invalidateCache(path: destPath)
            if isMove {
                let sourceDir = (selectedFiles.first?.path as NSString?)?.deletingLastPathComponent ?? ""
                if !sourceDir.isEmpty {
                    try? CoreBridge.shared.invalidateCache(path: sourceDir)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 刷新双方面板
                sourceVM.refresh()
                destVM.refresh()

                // 任务 F11-9：标记进度完成，显示"复制/移动完成：N 个项目"，2 秒后淡出收起
                self.taskProgressBar.completeDirectProgress(operation: operationName, count: successCount)
                // 延迟 2.2 秒收起进度栏（比 TaskProgressBar 内部 2.0s 淡出稍晚，确保淡出动画完成后再收起高度）
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    self?.hideProgressBar(animated: true)
                }

                // 注册撤销（仅对成功的操作）
                if !movedOrCopied.isEmpty {
                    let sourceSide: PaneSide = side == "left" ? .left : .right
                    let destSide: PaneSide = side == "left" ? .right : .left
                    let undoItems = movedOrCopied
                    if isMove {
                        self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                            // undo: 移回原位
                            for (src, dst) in undoItems {
                                try? CoreBridge.shared.moveFile(src: dst, dst: src)
                            }
                            // 注册 redo：再次移动
                            ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                                for (src, dst) in undoItems {
                                    try? CoreBridge.shared.moveFile(src: src, dst: dst)
                                }
                                ctrl2.refreshPane(sourceSide)
                                ctrl2.refreshPane(destSide)
                            }
                            ctrl.undoManager?.setActionName("移动 \(undoItems.count) 个项目")
                            ctrl.refreshPane(sourceSide)
                            ctrl.refreshPane(destSide)
                        }
                        self.ffUndoManager.setActionName("移动 \(undoItems.count) 个项目")
                    } else {
                        self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                            // undo: 删除复制项
                            for (_, dst) in undoItems {
                                try? CoreBridge.shared.deleteFile(path: dst)
                            }
                            // 注册 redo：重新复制
                            ctrl.undoManager?.registerUndo(withTarget: ctrl) { ctrl2 in
                                for (src, dst) in undoItems {
                                    try? CoreBridge.shared.copyFile(src: src, dst: dst)
                                }
                                ctrl2.refreshPane(destSide)
                            }
                            ctrl.undoManager?.setActionName("复制 \(undoItems.count) 个项目")
                            ctrl.refreshPane(destSide)
                        }
                        self.ffUndoManager.setActionName("复制 \(undoItems.count) 个项目")
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

    // MARK: - 底部进度栏（任务 F11-9）

    /// 展开底部进度栏（高度从 0 动画到 28pt 并显示）
    /// - Parameter animated: 是否使用动画展开
    private func showProgressBar(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.taskProgressBar.isHidden = false
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.taskProgressBarHeightConstraint.animator().constant = TaskProgressBar.height
                    self.taskProgressBar.layoutSubtreeIfNeeded()
                }, completionHandler: nil)
            } else {
                self.taskProgressBarHeightConstraint.constant = TaskProgressBar.height
            }
        }
    }

    /// 收起底部进度栏（高度从 28 动画回 0 并隐藏）
    /// - Parameter animated: 是否使用动画收起
    private func hideProgressBar(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.taskProgressBarHeightConstraint.animator().constant = 0
                    self.taskProgressBar.layoutSubtreeIfNeeded()
                }, completionHandler: {
                    self.taskProgressBar.isHidden = true
                })
            } else {
                self.taskProgressBarHeightConstraint.constant = 0
                self.taskProgressBar.isHidden = true
            }
        }
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
