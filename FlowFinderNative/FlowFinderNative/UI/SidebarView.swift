import Cocoa

// MARK: - Sidebar Notifications

extension Notification.Name {
    static let sidebarDidSelectDirectory = Notification.Name("sidebarDidSelectDirectory")
    static let paneDidActivate = Notification.Name("paneDidActivate")
}

// MARK: - SidebarView

class SidebarView: NSView {
    private var favoritesOutlineView: NSOutlineView!
    private var tagsOutlineView: NSOutlineView!
    private var deviceOutlineView: NSOutlineView!
    private var favoritesScrollView: NSScrollView!
    private var tagsScrollView: NSScrollView!
    private var deviceScrollView: NSScrollView!
    /// 收藏夹区域圆角遮罩
    private var favoritesMaskView: GlassSectionMaskView!
    /// 标签区域圆角遮罩
    private var tagsMaskView: GlassSectionMaskView!
    /// 下方区域圆角遮罩（包裹存储设备）
    private var deviceMaskView: GlassSectionMaskView!
    private let favoritesDataSource = FavoritesSidebarDataSource()
    private let tagsDataSource = TagsSidebarDataSource()
    private let deviceDataSource = DeviceSidebarDataSource()
    private var favoritesHeightConstraint: NSLayoutConstraint!
    private var deviceHeightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // 透明背景，依赖 MainWindowController 的 NSVisualEffectView 玻璃态
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // 圆角遮罩区域：收藏夹（独立）
        favoritesMaskView = GlassSectionMaskView()
        favoritesMaskView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(favoritesMaskView)

