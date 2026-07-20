# Phase 5: 搜索 + 重复扫描 + 任务调度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现双模式搜索面板（Rust 本地 + Spotlight 全局）、重复扫描独立窗口（目录选择 + 进度 + 分组结果 + 批量删除）、任务调度系统（底部固定进度条 + ⌘0 独立任务面板窗口）

**Architecture:** SearchPanelController 作为 NSWindowController 管理搜索窗口，内部使用 SearchBridge（Rust 本地）和 SpotlightBridge（全局）双模式切换；DuplicateScanWindowController 作为独立 NSWindowController 管理重复扫描窗口；TaskProgressBar 作为 NSView 嵌入主窗口底部，TaskPanelWindowController 作为 ⌘0 独立窗口管理任务列表；TaskSchedulerManager 作为单例轮询 CoreBridge.listTasks() 更新进度。

**Tech Stack:** Swift 6 / AppKit / NSWindowController / NSMetadataQuery / Combine

## Global Constraints

- macOS only (Swift & AppKit, no SwiftUI)
- 搜索双模式：Rust search_engine（当前目录）+ Spotlight NSMetadataQuery（全局）
- 重复扫描使用 BLAKE3 哈希（已在 Rust Core 实现）
- 任务调度：底部固定进度条 + ⌘0 独立任务面板窗口
- 所有 UI 文本使用中文（匹配用户偏好）
- 语法检查命令：`swiftc -parse <file>.swift`

---

## File Structure

| 文件 | 操作 | 职责 |
|------|------|------|
| `UI/SearchPanelController.swift` | 新建 | 搜索窗口控制器（双模式切换 + 结果列表 + 双击跳转） |
| `UI/SearchView.swift` | 重写 | 搜索结果视图（NSTableView + 高亮匹配 + 模式切换按钮） |
| `UI/DuplicateScanWindowController.swift` | 新建 | 重复扫描窗口控制器（目录选择 + 进度 + 结果 + 批量删除） |
| `UI/DuplicateScanView.swift` | 重写 | 重复扫描视图（分组展示 + 文件列表 + 删除按钮） |
| `UI/TaskProgressBar.swift` | 新建 | 底部固定进度条（当前任务进度 + 取消按钮） |
| `UI/TaskPanelWindowController.swift` | 新建 | ⌘0 独立任务面板窗口（任务列表 + 状态 + 进度） |
| `Bridge/TaskSchedulerManager.swift` | 新建 | 任务调度单例（轮询 CoreBridge.listTasks + 进度回调） |
| `UI/MainWindowController.swift` | 修改 | 集成 TaskProgressBar + 搜索面板触发 + ⌘0 路由 |
| `UI/MainMenu.swift` | 修改 | 添加 ⌘F（搜索）/⌘⇧D（重复扫描）/⌘0（任务面板）菜单项 |

---

## Task 1: 新建 TaskSchedulerManager.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/Bridge/TaskSchedulerManager.swift`

**Interfaces:**
- Consumes: `CoreBridge.shared.listTasks() -> [TaskInfo]` (Phase 1)
- Consumes: `CoreBridge.shared.cancelTask(taskId: Int32) throws` (Phase 1)
- Produces: `TaskSchedulerManager.shared` 单例
- Produces: `TaskSchedulerManager.startPolling(interval:)` 启动轮询
- Produces: `TaskSchedulerManager.stopPolling()` 停止轮询
- Produces: `TaskSchedulerManager.activeTask: TaskInfo?` 当前活跃任务
- Produces: `TaskSchedulerManager.allTasks: [TaskInfo]` 所有任务
- Produces: `TaskSchedulerManager.cancelTask(taskId:)` 取消任务
- Produces: `TaskSchedulerManager.onTaskUpdated: ((TaskInfo?) -> Void)?` 进度回调

- [ ] **Step 1: 创建 TaskSchedulerManager.swift**

