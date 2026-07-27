import Cocoa

// MARK: - Sidebar Notifications

extension Notification.Name {
    static let sidebarDidSelectDirectory = Notification.Name("sidebarDidSelectDirectory")
    static let paneDidActivate = Notification.Name("paneDidActivate")
}

// MARK: - DeviceExtendedInfo (设备扩展信息，用于悬停气泡)

/// 设备扩展信息：存储文件系统类型、挂载点等，供 tooltip 显示
private struct DeviceExtendedInfo {
    let fileSystemType: String
    let mountPoint: String
    let totalSize: UInt64
    let freeSize: UInt64
}

// MARK: - SidebarView

class SidebarView: NSView {
    /// 任务 R3: 侧边栏顶部应用图标 + FlowFinder 文字（红绿灯下方）
    private var brandView: NSView!
    /// 任务 R3: 应用图标视图（用于点击弹出关于对话框）
    private var brandIconView: NSImageView!
    /// 任务 T1: 工具栏行（夜间切换 + 设置 + 工具），位于设备上方
    private var toolBarRow: NSStackView!
    /// 任务 T1: 主题切换按钮（用于切换图标）
    private var themeToggleBtn: NSButton!

    private var favoritesOutlineView: NSOutlineView!
    private var deviceOutlineView: NSOutlineView!
    private var favoritesScrollView: NSScrollView!
    private var deviceScrollView: NSScrollView!
    /// 1.5 收藏夹区域玻璃背景（FFGlassView .panel 替代 GlassSectionMaskView）
    private var favoritesMaskView: FFGlassView!
    /// 1.5 标签区域玻璃背景
    private var tagsMaskView: FFGlassView!
    /// 1.5 下方区域玻璃背景（包裹存储设备，B8 改为浮动在侧边栏左下角）
    private var deviceMaskView: FFGlassView!
    /// B10: 设备栏自定义头部（汇总信息 + 折叠箭头）
    private var deviceHeaderView: DeviceHeaderView!
    /// 标签 flow 视图（替代 outlineView，支持横向 wrap）
    private var tagFlowView: TagFlowView!
    private let favoritesDataSource = FavoritesSidebarDataSource()
    private let tagsDataSource = TagsSidebarDataSource()
    private let deviceDataSource = DeviceSidebarDataSource()
    private var favoritesHeightConstraint: NSLayoutConstraint!
    private var tagsHeightConstraint: NSLayoutConstraint!
    private var deviceHeightConstraint: NSLayoutConstraint!

    /// B10: 设备栏折叠状态（默认折叠）
    private var isDeviceCollapsed = true

    /// B8: 设备栏折叠态高度（头部 32pt + 上下 padding 8pt = 48pt）
    private let deviceCollapsedHeight: CGFloat = 48
    /// B9: 设备行单行高度
    private let deviceRowHeight: CGFloat = 28

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

        // 任务 R3: 侧边栏顶部应用图标 + FlowFinder 文字（红绿灯下方）
        brandView = NSView()
        brandView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(brandView)

        brandIconView = NSImageView()
        brandIconView.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        brandIconView.imageScaling = .scaleProportionallyUpOrDown
        brandIconView.translatesAutoresizingMaskIntoConstraints = false
        brandView.addSubview(brandIconView)

        let appNameLabel = NSTextField(labelWithString: "FlowFinder")
        appNameLabel.font = NSFont.boldSystemFont(ofSize: 15)
        appNameLabel.textColor = NSColor.labelColor
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        brandView.addSubview(appNameLabel)

        // 点击 brandView 弹出关于对话框
        let brandClick = NSClickGestureRecognizer(target: self, action: #selector(showAboutWindow))
        brandView.addGestureRecognizer(brandClick)

        NSLayoutConstraint.activate([
            // 红绿灯下方（topAnchor 32pt 留给红绿灯）
            brandView.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            brandView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            brandView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            brandView.heightAnchor.constraint(equalToConstant: 56),

            brandIconView.leadingAnchor.constraint(equalTo: brandView.leadingAnchor),
            brandIconView.centerYAnchor.constraint(equalTo: brandView.centerYAnchor),
            brandIconView.widthAnchor.constraint(equalToConstant: 32),
            brandIconView.heightAnchor.constraint(equalToConstant: 32),

            appNameLabel.leadingAnchor.constraint(equalTo: brandIconView.trailingAnchor, constant: 8),
            appNameLabel.centerYAnchor.constraint(equalTo: brandView.centerYAnchor),
        ])

        // E18: 强磨砂玻璃 — material 使用 .sidebar（NSVisualEffectView.Material.sidebar）
        // level=.panel, cornerRadius=10 保持不变
        favoritesMaskView = FFGlassView(level: .panel, cornerRadius: 10, material: .sidebar)
        favoritesMaskView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(favoritesMaskView)

        tagsMaskView = FFGlassView(level: .panel, cornerRadius: 10, material: .sidebar)
        tagsMaskView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagsMaskView)

