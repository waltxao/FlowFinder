import Cocoa

// MARK: - Sidebar Notifications

extension Notification.Name {
    static let sidebarDidSelectDirectory = Notification.Name("sidebarDidSelectDirectory")
    static let paneDidActivate = Notification.Name("paneDidActivate")
    /// 任务 F11-8: 侧边栏标签点击筛选通知（问题3）。
    /// object 携带被点击的 Tag，MainWindowController 据此设置当前活动面板的 tagFilter
    static let sidebarDidSelectTag = Notification.Name("sidebarDidSelectTag")
    /// 任务 F11-8: 活动面板/标签筛选变化通知，侧边栏据此更新标签高亮
    static let paneTagFilterChanged = Notification.Name("paneTagFilterChanged")
    /// 任务 F11-11: 侧边栏工具面板入口通知（C1）
    /// 工具面板三个入口（查重 / 批量重命名 / AI 工具）点击后，由 SidebarView 发送对应通知，
    /// MainWindowController 及活动面板视图据此打开对应窗口或执行操作。
    /// - sidebarDidRequestDedupScan: 查重扫描，MainWindowController 打开 DuplicateScanWindowController
    /// - sidebarDidRequestBatchRename: 批量重命名，MainWindowController 转发 menuBatchRename
    /// - sidebarDidRequestAITools: AI 工具，活动面板视图触发 generateAITags
    static let sidebarDidRequestDedupScan = Notification.Name("sidebarDidRequestDedupScan")
    static let sidebarDidRequestBatchRename = Notification.Name("sidebarDidRequestBatchRename")
    static let sidebarDidRequestAITools = Notification.Name("sidebarDidRequestAITools")
}

// MARK: - DeviceExtendedInfo (设备扩展信息，用于悬停气泡)

/// 设备扩展信息：存储文件系统类型、挂载点等，供 tooltip 显示
/// 任务 F10-3: 改为 internal 可见性，供 MainWindowController 设备浮层复用（v0.6.6）
struct DeviceExtendedInfo {
    let fileSystemType: String
    let mountPoint: String
    let totalSize: UInt64
    let freeSize: UInt64
}

// MARK: - FFFNoDisclosureOutlineView

/// 隐藏系统 disclosure triangle 的 NSOutlineView 子类
/// 任务修复：收藏夹折叠箭头必须完全隐藏（问题1）
/// 系统 NSOutlineView 会自动绘制展开三角形（disclosure triangle），
/// 仅隐藏 cell 内部自定义 imageView 无效，需重写 frameOfOutlineCell 返回零矩形，
/// 使系统在布局时不为 disclosure triangle 分配空间，从而完全不绘制。
private class FFFNoDisclosureOutlineView: NSOutlineView {
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        return .zero  // 返回零矩形，系统不绘制展开三角形
    }
    // 彻底禁用焦点环：阻止 outlineView 成为 key view，
    // 消除点击收藏夹项目时整个模块外出现的蓝色边框（focusRingType=.none 在部分场景下仍会绘制）
    override var canBecomeKeyView: Bool {
        return false
    }
    // 消除 cell 左侧额外偏移，使图标最左边缘与标题文字最左边缘对齐
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        // NSOutlineView 默认在第一列左侧有约 6-8pt 偏移（即使 indentationPerLevel=0）
        // 将 cell frame 的 origin.x 移到最左边缘，宽度补偿
        if column == 0 {
            let offsetX = frame.origin.x
            frame.origin.x = 0
            frame.size.width += offsetX
        }
        return frame
    }
}

// MARK: - SidebarView

class SidebarView: NSView {
    /// 任务 R3: 侧边栏顶部应用图标 + FlowFinder 文字（红绿灯下方）
    private var brandView: NSView!
    /// 任务 R3: 应用图标视图（用于点击弹出关于对话框）
    private var brandIconView: NSImageView!
    /// 任务 T1: 工具栏行（夜间切换 + 设置 + 工具）
    /// 任务 F10-3: 设备区域已移出侧边栏（浮动在窗口左下角），toolBarRow 现位于标签下方
    private var toolBarRow: NSStackView!
    /// 任务 T1: 主题切换按钮（用于切换图标）
    private var themeToggleBtn: NSButton!