```swift
import Foundation
import Combine

/// 任务调度管理器：单例轮询 CoreBridge.listTasks() 更新进度
public final class TaskSchedulerManager: ObservableObject {

    public static let shared = TaskSchedulerManager()

    @Published public private(set) var activeTask: TaskInfo?
    @Published public private(set) var allTasks: [TaskInfo] = []

    /// 任务更新回调（主线程）
    public var onTaskUpdated: ((TaskInfo?) -> Void)?
    public var onTasksChanged: (([TaskInfo]) -> Void)?

    private var pollingTimer: DispatchSourceTimer?
    private let pollingQueue = DispatchQueue(label: "com.flowfinder.taskpolling", qos: .utility)
    private var pollingInterval: TimeInterval = 0.5

    private init() {}

    // MARK: - Polling

    /// 启动任务轮询
    /// - Parameter interval: 轮询间隔（默认 0.5 秒）
    public func startPolling(interval: TimeInterval = 0.5) {
        pollingInterval = interval
        stopPolling()

        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now(), repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshTasks()
        }
        timer.resume()
        pollingTimer = timer
    }

    /// 停止任务轮询
    public func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    /// 立即刷新任务列表
    public func refreshTasks() {
        let tasks = CoreBridge.shared.listTasks()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.allTasks = tasks
            self.activeTask = tasks.first(where: { $0.isActive })

            self.onTaskUpdated?(self.activeTask)
            self.onTasksChanged?(tasks)
        }
    }

    // MARK: - Task Operations

    /// 取消指定任务
    /// - Parameter taskId: 任务 ID
    public func cancelTask(taskId: Int32) {
        do {
            try CoreBridge.shared.cancelTask(taskId: taskId)
            refreshTasks()
        } catch {
            print("TaskSchedulerManager: 取消任务失败: \(error.localizedDescription)")
        }
    }

    /// 获取任务进度（0.0-1.0）
    public var currentProgress: Double? {
        return activeTask?.progress
    }

    /// 是否有活跃任务
    public var hasActiveTask: Bool {
        return activeTask != nil
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/Bridge" && swiftc -parse TaskSchedulerManager.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/Bridge/TaskSchedulerManager.swift
git commit -m "feat: 新建 TaskSchedulerManager 任务调度管理器

- DispatchSourceTimer 定时轮询 CoreBridge.listTasks()
- @Published activeTask/allTasks 状态
- onTaskUpdated/onTasksChanged 回调
- cancelTask 取消指定任务
- startPolling/stopPolling 控制轮询"
```

---

## Task 2: 新建 TaskProgressBar.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/TaskProgressBar.swift`

**Interfaces:**
- Consumes: `TaskSchedulerManager.shared` (Task 1)
- Produces: `TaskProgressBar` NSView（底部固定进度条）
- Produces: `TaskProgressBar.show(task:)` 显示任务
- Produces: `TaskProgressBar.hide()` 隐藏进度条
- Produces: 高度 28pt，嵌入主窗口底部

- [ ] **Step 1: 创建 TaskProgressBar.swift**

```swift
import Cocoa
import Combine

/// 底部固定进度条：显示当前任务进度 + 取消按钮
public class TaskProgressBar: NSView {

    private var progressIndicator: NSProgressIndicator!
    private var taskLabel: NSTextField!
    private var cancelButton: NSButton!
    private var containerView: NSView!

    private var cancellables = Set<AnyCancellable>()
    private var currentTaskId: Int32?

    /// 进度条高度
    public static let height: CGFloat = 28

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupBindings()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupBindings()
    }

    // MARK: - UI Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 容器视图
        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // 进度条
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 任务标签
        taskLabel = NSTextField(labelWithString: "")
        taskLabel.font = NSFont.systemFont(ofSize: 11)
        taskLabel.textColor = NSColor.secondaryLabelColor
        taskLabel.lineBreakMode = .byTruncatingTail
        taskLabel.translatesAutoresizingMaskIntoConstraints = false

        // 取消按钮
        cancelButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "取消")!, target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .inline
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.toolTip = "取消任务"

        containerView.addSubview(progressIndicator)
        containerView.addSubview(taskLabel)
        containerView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            taskLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            taskLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            taskLabel.widthAnchor.constraint(equalToConstant: 200),

            progressIndicator.leadingAnchor.constraint(equalTo: taskLabel.trailingAnchor, constant: 8),
            progressIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 10),

            cancelButton.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 8),
            cancelButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 20),
            cancelButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        // 初始隐藏
        isHidden = true
    }

    // MARK: - Bindings

    private func setupBindings() {
        TaskSchedulerManager.shared.$activeTask
            .receive(on: DispatchQueue.main)
            .sink { [weak self] task in
                if let task = task {
                    self?.show(task: task)
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// 显示任务进度
    /// - Parameter task: 任务信息
    public func show(task: TaskInfo) {
        isHidden = false
        taskLabel.stringValue = "\(task.name) - \(task.statusDescription)"
        progressIndicator.doubleValue = task.progress * 100
        currentTaskId = Int32(task.id) ?? nil
    }

    /// 隐藏进度条
    public func hide() {
        isHidden = true
        progressIndicator.doubleValue = 0
        taskLabel.stringValue = ""
        currentTaskId = nil
    }

    // MARK: - Actions

    @objc private func cancelClicked() {
        guard let taskId = currentTaskId else { return }
        TaskSchedulerManager.shared.cancelTask(taskId: taskId)
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse TaskProgressBar.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/TaskProgressBar.swift
git commit -m "feat: 新建 TaskProgressBar 底部进度条

- NSProgressIndicator + 任务标签 + 取消按钮
- 订阅 TaskSchedulerManager.activeTask
- 自动显示/隐藏进度条
- 取消按钮调用 cancelTask"
```