        deviceMaskView = FFGlassView(level: .panel, cornerRadius: 10, material: .sidebar)
        deviceMaskView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deviceMaskView)

        // 任务 T1: 工具栏行（夜间切换 + 设置 + 工具），位于设备上方
        toolBarRow = NSStackView()
        toolBarRow.orientation = .horizontal
        toolBarRow.spacing = 8
        toolBarRow.alignment = .centerY
        toolBarRow.distribution = .fillEqually
        toolBarRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolBarRow)

        themeToggleBtn = NSButton()
        themeToggleBtn.tag = 1001
        themeToggleBtn.bezelStyle = .inline
        themeToggleBtn.isBordered = false
        themeToggleBtn.image = NSImage(systemSymbolName: ThemeManager.shared.currentMode.iconName, accessibilityDescription: "切换主题")
        themeToggleBtn.contentTintColor = .secondaryLabelColor
        themeToggleBtn.target = self
        themeToggleBtn.action = #selector(toggleTheme)
        themeToggleBtn.translatesAutoresizingMaskIntoConstraints = false
        toolBarRow.addArrangedSubview(themeToggleBtn)

        let settingsBtn = NSButton()
        settingsBtn.bezelStyle = .inline
        settingsBtn.isBordered = false
        settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        settingsBtn.contentTintColor = .secondaryLabelColor
        settingsBtn.target = self
        settingsBtn.action = #selector(openSettings)
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        toolBarRow.addArrangedSubview(settingsBtn)

        let toolBtn = NSButton()
        toolBtn.bezelStyle = .inline
        toolBtn.isBordered = false
        toolBtn.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: "工具")
        toolBtn.contentTintColor = .secondaryLabelColor
        toolBtn.target = self
        toolBtn.action = #selector(toggleToolPanel)
        toolBtn.translatesAutoresizingMaskIntoConstraints = false
        toolBarRow.addArrangedSubview(toolBtn)

        // 收藏夹区域
        favoritesScrollView = makeScrollView()
        favoritesOutlineView = makeOutlineView()
        favoritesOutlineView.dataSource = favoritesDataSource
        favoritesOutlineView.delegate = favoritesDataSource
        // A1: 注册拖拽类型 — 支持拖拽文件/文件夹到收藏夹
        favoritesOutlineView.registerForDraggedTypes([.fileURL])
        // 右键菜单（动态：收藏夹显示「移除收藏」）
        let favoritesMenu = NSMenu()
        favoritesMenu.delegate = self
        favoritesOutlineView.menu = favoritesMenu
        favoritesScrollView.documentView = favoritesOutlineView
        // 放入遮罩容器，由 mask 提供圆角半透明背景
        favoritesMaskView.addSubview(favoritesScrollView)

        // 标签区域：使用自定义 TagFlowView 实现横向 wrap 药丸布局（设计稿 ff-pill-tag）
        tagFlowView = TagFlowView()
        tagFlowView.translatesAutoresizingMaskIntoConstraints = false
        tagFlowView.onAddTagTapped = { [weak self] in
            self?.showCreateTagDialog()
        }
        tagFlowView.onTagDeleted = { [weak self] tagId in
            self?.tagsDataSource.removeTag(id: tagId)
            self?.tagFlowView.updateTags(self?.tagsDataSource.allTags() ?? [])
        }
        tagsMaskView.addSubview(tagFlowView)

        // B10: 设备栏头部（汇总 + 折叠箭头）
        deviceHeaderView = DeviceHeaderView()
        deviceHeaderView.translatesAutoresizingMaskIntoConstraints = false
        // 点击头部切换折叠/展开
        let headerClick = NSClickGestureRecognizer(target: self, action: #selector(toggleDeviceExpanded))
        deviceHeaderView.addGestureRecognizer(headerClick)
        deviceMaskView.addSubview(deviceHeaderView)

        // 下方：存储设备（B10: 不再显示 section header，直接显示设备列表）
        deviceScrollView = makeScrollView()
        deviceOutlineView = makeOutlineView()
        deviceOutlineView.dataSource = deviceDataSource
        deviceOutlineView.delegate = deviceDataSource
        deviceScrollView.documentView = deviceOutlineView
        // 放入遮罩容器
        deviceMaskView.addSubview(deviceScrollView)

        // A1: 拖拽添加收藏夹后的回调（重新加载 + 更新高度）
        favoritesDataSource.onFavoritesChanged = { [weak self] in
            guard let self = self else { return }
            self.favoritesOutlineView.reloadData()
            self.updateFavoritesHeight()
        }

        // 初始化标签数据
        tagFlowView.updateTags(tagsDataSource.allTags())

        // 收藏夹区高度根据收藏数量动态调整（保留最小高度）
        favoritesHeightConstraint = favoritesMaskView.heightAnchor.constraint(equalToConstant: 48)
        favoritesHeightConstraint.priority = .required

        // B10: 设备区高度根据折叠状态动态调整
        deviceHeightConstraint = deviceMaskView.heightAnchor.constraint(equalToConstant: deviceCollapsedHeight)
        deviceHeightConstraint.priority = .required

        // 标签区高度根据 wrap 行数动态调整
        tagsHeightConstraint = tagsMaskView.heightAnchor.constraint(equalToConstant: 80)
        tagsHeightConstraint.priority = .required

        let padding: CGFloat = 12

        NSLayoutConstraint.activate([
            // 任务 R3: 收藏夹遮罩区域 — 从 brandView 下方开始
            favoritesMaskView.topAnchor.constraint(equalTo: brandView.bottomAnchor, constant: padding),
            favoritesMaskView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            favoritesMaskView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            favoritesHeightConstraint,

            // B8: 标签遮罩区域 — 紧跟收藏夹下方，高度由 tagsHeightConstraint 控制
            tagsMaskView.topAnchor.constraint(equalTo: favoritesMaskView.bottomAnchor, constant: padding),
            tagsMaskView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            tagsMaskView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            tagsHeightConstraint,

            // B8: 设备遮罩区域 — 浮动在侧边栏左下角（脱离垂直 stack）
            // 不再约束 top 到 tagsMaskView.bottom，而是固定到 sidebar 底部
            deviceMaskView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            deviceMaskView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            deviceMaskView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            deviceHeightConstraint,

            // 任务 T1: 工具栏行 — 位于设备上方，水平占满
            toolBarRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            toolBarRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            toolBarRow.bottomAnchor.constraint(equalTo: deviceMaskView.topAnchor, constant: -8),
            toolBarRow.heightAnchor.constraint(equalToConstant: 28),

            // 任务 T1: 确保 tags 不会被 toolBarRow 遮挡（tags 底部 + 间距 <= toolBarRow 顶部）
            tagsMaskView.bottomAnchor.constraint(lessThanOrEqualTo: toolBarRow.topAnchor, constant: -padding / 2),

            // 收藏夹 scrollView 填满收藏夹遮罩（内边距 8pt，圆角由 mask 的 masksToBounds 裁剪）
            favoritesScrollView.topAnchor.constraint(equalTo: favoritesMaskView.topAnchor, constant: 8),
            favoritesScrollView.leadingAnchor.constraint(equalTo: favoritesMaskView.leadingAnchor, constant: 8),
            favoritesScrollView.trailingAnchor.constraint(equalTo: favoritesMaskView.trailingAnchor, constant: -8),
            favoritesScrollView.bottomAnchor.constraint(equalTo: favoritesMaskView.bottomAnchor, constant: -8),

            // 标签 flowView 填满标签遮罩（内边距 8pt）
            tagFlowView.topAnchor.constraint(equalTo: tagsMaskView.topAnchor, constant: 8),
            tagFlowView.leadingAnchor.constraint(equalTo: tagsMaskView.leadingAnchor, constant: 8),
            tagFlowView.trailingAnchor.constraint(equalTo: tagsMaskView.trailingAnchor, constant: -8),
            tagFlowView.bottomAnchor.constraint(equalTo: tagsMaskView.bottomAnchor, constant: -8),

            // B10: 设备头部 — 固定在 deviceMaskView 顶部（高度 32pt）
            deviceHeaderView.topAnchor.constraint(equalTo: deviceMaskView.topAnchor, constant: 8),
            deviceHeaderView.leadingAnchor.constraint(equalTo: deviceMaskView.leadingAnchor, constant: 8),
            deviceHeaderView.trailingAnchor.constraint(equalTo: deviceMaskView.trailingAnchor, constant: -8),
            deviceHeaderView.heightAnchor.constraint(equalToConstant: 32),

            // B10: 设备 scrollView — 位于头部下方，填满剩余空间
            // 折叠时 mask 高度=48，scrollView 高度自动为 0（被 masksToBounds 裁剪）
            deviceScrollView.topAnchor.constraint(equalTo: deviceHeaderView.bottomAnchor, constant: 0),
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

        // 展开收藏夹区域（设备不再使用 section，无需 expandItem）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.favoritesOutlineView.expandItem(SidebarSection.favorites)
            self.updateFavoritesHeight()
            self.updateDeviceHeight()
            self.updateTagsHeight()
            // B10: 初始化设备头部汇总信息
            self.updateDeviceHeaderSummary()
        }
    }

    // MARK: - Helpers

    private func makeScrollView() -> NSScrollView {
        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        // 任务 S1: 强制使用自定义细滚动条
        sv.verticalScroller = FFScroller()
        sv.scrollerStyle = .overlay
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
        // 任务 F1: 收藏夹贴左边缘（Finder 风格，无缩进）
        ov.indentationPerLevel = 0
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

    // MARK: - B10: Device Collapse/Expand

    /// B10: 切换设备栏折叠/展开状态（带 200ms 动画）
    @objc private func toggleDeviceExpanded() {
        isDeviceCollapsed.toggle()
        let targetHeight: CGFloat
        if isDeviceCollapsed {
            targetHeight = deviceCollapsedHeight
        } else {
            targetHeight = deviceCollapsedHeight + CGFloat(deviceDataSource.deviceCount) * deviceRowHeight
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            deviceHeightConstraint.animator().constant = targetHeight
            layoutSubtreeIfNeeded()
        }, completionHandler: nil)

        // 更新箭头方向
        deviceHeaderView.updateArrow(isCollapsed: isDeviceCollapsed)
    }

    /// B10: 更新设备头部汇总信息（所有设备的可用空间和总容量之和）
    private func updateDeviceHeaderSummary() {
        let (totalFree, totalTotal) = deviceDataSource.totalSpaceSummary()
        deviceHeaderView.updateSummary(free: totalFree, total: totalTotal, isCollapsed: isDeviceCollapsed)
    }

    // MARK: - Context Menu

    /// 任务 R3: 点击侧边栏顶部应用图标弹出"关于 FlowFinder"独立窗口
    @objc private func showAboutWindow() {
        let aboutWC = AboutWindowController()
        aboutWC.showWindow(nil)
        aboutWC.window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 任务 T1: 切换夜间/日间模式
    @objc private func toggleTheme() {
        let newMode = ThemeManager.shared.currentMode.toggled
        ThemeManager.shared.applyMode(newMode)
        // 更新按钮图标
        themeToggleBtn.image = NSImage(systemSymbolName: newMode.iconName, accessibilityDescription: "切换主题")
    }

    /// 任务 T1: 打开设置窗口
    @objc private func openSettings() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
    }

    /// 任务 T1: 展开侧边栏底部工具面板（查重/重命名等）
    /// TODO: 后续实现工具面板展开动画
    @objc private func toggleToolPanel() {
        // 预留：点击后展开侧边栏底部隐藏的工具面板
    }

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
        tagFlowView.updateTags(tagsDataSource.allTags())
        updateTagsHeight()
    }

    /// 添加收藏夹（供外部调用）
    func addFavorite(name: String, path: String) {
        favoritesDataSource.addFavorite(name: name, path: path)
        favoritesOutlineView.reloadData()
        updateFavoritesHeight()
    }

    /// A1: 添加收藏夹（供外部调用，如 FileListView 的右键菜单）
    /// 与 addFavorite 功能相同，提供语义化的外部入口
    func addFavoriteFromExternal(name: String, path: String) {
        addFavorite(name: name, path: path)
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
            self?.tagFlowView.updateTags(self?.tagsDataSource.allTags() ?? [])
            self?.updateTagsHeight()
        }
    }

    // MARK: - Refresh

    func refreshDevices() {
        deviceDataSource.loadDevices()
        deviceOutlineView.reloadData()
        updateDeviceHeight()
        updateDeviceHeaderSummary()
    }

    private func updateDeviceHeight() {
        // B10: 高度根据折叠状态计算
        // 折叠态：48pt（仅头部）
        // 展开态：48pt + 设备数量 * 28pt
        let height: CGFloat
        if isDeviceCollapsed {
            height = deviceCollapsedHeight
        } else {
            height = deviceCollapsedHeight + CGFloat(deviceDataSource.deviceCount) * deviceRowHeight
        }
        deviceHeightConstraint.constant = max(height, deviceCollapsedHeight)
    }

    private func updateFavoritesHeight() {
        // section 标题行（24pt）+ 收藏夹行（24pt）
        let sectionHeight: CGFloat = 24
        let rowHeight: CGFloat = 24
        let height = sectionHeight + CGFloat(favoritesDataSource.favoriteCount) * rowHeight
        favoritesHeightConstraint.constant = max(height, 48)
    }

    /// 根据标签数量和 wrap 行数动态调整 tagsMaskView 高度
    /// tagFlowView 会报告其需要的理想高度
    private func updateTagsHeight() {
        let flowHeight = tagFlowView.idealHeight(forWidth: bounds.width - 24)  // 减去左右 padding 12*2
        let height = flowHeight + 16  // 上下 padding 8*2
        tagsHeightConstraint.constant = max(height, 80)
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
        }
        // 标签右键菜单由 TagFlowView 内部处理（每个药丸自己的 menu）
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

    /// 点击「添加收藏夹」按钮的回调（A1 后收藏夹标题不再有+按钮，保留以兼容）
    var onCreateFavoriteTapped: (() -> Void)?

    @objc func handleCreateTagButton() {
        onCreateTagTapped?()
    }

    @objc func handleCreateFavoriteButton() {
        onCreateFavoriteTapped?()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // 任务 F2: 收藏夹 section 必须可展开（修复"收藏夹没有任何东西"根因）
        // 原代码 `section != .favorites` 导致收藏夹不可展开，expandItem 无效，子项不显示
        if let section = item as? SidebarSection {
            return section == .favorites
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

        // 设备：由 DeviceSidebarDataSource 子类覆盖处理（使用 DeviceCellView）
        // 基类不再处理设备 cell，避免与子类的 DeviceCellView 冲突
        if case .device = item as? SidebarItem {
            // 子类应已覆盖此方法处理设备项；若执行到这里则返回空 cell
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
            // 任务 F1: 图标贴左边缘（constant 0），Finder 风格
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
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

            // A1: 仅标签区域标题旁添加"+"按钮（收藏夹区域移除+按钮，改用拖拽添加）
            if section == .tags {
                let addButton = NSButton()
                addButton.bezelStyle = .inline
                addButton.imagePosition = .imageOnly
                addButton.isBordered = false
                addButton.contentTintColor = NSColor.secondaryLabelColor
                addButton.translatesAutoresizingMaskIntoConstraints = false
                addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")
                addButton.action = #selector(handleCreateTagButton)
                addButton.target = self
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
        // B9: 设备行单行高度 28pt
        if case .device = item as? SidebarItem {
            return 28
        }
        return 24
    }

    // MARK: - Tag Pill (药丸样式，圆角背景 + 圆点 + 文字)

    /// 标签药丸：圆角胶囊背景 + 8x8 圆点 + 文字，宽度自适应内容
    /// 虽然保持行式布局，但视觉上呈现为药丸样式（接近设计稿 ff-pill-tag）
    private func configureTagPill(cell: NSTableCellView, tag: Tag) {
        // 清除旧子视图（处理 cell 复用，避免累积）
        cell.subviews.forEach { $0.removeFromSuperview() }
        cell.textField = nil
        cell.imageView = nil

        // 药丸容器（圆角背景）
        let pillContainer = NSView()
        pillContainer.wantsLayer = true
        pillContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        pillContainer.layer?.cornerRadius = 12  // 胶囊圆角
        pillContainer.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(pillContainer)

        // 圆点（8x8）
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        pillContainer.addSubview(dot)

        // 文字
        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        pillContainer.addSubview(label)
        cell.textField = label

        // 计算文字宽度以自适应药丸宽度
        let textWidth = (tag.name as NSString).size(withAttributes: [.font: label.font!]).width

        NSLayoutConstraint.activate([
            // pillContainer 左对齐，宽度 = 左padding(10) + dot(8) + gap(6) + text + 右padding(10)
            pillContainer.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            pillContainer.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            pillContainer.widthAnchor.constraint(equalToConstant: 10 + 8 + 6 + ceil(textWidth) + 10),
            pillContainer.heightAnchor.constraint(equalToConstant: 24),

            dot.leadingAnchor.constraint(equalTo: pillContainer.leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),
        ])
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
            // B10: 同时附带 userInfo，便于新监听者按需读取
            NotificationCenter.default.post(name: .sidebarDidSelectDirectory, object: entry, userInfo: ["path": dev.path])
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

    /// A1: 收藏夹变化回调（拖拽添加后通知 SidebarView 刷新）
    var onFavoritesChanged: (() -> Void)?

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
            // 默认收藏夹 5 项（桌面/文档/下载/应用程序/主目录）
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let homeName = homePathComponentsLast(home) ?? "主目录"
            favorites = [
                FavoriteItem(name: "桌面", path: (home as NSString).appendingPathComponent("Desktop")),
                FavoriteItem(name: "文档", path: (home as NSString).appendingPathComponent("Documents")),
                FavoriteItem(name: "下载", path: (home as NSString).appendingPathComponent("Downloads")),
                FavoriteItem(name: "应用程序", path: "/Applications"),
                FavoriteItem(name: homeName, path: home),
            ]
            saveFavorites()
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    /// 辅助：从 home path 提取最后一段作为显示名（如 /Users/waltxao → waltxao）
    private func homePathComponentsLast(_ path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        return components.last
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

    // MARK: - A1: Drag & Drop Support

    /// A1: 验证拖拽操作 — 仅接受文件 URL，返回 .move 表示可接收
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // 仅接受 .fileURL 类型
        let draggingTypes = info.draggingPasteboard.types ?? []
        guard draggingTypes.contains(.fileURL) else { return [] }
        return .move
    }

    /// A1: 接受拖拽 — 解析文件 URL，仅接受文件夹，调用 addFavorite
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let items = info.draggingPasteboard.pasteboardItems else { return false }
        var addedCount = 0
        for pbItem in items {
            guard let urlData = pbItem.data(forType: .fileURL),
                  let url = URL(dataRepresentation: urlData, relativeTo: nil) else { continue }
            let path = url.path
            // 仅接受文件夹（isDirectory==true），文件拒绝
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            // 使用 URL 最后一段作为收藏夹名称
            let name = url.lastPathComponent
            addFavorite(name: name, path: path)
            addedCount += 1
        }
        if addedCount > 0 {
            onFavoritesChanged?()
            return true
        }
        return false
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

    /// 返回所有标签（供 TagFlowView 渲染）
    func allTags() -> [Tag] {
        return tags
    }
}

// MARK: - DeviceSidebarDataSource (存储设备)

private class DeviceSidebarDataSource: SidebarDataSourceBase {
    private var devices: [DeviceItem] = []
    /// B11: 设备扩展信息（文件系统类型、挂载点），key 为设备 path
    private var deviceExtendedInfo: [String: DeviceExtendedInfo] = [:]

    var deviceCount: Int { devices.count }

    override init() {
        super.init()
        loadDevices()
    }

    // MARK: - B11: 真实磁盘容量读取（statfs 系统调用）

    /// B11: 使用 statfs 读取真实磁盘容量
    /// - Parameter path: 挂载点路径
    /// - Returns: (可用空间, 总容量) 元组，失败返回 nil
    private func getDiskSpace(at path: String) -> (free: UInt64, total: UInt64)? {
        var stat = statfs()
        guard statfs(path, &stat) == 0 else { return nil }
        let free = UInt64(stat.f_bavail) * UInt64(stat.f_bsize)
        let total = UInt64(stat.f_blocks) * UInt64(stat.f_bsize)
        return (free, total)
    }

    /// B11: 获取文件系统类型（如 apfs、hfs、smbfs 等）
    private func getFileSystemType(at path: String) -> String? {
        var stat = statfs()
        guard statfs(path, &stat) == 0 else { return nil }
        // f_fstypename 是长度为 16 的 CChar 元组，需转换为 String
        return withUnsafePointer(to: &stat.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 16) {
                String(cString: $0)
            }
        }
    }

    /// B11: 判断是否为系统隐藏卷（需要跳过）
    private func isSystemHiddenVolume(name: String, path: String) -> Bool {
        // 跳过 /System/Volumes/ 下的系统卷（除 /System/Volumes/Data 本身可选保留，这里全部跳过）
        if path.hasPrefix("/System/Volumes/") {
            return true
        }
        // 跳过名字包含 Recovery 或 VM 的卷
        if name.contains("Recovery") || name.contains("VM") { return true }
        // 跳过已知的系统隐藏卷名
        let systemNames: Set<String> = [
            "Preboot", "Update", "xarts", "iSCPreboot",
            "Hardware", "SSV", "Data"
        ]
        if systemNames.contains(name) { return true }
        // 跳过 UUID 命名的快照卷（36 字符且包含连字符）
        if name.count == 36 && name.contains("-") { return true }
        return false
    }

    // MARK: - Data Loading

    func loadDevices() {
        let volumes = CoreBridge.shared.listVolumes()
        devices = []
        deviceExtendedInfo = [:]

        // 1. 始终添加主硬盘（根目录 /）
        let rootURL = URL(fileURLWithPath: "/")
        var rootName = "Macintosh HD"
        if let name = try? rootURL.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName,
           !name.isEmpty, name != Host.current().localizedName {
            rootName = name
        }
        let rootSpace = getDiskSpace(at: "/")
        let rootFsType = getFileSystemType(at: "/") ?? "apfs"
        devices.append(DeviceItem(
            name: rootName,
            path: "/",
            isRemovable: false,
            isNetwork: false,
            totalSize: rootSpace?.total ?? 0,
            freeSize: rootSpace?.free ?? 0
        ))
        deviceExtendedInfo["/"] = DeviceExtendedInfo(
            fileSystemType: rootFsType,
            mountPoint: "/",
            totalSize: rootSpace?.total ?? 0,
            freeSize: rootSpace?.free ?? 0
        )

        // 2. 添加用户主目录（作为快捷设备入口）
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let homeName = homePath.components(separatedBy: "/").last ?? "Home"
        let homeSpace = getDiskSpace(at: homePath)
        let homeFsType = getFileSystemType(at: homePath) ?? "apfs"
        devices.append(DeviceItem(
            name: homeName,
            path: homePath,
            isRemovable: false,
            isNetwork: false,
            totalSize: homeSpace?.total ?? 0,
            freeSize: homeSpace?.free ?? 0
        ))
        deviceExtendedInfo[homePath] = DeviceExtendedInfo(
            fileSystemType: homeFsType,
            mountPoint: homePath,
            totalSize: homeSpace?.total ?? 0,
            freeSize: homeSpace?.free ?? 0
        )

        // 3. 过滤并添加外部/网络卷（B11: 增强过滤系统隐藏卷）
        for vol in volumes {
            // 只保留 /Volumes/ 下的挂载卷（U盘、外接硬盘、网络驱动器等）
            guard vol.path.hasPrefix("/Volumes/") else { continue }

            let volName = vol.name

            // B11: 过滤系统隐藏卷
            if isSystemHiddenVolume(name: volName, path: vol.path) { continue }

            // B11: 使用 statfs 读取真实磁盘容量（覆盖 Rust 端的值）
            let realSpace = getDiskSpace(at: vol.path)
            let totalSize = realSpace?.total ?? vol.totalSize
            let freeSize = realSpace?.free ?? vol.freeSize
            let fsType = getFileSystemType(at: vol.path) ?? vol.fsType

            let isNetwork = vol.fsType.lowercased().contains("smb")
                || vol.fsType.lowercased().contains("nfs")
                || vol.fsType.lowercased().contains("afp")
                || fsType.lowercased().contains("smb")
                || fsType.lowercased().contains("nfs")
                || fsType.lowercased().contains("afp")

            devices.append(DeviceItem(
                name: volName,
                path: vol.path,
                isRemovable: vol.isRemovable,
                isNetwork: isNetwork,
                totalSize: totalSize,
                freeSize: freeSize
            ))
            deviceExtendedInfo[vol.path] = DeviceExtendedInfo(
                fileSystemType: fsType,
                mountPoint: vol.path,
                totalSize: totalSize,
                freeSize: freeSize
            )
        }
    }

    // MARK: - B10: 汇总信息

    /// B10: 汇总所有设备的可用空间和总容量
    func totalSpaceSummary() -> (free: UInt64, total: UInt64) {
        var totalFree: UInt64 = 0
        var totalTotal: UInt64 = 0
        for dev in devices {
            totalFree += dev.freeSize
            totalTotal += dev.totalSize
        }
        return (totalFree, totalTotal)
    }

    // MARK: - B9: 获取设备扩展信息（供 cell tooltip 使用）

    func extendedInfo(for path: String) -> DeviceExtendedInfo? {
        return deviceExtendedInfo[path]
    }

    // MARK: - NSOutlineViewDataSource (B10: 无 section，直接返回设备列表)

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // B10: 直接返回设备数量（不再有 section 包装层）
            return devices.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return SidebarItem.device(devices[index])
        }
        return ""
    }

    // MARK: - B9: 覆盖 viewFor，使用自定义 DeviceCellView

    override func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if case .device(let dev) = item as? SidebarItem {
            let cellID = NSUserInterfaceItemIdentifier("DeviceCell")
            let cell = (outlineView.makeView(withIdentifier: cellID, owner: self) as? DeviceCellView)
                ?? DeviceCellView()
            cell.identifier = cellID
            let extInfo = deviceExtendedInfo[dev.path]
            cell.configure(dev: dev, extInfo: extInfo)
            return cell
        }
        return super.outlineView(outlineView, viewFor: tableColumn, item: item)
    }
}

