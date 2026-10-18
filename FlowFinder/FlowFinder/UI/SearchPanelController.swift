import Cocoa

/// 搜索模式
public enum SearchMode: Int, CaseIterable {
    case local = 0   // Rust 本地搜索（当前目录）
    case global = 1  // Spotlight 全局搜索

    public var title: String {
        switch self {
        case .local: return "当前目录"
        case .global: return "全局搜索"
        }
    }
}

// MARK: - SearchOpaqueContainerView

// FFOpaqueContainerView 已提取到 FFCommon.swift（统一实体背景容器）
// 原 SearchOpaqueContainerView 已由 FFOpaqueContainerView 替代

// MARK: - FFSearchNameCell

/// 搜索结果名称列：文件名 12pt + 路径 10pt tertiary 双行堆叠
private class FFSearchNameCell: NSTableCellView {

    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        nameLabel.font = NSFont.systemFont(ofSize: 12)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.cell?.truncatesLastVisibleLine = true

        pathLabel.font = NSFont.systemFont(ofSize: 10)
        pathLabel.textColor = NSColor.tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.cell?.truncatesLastVisibleLine = true

        addSubview(nameLabel)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            pathLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    func configure(name: String, path: String) {
        nameLabel.stringValue = name
        pathLabel.stringValue = path
    }
}

// MARK: - SearchPanelController

/// 搜索面板窗口控制器：大搜索框 + 筛选侧边栏 + 双行结果
/// 任务 F11-2: 窗口实体背景（windowBackgroundColor），移除 FFGlassView 透明玻璃架构（v0.6.7）。
public class SearchPanelController: NSWindowController {

    public static let shared = SearchPanelController()

    // MARK: - UI 引用

    private var searchField: NSSearchField!
    private var modeSegmentedControl: NSSegmentedControl!
    private var scopePopup: NSPopUpButton!
    private var typePopup: NSPopUpButton!
    private var timePopup: NSPopUpButton!
    private var filterSidebar: SearchFilterSidebar!
    private var resultsTableView: NSTableView!
    private var scrollView: NSScrollView!
    private var resultsHeader: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    /// 搜索进行中标志（用于正确判断进度条状态，而非依赖 isDisplayedWhenStopped）
    private var isSearching: Bool = false
    /// D1: 搜索代次计数器。每次发起新搜索自增；回调校验代次一致才应用结果，
    /// 避免旧搜索的迟到结果混入新查询（竞态）。
    private var searchGeneration: Int = 0
    /// D5: 结果批量刷新计数器（每 32 条刷新一次表）
    private var searchBatchPending: Int = 0
    /// D2: 主容器引用（主题切换时刷新静态 cgColor 背景快照）
    private weak var mainContainerView: NSView?
    /// D2: 主题变化监听 token
    private var appearanceObserver: NSObjectProtocol?

    // MARK: - 内容索引（FTS5）状态

    /// 内容索引状态栏容器（结果区表头下方）
    private var contentIndexStatusBar: NSView!
    /// 内容索引状态标签
    private var contentIndexStatusLabel: NSTextField!
    /// 内容索引构建进度条
    private var contentIndexProgress: NSProgressIndicator!
    /// 内容索引动作按钮（构建/取消/继续/重试/重建）
    private var contentIndexActionButton: NSButton!
    /// 内容索引状态轮询定时器
    private var contentIndexPollTimer: Timer?
    /// 当前查询的匹配路径集合（nil = 未查询 / 索引未就绪 / 内容筛选关闭）
    private var contentMatches: Set<String>?
    /// 内容查询是否在途（避免重复发起）
    private var contentQueryInFlight: Bool = false

    // MARK: - 数据

    /// F9-D: scopePopup 选项索引（工具栏范围筛选 popup，与 typePopup/timePopup 配合缩小结果集）
    private enum ScopePopupIndex: Int {
        case all = 0              // 全部范围
        case currentLocation = 1  // 当前位置
        case customLocation = 2   // 指定位置...
    }

    private var results: [FFSearchResult] = []
    /// 过滤后的结果（应用筛选侧边栏配置）
    private var filteredResults: [FFSearchResult] = []
    private var currentMode: SearchMode = .local
    private var currentQuery: String = ""
    private var currentPath: String = ""
    /// scopePopup 选中"指定位置..."时用户选择的路径（nil 表示未选择）
    private var customScopePath: String? = nil
    private var searchStartTime: Date?

    /// 双击结果跳转回调
    public var onNavigateToPath: ((String) -> Void)?