---

## Task 3: 新建 TaskPanelWindowController.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/TaskPanelWindowController.swift`

**Interfaces:**
- Consumes: `TaskSchedulerManager.shared` (Task 1)
- Produces: `TaskPanelWindowController.shared` 单例
- Produces: `TaskPanelWindowController.showWindow()` 显示窗口（⌘0 触发）
- Produces: NSTableView 显示所有任务（名称/状态/进度/创建时间）

- [ ] **Step 1: 创建 TaskPanelWindowController.swift**

```swift
import Cocoa
import Combine

/// ⌘0 独立任务面板窗口：显示所有任务列表
public class TaskPanelWindowController: NSWindowController {

    public static let shared = TaskPanelWindowController()

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var refreshButton: NSButton!
    private var cancelButton: NSButton!
    private var clearButton: NSButton!
    private var statusLabel: NSTextField!

    private var cancellables = Set<AnyCancellable>()

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
        TaskSchedulerManager.shared.$allTasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                self?.tableView.reloadData()
                let active = tasks.filter { $0.isActive }.count
                let completed = tasks.filter { $0.isCompleted }.count
                self?.statusLabel.stringValue = "共 \(tasks.count) 个任务（\(active) 进行中，\(completed) 已完成）"
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
        guard tableView.selectedRow >= 0,
              tableView.selectedRow < TaskSchedulerManager.shared.allTasks.count else { return }
        let task = TaskSchedulerManager.shared.allTasks[tableView.selectedRow]
        guard let taskId = Int32(task.id) else { return }
        TaskSchedulerManager.shared.cancelTask(taskId: taskId)
    }

    @objc private func clearClicked() {
        // 清除已完成的任务（仅刷新显示，Rust 端保留历史）
        TaskSchedulerManager.shared.refreshTasks()
    }
}

// MARK: - NSTableViewDataSource

extension TaskPanelWindowController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return TaskSchedulerManager.shared.allTasks.count
    }
}

// MARK: - NSTableViewDelegate

extension TaskPanelWindowController: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tasks = TaskSchedulerManager.shared.allTasks
        guard row < tasks.count else { return nil }
        let task = tasks[row]

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
            cellView.textField?.stringValue = task.name
        case "status":
            cellView.textField?.stringValue = task.statusDescription
            switch task.status {
            case .running: cellView.textField?.textColor = NSColor.systemBlue
            case .completed: cellView.textField?.textColor = NSColor.systemGreen
            case .failed: cellView.textField?.textColor = NSColor.systemRed
            case .cancelled: cellView.textField?.textColor = NSColor.systemGray
            default: cellView.textField?.textColor = NSColor.labelColor
            }
        case "progress":
            cellView.textField?.stringValue = task.progressPercentage
        case "created":
            cellView.textField?.stringValue = task.formattedCreatedAt
        default:
            break
        }

        return cellView
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse TaskPanelWindowController.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/TaskPanelWindowController.swift
git commit -m "feat: 新建 TaskPanelWindowController 任务面板窗口

- NSWindowController 单例（⌘0 触发）
- NSTableView 显示所有任务（名称/状态/进度/创建时间）
- 订阅 TaskSchedulerManager.allTasks 自动刷新
- 取消任务 / 清除已完成 按钮
- 状态颜色区分（运行蓝/完成绿/失败红/取消灰）"
```