// MARK: - DeviceHeaderView (B10: 设备栏头部 — 汇总信息 + 折叠箭头)

/// B10: 设备栏自定义头部视图
/// - 折叠态：显示汇总信息 "X GB 可用，共 Y GB" + 向上箭头
/// - 展开态：显示汇总信息 + 向下箭头
/// - 点击整块区域切换折叠/展开
private class DeviceHeaderView: NSView {
    private let iconView = NSImageView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let arrowView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        iconView.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "存储设备")
        iconView.contentTintColor = NSColor.secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        summaryLabel.font = NSFont.systemFont(ofSize: 11)
        summaryLabel.textColor = NSColor.secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(summaryLabel)

        arrowView.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        arrowView.contentTintColor = NSColor.secondaryLabelColor
        arrowView.imageScaling = .scaleProportionallyDown
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrowView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            summaryLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            summaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            arrowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            arrowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: 12),
            arrowView.heightAnchor.constraint(equalToConstant: 12),

            summaryLabel.trailingAnchor.constraint(equalTo: arrowView.leadingAnchor, constant: -4),
        ])
    }

    /// 更新汇总信息和箭头方向
    /// - Parameters:
    ///   - free: 总可用空间
    ///   - total: 总容量
    ///   - isCollapsed: 当前是否折叠
    func updateSummary(free: UInt64, total: UInt64, isCollapsed: Bool) {
        if total == 0 {
            summaryLabel.stringValue = "无存储设备"
        } else {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useTB]
            formatter.countStyle = .file
            let freeStr = formatter.string(fromByteCount: Int64(free))
            let totalStr = formatter.string(fromByteCount: Int64(total))
            summaryLabel.stringValue = "\(freeStr) 可用，共 \(totalStr)"
        }
        updateArrow(isCollapsed: isCollapsed)
    }

    /// 更新箭头方向（折叠=向上，展开=向下）
    func updateArrow(isCollapsed: Bool) {
        let arrowName = isCollapsed ? "chevron.up" : "chevron.down"
        arrowView.image = NSImage(systemSymbolName: arrowName, accessibilityDescription: nil)
    }
}

