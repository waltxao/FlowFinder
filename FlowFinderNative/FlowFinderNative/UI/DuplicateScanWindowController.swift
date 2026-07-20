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