        // 圆角遮罩区域：标签（独立）
        tagsMaskView = GlassSectionMaskView()
        tagsMaskView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagsMaskView)

        // 圆角遮罩区域：下方（存储设备）
        deviceMaskView = GlassSectionMaskView()
        deviceMaskView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deviceMaskView)

        // 收藏夹区域
        favoritesScrollView = makeScrollView()
        favoritesOutlineView = makeOutlineView()
        favoritesOutlineView.dataSource = favoritesDataSource
        favoritesOutlineView.delegate = favoritesDataSource
        // 右键菜单（动态：收藏夹显示「移除收藏」）
        let favoritesMenu = NSMenu()
        favoritesMenu.delegate = self
        favoritesOutlineView.menu = favoritesMenu
        favoritesScrollView.documentView = favoritesOutlineView
        // 放入遮罩容器，由 mask 提供圆角半透明背景
        favoritesMaskView.addSubview(favoritesScrollView)

        // 标签区域
        tagsScrollView = makeScrollView()
        tagsOutlineView = makeOutlineView()
        tagsOutlineView.dataSource = tagsDataSource
        tagsOutlineView.delegate = tagsDataSource
        // 「添加标签」按钮回调
        tagsDataSource.onCreateTagTapped = { [weak self] in
            self?.showCreateTagDialog()
        }
        // 右键菜单（动态：标签显示「删除标签」）
        let tagsMenu = NSMenu()
        tagsMenu.delegate = self
        tagsOutlineView.menu = tagsMenu
        tagsScrollView.documentView = tagsOutlineView
        // 放入遮罩容器
        tagsMaskView.addSubview(tagsScrollView)

        // 下方：存储设备（独立区域，固定底部）
        deviceScrollView = makeScrollView()
        deviceOutlineView = makeOutlineView()
        deviceOutlineView.dataSource = deviceDataSource
        deviceOutlineView.delegate = deviceDataSource
        deviceScrollView.documentView = deviceOutlineView
        // 放入遮罩容器
        deviceMaskView.addSubview(deviceScrollView)

        // 收藏夹区高度根据收藏数量动态调整（保留最小高度）
        favoritesHeightConstraint = favoritesMaskView.heightAnchor.constraint(equalToConstant: 48)
        favoritesHeightConstraint.priority = .required

        // 设备区高度根据设备数量动态调整（保留最小高度）
        // 高度约束作用于设备遮罩容器，scrollView 填满遮罩
        deviceHeightConstraint = deviceMaskView.heightAnchor.constraint(equalToConstant: 48)
        deviceHeightConstraint.priority = .required

        let padding: CGFloat = 12

        NSLayoutConstraint.activate([
            // 收藏夹遮罩区域：顶部固定，高度随内容动态变化
            favoritesMaskView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            favoritesMaskView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            favoritesMaskView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            favoritesHeightConstraint,

            // 标签遮罩区域：填充收藏夹与存储设备之间的剩余空间
            tagsMaskView.topAnchor.constraint(equalTo: favoritesMaskView.bottomAnchor, constant: padding),
            tagsMaskView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            tagsMaskView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            tagsMaskView.bottomAnchor.constraint(equalTo: deviceMaskView.topAnchor, constant: -padding),

            // 设备遮罩区域固定底部
            deviceMaskView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            deviceMaskView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            deviceMaskView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            deviceHeightConstraint,

            // 收藏夹 scrollView 填满收藏夹遮罩（内边距 8pt，圆角由 mask 的 masksToBounds 裁剪）
            favoritesScrollView.topAnchor.constraint(equalTo: favoritesMaskView.topAnchor, constant: 8),
            favoritesScrollView.leadingAnchor.constraint(equalTo: favoritesMaskView.leadingAnchor, constant: 8),
            favoritesScrollView.trailingAnchor.constraint(equalTo: favoritesMaskView.trailingAnchor, constant: -8),
            favoritesScrollView.bottomAnchor.constraint(equalTo: favoritesMaskView.bottomAnchor, constant: -8),

            // 标签 scrollView 填满标签遮罩（内边距 8pt）
            tagsScrollView.topAnchor.constraint(equalTo: tagsMaskView.topAnchor, constant: 8),
            tagsScrollView.leadingAnchor.constraint(equalTo: tagsMaskView.leadingAnchor, constant: 8),
            tagsScrollView.trailingAnchor.constraint(equalTo: tagsMaskView.trailingAnchor, constant: -8),
            tagsScrollView.bottomAnchor.constraint(equalTo: tagsMaskView.bottomAnchor, constant: -8),

            // 设备 scrollView 填满设备遮罩（内边距 8pt）
            deviceScrollView.topAnchor.constraint(equalTo: deviceMaskView.topAnchor, constant: 8),
            deviceScrollView.leadingAnchor.constraint(equalTo: deviceMaskView.leadingAnchor, constant: 8),
            deviceScrollView.trailingAnchor.constraint(equalTo: deviceMaskView.trailingAnchor, constant: -8),
            deviceScrollView.bottomAnchor.constraint(equalTo: deviceMaskView.bottomAnchor, constant: -8),
        ])

        // 监听卷挂载/卸载通知
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleVolumeMount(_:)),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleVolumeUnmount(_:)),
                       name: NSWorkspace.didUnmountNotification, object: nil)

        // 展开各自区域
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.favoritesOutlineView.expandItem(SidebarSection.favorites)
            self.tagsOutlineView.expandItem(SidebarSection.tags)
            self.deviceOutlineView.expandItem(SidebarSection.devices)
            self.updateFavoritesHeight()
            self.updateDeviceHeight()
        }
    }

    // MARK: - Helpers

    private func makeScrollView() -> NSScrollView {
        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.backgroundColor = .clear
        // NSClipView 默认绘制 controlBackgroundColor（浅灰），必须显式清除
        sv.contentView.drawsBackground = false
        sv.contentView.backgroundColor = .clear
        return sv
    }

    private func makeOutlineView() -> NSOutlineView {
        let ov = NSOutlineView()
        ov.allowsMultipleSelection = false
        ov.headerView = nil  // 无表头
        ov.rowHeight = 24
        ov.indentationPerLevel = 12
        ov.backgroundColor = NSColor.clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarItem"))
        column.width = 200
        ov.addTableColumn(column)
        ov.outlineTableColumn = column
        return ov
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Volume Events

    @objc private func handleVolumeMount(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDevices()
        }
    }

    @objc private func handleVolumeUnmount(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDevices()
        }
    }

    // MARK: - Context Menu

    @objc private func removeFavorite(_ sender: Any?) {
        let row = favoritesOutlineView.clickedRow
        guard row >= 0 else { return }
        let item = favoritesOutlineView.item(atRow: row)
        if case .favorite(let fav) = item as? SidebarItem {
            favoritesDataSource.removeFavorite(id: fav.id)
            favoritesOutlineView.reloadData()
            updateFavoritesHeight()
        }
    }

    @objc private func removeTag(_ sender: NSMenuItem?) {
        guard let tagId = sender?.representedObject as? String else { return }
        tagsDataSource.removeTag(id: tagId)
        tagsOutlineView.reloadData()
    }

    /// 添加收藏夹（供外部调用）
    func addFavorite(name: String, path: String) {
        favoritesDataSource.addFavorite(name: name, path: path)
        favoritesOutlineView.reloadData()
        updateFavoritesHeight()
    }

    // MARK: - Create Tag Dialog

    private func showCreateTagDialog() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "输入标签名称并选择颜色："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let containerWidth: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 64))

        // 名称输入框
        let nameField = NSTextField(frame: NSRect(x: 0, y: 36, width: containerWidth, height: 24))
        nameField.placeholderString = "标签名称"
        container.addSubview(nameField)

        // 预设颜色圆点按钮
        let presetColors: [String] = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#5856D6"]
        let dotSize: CGFloat = 22
        let spacing: CGFloat = 8
        let totalDotsWidth = CGFloat(presetColors.count) * dotSize + CGFloat(presetColors.count - 1) * spacing
        let startX = (containerWidth - totalDotsWidth) / 2

        let colorHolder = TagColorHolder(colors: presetColors)

        for (i, hex) in presetColors.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            let btn = NSButton(frame: NSRect(x: x, y: 4, width: dotSize, height: dotSize))
            btn.bezelStyle = .circular
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = (NSColor(hex: hex) ?? .systemBlue).cgColor
            btn.layer?.cornerRadius = dotSize / 2
            btn.layer?.borderColor = NSColor.labelColor.cgColor
            btn.layer?.borderWidth = (i == 0) ? 2 : 0
            btn.target = colorHolder
            btn.action = #selector(TagColorHolder.selectColor(_:))
            btn.tag = i
            container.addSubview(btn)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let tag = Tag(name: name, color: colorHolder.selectedHex)
            self?.tagsDataSource.addTag(tag)
            self?.tagsOutlineView.reloadData()
        }
    }

    // MARK: - Refresh

    func refreshDevices() {
        deviceDataSource.loadDevices()
        deviceOutlineView.reloadData()
        deviceOutlineView.expandItem(SidebarSection.devices)
        updateDeviceHeight()
    }

    private func updateDeviceHeight() {
        // section 标题行（24pt） + 设备行（52pt：图标行20 + 进度条行8 + 文字行12 + 间距8 + padding4）
        let sectionHeight: CGFloat = 24
        let deviceRowHeight: CGFloat = 52
        let height = sectionHeight + CGFloat(deviceDataSource.deviceCount) * deviceRowHeight
        deviceHeightConstraint.constant = max(height, 48)
    }

    private func updateFavoritesHeight() {
        // section 标题行（24pt）+ 收藏夹行（24pt）
        let sectionHeight: CGFloat = 24
        let rowHeight: CGFloat = 24
        let height = sectionHeight + CGFloat(favoritesDataSource.favoriteCount) * rowHeight
        favoritesHeightConstraint.constant = max(height, 48)
    }
}