// MARK: - DeviceCellView (B9: 设备行单行布局 + 悬停气泡)

/// B9: 设备行自定义 cell
/// - 单行布局：图标(16x16) + 设备名称(flex) + "X GB 可用"(灰色 10pt)
/// - 悬停 500ms 后显示 NSPopover 气泡（设备名、文件系统类型、挂载点、总容量、可用空间、使用率）
/// - 鼠标移出后隐藏气泡
private class DeviceCellView: NSTableCellView {
    private var trackingArea: NSTrackingArea?
    private var hoverTimer: Timer?
    private var popover: NSPopover?

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let freeField = NSTextField(labelWithString: "")

    /// 当前设备名（供 tooltip 使用）
    private var deviceName: String = ""
    /// 当前设备扩展信息（供 tooltip 使用）
    private var deviceInfo: DeviceExtendedInfo?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameField.font = NSFont.systemFont(ofSize: 11)
        nameField.textColor = NSColor.labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)

        // B9: "X GB 可用"文字（灰色 10pt）
        freeField.font = NSFont.systemFont(ofSize: 10)
        freeField.textColor = NSColor.tertiaryLabelColor
        freeField.lineBreakMode = .byTruncatingTail
        freeField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(freeField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

            freeField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            freeField.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameField.trailingAnchor.constraint(equalTo: freeField.leadingAnchor, constant: -4),
        ])
    }

    /// 配置设备行内容
    /// - Parameters:
    ///   - dev: 设备项
    ///   - extInfo: 扩展信息（文件系统类型、挂载点等，用于 tooltip）
    func configure(dev: DeviceItem, extInfo: DeviceExtendedInfo?) {
        deviceName = dev.name
        deviceInfo = extInfo

        nameField.stringValue = dev.name

        // 设备图标
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
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "设备")
            ?? NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)

        // B9: 显示 "X GB 可用"（仅显示可用空间，不显示总容量）
        if dev.totalSize > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useTB]
            formatter.countStyle = .file
            freeField.stringValue = "\(formatter.string(fromByteCount: Int64(dev.freeSize))) 可用"
        } else {
            freeField.stringValue = ""
        }
    }

    // MARK: - Tracking Area (悬停检测)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // B9: 悬停 500ms 后显示气泡
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showPopover()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        // B9: 鼠标移出，取消定时器并隐藏气泡
        hoverTimer?.invalidate()
        hoverTimer = nil
        popover?.performClose(nil)
    }

    // MARK: - Popover (悬停气泡)

    /// B9: 显示气泡，包含设备详情
    private func showPopover() {
        guard let info = deviceInfo else { return }
        // 若已有气泡先关闭
        popover?.performClose(nil)

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true

        let vc = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 130))

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        let freeStr = formatter.string(fromByteCount: Int64(info.freeSize))
        let totalStr = formatter.string(fromByteCount: Int64(info.totalSize))

        let usedPct: String
        if info.totalSize > 0 {
            let used = Double(info.totalSize - info.freeSize) / Double(info.totalSize) * 100
            usedPct = String(format: "%.1f%%", used)
        } else {
            usedPct = "—"
        }

        // 多行文本，使用 wrappingLabel
        let text = """
        设备名: \(deviceName)
        文件系统: \(info.fileSystemType)
        挂载点: \(info.mountPoint)
        总容量: \(totalStr)
        可用空间: \(freeStr)
        使用率: \(usedPct)
        """

        let textView = NSTextField(wrappingLabelWithString: text)
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.isSelectable = true
        textView.alignment = .left
        textView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        vc.view = container
        pop.contentViewController = vc
        pop.show(relativeTo: self.bounds, of: self, preferredEdge: .maxX)
        popover = pop
    }

    /// cell 复用时清理资源
    override func prepareForReuse() {
        super.prepareForReuse()
        hoverTimer?.invalidate()
        hoverTimer = nil
        popover?.performClose(nil)
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

// MARK: - TagFlowView (横向 wrap 药丸布局)

/// 设计稿 ff-sidebar-section 标签区域：药丸横向 wrap 排列
/// 布局：[section header: "标签" + "+" 按钮] + [药丸 flow wrap 区域]
/// 药丸样式：24px 高，9999px 圆角（胶囊），controlBackgroundColor 背景，8x8 圆点 + 文字
private class TagFlowView: NSView {

    // MARK: - Callbacks

    var onAddTagTapped: (() -> Void)?
    var onTagDeleted: ((String) -> Void)?
    var onTagSelected: ((Tag) -> Void)?

    // MARK: - State

    private var tags: [Tag] = []

    // MARK: - UI Elements

    private let headerLabel = NSTextField(labelWithString: "标签")
    private let addButton = NSButton()
    private let flowContainer = NSView()

    // MARK: - Layout Constants (设计稿)

    private let pillHeight: CGFloat = 24
    private let pillGap: CGFloat = 4       // 药丸之间水平+垂直间距
    private let headerHeight: CGFloat = 22
    private let dotSize: CGFloat = 8
    private let pillHPadding: CGFloat = 10
    private let pillGapIconText: CGFloat = 6

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // header label
        headerLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        headerLabel.textColor = NSColor.secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        // "+" 按钮
        addButton.bezelStyle = .inline
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")
        addButton.imagePosition = .imageOnly
        addButton.isBordered = false
        addButton.contentTintColor = NSColor.secondaryLabelColor
        addButton.target = self
        addButton.action = #selector(handleAddButton)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        // flow container（药丸容器）
        flowContainer.translatesAutoresizingMaskIntoConstraints = false
        flowContainer.wantsLayer = true
        flowContainer.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(flowContainer)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            headerLabel.heightAnchor.constraint(equalToConstant: headerHeight),

            addButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            addButton.widthAnchor.constraint(equalToConstant: 16),
            addButton.heightAnchor.constraint(equalToConstant: 16),

            flowContainer.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            flowContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            flowContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            flowContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @objc private func handleAddButton() {
        onAddTagTapped?()
    }

    // MARK: - Public API

    func updateTags(_ newTags: [Tag]) {
        self.tags = newTags
        rebuildPills()
        needsLayout = true
    }

    /// 计算指定宽度下的理想高度（供外部 updateTagsHeight 使用）
    func idealHeight(forWidth width: CGFloat) -> CGFloat {
        let headerTotal = headerHeight + 8  // header + 上下 spacing
        let flowWidth = max(width - 8, 50)  // 减去左右 padding 4*2
        let rows = computeLayout(forWidth: flowWidth)
        let flowHeight: CGFloat
        if rows.isEmpty {
            flowHeight = 0
        } else {
            flowHeight = CGFloat(rows.count) * pillHeight + CGFloat(max(rows.count - 1, 0)) * pillGap
        }
        return headerTotal + flowHeight + 8
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutPills()
    }

    /// 重建所有药丸子视图
    private func rebuildPills() {
        flowContainer.subviews.forEach { $0.removeFromSuperview() }
        for tag in tags {
            let pill = makePill(tag: tag)
            flowContainer.addSubview(pill)
        }
    }

    /// 计算每个药丸的 frame 并设置
    private func layoutPills() {
        let rows = computeLayout(forWidth: flowContainer.bounds.width)
        for (rowIdx, row) in rows.enumerated() {
            for (colIdx, frame) in row.enumerated() {
                let idx = offset(forRow: rowIdx, col: colIdx, rows: rows)
                guard idx < flowContainer.subviews.count else { continue }
                let pill = flowContainer.subviews[idx]
                pill.frame = frame
            }
        }
    }

    /// 返回每行的药丸 frame 数组（用于布局计算）
    private func computeLayout(forWidth width: CGFloat) -> [[NSRect]] {
        guard !tags.isEmpty else { return [] }
        var rows: [[NSRect]] = []
        var currentRow: [NSRect] = []
        var currentX: CGFloat = 0
        let gap = pillGap
        for tag in tags {
            let pillWidth = pillWidth(for: tag)
            if currentX + pillWidth > width && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                currentX = 0
            }
            let frame = NSRect(x: currentX, y: 0, width: pillWidth, height: pillHeight)
            currentRow.append(frame)
            currentX += pillWidth + gap
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        // 设置每行的 y 坐标（从顶部开始，y 向下递增）
        var result: [[NSRect]] = []
        for (rowIdx, row) in rows.enumerated() {
            let y = CGFloat(rowIdx) * (pillHeight + pillGap)
            let alignedRow = row.map { NSRect(x: $0.origin.x, y: y, width: $0.size.width, height: pillHeight) }
            result.append(alignedRow)
        }
        return result
    }

    /// 计算单个药丸宽度：左padding + dot + gap + text + 右padding
    private func pillWidth(for tag: Tag) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let textWidth = (tag.name as NSString).size(withAttributes: [.font: font]).width
        return pillHPadding + dotSize + pillGapIconText + ceil(textWidth) + pillHPadding
    }

    /// 根据 row/col 计算在 tags 数组中的偏移（按行优先顺序）
    private func offset(forRow row: Int, col: Int, rows: [[NSRect]]) -> Int {
        var offset = 0
        for i in 0..<row {
            offset += rows[i].count
        }
        return offset + col
    }

    // MARK: - Pill Creation

    private func makePill(tag: Tag) -> NSView {
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        pill.layer?.cornerRadius = pillHeight / 2  // 胶囊圆角
        // 用 identifier 存储 tag.id（NSGestureRecognizer 无 representedObject 属性）
        pill.identifier = NSUserInterfaceItemIdentifier(tag.id)

        // 圆点
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = dotSize / 2

        // 文字
        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail

        pill.addSubview(dot)
        pill.addSubview(label)

        // 用 autoresizing 而非约束（因为 pill.frame 由 layoutPills 手动设置）
        dot.autoresizingMask = []
        label.autoresizingMask = []

        // 设置 dot 和 label 的 frame（相对于 pill）
        let pillW = pillWidth(for: tag)
        dot.frame = NSRect(x: pillHPadding, y: (pillHeight - dotSize) / 2, width: dotSize, height: dotSize)
        label.frame = NSRect(x: pillHPadding + dotSize + pillGapIconText,
                             y: (pillHeight - 16) / 2,
                             width: pillW - pillHPadding * 2 - dotSize - pillGapIconText,
                             height: 16)

        // 右键菜单（删除标签）
        let menu = NSMenu()
        let mi = NSMenuItem(title: "删除标签", action: #selector(handleDeleteTag(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = tag.id
        menu.addItem(mi)
        pill.menu = menu

        // 点击选择（tag.id 通过 pill.identifier 传递，NSGestureRecognizer 无 representedObject）
        let click = NSClickGestureRecognizer(target: self, action: #selector(handlePillClick(_:)))
        pill.addGestureRecognizer(click)

        return pill
    }

    @objc private func handleDeleteTag(_ sender: NSMenuItem) {
        guard let tagId = sender.representedObject as? String else { return }
        onTagDeleted?(tagId)
    }

    @objc private func handlePillClick(_ sender: NSClickGestureRecognizer) {
        guard let tagId = sender.view?.identifier?.rawValue else { return }
        if let tag = tags.first(where: { $0.id == tagId }) {
            onTagSelected?(tag)
        }
    }
}