    /// 结果详情标签（任务 T12：选中结果后动态更新，替代静态占位文案）
    private var detailsLabel: NSTextField!
    /// 任务 T12: 窗口是否已首次定位（首次显示 center，之后尊重 frame autosave 保存的 frame）
    private var hasPresentedBefore = false

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "搜索"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 640, height: 400)
        window.center()
        window.setFrameAutosaveName("SearchPanelWindow")
        self.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }

        // 任务 F11-2: 窗口实体背景（v0.6.7）
        // 移除透明窗口配置（isOpaque=false + backgroundColor=.clear），改为实体窗口背景。
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true

        // ===== 顶部搜索工具栏 =====
        let searchToolbar = makeSearchToolbar()
        searchToolbar.translatesAutoresizingMaskIntoConstraints = false

        // ===== 中部内容区（筛选侧边栏 + 结果区） =====
        // 任务 F11-2: 筛选侧边栏实体背景（替代 FFGlassView .panel .sidebar，v0.6.7）
        filterSidebar = SearchFilterSidebar(frame: .zero)
        filterSidebar.translatesAutoresizingMaskIntoConstraints = false
        filterSidebar.onConfigChanged = { [weak self] _ in
            self?.applyFiltersAndReload()
        }
        let sidebarContainer = makeSolidContainer()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(filterSidebar)

        // 结果区容器
        let resultsPane = NSView()
        resultsPane.translatesAutoresizingMaskIntoConstraints = false
        resultsPane.wantsLayer = true
        resultsPane.layer?.backgroundColor = NSColor.clear.cgColor

        // 任务 F11-2: resultsHeader 容器实体背景（替代 FFGlassView .component，v0.6.7）
        let resultsHeaderContainer = makeSolidContainer()
        resultsHeaderContainer.translatesAutoresizingMaskIntoConstraints = false
        resultsHeader = NSTextField(labelWithString: "就绪")
        resultsHeader.font = NSFont.systemFont(ofSize: 11)
        resultsHeader.textColor = NSColor.secondaryLabelColor
        resultsHeader.translatesAutoresizingMaskIntoConstraints = false
        resultsHeaderContainer.addSubview(resultsHeader)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        resultsHeaderContainer.addSubview(progressIndicator)

        // 内容索引状态栏（结果区表头下方，常驻显示索引状态 + 动作入口）
        contentIndexStatusBar = makeSolidContainer()
        contentIndexStatusBar.translatesAutoresizingMaskIntoConstraints = false

        contentIndexStatusLabel = NSTextField(labelWithString: "内容索引：")
        contentIndexStatusLabel.font = NSFont.systemFont(ofSize: 11)
        contentIndexStatusLabel.textColor = NSColor.secondaryLabelColor
        contentIndexStatusLabel.lineBreakMode = .byTruncatingTail
        contentIndexStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        contentIndexProgress = NSProgressIndicator()
        contentIndexProgress.style = .bar
        contentIndexProgress.controlSize = .small
        contentIndexProgress.isIndeterminate = true
        contentIndexProgress.isDisplayedWhenStopped = false
        contentIndexProgress.translatesAutoresizingMaskIntoConstraints = false

        contentIndexActionButton = NSButton(title: "构建索引", target: self, action: #selector(contentIndexActionClicked))
        contentIndexActionButton.bezelStyle = .rounded
        contentIndexActionButton.controlSize = .small
        contentIndexActionButton.font = NSFont.systemFont(ofSize: 11)
        contentIndexActionButton.translatesAutoresizingMaskIntoConstraints = false

        contentIndexStatusBar.addSubview(contentIndexStatusLabel)
        contentIndexStatusBar.addSubview(contentIndexProgress)
        contentIndexStatusBar.addSubview(contentIndexActionButton)

        NSLayoutConstraint.activate([
            contentIndexStatusLabel.leadingAnchor.constraint(equalTo: contentIndexStatusBar.leadingAnchor, constant: 12),
            contentIndexStatusLabel.centerYAnchor.constraint(equalTo: contentIndexStatusBar.centerYAnchor),

            contentIndexProgress.leadingAnchor.constraint(equalTo: contentIndexStatusLabel.trailingAnchor, constant: 8),
            contentIndexProgress.centerYAnchor.constraint(equalTo: contentIndexStatusBar.centerYAnchor),
            contentIndexProgress.trailingAnchor.constraint(equalTo: contentIndexActionButton.leadingAnchor, constant: -8),

            contentIndexActionButton.trailingAnchor.constraint(equalTo: contentIndexStatusBar.trailingAnchor, constant: -12),
            contentIndexActionButton.centerYAnchor.constraint(equalTo: contentIndexStatusBar.centerYAnchor),
        ])

        // 结果列表
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        resultsTableView = NSTableView()
        resultsTableView.allowsMultipleSelection = false
        resultsTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        resultsTableView.usesAlternatingRowBackgroundColors = false
        resultsTableView.rowHeight = 40  // 双行堆叠需要更高行高
        resultsTableView.backgroundColor = .clear
        resultsTableView.doubleAction = #selector(resultDoubleClicked)
        resultsTableView.target = self

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.width = 280
        nameCol.resizingMask = .autoresizingMask
        resultsTableView.addTableColumn(nameCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "大小"
        sizeCol.width = 100
        sizeCol.resizingMask = .autoresizingMask
        resultsTableView.addTableColumn(sizeCol)

        let modifiedCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        modifiedCol.title = "修改时间"
        modifiedCol.width = 140
        modifiedCol.resizingMask = .autoresizingMask
        resultsTableView.addTableColumn(modifiedCol)

        resultsTableView.dataSource = self
        resultsTableView.delegate = self
        scrollView.documentView = resultsTableView

        // 任务 F11-2: 详情栏实体背景（替代 FFGlassView .panel .headerView，v0.6.7）
        // 保留 8pt 圆角卡片样式。
        let detailsBar = makeSolidContainer(cornerRadius: 8)
        detailsBar.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel = NSTextField(wrappingLabelWithString: "选择一个结果以查看详情")
        detailsLabel.font = NSFont.systemFont(ofSize: 11)
        detailsLabel.textColor = NSColor.tertiaryLabelColor
        detailsLabel.maximumNumberOfLines = 2
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsBar.addSubview(detailsLabel)

        // 组装结果区
        resultsPane.addSubview(resultsHeaderContainer)
        resultsPane.addSubview(contentIndexStatusBar)
        resultsPane.addSubview(scrollView)
        resultsPane.addSubview(detailsBar)

        // 主分栏视图
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor
        splitView.addArrangedSubview(sidebarContainer)
        splitView.addArrangedSubview(resultsPane)

        // 主容器（实体背景）
        let mainContainer = NSView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        // D2: 不用静态 cgColor 快照（不随主题变化）；背景色由 viewDidChangeEffectiveAppearance 动态刷新
        mainContainer.addSubview(searchToolbar)
        mainContainer.addSubview(splitView)
        mainContainerView = mainContainer

        NSLayoutConstraint.activate([
            // 顶部工具栏
            searchToolbar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            searchToolbar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            searchToolbar.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            searchToolbar.heightAnchor.constraint(equalToConstant: 68),

            // 分栏视图
            splitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: searchToolbar.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),

            // 筛选侧边栏宽度 180pt
            sidebarContainer.widthAnchor.constraint(equalToConstant: 180),
        ])

        // 结果区内部约束
        NSLayoutConstraint.activate([
            resultsHeaderContainer.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor),
            resultsHeaderContainer.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor),
            resultsHeaderContainer.topAnchor.constraint(equalTo: resultsPane.topAnchor),
            resultsHeaderContainer.heightAnchor.constraint(equalToConstant: 22),

            resultsHeader.leadingAnchor.constraint(equalTo: resultsHeaderContainer.leadingAnchor, constant: 12),
            resultsHeader.centerYAnchor.constraint(equalTo: resultsHeaderContainer.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: resultsHeaderContainer.trailingAnchor, constant: -12),
            progressIndicator.centerYAnchor.constraint(equalTo: resultsHeaderContainer.centerYAnchor),

            contentIndexStatusBar.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor),
            contentIndexStatusBar.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor),
            contentIndexStatusBar.topAnchor.constraint(equalTo: resultsHeaderContainer.bottomAnchor),
            contentIndexStatusBar.heightAnchor.constraint(equalToConstant: 26),

            scrollView.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentIndexStatusBar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: detailsBar.topAnchor),

            detailsBar.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor, constant: 8),
            detailsBar.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor, constant: -8),
            detailsBar.bottomAnchor.constraint(equalTo: resultsPane.bottomAnchor, constant: -4),
            detailsBar.heightAnchor.constraint(equalToConstant: 36),
            detailsLabel.leadingAnchor.constraint(equalTo: detailsBar.leadingAnchor, constant: 12),
            detailsLabel.centerYAnchor.constraint(equalTo: detailsBar.centerYAnchor),

            filterSidebar.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            filterSidebar.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            filterSidebar.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            filterSidebar.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
        ])

        splitView.setPosition(180, ofDividerAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        // 任务 F11-2: 实体背景容器（替代 NSGlassEffectView/NSVisualEffectView 透明架构，v0.6.7）
        let containerView = FFOpaqueContainerView()
        containerView.wantsLayer = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        // D2: cgColor 是快照不随主题变化；窗口背景由系统绘制，层背景色仅在主题切换时刷新一次
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        containerView.addSubview(mainContainer)
        NSLayoutConstraint.activate([
            mainContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mainContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        window.contentView = containerView

        // D2: 主题切换时刷新静态 cgColor 快照背景（移除 appearance 快照后窗口本身跟随系统，
        // 但 layer 背景色是快照，需在主题变化时重绘）
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .appearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, let mainView = self.mainContainerView else { return }
            let isDark = ThemeManager.shared.resolvedIsDark
            let bg: NSColor = isDark ? NSColor(calibratedWhite: 0.16, alpha: 1.0) : NSColor.windowBackgroundColor
            mainView.layer?.backgroundColor = bg.cgColor
            mainView.needsDisplay = true
        }
    }

    // MARK: - 任务 F11-2: 实体背景容器工厂（v0.6.7）

    /// 创建实体背景 NSView 容器（替代 FFGlassView .panel/.component）。
    /// - Parameter cornerRadius: 圆角（默认 0；卡片样式传 8/10 等）
    /// - Returns: isOpaque=true 的 NSView，背景色为系统动态 controlBackgroundColor。
    private func makeSolidContainer(cornerRadius: CGFloat = 0) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = cornerRadius
        // 不设置 masksToBounds：避免裁剪容器内内容
        return view
    }

    /// 构建顶部搜索工具栏（大搜索框 32pt + 控件行）（v0.6.7）
    private func makeSearchToolbar() -> NSView {
        // 任务 F11-2: 实体背景容器（替代 FFGlassView .panel .headerView，v0.6.7）
        let toolbar = makeSolidContainer()

        // 大搜索框（32pt 高）
        searchField = NSSearchField()
        searchField.placeholderString = "输入搜索关键词..."
        searchField.setAccessibilityLabel("搜索关键词")
        searchField.target = self
        searchField.action = #selector(searchClicked)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.controlSize = .large

        // 控件行：模式切换 + 范围 + 类型 + 修改时间
        modeSegmentedControl = NSSegmentedControl(labels: SearchMode.allCases.map { $0.title }, trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modeSegmentedControl.selectedSegment = 0
        modeSegmentedControl.controlSize = .small
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

        scopePopup = NSPopUpButton()
        scopePopup.addItems(withTitles: ["全部范围", "当前位置", "指定位置..."])
        scopePopup.controlSize = .small
        scopePopup.translatesAutoresizingMaskIntoConstraints = false
        scopePopup.target = self
        scopePopup.action = #selector(filterPopupChanged(_:))

        typePopup = NSPopUpButton()
        typePopup.addItems(withTitles: ["全部类型", "PDF", "图片", "视频", "文档", "音频"])
        typePopup.controlSize = .small
        typePopup.translatesAutoresizingMaskIntoConstraints = false
        typePopup.target = self
        typePopup.action = #selector(filterPopupChanged(_:))

        timePopup = NSPopUpButton()
        timePopup.addItems(withTitles: ["任意时间", "今天", "本周", "本月", "今年"])
        timePopup.controlSize = .small
        timePopup.translatesAutoresizingMaskIntoConstraints = false
        timePopup.target = self
        timePopup.action = #selector(filterPopupChanged(_:))

        let controlsStack = NSStackView(views: [modeSegmentedControl, scopePopup, typePopup, timePopup])
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 8
        controlsStack.alignment = .centerY
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(searchField)
        toolbar.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 8),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            controlsStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.trailingAnchor, constant: -12),
            controlsStack.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            controlsStack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -6),
        ])

        return toolbar
    }

    // MARK: - Public API

    /// 显示搜索面板
    /// - Parameters:
    ///   - initialQuery: 初始查询（可选）
    ///   - searchPath: 搜索路径（本地模式使用）
    public func showPanel(initialQuery: String = "", searchPath: String = "") {
        currentPath = searchPath
        // 每次打开面板重置范围选择：清空自定义路径并回到"全部范围"，避免上次选择残留误导
        customScopePath = nil
        scopePopup.selectItem(at: ScopePopupIndex.all.rawValue)
        if !initialQuery.isEmpty {
            searchField.stringValue = initialQuery
            currentQuery = initialQuery
            performSearch()
        }
        // 确保应用在前台
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        // 显示窗口并置前
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // 任务 T12: 仅首次显示时居中；之后尊重 setFrameAutosaveName 恢复的用户 frame，
        // 避免每次打开覆盖用户调整过的窗口位置/尺寸。
        if !hasPresentedBefore {
            window?.center()
            hasPresentedBefore = true
        }
        // 设置搜索框为第一响应者
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.searchField)
        }
        // 启动内容索引状态轮询（窗口可见期间）
        startContentIndexPolling()
    }

    /// 关闭面板时停掉仍在跑的本地 Rust 搜索与内容索引状态轮询，避免后台继续遍历
    public override func close() {
        SearchBridge.shared.cancelSearch()
        stopContentIndexPolling()
        super.close()
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        currentMode = SearchMode(rawValue: modeSegmentedControl.selectedSegment) ?? .local
        if !currentQuery.isEmpty {
            performSearch()
        }
    }

    @objc private func searchClicked() {
        currentQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        performSearch()
    }

    @objc private func resultDoubleClicked() {
        guard resultsTableView.clickedRow >= 0,
              resultsTableView.clickedRow < filteredResults.count else { return }
        let result = filteredResults[resultsTableView.clickedRow]
        onNavigateToPath?(result.path)
        close()
    }

    // MARK: - Search

    private func performSearch() {
        guard !currentQuery.isEmpty else {
            searchGeneration += 1
            contentMatches = nil
            contentQueryInFlight = false
            results = []
            filteredResults = []
            resultsTableView.reloadData()
            resultsHeader.stringValue = "请输入搜索关键词"
            return
        }

        // D1: 自增代次，使旧搜索的迟到回调被丢弃
        searchGeneration += 1
        // 实际停掉仍在跑的本地 Rust 搜索（不再只是丢弃迟到结果）
        SearchBridge.shared.cancelSearch()
        // 清空内容匹配缓存：新查询需重新走一次索引查询
        contentMatches = nil
        contentQueryInFlight = false
        let generation = searchGeneration
        results = []
        filteredResults = []
        resultsTableView.reloadData()
        isSearching = true
        progressIndicator.startAnimation(nil)
        resultsHeader.stringValue = "搜索中..."
        searchStartTime = Date()

        switch currentMode {
        case .local:
            performLocalSearch(generation: generation)
        case .global:
            performGlobalSearch(generation: generation)
        }
    }

    private func performLocalSearch(generation: Int) {
        let path = currentPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : currentPath

        // D5: 结果批量刷新。每结果立即 reloadData 是 O(n²)（每次过滤全表+重载），
        // 改为每 32 条刷新一次，最后一条强制刷新。
        searchBatchPending = 0

        SearchBridge.shared.search(
            path: path,
            query: currentQuery,
            resultHandler: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, self.searchGeneration == generation else { return }
                    self.results.append(result)
                    self.searchBatchPending += 1
                    if self.searchBatchPending >= 32 {
                        self.searchBatchPending = 0
                        self.applyFiltersAndReload()
                    }
                }
            },
            completion: { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self, self.searchGeneration == generation else { return }
                    if self.searchBatchPending > 0 {
                        self.searchBatchPending = 0
                        self.applyFiltersAndReload()
                    }
                    self.isSearching = false
                    self.progressIndicator.stopAnimation(nil)
                    self.updateResultsHeader(error: error)
                }
            }
        )
    }

    private func performGlobalSearch(generation: Int) {
        SpotlightBridge.shared.search(query: currentQuery) { [weak self] results in
            DispatchQueue.main.async {
                guard let self = self, self.searchGeneration == generation else { return }
                self.isSearching = false
                self.results = results
                self.applyFiltersAndReload()
                self.progressIndicator.stopAnimation(nil)
                self.updateResultsHeader(error: nil)
            }
        }
    }

    private func updateResultsHeader(error: Error?) {
        let elapsed = searchStartTime.map { Date().timeIntervalSince($0) } ?? 0
        if let error = error {
            resultsHeader.stringValue = "错误: \(error.localizedDescription)"
        } else {
            resultsHeader.stringValue = "找到 \(filteredResults.count) 个结果 · 用时 \(String(format: "%.2f", elapsed)) 秒"
        }
    }

    // MARK: - 筛选应用

    /// F9-D: 工具栏 popup 变更时触发重新筛选（scopePopup 切到"指定位置..."时先弹路径选择器）
    @objc private func filterPopupChanged(_ sender: NSPopUpButton) {
        // "指定位置..." 选中时弹出路径选择器，让用户选择目标目录
        if sender === scopePopup,
           ScopePopupIndex(rawValue: scopePopup.indexOfSelectedItem) == .customLocation {
            promptForCustomScopePath()
            return
        }
        applyFiltersAndReload()
    }

    /// F9-D: 弹出 NSOpenPanel 让用户选择"指定位置"目录，选定后存入 customScopePath 并重新筛选
    private func promptForCustomScopePath() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = false
        openPanel.prompt = "选择"
        openPanel.title = "选择搜索范围目录"
        // 起始目录优先用 currentPath
        if !currentPath.isEmpty {
            openPanel.directoryURL = URL(fileURLWithPath: currentPath)
        }

        openPanel.beginSheetModal(for: window!) { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = openPanel.url {
                self.customScopePath = url.path
                self.applyFiltersAndReload()
            } else {
                // 用户取消：回退到"全部范围"并清空自定义路径，避免误导
                self.customScopePath = nil
                self.scopePopup.selectItem(at: ScopePopupIndex.all.rawValue)
                self.applyFiltersAndReload()
            }
        }
    }

    /// 根据筛选侧边栏配置过滤结果并重载表格。
    /// 内容包含时先确保索引查询在途（异步），其余筛选同步执行。
    private func applyFiltersAndReload() {
        let config = filterSidebar.config
        if config.matchContent && !currentQuery.isEmpty {
            ensureContentMatches(for: currentQuery)
        } else {
            contentMatches = nil
        }
        reloadFilteredResults()
    }

    /// 确保当前查询的内容匹配集合已就绪：索引就绪时异步发起一次索引查询，
    /// 未就绪时内容筛选禁用（不回退到主线程逐文件读取）。
    private func ensureContentMatches(for query: String) {
        guard ContentIndexBridge.shared.status() == .ready else {
            contentMatches = nil
            return
        }
        if contentMatches != nil || contentQueryInFlight { return }
        contentQueryInFlight = true
        let generation = searchGeneration
        let escaped = escapeContentQuery(query)
        ContentIndexBridge.shared.query(escaped, maxResults: 500) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.searchGeneration == generation else { return }
                self.contentQueryInFlight = false
                switch result {
                case .success(let matches):
                    self.contentMatches = matches
                case .failure:
                    self.contentMatches = []
                }
                self.reloadFilteredResults()
            }
        }
    }

    /// 实际执行筛选（同步，纯内存集合成员判断）+ 重载表格。
    private func reloadFilteredResults() {
        let config = filterSidebar.config
        let scopeIndex = ScopePopupIndex(rawValue: scopePopup.indexOfSelectedItem) ?? .all
        let typeIndex = typePopup.indexOfSelectedItem
        let timeIndex = timePopup.indexOfSelectedItem
        let now = Date()
        let calendar = Calendar.current

        // 计算 scope 过滤所需的前缀路径（nil 表示不限制路径）
        let scopePrefixPath: String? = {
            switch scopeIndex {
            case .all:
                return nil
            case .currentLocation:
                return currentPath.isEmpty ? nil : normalizePath(currentPath)
            case .customLocation:
                guard let custom = customScopePath, !custom.isEmpty else { return nil }
                return normalizePath(custom)
            }
        }()

        let query = currentQuery

        filteredResults = results.filter { result in
            // 范围筛选：只保留路径以指定前缀开头的结果
            if let prefix = scopePrefixPath {
                if !isPath(result.path, under: prefix) { return false }
            }
            // 文件类型筛选（侧边栏）
            if !config.enabledTypes.isEmpty {
                let matched = fileTypeOf(result)
                if !config.enabledTypes.contains(matched) { return false }
            }
            // 文件类型筛选（工具栏 popup，与侧边栏取交集）
            if typeIndex > 0 {
                let popupTypes: [FileTypeFilter] = [.pdf, .image, .video, .document, .audio]
                let popupType = popupTypes[typeIndex - 1]
                if fileTypeOf(result) != popupType { return false }
            }
            // 修改时间筛选（工具栏 popup）
            if timeIndex > 0 {
                let modDate = Date(timeIntervalSince1970: TimeInterval(result.modified))
                let cutoff: Date?
                switch timeIndex {
                case 1: cutoff = calendar.date(byAdding: .day, value: -1, to: now)
                case 2: cutoff = calendar.date(byAdding: .day, value: -7, to: now)
                case 3: cutoff = calendar.date(byAdding: .month, value: -1, to: now)
                case 4: cutoff = calendar.date(byAdding: .year, value: -1, to: now)
                default: cutoff = nil
                }
                if let cutoff = cutoff, modDate < cutoff { return false }
            }
            // 文件名包含：默认开启；关闭时不再要求文件名匹配（但 Rust 端已按文件名返回结果，
            // 关闭此开关时保留所有返回项，不额外排除）
            if config.matchFileName && !query.isEmpty {
                if config.caseSensitive {
                    if !result.name.contains(query) { return false }
                } else {
                    if !result.name.lowercased().contains(query.lowercased()) { return false }
                }
            }
            // 内容包含：用索引查询的匹配路径 Set 做 O(1) 成员判断，不再逐文件读取
            if config.matchContent && !query.isEmpty {
                if let matches = contentMatches, !matches.contains(result.path) {
                    return false
                }
                // contentMatches == nil：索引未就绪/查询未完成，内容筛选禁用（不过滤、不读文件）
            }
            return true
        }
        resultsTableView.reloadData()
        if isSearching {
            // 搜索进行中：显示省略号表示仍在更新
            resultsHeader.stringValue = "找到 \(filteredResults.count) 个结果..."
        } else {
            resultsHeader.stringValue = "找到 \(filteredResults.count) 个结果"
        }
    }

    /// FTS5 phrase 查询转义（契约 §8.4）：双引号包裹 + 内部双引号翻倍，
    /// 避免空格/引号/AND/OR/NEAR 被当作 FTS5 语法，实现子串式包含匹配。
    private func escapeContentQuery(_ query: String) -> String {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - 内容索引状态

    /// 内容索引状态栏描述（纯函数，供 UI 与单元测试共用）。
    /// 契约 §6.2 逐状态唯一映射：label / 是否显示进度 / 动作按钮文案与可见性。
    struct ContentIndexStatusDescriptor: Equatable {
        let label: String
        let showsProgress: Bool
        let showsActionButton: Bool
        let actionTitle: String
    }

    static func contentIndexStatusDescriptor(status: ContentIndexStatus,
                                             stats: ContentIndexStats?) -> ContentIndexStatusDescriptor {
        switch status {
        case .empty:
            return ContentIndexStatusDescriptor(label: "内容索引尚未构建",
                                                showsProgress: false, showsActionButton: true, actionTitle: "构建索引")
        case .indexing:
            let paused = stats?.paused ?? false
            return ContentIndexStatusDescriptor(label: paused ? "内容索引构建已暂停" : "正在构建内容索引…",
                                                showsProgress: true, showsActionButton: true,
                                                actionTitle: paused ? "继续" : "取消")
        case .ready:
            return ContentIndexStatusDescriptor(label: "内容索引就绪（\(stats?.documentCount ?? 0) 个文件）",
                                                showsProgress: false, showsActionButton: true, actionTitle: "重建")
        case .error:
            return ContentIndexStatusDescriptor(label: "内容索引错误：\(stats?.error ?? "未知错误")",
                                                showsProgress: false, showsActionButton: true, actionTitle: "重试")
        case .cancelled:
            return ContentIndexStatusDescriptor(label: "内容索引构建已取消",
                                                showsProgress: false, showsActionButton: true, actionTitle: "继续构建")
        case .unavailable:
            return ContentIndexStatusDescriptor(label: "内容搜索不可用",
                                                showsProgress: false, showsActionButton: false, actionTitle: "")
        }
    }

    /// 结果详情文案（纯函数，供选中回调与单元测试共用）。
    /// - nil：无选中占位
    /// - 非 nil：第一行 名称 · 大小 · 修改时间，第二行完整路径
    static func detailsText(for result: FFSearchResult?) -> String {
        guard let result = result else { return "选择一个结果以查看详情" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeText = formatter.string(fromByteCount: Int64(result.size))
        let dateText = result.modified > 0 ? FFFormat.date(Date(timeIntervalSince1970: TimeInterval(result.modified))) : "未知时间"
        return "\(result.name) · \(sizeText) · 修改于 \(dateText)\n\(result.path)"
    }

    private func startContentIndexPolling() {
        stopContentIndexPolling()
        updateContentIndexStatusUI()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateContentIndexStatusUI()
        }
        RunLoop.main.add(timer, forMode: .common)
        contentIndexPollTimer = timer
    }

    private func stopContentIndexPolling() {
        contentIndexPollTimer?.invalidate()
        contentIndexPollTimer = nil
    }

    /// 内容索引状态机 → 状态行 UI（契约 §6.2 逐状态唯一映射，映射表抽为纯函数供测试）。
    private func updateContentIndexStatusUI() {
        let status = ContentIndexBridge.shared.status()
        let stats = ContentIndexBridge.shared.stats()
        let descriptor = Self.contentIndexStatusDescriptor(status: status, stats: stats)

        contentIndexStatusLabel.stringValue = descriptor.label

        if descriptor.showsProgress {
            if let stats = stats, stats.totalCandidates > 0 {
                contentIndexProgress.isIndeterminate = false
                contentIndexProgress.maxValue = Double(stats.totalCandidates)
                contentIndexProgress.doubleValue = Double(stats.processed)
            } else {
                contentIndexProgress.isIndeterminate = true
            }
            contentIndexProgress.isHidden = false
            contentIndexProgress.startAnimation(nil)
        } else {
            contentIndexProgress.isHidden = true
            contentIndexProgress.stopAnimation(nil)
        }

        contentIndexActionButton.isHidden = !descriptor.showsActionButton
        if descriptor.showsActionButton {
            contentIndexActionButton.title = descriptor.actionTitle
        }
    }

    @objc private func contentIndexActionClicked() {
        let status = ContentIndexBridge.shared.status()
        switch status {
        case .empty, .error, .cancelled:
            startContentIndexBuild(mode: .incremental)
        case .indexing:
            if ContentIndexBridge.shared.stats()?.paused == true {
                ContentIndexBridge.shared.resume()
            } else {
                ContentIndexBridge.shared.cancel()
            }
        case .ready:
            startContentIndexBuild(mode: .rebuild)
        case .unavailable:
            break
        }
        updateContentIndexStatusUI()
    }

    private func startContentIndexBuild(mode: ContentIndexMode) {
        let root = NSHomeDirectory()
        _ = ContentIndexBridge.shared.start(rootPath: root, mode: mode)
    }

    /// F9-D: 规范化路径：去掉末尾的 "/"（根目录 "/" 除外），统一用于前缀比较
    private func normalizePath(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }

    /// F9-D: 判断 childPath 是否位于 parentPath 之下（含 parentPath 自身）
    /// 用前缀比较并确保边界是目录分隔符，避免 "/a/b" 误匹配 "/a/bc"
    private func isPath(_ childPath: String, under parentPath: String) -> Bool {
        let child = normalizePath(childPath)
        let parent = normalizePath(parentPath)
        if child == parent { return true }
        // 父路径为根目录 "/" 时，所有路径都匹配
        if parent == "/" { return true }
        return child.hasPrefix(parent + "/")
    }

    /// 根据文件扩展名推断 FileTypeFilter
    private func fileTypeOf(_ result: FFSearchResult) -> FileTypeFilter {
        let ext = (result.name as NSString).pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp", "svg"]
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv"]
        let audioExts: Set<String> = ["mp3", "wav", "aac", "flac", "m4a", "ogg"]
        let docExts: Set<String> = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "pages", "numbers", "key"]
        if ext == "pdf" { return .pdf }
        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        if audioExts.contains(ext) { return .audio }
        if docExts.contains(ext) { return .document }
        return .other
    }
}

