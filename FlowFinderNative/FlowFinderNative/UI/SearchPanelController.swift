import Cocoa
import Combine

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
        let detailsLabel = NSTextField(labelWithString: "选择一个结果以查看详情")
        detailsLabel.font = NSFont.systemFont(ofSize: 11)
        detailsLabel.textColor = NSColor.tertiaryLabelColor
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsBar.addSubview(detailsLabel)

        // 组装结果区
        resultsPane.addSubview(resultsHeaderContainer)
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
        mainContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        mainContainer.addSubview(searchToolbar)
        mainContainer.addSubview(splitView)
        mainContainer.appearance = NSApp.effectiveAppearance

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

            scrollView.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: resultsHeaderContainer.bottomAnchor),
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
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        containerView.addSubview(mainContainer)
        NSLayoutConstraint.activate([
            mainContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mainContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        window.contentView = containerView
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
        view.layer?.masksToBounds = cornerRadius > 0
        return view
    }

    /// 构建顶部搜索工具栏（大搜索框 32pt + 控件行）（v0.6.7）
    private func makeSearchToolbar() -> NSView {
        // 任务 F11-2: 实体背景容器（替代 FFGlassView .panel .headerView，v0.6.7）
        let toolbar = makeSolidContainer()

        // 大搜索框（32pt 高）
        searchField = NSSearchField()
        searchField.placeholderString = "输入搜索关键词..."
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
        window?.center()
        // 设置搜索框为第一响应者
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.searchField)
        }
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
            results = []
            filteredResults = []
            resultsTableView.reloadData()
            resultsHeader.stringValue = "请输入搜索关键词"
            return
        }

        results = []
        filteredResults = []
        resultsTableView.reloadData()
        isSearching = true
        progressIndicator.startAnimation(nil)
        resultsHeader.stringValue = "搜索中..."
        searchStartTime = Date()

        switch currentMode {
        case .local:
            performLocalSearch()
        case .global:
            performGlobalSearch()
        }
    }

    private func performLocalSearch() {
        let path = currentPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : currentPath

        SearchBridge.shared.search(
            path: path,
            query: currentQuery,
            resultHandler: { [weak self] result in
                DispatchQueue.main.async {
                    self?.results.append(result)
                    self?.applyFiltersAndReload()
                }
            },
            completion: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isSearching = false
                    self?.progressIndicator.stopAnimation(nil)
                    self?.updateResultsHeader(error: error)
                }
            }
        )
    }

    private func performGlobalSearch() {
        SpotlightBridge.shared.search(query: currentQuery) { [weak self] results in
            DispatchQueue.main.async {
                self?.isSearching = false
                self?.results = results
                self?.applyFiltersAndReload()
                self?.progressIndicator.stopAnimation(nil)
                self?.updateResultsHeader(error: nil)
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

    /// 根据筛选侧边栏配置过滤结果并重载表格
    private func applyFiltersAndReload() {
        let config = filterSidebar.config
        // 读取工具栏 popup 状态
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
            // 标签筛选（暂未接入标签系统，跳过）
            // 搜索条件筛选（matchContent/caseSensitive 由 Rust 引擎处理，此处仅做客户端兜底）
            if config.caseSensitive {
                if !result.name.contains(currentQuery) { return false }
            } else {
                if !result.name.lowercased().contains(currentQuery.lowercased()) { return false }
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
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                cellView.textField?.stringValue = formatter.string(from: date)
            } else {
                cellView.textField?.stringValue = "—"
            }
        default:
            break
        }

        return cellView
    }
}
