import Cocoa

// MARK: - ExpandableDetailsBar

/// 可展开的文件详情面板
///
/// 收起状态（高度 28pt）：
///   - 左侧：选中文件的高清预览图标（24x24，`NSWorkspace.shared.icon(forFile:)`）
///   - 中间：文件名 + 大小（单行，11pt）
///   - 右侧：展开按钮（chevron.up SF Symbol）
///
/// 展开状态（高度 120pt）：
///   - 左侧：大尺寸预览图标（48x48，异步加载 QuickLook 缩略图）
///   - 右侧网格：名称 / 类型 / 大小 / 创建日期 / 修改日期 / 权限
///   - 底部：完整路径 + 标签（药丸样式）
///
/// 接口：
///   - `update(with entry: FileEntry?)` 更新显示的文件信息
///   - `isExpanded: Bool` 展开/收起状态
class ExpandableDetailsBar: NSView {

    // MARK: - Constants

    private let collapsedHeight: CGFloat = 28
    private let expandedHeight: CGFloat = 120

    // MARK: - State

    private var entry: FileEntry?
    private var selectedCount: Int = 0

    /// 展开/收起状态。设置时自动带动画过渡。
    var isExpanded: Bool = false {
        didSet {
            guard isExpanded != oldValue else { return }
            applyExpandedState(animated: true)
        }
    }

    // MARK: - UI

    private var heightConstraint: NSLayoutConstraint!

    private let chevronButton = NSButton()
    private let compactView = NSView()
    private let expandedView = NSView()

    // compact
    private let smallIconView = NSImageView()
    private let compactNameField = NSTextField(labelWithString: "")

    // expanded
    private let bigIconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let typeField = NSTextField(labelWithString: "")
    private let sizeField = NSTextField(labelWithString: "")
    private let createdField = NSTextField(labelWithString: "")
    private let modifiedField = NSTextField(labelWithString: "")
    private let permField = NSTextField(labelWithString: "")
    private let pathField = NSTextField(labelWithString: "")
    private let tagsContainer = NSStackView()