// MARK: - SidebarView + NSMenuDelegate

extension SidebarView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === favoritesOutlineView.menu {
            // 收藏夹右键菜单
            let row = favoritesOutlineView.clickedRow
            guard row >= 0 else { return }
            let item = favoritesOutlineView.item(atRow: row)
            if case .favorite = item as? SidebarItem {
                let mi = menu.addItem(withTitle: "移除收藏", action: #selector(removeFavorite(_:)), keyEquivalent: "")
                mi.target = self
            }
        } else if menu === tagsOutlineView.menu {
            // 标签右键菜单
            let row = tagsOutlineView.clickedRow
            guard row >= 0 else { return }
            let item = tagsOutlineView.item(atRow: row)
            if case .tag(let tag) = item as? SidebarItem {
                let mi = menu.addItem(withTitle: "删除标签", action: #selector(removeTag(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = tag.id
            }
        }
    }
}

// MARK: - TagColorHolder (颜色选择辅助类)

private class TagColorHolder: NSObject {
    private let colors: [String]
    private(set) var selectedHex: String

    init(colors: [String]) {
        self.colors = colors
        self.selectedHex = colors.first ?? "#007AFF"
        super.init()
    }

    @objc func selectColor(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < colors.count else { return }
        selectedHex = colors[idx]
        // 更新按钮选中边框
        if let container = sender.superview {
            for case let btn as NSButton in container.subviews {
                btn.layer?.borderWidth = btn === sender ? 2 : 0
            }
        }
    }
}