    private var favoritesOutlineView: NSOutlineView!
    /// 任务 F10-5: 标签视图（垂直纵向排列：圆点 + 完整标签名，每行一个）（v0.6.6）
    private var tagFlowView: TagFlowView!
    /// 外置标题（访达风格：灰色小字紧贴左侧）
    private var favoritesTitleLabel: NSTextField!
    private var tagsTitleLabel: NSTextField!
    /// 标签标题旁"+"按钮
    private var tagsAddButton: NSButton!
    private let favoritesDataSource = FavoritesSidebarDataSource()
    private let tagsDataSource = TagsSidebarDataSource()
    private var favoritesHeightConstraint: NSLayoutConstraint!
    private var tagsHeightConstraint: NSLayoutConstraint!

    // v0.6.9: 侧边栏底部工具按钮，点击后在操作区弹出 ToolOverlayView 覆盖页
    /// 工具按钮引用（用于切换激活态 contentTintColor）
    private var toolBtn: NSButton!
    /// 工具面板当前是否展开
    private var isToolPanelExpanded: Bool = false

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
        // 任务 F6: 应用图标 8pt 圆角矩形包裹（v0.6.5），使用超椭圆
        brandIconView.wantsLayer = true
        brandIconView.applySquircleCornerRadius(8)
        brandIconView.layer?.masksToBounds = true
        brandIconView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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

        // 访达风格：标题下方直接显示内容，无白色圆角卡片背景
        favoritesTitleLabel = makeSectionTitleLabel("我的收藏")
        addSubview(favoritesTitleLabel)

        tagsTitleLabel = makeSectionTitleLabel("标签")
        addSubview(tagsTitleLabel)