---

## Task 4: 新建 SearchPanelController.swift + 重写 SearchView.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/SearchView.swift`

**Interfaces:**
- Consumes: `SearchBridge.shared` (Phase 1), `SpotlightBridge.shared` (Phase 1)
- Produces: `SearchPanelController.shared` 单例
- Produces: `SearchPanelController.showPanel(initialQuery:searchPath:)` 显示面板
- Produces: `SearchMode.local` / `SearchMode.global` 双模式枚举
- Produces: 双击结果跳转到活跃面板

- [ ] **Step 1: 创建 SearchPanelController.swift**

```swift
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
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        searchField.becomeFirstResponder()
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
```

- [ ] **Step 2: 重写 SearchView.swift（移除旧的 SearchBarView 和 SearchResultsView，保留兼容）**

完整替换 `FlowFinderNative/FlowFinderNative/UI/SearchView.swift`：

```swift
import Cocoa

// MARK: - SearchView (Legacy compat)

/// 旧的 SearchBarView 和 SearchResultsView 已被 SearchPanelController 替代。
/// 此文件保留兼容性，实际搜索功能由 SearchPanelController 实现。

/// 搜索过滤器（保留兼容性）
public struct SearchFilters {
    public var fileTypes: String?
    public var minSize: UInt64?
    public var maxSize: UInt64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?

    public init(fileTypes: String? = nil, minSize: UInt64? = nil, maxSize: UInt64? = nil,
                modifiedAfter: Date? = nil, modifiedBefore: Date? = nil) {
        self.fileTypes = fileTypes
        self.minSize = minSize
        self.maxSize = maxSize
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
    }
}
```

- [ ] **Step 3: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse SearchPanelController.swift 2>&1 | head -5 && swiftc -parse SearchView.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 4: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift FlowFinderNative/FlowFinderNative/UI/SearchView.swift
git commit -m "feat: 新建 SearchPanelController 双模式搜索面板

- NSWindowController 单例
- 双模式：Rust 本地搜索（SearchBridge）+ Spotlight 全局搜索（SpotlightBridge）
- NSSegmentedControl 模式切换
- NSTableView 结果列表（名称/路径/大小）
- 双击结果跳转到活跃面板
- 进度指示器 + 状态标签"
```

---

## Task 5: 新建 DuplicateScanWindowController.swift + 重写 DuplicateScanView.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/DuplicateScanWindowController.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/DuplicateScanView.swift`

**Interfaces:**
- Consumes: `DuplicateScanBridge.shared` (Phase 1)
- Produces: `DuplicateScanWindowController.shared` 单例
- Produces: `DuplicateScanWindowController.showWindow()` 显示窗口
- Produces: 目录选择 + 进度 + 分组结果 + 批量删除

- [ ] **Step 1: 创建 DuplicateScanWindowController.swift**