// MARK: - SidebarDataSourceBase

private class SidebarDataSourceBase: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

    /// 点击「添加标签」按钮的回调
    var onCreateTagTapped: (() -> Void)?

    @objc func handleCreateTagButton() {
        onCreateTagTapped?()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // 收藏夹不可折叠（始终展开），标签和设备可折叠
        if let section = item as? SidebarSection {
            return section != .favorites
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // 区域标题不可选
        if item is SidebarSection { return false }
        return true
    }

    // MARK: - Shared Cell Rendering

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = (outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        cell.identifier = cellID

        // 清除旧子视图与引用
        cell.subviews.forEach { $0.removeFromSuperview() }
        cell.imageView = nil
        cell.textField = nil

        // 标签：药丸样式（自定义布局）
        if case .tag(let tag) = item as? SidebarItem {
            configureTagPill(cell: cell, tag: tag)
            return cell
        }

        // 设备：进度条 + 可用空间（自定义布局）
        if case .device(let dev) = item as? SidebarItem {
            configureDeviceCell(cell: cell, dev: dev)
            return cell
        }

        // 默认布局：图标 + 文字（区域标题 / 收藏夹）
        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.textColor = NSColor.labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        if let section = item as? SidebarSection {
            textField.stringValue = section.title
            textField.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            textField.textColor = NSColor.secondaryLabelColor
            imageView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            imageView.isHidden = true

            // 标签区域标题旁添加"+"按钮
            if section == .tags {
                let addButton = NSButton()
                addButton.bezelStyle = .inline
                addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")
                addButton.imagePosition = .imageOnly
                addButton.isBordered = false
                addButton.contentTintColor = NSColor.secondaryLabelColor
                addButton.target = self
                addButton.action = #selector(handleCreateTagButton)
                addButton.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(addButton)

                NSLayoutConstraint.activate([
                    addButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    addButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    addButton.widthAnchor.constraint(equalToConstant: 16),
                    addButton.heightAnchor.constraint(equalToConstant: 16),
                    textField.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),
                ])
            } else {
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
            }

            return cell
        }

        // 非区域标题行（收藏夹项）：文本填充至右侧
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true

        switch item as? SidebarItem {
        case .favorite(let fav):
            textField.stringValue = fav.name
            // 使用 NSWorkspace 获取真实位置图标（桌面、文稿、下载等各有不同图标）
            let workspaceIcon = NSWorkspace.shared.icon(forFile: fav.path)
            workspaceIcon.size = NSSize(width: 16, height: 16)
            imageView.image = workspaceIcon

        default:
            textField.stringValue = ""
        }

        return cell
    }

    // MARK: - Row Height

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        // 设备行使用更高的高度以容纳「图标 + 进度条 + 可用空间」三行
        if case .device = item as? SidebarItem {
            return 52
        }
        return 24
    }

    // MARK: - Tag Pill (药丸样式)

    private func configureTagPill(cell: NSTableCellView, tag: Tag) {
        let pillHeight: CGFloat = 20

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        pill.layer?.cornerRadius = pillHeight / 2  // ≈10pt
        pill.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(pill)

        // 左侧彩色小圆点（8x8，cornerRadius = 4）
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(dot)

        // 标签文字
        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        cell.textField = label

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            pill.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: pillHeight),

            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
        ])
    }

    // MARK: - Device Cell (进度条 + 可用空间)

    private func configureDeviceCell(cell: NSTableCellView, dev: DeviceItem) {
        // 上行：图标(14x14) + 名称(11pt)
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let iconName: String
        if dev.path == "/" {
            iconName = "internaldrive"
        } else if dev.path == FileManager.default.homeDirectoryForCurrentUser.path {
            iconName = "house"
        } else if dev.isNetwork {
            iconName = "externaldrive.connected.to.line"
        } else {
            iconName = "externaldrive"
        }
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "设备")
            ?? NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)

        let nameField = NSTextField(labelWithString: dev.name)
        nameField.font = NSFont.systemFont(ofSize: 11)
        nameField.textColor = NSColor.labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        // 中行：水平进度条（4pt 高，填充宽度）
        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        // NSProgressIndicator.controlTint 自 10.15 起已弃用且不生效，
        // 进度条已用部分自动跟随系统强调色（默认即为 systemBlue），剩余轨道为系统灰色。
        progress.translatesAutoresizingMaskIntoConstraints = false
        if dev.totalSize > 0 {
            let used = Double(dev.totalSize - dev.freeSize) / Double(dev.totalSize)
            progress.doubleValue = min(max(used, 0), 1)
        } else {
            progress.doubleValue = 0
        }

        // 下行：可用空间文字(9pt)
        let freeField = NSTextField(labelWithString: formatFreeSpace(dev.freeSize))
        freeField.font = NSFont.systemFont(ofSize: 9)
        freeField.textColor = NSColor.tertiaryLabelColor
        freeField.lineBreakMode = .byTruncatingTail
        freeField.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(nameField)
        cell.addSubview(progress)
        cell.addSubview(freeField)
        cell.imageView = icon
        cell.textField = nameField

        let progressHeight = progress.heightAnchor.constraint(equalToConstant: 4)
        progressHeight.priority = .required

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            icon.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            nameField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            nameField.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            progress.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            progress.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            progress.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
            progressHeight,

            freeField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            freeField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            freeField.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 2),
        ])
    }

    // MARK: - Free Space Formatting

    private func formatFreeSpace(_ bytes: UInt64) -> String {
        if bytes == 0 { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytes))) 可用"
    }

    // MARK: - Selection

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 else { return }

        let item = outlineView.item(atRow: selectedRow)
        guard let sidebarItem = item as? SidebarItem else { return }

        switch sidebarItem {
        case .favorite(let fav):
            let entry = FileEntry(path: fav.path, name: fav.name, isDirectory: true)
            NotificationCenter.default.post(name: .sidebarDidSelectDirectory, object: entry)
        case .device(let dev):
            let entry = FileEntry(path: dev.path, name: dev.name, isDirectory: true)
            NotificationCenter.default.post(name: .sidebarDidSelectDirectory, object: entry)
        case .tag:
            // 标签点击可选不做导航（未来可筛选同名标签文件）
            break
        }
    }
}

