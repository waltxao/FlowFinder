import Cocoa

// MARK: - DuplicateGroupViewDelegate

protocol DuplicateGroupViewDelegate: AnyObject {
    /// 选中状态变更通知（保留项变更或删除选择变更）
    func duplicateGroupView(_ view: DuplicateGroupView, didChangeSelectionInGroup groupId: String, keepFilePath: String, deleteFilePaths: [String])
    /// 组被选中（用于预览面板更新）
    func duplicateGroupView(_ view: DuplicateGroupView, didSelectGroup group: FFDuplicateGroup)
}

// MARK: - DuplicateGroupView

/// 重复文件组视图：可折叠组头 + 文件行列表
/// 组头：展开箭头 + 16x16 图标 + 组名 + 计数药丸 + 可释放空间标签
/// 文件行：radio 选择圈（14x14 自绘） + 16x16 图标 + 路径 + 大小 + 保留/删除标签
class DuplicateGroupView: NSView {

    weak var delegate: DuplicateGroupViewDelegate?

    private let group: FFDuplicateGroup
    private var isExpanded = true

    /// 当前保留的文件路径（radio 逻辑：每组仅一个"保留"）
    private var keepFilePath: String
    /// 待删除的文件路径集合
    private(set) var deleteFilePaths: Set<String> = []

    // UI 引用
    private let headerView = NSButton()
    private let filesStack = NSStackView()
    private var fileRows: [DuplicateFileRow] = []

    // MARK: - Init

    init(group: FFDuplicateGroup) {
        self.group = group
        // 默认保留第一个文件，其余标记为删除
        self.keepFilePath = group.files.first?.path ?? ""
        super.init(frame: .zero)
        // 默认除保留项外的所有文件标记为删除
        self.deleteFilePaths = Set(group.files.filter { $0.path != keepFilePath }.map { $0.path })
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // 组头按钮（整行可点击展开/折叠）
        headerView.isBordered = false
        headerView.target = self
        headerView.action = #selector(toggleExpand)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        headerView.applySquircleCornerRadius(6)
        addSubview(headerView)

        // 组头内容：展开箭头 + 图标 + 组名 + 计数药丸 + 可释放空间
        let chevron = NSTextField(labelWithString: "▼")
        chevron.font = NSFont.systemFont(ofSize: 10)
        chevron.textColor = NSColor.secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.identifier = NSUserInterfaceItemIdentifier("chevron")

        let groupIcon = NSImageView()
        groupIcon.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "重复组")
        groupIcon.contentTintColor = NSColor.systemBlue
        groupIcon.imageScaling = .scaleProportionallyDown
        groupIcon.translatesAutoresizingMaskIntoConstraints = false

        let groupName = NSTextField(labelWithString: "重复组（\(group.hash.prefix(8))）")
        groupName.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        groupName.textColor = NSColor.labelColor
        groupName.translatesAutoresizingMaskIntoConstraints = false

        let countPill = makePill(text: "\(group.files.count)", bgColor: .systemBlue)
        let spaceLabel = NSTextField(labelWithString: "可释放 \(formatSize(group.size * UInt64(max(0, group.files.count - 1))))")
        spaceLabel.font = NSFont.systemFont(ofSize: 11)
        spaceLabel.textColor = NSColor.systemGreen
        spaceLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [chevron, groupIcon, groupName, countPill, NSView(), spaceLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerStack)

        // 文件行堆叠
        filesStack.orientation = .vertical
        filesStack.spacing = 0
        filesStack.detachesHiddenViews = false
        filesStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(filesStack)

        // 构建文件行
        for file in group.files {
            let row = DuplicateFileRow(file: file, isKeep: file.path == keepFilePath)
            row.delegate = self
            fileRows.append(row)
            filesStack.addArrangedSubview(row)
            constrainRow(row)
        }

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            headerStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            headerStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            chevron.widthAnchor.constraint(equalToConstant: 12),
            groupIcon.widthAnchor.constraint(equalToConstant: 16),
            groupIcon.heightAnchor.constraint(equalToConstant: 16),

            filesStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            filesStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            filesStack.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            filesStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func constrainRow(_ row: DuplicateFileRow) {
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: filesStack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: filesStack.trailingAnchor),
        ])
    }

    /// 创建计数药丸
    private func makePill(text: String, bgColor: NSColor) -> NSTextField {
        let pill = NSTextField(labelWithString: text)
        pill.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        pill.textColor = NSColor.white
        pill.alignment = .center
        pill.wantsLayer = true
        pill.layer?.backgroundColor = bgColor.cgColor
        pill.applySquircleCornerRadius(7)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        pill.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return pill
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Actions

    @objc private func toggleExpand() {
        isExpanded.toggle()
        filesStack.isHidden = !isExpanded
        // 更新箭头方向
        if let chevron = headerView.subviews.compactMap({ $0 as? NSStackView }).first?
            .arrangedSubviews.compactMap({ $0 as? NSTextField }).first(where: { $0.identifier == NSUserInterfaceItemIdentifier("chevron") }) {
            chevron.stringValue = isExpanded ? "▼" : "▶"
        }
    }

    /// 通知 delegate 选中状态变更
    private func notifySelectionChange() {
        delegate?.duplicateGroupView(self,
                                     didChangeSelectionInGroup: group.id,
                                     keepFilePath: keepFilePath,
                                     deleteFilePaths: Array(deleteFilePaths))
    }

    /// 获取当前组数据
    func getGroup() -> FFDuplicateGroup { return group }
}

// MARK: - DuplicateFileRowDelegate

private protocol DuplicateFileRowDelegate: AnyObject {
    func fileRowDidClickRadio(_ row: DuplicateFileRow, filePath: String)
    func fileRowDidClickDeleteToggle(_ row: DuplicateFileRow, filePath: String, isMarkedForDelete: Bool)
}

// MARK: - DuplicateGroupView (DuplicateFileRowDelegate 实现)

extension DuplicateGroupView: DuplicateFileRowDelegate {

    fileprivate func fileRowDidClickRadio(_ row: DuplicateFileRow, filePath: String) {
        // radio 逻辑：点击 radio 设为保留项，其余自动变删除
        keepFilePath = filePath
        deleteFilePaths = Set(group.files.filter { $0.path != keepFilePath }.map { $0.path })
        // 更新所有行的视觉状态
        for fileRow in fileRows {
            fileRow.updateKeepState(isKeep: fileRow.filePath == keepFilePath)
        }
        notifySelectionChange()
    }

    fileprivate func fileRowDidClickDeleteToggle(_ row: DuplicateFileRow, filePath: String, isMarkedForDelete: Bool) {
        // 单独切换删除标记（不影响保留项）
        if isMarkedForDelete {
            deleteFilePaths.insert(filePath)
            // 若取消保留项的删除，需重新指定保留项
            if filePath == keepFilePath {
                keepFilePath = group.files.first(where: { !deleteFilePaths.contains($0.path) })?.path ?? ""
            }
        } else {
            deleteFilePaths.remove(filePath)
            // 若没有保留项，则此项成为保留项
            if keepFilePath.isEmpty || deleteFilePaths.contains(keepFilePath) {
                keepFilePath = filePath
            }
        }
        // 更新所有行视觉
        for fileRow in fileRows {
            fileRow.updateKeepState(isKeep: fileRow.filePath == keepFilePath)
            fileRow.updateDeleteMark(isMarked: deleteFilePaths.contains(fileRow.filePath))
        }
        notifySelectionChange()
    }
}

// MARK: - DuplicateFileRow

/// 单个文件行：radio 圈 + 图标 + 路径 + 大小 + 保留/删除标签
private class DuplicateFileRow: NSView {