        tagsAddButton = NSButton()
        tagsAddButton.bezelStyle = .inline
        tagsAddButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")
        tagsAddButton.imagePosition = .imageOnly
        tagsAddButton.isBordered = false
        tagsAddButton.contentTintColor = NSColor.secondaryLabelColor
        tagsAddButton.target = self
        tagsAddButton.action = #selector(showCreateTagDialog)
        tagsAddButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagsAddButton)

        // 任务 F10-3: 设备区域已移出侧边栏，改为 MainWindowController 的浮动浮层（v0.6.6）
        // 故 deviceMaskView 不再在此创建

        // 任务 T1: 工具栏行（夜间切换 + 设置 + 工具），位于标签下方
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
        // 任务 F11-11: 保存引用以便切换激活态（C1）
        self.toolBtn = toolBtn

        // 收藏夹区域：直接使用 OutlineView，不套 NSScrollView（避免 ClipView 裁剪内容）
        favoritesOutlineView = makeOutlineView()
        favoritesOutlineView.dataSource = favoritesDataSource
        favoritesOutlineView.delegate = favoritesDataSource
        // A1: 注册拖拽类型 — 支持拖拽文件/文件夹到收藏夹
        favoritesOutlineView.registerForDraggedTypes([.fileURL])
        // 右键菜单（动态：收藏夹显示「移除收藏」）
        let favoritesMenu = NSMenu()
        favoritesMenu.delegate = self
        favoritesOutlineView.menu = favoritesMenu
        favoritesOutlineView.translatesAutoresizingMaskIntoConstraints = false
        // 直接放入侧边栏（访达风格：无圆角卡片背景，无滚动容器）
        addSubview(favoritesOutlineView)

        // 任务 F10-5: 标签区域 - 垂直纵向排列（圆点 + 完整标签名，每行一个）（v0.6.6）
        tagFlowView = TagFlowView()
        tagFlowView.translatesAutoresizingMaskIntoConstraints = false
        tagFlowView.onAddTagTapped = { [weak self] in
            self?.showCreateTagDialog()
        }
        tagFlowView.onTagDeleted = { [weak self] tagId in
            self?.tagsDataSource.removeTag(id: tagId)
            self?.tagFlowView.updateTags(self?.tagsDataSource.allTags() ?? [])
        }
        // 任务 F11-8: 标签点击 -> 发送通知，由 MainWindowController 设置当前活动面板的 tagFilter（问题3）
        tagFlowView.onTagSelected = { [weak self] tag in
            guard self != nil else { return }
            NotificationCenter.default.post(name: .sidebarDidSelectTag, object: tag)
        }
        addSubview(tagFlowView)

        // 任务 F11-8: 监听面板标签筛选变化，更新标签行高亮（当前筛选的标签高亮显示）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePaneTagFilterChanged(_:)),
            name: .paneTagFilterChanged, object: nil
        )

        // 任务 F10-3: 设备区域相关视图（deviceHeaderView/deviceScrollView/deviceOutlineView）
        // 已迁移至 MainWindowController 的 createDevicePanel 浮层，此处不再创建

        // A1: 拖拽添加收藏夹后的回调（重新加载 + 更新高度）
        favoritesDataSource.onFavoritesChanged = { [weak self] in
            guard let self = self else { return }
            self.favoritesOutlineView.reloadData()
            self.updateFavoritesHeight()
        }

        // 初始化标签数据
        tagFlowView.updateTags(tagsDataSource.allTags())

        // 收藏夹区高度根据收藏数量动态调整（保留最小高度）
        favoritesHeightConstraint = favoritesOutlineView.heightAnchor.constraint(equalToConstant: 48)
        favoritesHeightConstraint.priority = .required

        // 任务 F10-5: 标签区高度根据标签行数动态调整（垂直布局）
        tagsHeightConstraint = tagFlowView.heightAnchor.constraint(equalToConstant: 80)
        tagsHeightConstraint.priority = .required

        // 任务 F10-3: deviceHeightConstraint 已随设备区域迁移至 MainWindowController 浮层（v0.6.6）

        let padding: CGFloat = 12

        NSLayoutConstraint.activate([
            // 收藏夹标题（紧跟 brandView 下方，与收藏夹图标左对齐）
            favoritesTitleLabel.topAnchor.constraint(equalTo: brandView.bottomAnchor, constant: padding),
            favoritesTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            favoritesTitleLabel.heightAnchor.constraint(equalToConstant: 16),

            // 收藏夹内容（标题下方 12pt 间距，避免标题与首项重叠，无卡片背景，高度自适应全部列出）
            favoritesOutlineView.topAnchor.constraint(equalTo: favoritesTitleLabel.bottomAnchor, constant: 12),
            favoritesOutlineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            favoritesOutlineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            favoritesHeightConstraint,

            // 标签标题（收藏夹下方 16pt 区块间距，与收藏夹标题左对齐）
            tagsTitleLabel.topAnchor.constraint(equalTo: favoritesOutlineView.bottomAnchor, constant: 16),
            tagsTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            tagsTitleLabel.heightAnchor.constraint(equalToConstant: 16),

            // "+" 按钮与标签标题同行右侧
            tagsAddButton.centerYAnchor.constraint(equalTo: tagsTitleLabel.centerYAnchor),
            tagsAddButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding - 4),
            tagsAddButton.widthAnchor.constraint(equalToConstant: 16),
            tagsAddButton.heightAnchor.constraint(equalToConstant: 16),

            // 标签内容（标题下方直接显示，无卡片背景）
            tagFlowView.topAnchor.constraint(equalTo: tagsTitleLabel.bottomAnchor, constant: 4),
            tagFlowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            tagFlowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            tagsHeightConstraint,

            // 工具栏行
            toolBarRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            toolBarRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            toolBarRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            toolBarRow.heightAnchor.constraint(equalToConstant: 28),
        ])

        // 任务 F10-3: 卷挂载/卸载监听已迁移至 MainWindowController（设备浮层负责刷新）（v0.6.6）

        // 收藏夹无 section 层级，直接显示收藏项列表，无需 expandItem
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateFavoritesHeight()
            self.updateTagsHeight()
        }
        // 监听标签数据源刷新通知，更新标签显示
        NotificationCenter.default.addObserver(self, selector: #selector(refreshTagDisplay), name: NSNotification.Name("SidebarTagsDidRefresh"), object: nil)

        // v0.6.9: 监听工具面板状态同步通知（覆盖页关闭时由 MainWindowController 回传状态）
        // 避免 isToolPanelExpanded 与实际显示状态不同步导致需点击两次才能重新打开
        NotificationCenter.default.addObserver(self, selector: #selector(handleToolPanelStateSync(_:)), name: NSNotification.Name("SidebarToolPanelDidToggle"), object: nil)

        // 监听主题变更，更新品牌图标背景色
        ThemeManager.shared.onModeChanged = { [weak self] _ in
            self?.brandIconView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            self?.themeToggleBtn.image = NSImage(systemSymbolName: ThemeManager.shared.currentMode.iconName, accessibilityDescription: "切换主题")
        }
    }

    // MARK: - Helpers

    /// 创建外置标题 Label（灰色小字，访达风格）
    private func makeSectionTitleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeScrollView() -> NSScrollView {
        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = false
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
        let ov = FFFNoDisclosureOutlineView()
        ov.allowsMultipleSelection = false
        ov.headerView = nil  // 无表头
        // 收藏夹项目行高 28pt
        ov.rowHeight = 28
        // 任务 F1: 收藏夹贴左边缘（Finder 风格，无缩进）
        ov.indentationPerLevel = 0
        // 行间距：水平无间距，垂直 4pt 间距，保证行间留白
        ov.intercellSpacing = NSSize(width: 0, height: 4)
        // 选中样式：regular（实心高亮，确保收藏夹选中高亮框正确显示）
        ov.selectionHighlightStyle = .regular
        ov.backgroundColor = NSColor.clear
        // 禁止默认选中，避免启动时出现高亮
        ov.allowsEmptySelection = true
        ov.deselectAll(nil)
        // 禁用焦点框（蓝色边框），NSOutlineView 获得键盘焦点时不再显示蓝色 ring
        ov.focusRingType = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarItem"))
        column.width = 200
        ov.addTableColumn(column)
        ov.outlineTableColumn = column
        return ov
    }

    // 任务 F10-3: 设备区域已迁移至 MainWindowController，SidebarView 不再监听卷挂载/卸载通知（v0.6.6）
    // 原 deinit removeObserver、handleVolumeMount/Unmount、toggleDeviceExpanded、updateDeviceHeaderSummary
    // 已随设备浮层迁移

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
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    /// v0.6.9: 点击工具按钮直接触发 ToolOverlayView 覆盖页（不再展开侧边栏内联面板）
    /// 通知 MainWindowController 在当前激活操作区显示工具选择覆盖页
    @objc private func toggleToolPanel() {
        isToolPanelExpanded.toggle()

        // 切换按钮激活态外观：展开时强调色，收起时次级标签色
        toolBtn.contentTintColor = isToolPanelExpanded ? .controlAccentColor : .secondaryLabelColor

        // 通知 MainWindowController 显示/隐藏 ToolOverlayView + 设备浮层联动
        NotificationCenter.default.post(
            name: NSNotification.Name("SidebarToolPanelDidToggle"),
            object: nil,
            userInfo: ["isExpanded": isToolPanelExpanded]
        )
    }

    /// v0.6.9: 同步工具面板状态（覆盖页通过关闭按钮/Esc 关闭时，MainWindowController 回传 isExpanded=false）
    /// 避免 isToolPanelExpanded 与实际显示状态不同步，导致下次点击需 toggle 两次才能重新打开
    @objc private func handleToolPanelStateSync(_ notification: Notification) {
        guard let isExpanded = notification.userInfo?["isExpanded"] as? Bool else { return }
        // 仅同步状态不同步的情况（覆盖页关闭时回传 false）
        if isToolPanelExpanded != isExpanded {
            isToolPanelExpanded = isExpanded
            toolBtn.contentTintColor = isToolPanelExpanded ? .controlAccentColor : .secondaryLabelColor
        }
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

    /// 标签数据源刷新后更新标签流视图显示
    @objc private func refreshTagDisplay() {
        tagFlowView.updateTags(tagsDataSource.allTags())
        updateTagsHeight()
    }

    /// 任务 F11-8: 处理面板标签筛选变化通知，更新标签行高亮。
    /// userInfo["tagFilter"] 为当前活动面板的 tagFilter（Tag 或 nil），用于高亮对应标签行。
    @objc private func handlePaneTagFilterChanged(_ notification: Notification) {
        let tagFilter = notification.userInfo?["tagFilter"] as? Tag
        tagFlowView.setHighlightedTagId(tagFilter?.id)
    }

    /// 任务 F11-8: 清理通知观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
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

    /// 返回侧边栏所有标签（供 TagSelectorDialog 使用，确保文件标签对话框显示用户自定义标签）
    func allSidebarTags() -> [Tag] {
        return tagsDataSource.allTags()
    }

    // MARK: - Create Tag Dialog

    @objc private func showCreateTagDialog() {
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

    // 任务 F10-3: 设备刷新逻辑（refreshDevices/updateDeviceHeight）已迁移至 MainWindowController 浮层（v0.6.6）

    private func updateFavoritesHeight() {
        // 仅收藏夹行（28pt），无卡片内边距
        let rowHeight: CGFloat = 28
        let height = CGFloat(favoritesDataSource.favoriteCount) * rowHeight
        favoritesHeightConstraint.constant = max(height, 28)
    }

    /// 根据 tagFlowView 报告的理想高度调整标签区高度
    private func updateTagsHeight() {
        let flowHeight = tagFlowView.idealHeight(forWidth: bounds.width - 24)
        tagsHeightConstraint.constant = max(flowHeight, 30)
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
        // 任务 F10-5: 标签右键菜单由 TagFlowView 内部处理（每个标签行自己的 menu）
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

/// 任务 F10-3: 改为 internal 可见性，因 DeviceSidebarDataSource 需被 MainWindowController 复用（v0.6.6）
class SidebarDataSourceBase: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

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
        // 无 section 层级，收藏项均为叶子节点
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }

    // MARK: - Collapse Control

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        return false
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

        // 默认布局：图标 + 文字（收藏夹项）
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
            // 图标贴左边缘（constant 0），Finder 风格
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        // 收藏夹项：文本填充至右侧
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true

        switch item as? SidebarItem {
        case .favorite(let fav):
            textField.stringValue = fav.name
            // 任务 F10-4: 修正 F4 错误 - 收藏夹改回彩色真实图标（v0.6.6）
            // F4 错误地改为蓝色模板 SF Symbols，应使用 NSWorkspace 真实位置图标
            // 放大对齐访达 20pt，contentTintColor = nil 保留彩色（移除 F4 的 controlAccentColor）
            let workspaceIcon = NSWorkspace.shared.icon(forFile: fav.path)
            workspaceIcon.size = NSSize(width: 20, height: 20)
            imageView.image = workspaceIcon
            imageView.contentTintColor = nil

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
        // 收藏夹项目行 28pt
        return 28
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
        let pillContainer = SquircleMaskedView()
        pillContainer.wantsLayer = true
        pillContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        pillContainer.squircleRadius = 12  // 胶囊圆角（超椭圆）
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
        // 无 section 层级：root 直接返回收藏项数量
        if item == nil {
            return favorites.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        // 无 section 层级：root 直接返回收藏项
        if item == nil {
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
        // 监听文件标签变更通知，自动刷新侧边栏标签列表
        NotificationCenter.default.addObserver(self, selector: #selector(handleFileTagsChange), name: NSNotification.Name("FileTagsDidChange"), object: nil)
    }

    /// 文件标签变更时重新加载侧边栏标签列表并通知 SidebarView 刷新显示
    @objc func handleFileTagsChange(_ notification: Notification) {
        // 如果通知携带了标签数据，将其添加到侧边栏标签列表（同步到 UserDefaults）
        if let tags = notification.userInfo?["tags"] as? [Tag] {
            for tag in tags {
                if !self.tags.contains(where: { $0.name == tag.name }) {
                    self.tags.append(tag)
                }
            }
            saveTags()
        } else {
            loadTags()
        }
        // 通知 SidebarView 刷新显示
        NotificationCenter.default.post(name: NSNotification.Name("SidebarTagsDidRefresh"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

/// 任务 F10-3: 改为 internal 可见性，供 MainWindowController 设备浮层复用（v0.6.6）
/// 设备数据源：负责 statfs 读取磁盘容量、过滤隐藏卷、提供设备列表
class DeviceSidebarDataSource: SidebarDataSourceBase {
    /// 任务 F10-3: 改为 internal，供浮层读取设备列表（v0.6.6）
    private(set) var devices: [DeviceItem] = []
    /// B11: 设备扩展信息（文件系统类型、挂载点），key 为设备 path
    /// 任务 F10-3: 改为 internal，供浮层读取扩展信息（v0.6.6）
    private(set) var deviceExtendedInfo: [String: DeviceExtendedInfo] = [:]

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
/// 任务 F10-3: 改为 internal 可见性，供 MainWindowController 设备浮层复用（v0.6.6）
class DeviceHeaderView: NSView {
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
            // 紧凑格式：避免侧边栏宽度不足时截断
            summaryLabel.stringValue = "\(freeStr) 可用 / \(totalStr)"
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
/// 任务 F10-3: 改为 internal 可见性，供 MainWindowController 设备浮层复用（v0.6.6）
class DeviceCellView: NSTableCellView {
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
        // 修复：裁剪子视图内容到 cell 边界内，防止文字溢出到相邻行
        wantsLayer = true
        layer?.masksToBounds = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameField.font = NSFont.systemFont(ofSize: 11)
        nameField.textColor = NSColor.labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.cell?.wraps = false
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // 任务修复：nameField 低拥抱优先级，允许被压缩以优先满足 freeField 布局（问题2）
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)

        // B9: "X GB 可用"文字（灰色 10pt）
        freeField.font = NSFont.systemFont(ofSize: 10)
        freeField.textColor = NSColor.tertiaryLabelColor
        freeField.lineBreakMode = .byTruncatingTail
        freeField.cell?.truncatesLastVisibleLine = true
        freeField.cell?.wraps = false
        freeField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        // 任务修复：freeField 高拥抱优先级，防止被拉伸导致与 nameField 文字重叠（问题2）
        freeField.setContentHuggingPriority(.required, for: .horizontal)
        freeField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(freeField)

        // 任务修复：nameField 尾部约束优先级降为 750，避免侧边栏变窄时与 widthAnchor>=30
        // 及 freeField 约束冲突，Auto Layout 打破约束导致文字溢出重叠（问题2）
        let nameTrailingConstraint = nameField.trailingAnchor.constraint(equalTo: freeField.leadingAnchor, constant: -4)
        nameTrailingConstraint.priority = .defaultHigh  // 750

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

            freeField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            freeField.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameTrailingConstraint,
            // 防止 nameField 被压缩到 0
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
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

// MARK: - TagFlowView (垂直纵向排列，圆点 + 完整标签名)

/// 任务 F10-5: 标签模块改为垂直纵向排列（v0.6.6）
/// 每行一个标签：8x8 彩色圆点 + 13pt 完整标签名，行高 28pt
/// 对齐访达侧边栏项目高度，标签名完整显示不截断，行宽填满侧边栏
/// 布局：[section header: "标签" + "+" 按钮] + [垂直标签行列表]
private class TagFlowView: NSView {

    // MARK: - Callbacks

    var onAddTagTapped: (() -> Void)?
    var onTagDeleted: ((String) -> Void)?
    var onTagSelected: ((Tag) -> Void)?

    // MARK: - State

    private var tags: [Tag] = []
    /// 任务 F11-8: 当前高亮的标签 id（来自活动面板的 tagFilter），nil 表示无高亮
    private var highlightedTagId: String?

    // MARK: - UI Elements

    /// 标签行垂直列表容器（NSStackView，vertical）
    private let listContainer: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.alignment = .leading          // 行左对齐
        sv.spacing = 6                   // 药丸行间距 6pt
        sv.distribution = .fill           // 各行按内容填充
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.wantsLayer = true
        sv.layer?.backgroundColor = NSColor.clear.cgColor
        return sv
    }()

    // MARK: - Layout Constants (药丸样式)

    /// 行高 22pt（紧凑药丸）
    private let rowHeight: CGFloat = 22
    /// 药丸高度 20pt
    private let pillHeight: CGFloat = 20
    private let dotSize: CGFloat = 7
    /// 药丸内部水平内边距
    private let pillPaddingH: CGFloat = 8
    /// 圆点与文字间距
    private let dotLabelGap: CGFloat = 5

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

        // 标签行列表容器直接填满整个视图（标题已外置到卡片上方）
        addSubview(listContainer)

        NSLayoutConstraint.activate([
            listContainer.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            listContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            listContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            listContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
        ])
    }

    // MARK: - Public API

    func updateTags(_ newTags: [Tag]) {
        self.tags = newTags
        rebuildRows()
    }

    /// 任务 F11-8: 设置当前高亮标签 id（来自活动面板 tagFilter），并重建行以应用高亮样式。
    /// nil 表示无高亮（取消筛选）。点击同一标签切换筛选时由 MainWindowController 负责置 nil。
    func setHighlightedTagId(_ tagId: String?) {
        // 仅在变化时重建，避免无谓刷新
        guard highlightedTagId != tagId else { return }
        highlightedTagId = tagId
        rebuildRows()
    }

    /// 计算指定宽度下的理想高度（供外部 updateTagsHeight 使用）
    /// 无 header：高度 = 行数 × 28pt
    func idealHeight(forWidth width: CGFloat) -> CGFloat {
        let rowsHeight = CGFloat(tags.count) * rowHeight
        let spacing = CGFloat(max(tags.count - 1, 0)) * 6
        return rowsHeight + spacing
    }

    // MARK: - Rows Rebuild

    /// 重建所有标签行子视图
    private func rebuildRows() {
        // 移除旧的 arrangedSubviews
        listContainer.arrangedSubviews.forEach {
            listContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for tag in tags {
            let pill = makeTagRow(tag: tag)
            listContainer.addArrangedSubview(pill)
            // 药丸宽度由内容自适应，高度固定，左边缘贴 listContainer leading
            pill.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            pill.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor).isActive = true
            // 大目录优化：限制药丸不超过容器宽度，使长标签名以省略号截断而非被裁剪
            pill.trailingAnchor.constraint(lessThanOrEqualTo: listContainer.trailingAnchor).isActive = true
        }
    }

    // MARK: - Tag Row Creation (药丸样式：胶囊形 + 浅色底 + 圆点 + 文字)

    /// 创建药丸标签行
    /// 药丸：胶囊形（左右半圆），背景为标签色的浅色底，内含圆点 + 文字
    /// 药丸宽度由内容自适应，左边缘与收藏夹图标对齐
    private func makeTagRow(tag: Tag) -> NSView {
        let isHighlighted = (highlightedTagId == tag.id)
        let tagColor = NSColor(hex: tag.color) ?? .systemBlue

        // 药丸容器：胶囊形，内容自适应宽度
        let pill = SquircleMaskedView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.identifier = NSUserInterfaceItemIdentifier(tag.id)
        pill.wantsLayer = true
        // 浅色底（标签色的淡色版本），高亮态加深
        let bgAlpha: CGFloat = isHighlighted ? 0.25 : 0.15
        pill.layer?.backgroundColor = tagColor.withAlphaComponent(bgAlpha).cgColor
        // 胶囊形：圆角 = 高度的一半，形成左右半圆（超椭圆）
        pill.squircleRadius = pillHeight / 2

        // 圆点（8x8，tag.color）
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tagColor.cgColor
        dot.layer?.cornerRadius = dotSize / 2
        dot.translatesAutoresizingMaskIntoConstraints = false

        // 文字（12pt；高亮态加粗）
        let label = NSTextField(labelWithString: tag.name)
        label.font = isHighlighted
            ? NSFont.boldSystemFont(ofSize: 12)
            : NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        pill.addSubview(dot)
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            // 药丸内部布局：圆点左 padding → 圆点 → gap → 文字 → 右 padding
            // 药丸宽度由这些约束 + label 内在宽度自动确定
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: pillPaddingH),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: dotLabelGap),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -pillPaddingH),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])

        // 右键菜单（删除标签）
        let menu = NSMenu()
        let mi = NSMenuItem(title: "删除标签", action: #selector(handleDeleteTag(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = tag.id
        menu.addItem(mi)
        pill.menu = menu

        // 点击选择
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleRowClick(_:)))
        pill.addGestureRecognizer(click)

        return pill
    }

    @objc private func handleDeleteTag(_ sender: NSMenuItem) {
        guard let tagId = sender.representedObject as? String else { return }
        onTagDeleted?(tagId)
    }

    @objc private func handleRowClick(_ sender: NSClickGestureRecognizer) {
        guard let tagId = sender.view?.identifier?.rawValue else { return }
        if let tag = tags.first(where: { $0.id == tagId }) {
            onTagSelected?(tag)
        }
    }
}
