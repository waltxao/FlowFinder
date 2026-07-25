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

/// 重写 isOpaque 返回 true 的 NSView 子类（与 MainWindowController 同架构）
private class SearchOpaqueContainerView: NSView {
    override var isOpaque: Bool { return true }
}

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
/// 窗口级玻璃架构：OpaqueContainerView + NSGlassEffectView + mainContainer
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

    private var results: [FFSearchResult] = []
    /// 过滤后的结果（应用筛选侧边栏配置）
    private var filteredResults: [FFSearchResult] = []
    private var currentMode: SearchMode = .local
    private var currentQuery: String = ""
    private var currentPath: String = ""
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

        // 窗口透明以支持玻璃效果
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        // ===== 顶部搜索工具栏 =====
        let searchToolbar = makeSearchToolbar()
        searchToolbar.translatesAutoresizingMaskIntoConstraints = false

        // ===== 中部内容区（筛选侧边栏 + 结果区） =====
        // 筛选侧边栏（180pt，FFGlassView .panel .sidebar 包裹）
        filterSidebar = SearchFilterSidebar(frame: .zero)
        filterSidebar.translatesAutoresizingMaskIntoConstraints = false
        filterSidebar.onConfigChanged = { [weak self] _ in
            self?.applyFiltersAndReload()
        }
        let sidebarGlass = FFGlassView(level: .panel, cornerRadius: 0, material: .sidebar)
        sidebarGlass.translatesAutoresizingMaskIntoConstraints = false
        sidebarGlass.addSubview(filterSidebar)

        // 结果区容器
        let resultsPane = NSView()
        resultsPane.translatesAutoresizingMaskIntoConstraints = false
        resultsPane.wantsLayer = true
        resultsPane.layer?.backgroundColor = NSColor.clear.cgColor

        // resultsHeader（22pt，"找到 N 个结果 · 用时 X 秒"）
        let resultsHeaderContainer = FFGlassView(level: .component, cornerRadius: 0)
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

        // 收起详情栏（36pt，FFGlassView .panel .headerView）
        let detailsBar = FFGlassView(level: .panel, cornerRadius: 8, material: .headerView)
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
        splitView.addArrangedSubview(sidebarGlass)
        splitView.addArrangedSubview(resultsPane)

        // 主容器（透明背景以透出玻璃效果）
        let mainContainer = NSView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        mainContainer.layer?.backgroundColor = NSColor.clear.cgColor
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
            sidebarGlass.widthAnchor.constraint(equalToConstant: 180),
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

            filterSidebar.leadingAnchor.constraint(equalTo: sidebarGlass.leadingAnchor),
            filterSidebar.trailingAnchor.constraint(equalTo: sidebarGlass.trailingAnchor),
            filterSidebar.topAnchor.constraint(equalTo: sidebarGlass.topAnchor),
            filterSidebar.bottomAnchor.constraint(equalTo: sidebarGlass.bottomAnchor),
        ])

        splitView.setPosition(180, ofDividerAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        // ===== 窗口级玻璃架构（参照 MainWindowController） =====
        if #available(macOS 26.0, *) {
            let containerView = SearchOpaqueContainerView()
            containerView.wantsLayer = true
            containerView.translatesAutoresizingMaskIntoConstraints = false

            let glassView = NSGlassEffectView()
            glassView.style = .clear
            glassView.cornerRadius = 0
            glassView.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(glassView)
            containerView.addSubview(mainContainer)

            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                glassView.topAnchor.constraint(equalTo: containerView.topAnchor),
                glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                mainContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                mainContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                mainContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
                mainContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            window.contentView = containerView
        } else {
            // macOS 12-25 回退：NSVisualEffectView
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .underWindowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.addSubview(mainContainer)
            NSLayoutConstraint.activate([
                mainContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                mainContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                mainContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                mainContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            ])
            window.contentView = visualEffectView
        }
    }

    /// 构建顶部搜索工具栏（大搜索框 32pt + 控件行）
    private func makeSearchToolbar() -> NSView {
        // 玻璃背景
        let toolbar = FFGlassView(level: .panel, cornerRadius: 0, material: .headerView)

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
        if !initialQuery.isEmpty {
            searchField.stringValue = initialQuery
            currentQuery = initialQuery
            performSearch()
        }
        // 确保应用在前台
        NSApp.activate(ignoringOtherApps: true)
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

    /// 工具栏 popup 变更时触发重新筛选
    @objc private func filterPopupChanged(_ sender: NSPopUpButton) {
        applyFiltersAndReload()
    }

    /// 根据筛选侧边栏配置过滤结果并重载表格
    private func applyFiltersAndReload() {
        let config = filterSidebar.config
        // 读取工具栏 popup 状态
        let typeIndex = typePopup.indexOfSelectedItem
        let timeIndex = timePopup.indexOfSelectedItem
        let now = Date()
        let calendar = Calendar.current

        filteredResults = results.filter { result in
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
