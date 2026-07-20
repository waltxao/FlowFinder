import Cocoa
import Combine

/// SMB 管理面板：挂载 + 列表 + 卸载 + 自动重连
public class SMBManagerPanel: NSView {

    private var urlTextField: NSTextField!
    private var mountButton: NSButton!
    private var refreshButton: NSButton!
    private var unmountButton: NSButton!
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!

    private var volumes: [SMBVolume] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        refreshList()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        refreshList()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 标题
        let titleLabel = NSTextField(labelWithString: "SMB 网络共享")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // URL 输入
        let urlLabel = NSTextField(labelWithString: "服务器地址：")
        urlLabel.font = NSFont.systemFont(ofSize: 12)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        urlTextField = NSTextField()
        urlTextField.placeholderString = "smb://user:pass@server/share"
        urlTextField.translatesAutoresizingMaskIntoConstraints = false

        mountButton = NSButton(title: "连接", target: self, action: #selector(mountClicked))
        mountButton.bezelStyle = .rounded
        mountButton.translatesAutoresizingMaskIntoConstraints = false

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

        // 已挂载列表标签
        let listLabel = NSTextField(labelWithString: "已挂载的共享：")
        listLabel.font = NSFont.boldSystemFont(ofSize: 12)
        listLabel.translatesAutoresizingMaskIntoConstraints = false

        // 刷新 / 卸载按钮
        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        unmountButton = NSButton(title: "卸载", target: self, action: #selector(unmountClicked))
        unmountButton.bezelStyle = .rounded
        unmountButton.isEnabled = false
        unmountButton.translatesAutoresizingMaskIntoConstraints = false

        // 已挂载列表
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.width = 150
        tableView.addTableColumn(nameCol)

        let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathCol.title = "挂载路径"
        pathCol.width = 250
        tableView.addTableColumn(pathCol)

        let urlCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlCol.title = "服务器地址"
        urlCol.width = 200
        tableView.addTableColumn(urlCol)

        scrollView.documentView = tableView

        // 添加子视图
        addSubview(titleLabel)
        addSubview(urlLabel)
        addSubview(urlTextField)
        addSubview(mountButton)
        addSubview(progressIndicator)
        addSubview(statusLabel)
        addSubview(listLabel)
        addSubview(refreshButton)
        addSubview(unmountButton)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            urlLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            urlTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            urlTextField.leadingAnchor.constraint(equalTo: urlLabel.trailingAnchor, constant: 8),
            urlTextField.widthAnchor.constraint(equalToConstant: 350),

            mountButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            mountButton.leadingAnchor.constraint(equalTo: urlTextField.trailingAnchor, constant: 8),

            progressIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            progressIndicator.leadingAnchor.constraint(equalTo: mountButton.trailingAnchor, constant: 8),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 8),

            listLabel.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 20),
            listLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            refreshButton.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            refreshButton.leadingAnchor.constraint(equalTo: listLabel.trailingAnchor, constant: 16),

            unmountButton.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            unmountButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: listLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    @objc private func mountClicked() {
        let url = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            statusLabel.stringValue = "请输入服务器地址"
            return
        }

        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在连接..."
        mountButton.isEnabled = false

        SMBBridge.shared.mount(url: url) { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)
                self?.mountButton.isEnabled = true

                switch result {
                case .success(let path):
                    self?.statusLabel.stringValue = "已连接：\(path)"
                    self?.refreshList()
                case .failure(let error):
                    self?.statusLabel.stringValue = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func refreshClicked() {
        refreshList()
    }

    @objc private func unmountClicked() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < volumes.count else { return }
        let volume = volumes[tableView.selectedRow]

        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在卸载..."
        unmountButton.isEnabled = false

        SMBBridge.shared.unmount(mountPoint: volume.path) { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)

                switch result {
                case .success:
                    self?.statusLabel.stringValue = "已卸载：\(volume.name)"
                    self?.refreshList()
                case .failure(let error):
                    self?.statusLabel.stringValue = "卸载失败：\(error.localizedDescription)"
                    self?.updateUnmountButton()
                }
            }
        }
    }

    // MARK: - Private

    private func refreshList() {
        SMBBridge.shared.refreshMountedVolumes()
        volumes = SMBBridge.shared.listMounted()
        tableView.reloadData()
        updateUnmountButton()
        statusLabel.stringValue = "共 \(volumes.count) 个已挂载共享"
    }

    private func updateUnmountButton() {
        unmountButton.isEnabled = tableView.selectedRow >= 0
    }
}

// MARK: - NSTableViewDataSource

extension SMBManagerPanel: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return volumes.count
    }
}

// MARK: - NSTableViewDelegate

extension SMBManagerPanel: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < volumes.count else { return nil }
        let volume = volumes[row]

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
            cellView.textField?.stringValue = volume.name
        case "path":
            cellView.textField?.stringValue = volume.path
        case "url":
            cellView.textField?.stringValue = volume.url
        default:
            break
        }

        return cellView
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateUnmountButton()
    }
}