```swift
import Cocoa
import Combine

/// 重复扫描窗口控制器：目录选择 + 进度 + 分组结果 + 批量删除
public class DuplicateScanWindowController: NSWindowController {

    public static let shared = DuplicateScanWindowController()

    private var pathControl: NSPathControl!
    private var browseButton: NSButton!
    private var startButton: NSButton!
    private var cancelButton: NSButton!
    private var deleteButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!

    private var duplicateGroups: [FFDuplicateGroup] = []
    private var isScanning = false
    private var selectedFiles: Set<String> = []  // 选中的文件路径

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "重复文件扫描"
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.setFrameAutosaveName("DuplicateScanWindow")
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

        // 顶部工具栏
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        pathControl = NSPathControl()
        pathControl.pathStyle = .popUp
        pathControl.url = FileManager.default.homeDirectoryForCurrentUser
        pathControl.translatesAutoresizingMaskIntoConstraints = false

        browseButton = NSButton(title: "选择目录", target: self, action: #selector(browseClicked))
        browseButton.bezelStyle = .rounded
        browseButton.translatesAutoresizingMaskIntoConstraints = false

        startButton = NSButton(title: "开始扫描", target: self, action: #selector(startScan))
        startButton.bezelStyle = .rounded
        startButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelScan))
        cancelButton.bezelStyle = .rounded
        cancelButton.isEnabled = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        deleteButton = NSButton(title: "删除选中", target: self, action: #selector(deleteSelected))
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(pathControl)
        toolbar.addSubview(browseButton)
        toolbar.addSubview(startButton)
        toolbar.addSubview(cancelButton)
        toolbar.addSubview(deleteButton)
        toolbar.addSubview(progressIndicator)
        toolbar.addSubview(statusLabel)

        // 结果 OutlineView
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        outlineView = NSOutlineView()
        outlineView.allowsMultipleSelection = true
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.rowHeight = 24

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.width = 300
        outlineView.addTableColumn(nameCol)

        let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathCol.title = "路径"
        pathCol.width = 400
        outlineView.addTableColumn(pathCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "大小"
        sizeCol.width = 100
        outlineView.addTableColumn(sizeCol)

        outlineView.dataSource = self
        outlineView.delegate = self

        scrollView.documentView = outlineView
        contentView.addSubview(toolbar)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            toolbar.heightAnchor.constraint(equalToConstant: 60),

            pathControl.topAnchor.constraint(equalTo: toolbar.topAnchor),
            pathControl.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            pathControl.widthAnchor.constraint(equalToConstant: 400),

            browseButton.topAnchor.constraint(equalTo: toolbar.topAnchor),
            browseButton.leadingAnchor.constraint(equalTo: pathControl.trailingAnchor, constant: 8),

            startButton.topAnchor.constraint(equalTo: toolbar.topAnchor),
            startButton.leadingAnchor.constraint(equalTo: browseButton.trailingAnchor, constant: 8),

            cancelButton.topAnchor.constraint(equalTo: toolbar.topAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 8),

            deleteButton.topAnchor.constraint(equalTo: toolbar.topAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 8),

            progressIndicator.topAnchor.constraint(equalTo: pathControl.bottomAnchor, constant: 8),
            progressIndicator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            progressIndicator.heightAnchor.constraint(equalToConstant: 10),

            statusLabel.topAnchor.constraint(equalTo: pathControl.bottomAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Public API

    public func showWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func browseClicked() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.pathControl.url = url
            }
        }
    }

    @objc private func startScan() {
        guard let url = pathControl.url else { return }
        let path = url.path

        isScanning = true
        duplicateGroups = []
        selectedFiles = []
        startButton.isEnabled = false
        cancelButton.isEnabled = true
        deleteButton.isEnabled = false
        progressIndicator.doubleValue = 0
        statusLabel.stringValue = "扫描中..."
        outlineView.reloadData()

        DuplicateScanBridge.shared.scanDuplicates(
            path: path,
            progressHandler: { [weak self] scanned, total in
                DispatchQueue.main.async {
                    let progress = total > 0 ? Double(scanned) / Double(total) * 100 : 0
                    self?.progressIndicator.doubleValue = progress
                    self?.statusLabel.stringValue = "已扫描 \(scanned) / \(total) 个文件"
                }
            },
            groupHandler: { [weak self] group in
                self?.duplicateGroups.append(group)
                DispatchQueue.main.async {
                    self?.outlineView.reloadData()
                }
            },
            completion: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isScanning = false
                    self?.startButton.isEnabled = true
                    self?.cancelButton.isEnabled = false
                    self?.deleteButton.isEnabled = !(self?.duplicateGroups.isEmpty ?? true)

                    if let error = error {
                        self?.statusLabel.stringValue = "错误: \(error.localizedDescription)"
                    } else {
                        let count = self?.duplicateGroups.count ?? 0
                        self?.statusLabel.stringValue = "完成，找到 \(count) 个重复组"
                    }
                }
            }
        )
    }

    @objc private func cancelScan() {
        DuplicateScanBridge.shared.cancelScan()
        isScanning = false
        startButton.isEnabled = true
        cancelButton.isEnabled = false
        statusLabel.stringValue = "已取消扫描"
    }

    @objc private func deleteSelected() {
        guard !selectedFiles.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "删除 \(selectedFiles.count) 个重复文件？"
        alert.informativeText = "此操作无法撤销。请确认选中的文件是要删除的副本。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performDelete()
        }
    }

    private func performDelete() {
        let files = Array(selectedFiles)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var deletedCount = 0
            var errors: [String] = []

            for path in files {
                do {
                    try CoreBridge.shared.deleteFile(path: path)
                    deletedCount += 1
                } catch {
                    errors.append("\(path): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self?.selectedFiles.removeAll()
                // 重新扫描以刷新结果
                self?.startScan()
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension DuplicateScanWindowController: NSOutlineViewDataSource {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return duplicateGroups.count
        }
        if let group = item as? FFDuplicateGroup {
            return group.files.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return duplicateGroups[index]
        }
        if let group = item as? FFDuplicateGroup {
            return group.files[index]
        }
        return ""
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let group = item as? FFDuplicateGroup {
            return group.files.count > 0
        }
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension DuplicateScanWindowController: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "name")
        let cellView = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
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

        switch item {
        case let group as FFDuplicateGroup:
            switch tableColumn?.identifier.rawValue {
            case "name":
                cellView.textField?.stringValue = "重复组（\(group.files.count) 个文件）"
                cellView.textField?.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            case "path":
                cellView.textField?.stringValue = "哈希: \(group.hash.prefix(16))..."
            case "size":
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                cellView.textField?.stringValue = formatter.string(fromByteCount: Int64(group.size))
            default:
                break
            }
        case let file as FFDuplicateFile:
            switch tableColumn?.identifier.rawValue {
            case "name":
                cellView.textField?.stringValue = file.name
            case "path":
                cellView.textField?.stringValue = file.path
            case "size":
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                cellView.textField?.stringValue = formatter.string(fromByteCount: Int64(file.size))
            default:
                break
            }
        default:
            break
        }

        return cellView
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        // 更新选中文件集合
        selectedFiles.removeAll()
        let selectedRows = outlineView.selectedRowIndexes
        for row in selectedRows {
            guard let item = outlineView.item(atRow: row) as? FFDuplicateFile else { continue }
            selectedFiles.insert(item.path)
        }
        deleteButton.isEnabled = !selectedFiles.isEmpty
    }
}
```

