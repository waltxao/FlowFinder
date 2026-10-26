import Cocoa
import Combine

/// ⌘0 独立任务面板窗口：显示所有任务列表
public class TaskPanelWindowController: NSWindowController {

    public static let shared = TaskPanelWindowController()

    /// ⌘W 命中任务中心窗口时关闭自身。
    @objc func menuCloseTab(_ sender: Any?) {
        close()
    }

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var refreshButton: NSButton!
    private var cancelButton: NSButton!
    private var revealButton: NSButton!
    private var clearButton: NSButton!
    private var statusLabel: NSTextField!

    private var cancellables = Set<AnyCancellable>()

    private enum PanelRow {
        case app(FFTask)
        case system(TaskInfo)

        /// 任务作用的对象（R4-24）。Rust 侧任务只带名称与描述，没有可靠路径。
        var locationPath: String? {
            switch self {
            case .app(let task): return task.locationPath
            case .system: return nil
            }
        }
    }
    private var rows: [PanelRow] = []
    private var emptyLabel: NSTextField!

    /// internal 供回归测试定位行与断言控件状态
    var rowTaskIDs: [String] {
        rows.map { row in
            switch row {
            case .app(let task): return task.id
            case .system(let task): return task.id
            }
        }
    }
    var tableViewForTesting: NSTableView? { tableView }
    var cancelButtonForTesting: NSButton? { cancelButton }
    var revealButtonForTesting: NSButton? { revealButton }

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = FFNaming.taskCenterBase
        window.minSize = NSSize(width: 500, height: 300)
        window.center()
        window.setFrameAutosaveName("TaskPanelWindow")
        self.init(window: window)
        setupUI()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }
        let contentView = window.contentView!

        // 工具栏
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "取消任务", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        revealButton = NSButton(title: "定位", target: self, action: #selector(revealClicked))
        revealButton.bezelStyle = .rounded
        revealButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton = NSButton(title: "清除已完成", target: self, action: #selector(clearClicked))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(refreshButton)
        toolbar.addSubview(cancelButton)
        toolbar.addSubview(revealButton)
        toolbar.addSubview(clearButton)
        toolbar.addSubview(statusLabel)

        // 表格
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        // 交替行底色会在最后一行下方继续画出空行条纹，看起来像可点的行（R4-22）。
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.rowHeight = 24

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "任务名称"
        nameCol.width = 200
        tableView.addTableColumn(nameCol)

        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusCol.title = "状态"
        statusCol.width = 100
        tableView.addTableColumn(statusCol)

        let progressCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("progress"))
        progressCol.title = "进度"
        progressCol.width = 120
        tableView.addTableColumn(progressCol)

        let createdCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("created"))
        createdCol.title = "创建时间"
        createdCol.width = 150
        tableView.addTableColumn(createdCol)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        contentView.addSubview(toolbar)
        contentView.addSubview(scrollView)

        emptyLabel = NSTextField(labelWithString: "暂无任务")
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = FFVisualTokens.hint
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            refreshButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            refreshButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            cancelButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            revealButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 8),
            revealButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            clearButton.leadingAnchor.constraint(equalTo: revealButton.trailingAnchor, constant: 8),
            clearButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            statusLabel.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Bindings

    private func setupBindings() {
        Publishers.CombineLatest(FFTaskService.shared.$tasks,
                                 TaskSchedulerManager.shared.$allTasks)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appTasks, systemTasks in
                guard let self else { return }
                self.rows = appTasks.map(PanelRow.app) + systemTasks.map(PanelRow.system)
                self.tableView.reloadData()
                self.updateActionbar()

                let activeApp = appTasks.filter(\.isActive).count
                let activeSystem = systemTasks.filter { $0.isActive }.count
                let completedSystem = systemTasks.filter { $0.isCompleted }.count
                let completedApp = appTasks.filter { !$0.isActive }.count
                self.emptyLabel.isHidden = !self.rows.isEmpty
                if self.rows.isEmpty {
                    self.statusLabel.stringValue = ""
                } else {
                    self.statusLabel.stringValue =
                        "共 \(self.rows.count) 个任务（\(activeApp + activeSystem) 进行中，\(completedApp + completedSystem) 已完成）"
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    public func showWindow() {
        TaskSchedulerManager.shared.refreshTasks()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        updateActionbar()
    }

    // MARK: - Actions

    @objc private func refreshClicked() {
        TaskSchedulerManager.shared.refreshTasks()
        tableView.reloadData()
        updateActionbar()
    }

    /// 「取消任务」只在选中行确实可取消时可用，避免点击后静默无效（R4-23）。
    /// 「定位」同一套规则（R4-24）：只有任务带着仍在磁盘上的对象时才可用，禁用原因写进 tooltip。
    private func updateActionbar() {
        let row = tableView.selectedRow
        let selected = (row >= 0 && row < rows.count) ? rows[row] : nil
        let cancellable = selected.map(isCancellable) ?? false
        cancelButton.isEnabled = cancellable
        cancelButton.toolTip = cancellable ? nil : "选中一个进行中的任务后可取消"

        let target = revealTarget(for: selected)
        revealButton.isEnabled = target.path != nil
        revealButton.toolTip = target.path ?? target.disabledReason
    }

    private func isCancellable(_ row: PanelRow) -> Bool {
        switch row {
        case .app(let task): return FFTaskService.shared.canCancel(task.id)
        case .system(let task): return task.isActive
        }
    }

    private func revealTarget(for row: PanelRow?) -> (path: String?, disabledReason: String?) {
        guard let row else { return (nil, "选中一个任务后可定位") }
        guard let path = row.locationPath, !path.isEmpty else {
            return (nil, "该任务没有可定位的对象")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return (nil, "对象已不在磁盘上：\(path)")
        }
        return (path, nil)
    }

    /// 把主窗口活动面板带到任务对象所在处（R4-24）。
    @objc private func revealClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count,
              let path = revealTarget(for: rows[row]).path else { return }
        if let main = TaskPanelWindowController.frontmostMainWindow() {
            main.revealTaskLocation(path: path)
            return
        }
        // 没有可见主窗口时退回访达，至少不会点了没反应。
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// 取最靠前的可见主窗口（`NSApp.windows` 按前后顺序排列）。
    private static func frontmostMainWindow() -> MainWindowController? {
        NSApp.windows.lazy.compactMap { $0.windowController as? MainWindowController }
            .first { controller in
                guard let window = controller.window else { return false }
                return window.isVisible && !window.isMiniaturized
            }
    }

    @objc private func cancelClicked() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < rows.count else { return }
        switch rows[tableView.selectedRow] {
        case .app(let task):
            guard FFTaskService.shared.canCancel(task.id) else { return }
            FFTaskService.shared.cancel(task.id)
        case .system(let task):
            TaskSchedulerManager.shared.cancelTask(taskId: task.id)
        }
    }

    @objc private func clearClicked() {
        // 清除应用任务与 Rust 任务的已完成历史，正在执行的任务保留
        FFTaskService.shared.removeFinished()
        TaskSchedulerManager.shared.clearCompletedTasks()
    }
}