// MARK: - FavoritesSidebarDataSource (收藏夹)

private class FavoritesSidebarDataSource: SidebarDataSourceBase {
    private var favorites: [FavoriteItem] = []

    private let favoritesKey = "SidebarFavorites"

    var favoriteCount: Int { favorites.count }

    override init() {
        super.init()
        loadFavorites()
    }

    // MARK: - Data Loading

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            favorites = decoded
        } else {
            // 默认收藏夹
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            favorites = [
                FavoriteItem(name: "桌面", path: (home as NSString).appendingPathComponent("Desktop")),
                FavoriteItem(name: "文档", path: (home as NSString).appendingPathComponent("Documents")),
                FavoriteItem(name: "下载", path: (home as NSString).appendingPathComponent("Downloads")),
                FavoriteItem(name: "应用程序", path: "/Applications"),
            ]
            saveFavorites()
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    // MARK: - CRUD

    func addFavorite(name: String, path: String) {
        let fav = FavoriteItem(name: name, path: path)
        favorites.append(fav)
        saveFavorites()
    }

    func removeFavorite(id: String) {
        favorites.removeAll(where: { $0.id == id })
        saveFavorites()
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // 仅收藏夹一个 section
            return 1
        }
        if let section = item as? SidebarSection, section == .favorites {
            return favorites.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return SidebarSection.favorites
        }
        if let section = item as? SidebarSection, section == .favorites {
            return SidebarItem.favorite(favorites[index])
        }
        return ""
    }
}