    /// 当前正在请求缩略图的路径（用于避免过期回调覆盖）
    private var thumbnailLoadPath: String?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // chevron 按钮（共享，始终可见于右上角）
        chevronButton.bezelStyle = .texturedRounded
        chevronButton.imagePosition = .imageOnly
        chevronButton.isBordered = false
        chevronButton.refusesFirstResponder = true
        chevronButton.contentTintColor = NSColor.secondaryLabelColor
        chevronButton.target = self
        chevronButton.action = #selector(toggleExpanded)
        chevronButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "展开")
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevronButton)

        // compact 视图（收起态）
        compactView.translatesAutoresizingMaskIntoConstraints = false
        smallIconView.imageScaling = .scaleProportionallyUpOrDown
        smallIconView.translatesAutoresizingMaskIntoConstraints = false
        compactView.addSubview(smallIconView)

        compactNameField.font = NSFont.systemFont(ofSize: 11)
        compactNameField.textColor = NSColor.labelColor
        compactNameField.lineBreakMode = .byTruncatingTail
        compactNameField.maximumNumberOfLines = 1
        compactNameField.cell?.truncatesLastVisibleLine = true
        compactNameField.translatesAutoresizingMaskIntoConstraints = false
        compactView.addSubview(compactNameField)
        addSubview(compactView)

        // expanded 视图（展开态）
        expandedView.translatesAutoresizingMaskIntoConstraints = false
        bigIconView.imageScaling = .scaleProportionallyUpOrDown
        bigIconView.translatesAutoresizingMaskIntoConstraints = false
        expandedView.addSubview(bigIconView)

        // 属性网格（2 列 x 3 行）
        let grid = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        expandedView.addSubview(grid)

        let nameLabel = makeLabel("名称")
        configureValue(nameField)
        let typeLabel = makeLabel("类型")
        configureValue(typeField)
        let sizeLabel = makeLabel("大小")
        configureValue(sizeField)
        let createdLabel = makeLabel("创建")
        configureValue(createdField)
        let modifiedLabel = makeLabel("修改")
        configureValue(modifiedField)
        let permLabel = makeLabel("权限")
        configureValue(permField)

        for v in [nameLabel, nameField, typeLabel, typeField, sizeLabel, sizeField,
                  createdLabel, createdField, modifiedLabel, modifiedField, permLabel, permField] {
            grid.addSubview(v)
        }

        // 完整路径
        pathField.font = NSFont.systemFont(ofSize: 10)
        pathField.textColor = NSColor.secondaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.maximumNumberOfLines = 1
        pathField.cell?.truncatesLastVisibleLine = true
        pathField.translatesAutoresizingMaskIntoConstraints = false
        expandedView.addSubview(pathField)

        // 标签容器（药丸）
        tagsContainer.orientation = .horizontal
        tagsContainer.spacing = 4
        tagsContainer.alignment = .leading
        tagsContainer.translatesAutoresizingMaskIntoConstraints = false
        expandedView.addSubview(tagsContainer)
        addSubview(expandedView)

        // 顶部细分隔线（最后添加，确保绘制在最上层）
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // 高度约束（由展开状态驱动）
        heightConstraint = heightAnchor.constraint(equalToConstant: collapsedHeight)
        heightConstraint.priority = .required

        NSLayoutConstraint.activate([
            // 分隔线
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            // chevron
            chevronButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            chevronButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevronButton.widthAnchor.constraint(equalToConstant: 20),
            chevronButton.heightAnchor.constraint(equalToConstant: 20),

            // compact 填充整个 bar
            compactView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            compactView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            compactView.topAnchor.constraint(equalTo: topAnchor),
            compactView.bottomAnchor.constraint(equalTo: bottomAnchor),

            smallIconView.leadingAnchor.constraint(equalTo: compactView.leadingAnchor),
            smallIconView.centerYAnchor.constraint(equalTo: compactView.centerYAnchor),
            smallIconView.widthAnchor.constraint(equalToConstant: 24),
            smallIconView.heightAnchor.constraint(equalToConstant: 24),

            compactNameField.leadingAnchor.constraint(equalTo: smallIconView.trailingAnchor, constant: 8),
            compactNameField.centerYAnchor.constraint(equalTo: compactView.centerYAnchor),
            compactNameField.trailingAnchor.constraint(equalTo: compactView.trailingAnchor, constant: -28),

            // expanded
            expandedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            expandedView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            expandedView.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            bigIconView.leadingAnchor.constraint(equalTo: expandedView.leadingAnchor),
            bigIconView.topAnchor.constraint(equalTo: expandedView.topAnchor),
            bigIconView.widthAnchor.constraint(equalToConstant: 48),
            bigIconView.heightAnchor.constraint(equalToConstant: 48),

            grid.leadingAnchor.constraint(equalTo: bigIconView.trailingAnchor, constant: 12),
            grid.topAnchor.constraint(equalTo: expandedView.topAnchor),
            grid.trailingAnchor.constraint(equalTo: expandedView.trailingAnchor, constant: -28),

            // 左列
            nameLabel.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: grid.topAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: grid.centerXAnchor, constant: -8),

            typeLabel.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            typeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            typeField.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 4),
            typeField.centerYAnchor.constraint(equalTo: typeLabel.centerYAnchor),
            typeField.trailingAnchor.constraint(equalTo: grid.centerXAnchor, constant: -8),

            sizeLabel.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            sizeLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 4),
            sizeField.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 4),
            sizeField.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            sizeField.trailingAnchor.constraint(equalTo: grid.centerXAnchor, constant: -8),
            grid.bottomAnchor.constraint(greaterThanOrEqualTo: sizeLabel.bottomAnchor),

            // 右列
            createdLabel.leadingAnchor.constraint(equalTo: grid.centerXAnchor, constant: 8),
            createdLabel.topAnchor.constraint(equalTo: grid.topAnchor),
            createdField.leadingAnchor.constraint(equalTo: createdLabel.trailingAnchor, constant: 4),
            createdField.centerYAnchor.constraint(equalTo: createdLabel.centerYAnchor),
            createdField.trailingAnchor.constraint(equalTo: grid.trailingAnchor),

            modifiedLabel.leadingAnchor.constraint(equalTo: grid.centerXAnchor, constant: 8),
            modifiedLabel.topAnchor.constraint(equalTo: createdLabel.bottomAnchor, constant: 4),
            modifiedField.leadingAnchor.constraint(equalTo: modifiedLabel.trailingAnchor, constant: 4),
            modifiedField.centerYAnchor.constraint(equalTo: modifiedLabel.centerYAnchor),
            modifiedField.trailingAnchor.constraint(equalTo: grid.trailingAnchor),

            permLabel.leadingAnchor.constraint(equalTo: grid.centerXAnchor, constant: 8),
            permLabel.topAnchor.constraint(equalTo: modifiedLabel.bottomAnchor, constant: 4),
            permField.leadingAnchor.constraint(equalTo: permLabel.trailingAnchor, constant: 4),
            permField.centerYAnchor.constraint(equalTo: permLabel.centerYAnchor),
            permField.trailingAnchor.constraint(equalTo: grid.trailingAnchor),

            // 路径 + 标签
            pathField.leadingAnchor.constraint(equalTo: expandedView.leadingAnchor),
            pathField.topAnchor.constraint(equalTo: bigIconView.bottomAnchor, constant: 6),
            pathField.trailingAnchor.constraint(equalTo: expandedView.trailingAnchor),

            tagsContainer.leadingAnchor.constraint(equalTo: expandedView.leadingAnchor),
            tagsContainer.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 4),
            tagsContainer.trailingAnchor.constraint(lessThanOrEqualTo: expandedView.trailingAnchor),
            tagsContainer.heightAnchor.constraint(lessThanOrEqualToConstant: 20),

            heightConstraint,
        ])

        applyExpandedState(animated: false)
        refresh()
    }

    // MARK: - Builders

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 10)
        f.textColor = NSColor.secondaryLabelColor
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.required, for: .horizontal)
        f.setContentCompressionResistancePriority(.required, for: .horizontal)
        f.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return f
    }

    private func configureValue(_ f: NSTextField) {
        f.font = NSFont.systemFont(ofSize: 10)
        f.textColor = NSColor.labelColor
        f.lineBreakMode = .byTruncatingTail
        f.maximumNumberOfLines = 1
        f.cell?.truncatesLastVisibleLine = true
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    // MARK: - Public API

    /// 更新显示的文件信息（任务要求接口）
    func update(with entry: FileEntry?) {
        self.entry = entry
        refresh()
    }

    /// 更新选中数量（用于多选时显示 "已选中 N 项"）
    func setSelectedCount(_ count: Int) {
        self.selectedCount = count
        refresh()
    }

    /// 兼容旧接口（file + selectedCount 一起更新）
    func update(file: FileEntry?, selectedCount: Int) {
        self.entry = file
        self.selectedCount = selectedCount
        refresh()
    }

    // MARK: - Toggle

    @objc private func toggleExpanded() {
        isExpanded.toggle()
    }

    private func applyExpandedState(animated: Bool) {
        heightConstraint.constant = isExpanded ? expandedHeight : collapsedHeight
        compactView.isHidden = isExpanded
        expandedView.isHidden = !isExpanded

        let symbol = isExpanded ? "chevron.down" : "chevron.up"
        chevronButton.image = NSImage(systemSymbolName: symbol,
                                      accessibilityDescription: isExpanded ? "收起" : "展开")

        if isExpanded { loadThumbnail() }

        let performLayout = { [weak self] in
            self?.window?.layoutIfNeeded()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                performLayout()
            }
        } else {
            performLayout()
        }
    }

    // MARK: - Refresh

    private func refresh() {
        // 文件变化时取消上一次的缩略图请求
        if let oldPath = thumbnailLoadPath, oldPath != entry?.path {
            ThumbnailManager.shared.cancelGeneration(for: oldPath)
            thumbnailLoadPath = nil
            bigIconView.image = nil
        }

        // compact 行
        if selectedCount > 1 {
            compactNameField.stringValue = "已选中 \(selectedCount) 项"
            smallIconView.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        } else if let entry = entry {
            compactNameField.stringValue = "\(entry.name)  ·  \(entry.formattedSize)"
            smallIconView.image = NSWorkspace.shared.icon(forFile: entry.path)
        } else {
            compactNameField.stringValue = "未选择文件"
            smallIconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        }

        // expanded 字段
        guard let entry = entry, selectedCount <= 1 else {
            let placeholder = selectedCount > 1 ? "已选中 \(selectedCount) 项" : "未选择文件"
            nameField.stringValue = placeholder
            typeField.stringValue = ""
            sizeField.stringValue = ""
            createdField.stringValue = ""
            modifiedField.stringValue = ""
            permField.stringValue = ""
            pathField.stringValue = ""
            bigIconView.image = smallIconView.image
            clearTags()
            showNoTagsPlaceholder()
            return
        }

        nameField.stringValue = entry.name
        typeField.stringValue = entry.kindDescription
        sizeField.stringValue = entry.formattedSize
        createdField.stringValue = entry.formattedCreationDate
        modifiedField.stringValue = entry.formattedModificationDate
        permField.stringValue = permissionString(path: entry.path)
        pathField.stringValue = entry.path
        bigIconView.image = NSWorkspace.shared.icon(forFile: entry.path)

        updateTags(path: entry.path)

        if isExpanded { loadThumbnail() }
    }

    // MARK: - Thumbnail

    private func loadThumbnail() {
        guard let entry = entry, !entry.isDirectory, selectedCount <= 1 else { return }
        let path = entry.path
        thumbnailLoadPath = path
        ThumbnailManager.shared.generateThumbnail(
            path: path,
            size: CGSize(width: 48, height: 48)
        ) { [weak self] image in
            guard let self = self, let image = image else { return }
            // 防止过期回调覆盖当前显示
            guard self.thumbnailLoadPath == path, self.isExpanded else { return }
            self.bigIconView.image = image
        }
    }

    // MARK: - Tags (药丸样式)

    private func updateTags(path: String) {
        clearTags()
        let tags = TagBridge.shared.getTags(path: path)
        if tags.isEmpty {
            showNoTagsPlaceholder()
            return
        }
        for tag in tags {
            tagsContainer.addArrangedSubview(makeTagPill(tag: tag))
        }
    }

    private func showNoTagsPlaceholder() {
        let none = NSTextField(labelWithString: "无标签")
        none.font = NSFont.systemFont(ofSize: 10)
        none.textColor = NSColor.tertiaryLabelColor
        none.translatesAutoresizingMaskIntoConstraints = false
        tagsContainer.addArrangedSubview(none)
    }

    private func clearTags() {
        for v in tagsContainer.arrangedSubviews {
            tagsContainer.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    private func makeTagPill(tag: Tag) -> NSView {
        let pillHeight: CGFloat = 18
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        pill.layer?.cornerRadius = pillHeight / 2
        pill.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(dot)

        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            pill.heightAnchor.constraint(equalToConstant: pillHeight),
        ])
        return pill
    }

    // MARK: - Permissions

    /// 通过 FileManager 获取权限信息并格式化为 "drwxr-xr-x 755 owner:group"
    private func permissionString(path: String) -> String {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
            let fileType = attrs[.type] as? FileAttributeType
            let isDir = fileType == .typeDirectory
            let rwx = rwxString(perms: perms, isDir: isDir)
            let octal = String(format: "%o", perms & 0o777)
            let owner = (attrs[.ownerAccountName] as? String) ?? ""
            let group = (attrs[.groupOwnerAccountName] as? String) ?? ""
            var result = "\(rwx)  \(octal)"
            if !owner.isEmpty || !group.isEmpty {
                result += "  \(owner):\(group)"
            }
            return result
        } catch {
            return "--"
        }
    }

    private func rwxString(perms: Int16, isDir: Bool) -> String {
        var s = isDir ? "d" : "-"
        let owner = (perms >> 6) & 0o7
        let group = (perms >> 3) & 0o7
        let other = perms & 0o7
        for v in [owner, group, other] {
            s += (v & 4 != 0) ? "r" : "-"
            s += (v & 2 != 0) ? "w" : "-"
            s += (v & 1 != 0) ? "x" : "-"
        }
        return s
    }
}