// MARK: - NSTableViewDataSource

extension TaskPanelWindowController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }
}

// MARK: - NSTableViewDelegate

extension TaskPanelWindowController: NSTableViewDelegate {

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateActionbar()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }

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
        guard let text = cellView.textField else { return cellView }
        text.textColor = .labelColor

        switch rows[row] {
        case .app(let task):
            switch tableColumn?.identifier.rawValue {
            case "name":
                text.stringValue = task.detail.isEmpty ? task.title : "\(task.title) · \(task.detail)"
            case "status":
                text.stringValue = task.statusText
                switch task.state {
                case .running: text.textColor = .systemBlue
                case .finished: text.textColor = .systemGreen
                case .failed: text.textColor = .systemRed
                case .cancelled: text.textColor = .systemGray
                case .queued, .paused: text.textColor = .secondaryLabelColor
                }
            case "progress":
                text.stringValue = "\(Int(task.progress * 100))%"
            case "created":
                text.stringValue = FFFormat.dateCompact(task.startedAt)
            default:
                break
            }
        case .system(let task):
            switch tableColumn?.identifier.rawValue {
            case "name":
                text.stringValue = task.name
            case "status":
                text.stringValue = task.statusDescription
                switch task.status {
                case .running: text.textColor = NSColor.systemBlue
                case .completed: text.textColor = NSColor.systemGreen
                case .failed: text.textColor = NSColor.systemRed
                case .cancelled: text.textColor = NSColor.systemGray
                default: text.textColor = NSColor.labelColor
                }
            case "progress":
                text.stringValue = task.progressPercentage
            case "created":
                text.stringValue = task.formattedCreatedAt
            default:
                break
            }
        }

        return cellView
    }
}
