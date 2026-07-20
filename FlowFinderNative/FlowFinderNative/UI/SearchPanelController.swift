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

/// 搜索面板窗口控制器：双模式搜索（Rust 本地 + Spotlight 全局）
public class SearchPanelController: NSWindowController {

    public static let shared = SearchPanelController()

    private var searchField: NSSearchField!
    private var modeSegmentedControl: NSSegmentedControl!
    private var resultsTableView: NSTableView!
    private var scrollView: NSScrollView!
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    private var results: [FFSearchResult] = []
    private var currentMode: SearchMode = .local
    private var currentQuery: String = ""
    private var currentPath: String = ""

    /// 双击结果跳转回调
    public var onNavigateToPath: ((String) -> Void)?

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "搜索"
        window.minSize = NSSize(width: 500, height: 300)
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
        let contentView = window.contentView!

        // 搜索栏容器
        let searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        // 模式切换
        modeSegmentedControl = NSSegmentedControl(labels: SearchMode.allCases.map { $0.title }, trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modeSegmentedControl.selectedSegment = 0
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

        // 搜索框
        searchField = NSSearchField()
        searchField.placeholderString = "输入搜索关键词..."
        searchField.target = self
        searchField.action = #selector(searchClicked)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // 进度指示器
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 状态标签
        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.addSubview(modeSegmentedControl)
        searchContainer.addSubview(searchField)
        searchContainer.addSubview(progressIndicator)
        searchContainer.addSubview(statusLabel)

        // 结果表格
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        resultsTableView = NSTableView()
        resultsTableView.allowsMultipleSelection = false
        resultsTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        resultsTableView.usesAlternatingRowBackgroundColors = true
        resultsTableView.rowHeight = 24
        resultsTableView.doubleAction = #selector(resultDoubleClicked)
        resultsTableView.target = self

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.width = 250
        resultsTableView.addTableColumn(nameCol)

        let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathCol.title = "路径"
        pathCol.width = 400
        resultsTableView.addTableColumn(pathCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "大小"
        sizeCol.width = 100
        resultsTableView.addTableColumn(sizeCol)

        resultsTableView.dataSource = self
        resultsTableView.delegate = self

        scrollView.documentView = resultsTableView
        contentView.addSubview(searchContainer)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            searchContainer.heightAnchor.constraint(equalToConstant: 28),

            modeSegmentedControl.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor),
            modeSegmentedControl.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            modeSegmentedControl.widthAnchor.constraint(equalToConstant: 180),

            searchField.leadingAnchor.constraint(equalTo: modeSegmentedControl.trailingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            progressIndicator.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            progressIndicator.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),

            statusLabel.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
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
              resultsTableView.clickedRow < results.count else { return }
        let result = results[resultsTableView.clickedRow]
        onNavigateToPath?(result.path)
        close()
    }

    // MARK: - Search

    private func performSearch() {
        guard !currentQuery.isEmpty else {
            results = []
            resultsTableView.reloadData()
            statusLabel.stringValue = "请输入搜索关键词"
            return
        }

        results = []
        resultsTableView.reloadData()
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "搜索中..."

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
                self?.results.append(result)
                self?.resultsTableView.reloadData()
                self?.statusLabel.stringValue = "找到 \(self?.results.count ?? 0) 个结果"
            },
            completion: { [weak self] error in
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(nil)
                    if let error = error {
                        self?.statusLabel.stringValue = "错误: \(error.localizedDescription)"
                    } else {
                        self?.statusLabel.stringValue = "完成，共 \(self?.results.count ?? 0) 个结果"
                    }
                }
            }
        )
    }

    private func performGlobalSearch() {
        SpotlightBridge.shared.search(query: currentQuery) { [weak self] results in
            self?.results = results
            self?.resultsTableView.reloadData()
            self?.progressIndicator.stopAnimation(nil)
            self?.statusLabel.stringValue = "完成，共 \(results.count) 个结果"
        }
    }
}

// MARK: - NSTableViewDataSource

extension SearchPanelController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return results.count
    }
}

// MARK: - NSTableViewDelegate

extension SearchPanelController: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count else { return nil }
        let result = results[row]

        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "")
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

        switch tableColumn?.identifier.rawValue {
        case "name":
            cellView.textField?.stringValue = result.name
        case "path":
            cellView.textField?.stringValue = result.path
        case "size":
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            cellView.textField?.stringValue = formatter.string(fromByteCount: Int64(result.size))
        default:
            break
        }

        return cellView
    }
}