// MARK: - TagsSidebarDataSource (标签)

private class TagsSidebarDataSource: SidebarDataSourceBase {
    private var tags: [Tag] = []

    private let tagsKey = "SidebarTags"

    override init() {
        super.init()
        loadTags()
    }

    // MARK: - Data Loading

    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: tagsKey),
           let decoded = try? JSONDecoder().decode([Tag].self, from: data) {
            tags = decoded
        } else {
            tags = [
                Tag(name: "重要", color: "#FF3B30"),
                Tag(name: "工作", color: "#007AFF"),
                Tag(name: "个人", color: "#34C759"),
            ]
            saveTags()
        }
    }

    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: tagsKey)
        }
    }

    // MARK: - CRUD

    func addTag(_ tag: Tag) {
        tags.append(tag)
        saveTags()
    }

    func removeTag(id: String) {
        tags.removeAll(where: { $0.id == id })
        saveTags()
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // 仅标签一个 section
            return 1
        }
        if let section = item as? SidebarSection, section == .tags {
            return tags.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return SidebarSection.tags
        }
        if let section = item as? SidebarSection, section == .tags {
            return SidebarItem.tag(tags[index])
        }
        return ""
    }
}

// MARK: - DeviceSidebarDataSource (存储设备)

private class DeviceSidebarDataSource: SidebarDataSourceBase {
    private var devices: [DeviceItem] = []

    var deviceCount: Int { devices.count }

    override init() {
        super.init()
        loadDevices()
    }

    // MARK: - Data Loading

    func loadDevices() {
        let volumes = CoreBridge.shared.listVolumes()
        devices = []

        // 1. 始终添加主硬盘（根目录 /），即使 Rust 端过滤了它
        // volumeNameKey 可能返回电脑名而非卷名，使用 volumeLocalizedNameKey 并提供回退
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let rootURL = URL(fileURLWithPath: "/")
        var rootName = "Macintosh HD"
        if let name = try? rootURL.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName,
           !name.isEmpty, name != Host.current().localizedName {
            rootName = name
        }
        devices.append(DeviceItem(
            name: rootName,
            path: "/",
            isRemovable: false,
            isNetwork: false,
            totalSize: 0,
            freeSize: 0
        ))

        // 2. 添加用户主目录（作为快捷设备入口）
        let homeName = homePath.components(separatedBy: "/").last ?? "Home"
        devices.append(DeviceItem(
            name: homeName,
            path: homePath,
            isRemovable: false,
            isNetwork: false,
            totalSize: 0,
            freeSize: 0
        ))

        // 3. 过滤并添加外部/网络卷
        for vol in volumes {
            // 只保留 /Volumes/ 下的挂载卷（U盘、外接硬盘、网络驱动器等）
            guard vol.path.hasPrefix("/Volumes/") else { continue }

            // 过滤系统隐藏卷（VM、Preboot、Update 等）
            let volName = vol.name
            let systemNames: Set<String> = [
                "VM", "Preboot", "Update", "xarts", "iSCPreboot",
                "Hardware", "Recovery", "SSV", "Data"
            ]
            if systemNames.contains(volName) { continue }

            // 过滤 UUID 命名的快照卷
            if volName.count == 36 && volName.contains("-") { continue }

            let isNetwork = vol.fsType.lowercased().contains("smb")
                || vol.fsType.lowercased().contains("nfs")
                || vol.fsType.lowercased().contains("afp")

            devices.append(DeviceItem(
                name: volName,
                path: vol.path,
                isRemovable: vol.isRemovable,
                isNetwork: isNetwork,
                totalSize: vol.totalSize,
                freeSize: vol.freeSize
            ))
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // 仅存储设备一个 section
            return 1
        }
        if let section = item as? SidebarSection, section == .devices {
            return devices.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return SidebarSection.devices
        }
        if let section = item as? SidebarSection, section == .devices {
            return SidebarItem.device(devices[index])
        }
        return ""
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255.0
            g = CGFloat((int >> 8) & 0xFF) / 255.0
            b = CGFloat(int & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