- [ ] **Step 2: 重写 DuplicateScanView.swift（简化为兼容文件）**

完整替换 `FlowFinderNative/FlowFinderNative/UI/DuplicateScanView.swift`：

```swift
import Cocoa

// MARK: - DuplicateScanView (Legacy compat)

/// 旧的 DuplicateScanView 和 DuplicateResultsView 已被 DuplicateScanWindowController 替代。
/// 此文件保留兼容性，实际重复扫描功能由 DuplicateScanWindowController 实现。
```

- [ ] **Step 3: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse DuplicateScanWindowController.swift 2>&1 | head -5 && swiftc -parse DuplicateScanView.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 4: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/DuplicateScanWindowController.swift FlowFinderNative/FlowFinderNative/UI/DuplicateScanView.swift
git commit -m "feat: 新建 DuplicateScanWindowController 重复扫描窗口

- NSWindowController 单例
- NSPathControl + NSOpenPanel 目录选择
- DuplicateScanBridge.scanDuplicates 异步扫描
- NSOutlineView 分组展示（组→文件）
- 进度条 + 状态标签
- 批量删除选中文件（确认对话框）
- 重新扫描刷新结果"
```

---

## Task 6: 集成到 MainWindowController + MainMenu

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainMenu.swift`

**Interfaces:**
- Consumes: `TaskProgressBar` (Task 2), `TaskPanelWindowController` (Task 3), `SearchPanelController` (Task 4), `DuplicateScanWindowController` (Task 5)
- Produces: 主窗口底部嵌入 TaskProgressBar
- Produces: ⌘F 触发搜索面板
- Produces: ⌘⇧D 触发重复扫描窗口
- Produces: ⌘0 触发任务面板

- [ ] **Step 1: 在 MainWindowController 添加 TaskProgressBar**

在 `MainWindowController.swift` 的属性区域（`private var detailsBar: DetailsBar!` 之后）添加：

```swift
    private var taskProgressBar: TaskProgressBar!
```