// MARK: - NSTableViewDataSource

extension SearchPanelController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredResults.count
    }
}

// MARK: - NSTableViewDelegate

extension SearchPanelController: NSTableViewDelegate {
    /// 任务 T12: 选中结果后更新详情栏（替代静态"选择一个结果以查看详情"死 UI）。
    /// 无选中时回退占位文案；文案由纯函数 detailsText 生成（可单测）。
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, tableView === resultsTableView else { return }
        let row = resultsTableView.selectedRow
        guard row >= 0, row < filteredResults.count else {
            detailsLabel?.stringValue = Self.detailsText(for: nil)
            return
        }
        detailsLabel?.stringValue = Self.detailsText(for: filteredResults[row])
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredResults.count else { return nil }
        let result = filteredResults[row]

        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "")
        let identifier = tableColumn?.identifier.rawValue ?? ""

        if identifier == "name" {
            // 名称列：使用双行堆叠 cell
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? FFSearchNameCell
                ?? FFSearchNameCell()
            cell.identifier = cellID
            cell.configure(name: result.name, path: result.path)
            // T13: 搜索结果行无障碍标签（文件名 + 大小）
            cell.setAccessibilityLabel(FileEntryAccessibility.searchResultLabel(result))
            return cell
        }

        // 其他列：标准单行 cell
        let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = cellID

        if cellView.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            tf.lineBreakMode = .byTruncatingTail
            cellView.addSubview(tf)
            cellView.textField = tf
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        switch identifier {
        case "size":
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            cellView.textField?.stringValue = formatter.string(fromByteCount: Int64(result.size))
        case "modified":
            if result.modified > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(result.modified))
                cellView.textField?.stringValue = FFFormat.date(date)
            } else {
                cellView.textField?.stringValue = "—"
            }
        default:
            break
        }

        return cellView
    }
}
