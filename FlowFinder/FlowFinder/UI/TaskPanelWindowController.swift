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
    private var clearButton: NSButton!
    private var statusLabel: NSTextField!

    private var cancellables = Set<AnyCancellable>()

    private enum PanelRow {
        case app(FFTask)
        case system(TaskInfo)
    }
    private var rows: [PanelRow] = []
    private var emptyLabel: NSTextField!

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
        window.title = "任务面板"
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

        clearButton = NSButton(title: "清除已完成", target: self, action: #selector(clearClicked))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(refreshButton)
        toolbar.addSubview(cancelButton)
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
        tableView.usesAlternatingRowBackgroundColors = true
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
        emptyLabel.textColor = .tertiaryLabelColor
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

            clearButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 8),
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

                let activeApp = appTasks.filter(\.isActive).count
                let activeSystem = systemTasks.filter { $0.isActive }.count
                let completedSystem = systemTasks.filter { $0.isCompleted }.count
                let completedApp = appTasks.filter { !$0.isActive }.count
                self.emptyLabel.isHidden = !self.rows.isEmpty
                if self.rows.isEmpty {
                    self.statusLabel.stringValue = "暂无任务"
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
    }

    // MARK: - Actions

    @objc private func refreshClicked() {
        TaskSchedulerManager.shared.refreshTasks()
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

    private static let appDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

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
                text.stringValue = Self.appDateFormatter.string(from: task.startedAt)
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