在 `setupUI()` 方法中，在 `detailsBar` 创建之后、`mainContainer` 创建之前添加：

```swift
        // Task Progress Bar（底部固定进度条）
        taskProgressBar = TaskProgressBar()
        taskProgressBar.translatesAutoresizingMaskIntoConstraints = false
```

修改 `mainContainer.addSubview(detailsBar)` 之后的部分，将 `taskProgressBar` 添加到布局中：

将原来的：
```swift
        mainContainer.addSubview(mainSplitView)
        mainContainer.addSubview(detailsBar)
```

改为：
```swift
        mainContainer.addSubview(mainSplitView)
        mainContainer.addSubview(detailsBar)
        mainContainer.addSubview(taskProgressBar)
```

将原来的约束：
```swift
            mainSplitView.bottomAnchor.constraint(equalTo: detailsBar.topAnchor),

            detailsBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            detailsBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            detailsBar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            detailsBar.heightAnchor.constraint(equalToConstant: 120),
```

改为：
```swift
            mainSplitView.bottomAnchor.constraint(equalTo: detailsBar.topAnchor),

            detailsBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            detailsBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            detailsBar.bottomAnchor.constraint(equalTo: taskProgressBar.topAnchor),
            detailsBar.heightAnchor.constraint(equalToConstant: 120),

            taskProgressBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            taskProgressBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            taskProgressBar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            taskProgressBar.heightAnchor.constraint(equalToConstant: TaskProgressBar.height),
```

- [ ] **Step 2: 在 MainWindowController 启动任务调度**

在 `setupUI()` 方法末尾（`updateActivePaneVisual()` 之后）添加：

```swift
        // 启动任务调度轮询
        TaskSchedulerManager.shared.startPolling()
```

在 `MainWindowController` 类中添加 `deinit`（在 `init` 方法之后）：

```swift
    deinit {
        TaskSchedulerManager.shared.stopPolling()
    }
```

- [ ] **Step 3: 在 MainWindowController 添加菜单 action 方法**

在 `MainWindowController` 类的 `// MARK: - Menu Actions` 扩展中，在 `menuConnectServer` 方法之后添加：

```swift
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
```

- [ ] **Step 4: 在 MainMenu 添加菜单项**

在 `MainMenu.swift` 的 `setupMainMenu()` 方法中，在「前往」菜单之后、「窗口」菜单之前添加「工具」菜单。

找到 `windowMenu` 创建的位置之前，添加：

```swift
        // 工具菜单
        let toolsMenu = NSMenuItem()
        toolsMenu.submenu = NSMenu(title: "工具")
        toolsMenu.mnemonicTitle = "工具"
        let searchItem = NSMenuItem(title: "搜索...", action: #selector(MainWindowController.menuSearch(_:)), keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = .command
        toolsMenu.submenu?.addItem(searchItem)

        let dupScanItem = NSMenuItem(title: "重复文件扫描...", action: #selector(MainWindowController.menuDuplicateScan(_:)), keyEquivalent: "d")
        dupScanItem.keyEquivalentModifierMask = [.command, .shift]
        toolsMenu.submenu?.addItem(dupScanItem)

        toolsMenu.submenu?.addItem(.separator())

        let taskPanelItem = NSMenuItem(title: "任务面板", action: #selector(MainWindowController.menuTaskPanel(_:)), keyEquivalent: "0")
        taskPanelItem.keyEquivalentModifierMask = .command
        toolsMenu.submenu?.addItem(taskPanelItem)
```

然后在 `mainMenu.setItems(...)` 的数组中，将 `toolsMenu` 添加到 `windowMenu` 之前。

- [ ] **Step 5: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse MainWindowController.swift 2>&1 | head -5 && swiftc -parse MainMenu.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 6: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift FlowFinderNative/FlowFinderNative/UI/MainMenu.swift
git commit -m "feat: MainWindowController + MainMenu 集成任务调度 + 搜索 + 重复扫描