    weak var delegate: DuplicateFileRowDelegate?

    let filePath: String
    private let file: FFDuplicateFile

    private let radioView = NSView()
    private let fileIcon = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    /// 删除标记按钮（点击切换删除状态）
    private let deleteToggleButton = NSButton()

    private var isKeep = false
    private var isMarkedForDelete = false

    init(file: FFDuplicateFile, isKeep: Bool) {
        self.file = file
        self.filePath = file.path
        self.isKeep = isKeep
        self.isMarkedForDelete = !isKeep
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // radio 圈（14x14 自绘）
        radioView.wantsLayer = true
        radioView.layer?.cornerRadius = 7
        radioView.layer?.borderWidth = 1.5
        radioView.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        radioView.translatesAutoresizingMaskIntoConstraints = false
        // 点击手势
        let radioClick = NSClickGestureRecognizer(target: self, action: #selector(radioClicked))
        radioView.addGestureRecognizer(radioClick)

        // 文件图标
        fileIcon.image = NSImage(systemSymbolName: "doc", accessibilityDescription: file.name)
        fileIcon.contentTintColor = NSColor.secondaryLabelColor
        fileIcon.imageScaling = .scaleProportionallyDown
        fileIcon.translatesAutoresizingMaskIntoConstraints = false

        // 路径标签
        pathLabel.stringValue = file.path
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = NSColor.labelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.cell?.truncatesLastVisibleLine = true
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        // 大小标签
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        sizeLabel.stringValue = formatter.string(fromByteCount: Int64(file.size))
        sizeLabel.font = NSFont.systemFont(ofSize: 11)
        sizeLabel.textColor = NSColor.secondaryLabelColor
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false

        // 状态标签（保留/删除）
        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 删除切换按钮（X 图标）
        deleteToggleButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "切换删除")
        deleteToggleButton.contentTintColor = NSColor.secondaryLabelColor
        deleteToggleButton.isBordered = false
        deleteToggleButton.target = self
        deleteToggleButton.action = #selector(deleteToggleClicked)
        deleteToggleButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [radioView, fileIcon, pathLabel, sizeLabel, NSView(), statusLabel, deleteToggleButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            radioView.widthAnchor.constraint(equalToConstant: 14),
            radioView.heightAnchor.constraint(equalToConstant: 14),
            fileIcon.widthAnchor.constraint(equalToConstant: 16),
            fileIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        updateKeepState(isKeep: isKeep)
        updateDeleteMark(isMarked: isMarkedForDelete)
    }

    @objc private func radioClicked() {
        delegate?.fileRowDidClickRadio(self, filePath: filePath)
    }

    @objc private func deleteToggleClicked() {
        isMarkedForDelete.toggle()
        delegate?.fileRowDidClickDeleteToggle(self, filePath: filePath, isMarkedForDelete: isMarkedForDelete)
    }

    /// 更新保留状态视觉（radio 圈填充）
    func updateKeepState(isKeep: Bool) {
        self.isKeep = isKeep
        if isKeep {
            radioView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            radioView.layer?.borderColor = NSColor.controlAccentColor.cgColor
            statusLabel.stringValue = "保留"
            statusLabel.textColor = NSColor.systemGreen
        } else {
            radioView.layer?.backgroundColor = NSColor.clear.cgColor
            radioView.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        }
    }

    /// 更新删除标记视觉
    func updateDeleteMark(isMarked: Bool) {
        self.isMarkedForDelete = isMarked
        if isMarked {
            statusLabel.stringValue = "删除"
            statusLabel.textColor = NSColor.systemRed
            deleteToggleButton.contentTintColor = NSColor.systemRed
            deleteToggleButton.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已标记删除")
        } else if !isKeep {
            statusLabel.stringValue = ""
            deleteToggleButton.contentTintColor = NSColor.secondaryLabelColor
            deleteToggleButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "切换删除")
        }
    }
}