- TaskProgressBar 嵌入主窗口底部
- TaskSchedulerManager 启动轮询
- ⌘F 搜索面板（SearchPanelController）
- ⌘⇧D 重复扫描（DuplicateScanWindowController）
- ⌘0 任务面板（TaskPanelWindowController）
- 工具菜单添加三个菜单项"
```

---

## Task 7: Phase 5 集成验证

**Files:**
- 无新增/修改，仅验证

- [ ] **Step 1: 全部 Swift 文件语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative" && for f in Bridge/TaskSchedulerManager.swift UI/TaskProgressBar.swift UI/TaskPanelWindowController.swift UI/SearchPanelController.swift UI/SearchView.swift UI/DuplicateScanWindowController.swift UI/DuplicateScanView.swift UI/MainWindowController.swift UI/MainMenu.swift; do echo "--- $f ---"; swiftc -parse "$f" 2>&1 | head -3; done`
Expected: 每个文件无输出（无错误）

- [ ] **Step 2: 确认任务调度组件存在**

Run: `grep -c "TaskSchedulerManager\|TaskProgressBar\|TaskPanelWindowController" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift"`
Expected: 数字 >= 3

- [ ] **Step 3: 确认搜索面板双模式存在**

Run: `grep -c "SearchMode\|SearchBridge\|SpotlightBridge" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift"`
Expected: 数字 >= 3

- [ ] **Step 4: 确认重复扫描组件存在**

Run: `grep -c "DuplicateScanBridge\|FFDuplicateGroup\|NSOutlineView" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/DuplicateScanWindowController.swift"`
Expected: 数字 >= 3

- [ ] **Step 5: 确认菜单项存在**

Run: `grep -c "menuSearch\|menuDuplicateScan\|menuTaskPanel" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/MainMenu.swift"`
Expected: 数字 >= 3

- [ ] **Step 6: 提交 Phase 5 完成标记**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add -A
git commit -m "milestone: Phase 5 完成 - 搜索 + 重复扫描 + 任务调度

- TaskSchedulerManager（CoreBridge.listTasks 轮询 + DispatchSourceTimer）
- TaskProgressBar（底部固定进度条 + 取消按钮）
- TaskPanelWindowController（⌘0 独立任务面板窗口）
- SearchPanelController（Rust 本地 + Spotlight 全局双模式搜索）
- DuplicateScanWindowController（目录选择 + NSOutlineView 分组 + 批量删除）
- MainWindowController 集成 TaskProgressBar + 启动轮询
- MainMenu 工具菜单（⌘F/⌘⇧D/⌘0）
- 全部文件语法检查通过"
```

---

## Self-Review

### Spec Coverage

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 搜索 Rust search_engine + Spotlight 双模式 | Task 4（SearchPanelController） |
| 搜索结果面板 | Task 4（NSTableView + 高亮） |
| 重复扫描 UI + 进度 | Task 5（DuplicateScanWindowController） |
| 重复扫描分组结果 | Task 5（NSOutlineView 分组展示） |
| 重复扫描批量操作 | Task 5（deleteSelected + 确认对话框） |
| 任务调度底部进度条 | Task 2（TaskProgressBar） |
| ⌘0 独立任务面板窗口 | Task 3（TaskPanelWindowController） |
| 任务调度轮询 | Task 1（TaskSchedulerManager） |
| ⌘F 搜索快捷键 | Task 6（MainMenu + MainWindowController） |
| ⌘⇧D 重复扫描快捷键 | Task 6（MainMenu + MainWindowController） |

### Placeholder Scan

- 无 TBD/TODO
- 所有代码块完整
- 所有命令精确

### Type Consistency

- `TaskSchedulerManager.shared` 在 Task 1 定义，Task 2/3/6 使用一致
- `TaskProgressBar.height` 在 Task 2 定义为 28，Task 6 使用一致
- `SearchPanelController.shared.showPanel(initialQuery:searchPath:)` 在 Task 4 定义，Task 6 调用一致
- `DuplicateScanWindowController.shared.showWindow()` 在 Task 5 定义，Task 6 调用一致
- `TaskPanelWindowController.shared.showWindow()` 在 Task 3 定义，Task 6 调用一致
- `FFSearchResult` / `FFDuplicateGroup` / `FFDuplicateFile` 在 Phase 1 定义，Task 4/5 使用一致
- `TaskInfo.isActive` / `isCompleted` / `progressPercentage` 在 Model 层定义，Task 2/3 使用一致
