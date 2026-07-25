import Cocoa

// MARK: - OpaqueContainerView（设置窗口专用）

/// 重写 isOpaque 返回 true 的 NSView 子类，与 MainWindowController 同架构。
/// 让窗口服务器捕获鼠标事件，玻璃视觉效果由 NSGlassEffectView 子视图绘制。
private class SettingsOpaqueContainerView: NSView {
    override var isOpaque: Bool { return true }
}

// MARK: - SettingsSection

/// 设置侧边栏分区枚举
enum SettingsSection: Int, CaseIterable {
    case general = 0      // 通用
    case appearance = 1   // 外观
    case fileManage = 2   // 文件管理
    case smb = 3          // 网络存储 SMB
    case shortcuts = 4    // 快捷键
    case about = 5        // 关于

    var title: String {
        switch self {
        case .general:      return "通用"
        case .appearance:   return "外观"
        case .fileManage:   return "文件管理"
        case .smb:          return "网络存储"
        case .shortcuts:    return "快捷键"
        case .about:        return "关于"
        }
    }

    var iconName: String {
        switch self {
        case .general:      return "gearshape"
        case .appearance:   return "paintbrush"
        case .fileManage:   return "folder"
        case .smb:          return "network"
        case .shortcuts:    return "keyboard"
        case .about:        return "info.circle"
        }
    }
}

// MARK: - SettingsWindowController

/// 设置窗口控制器：左侧边栏（180pt，6 分区）+ 右侧滚动内容区
/// 窗口级玻璃架构：OpaqueContainerView + NSGlassEffectView + mainContainer（参照 MainWindowController）
public class SettingsWindowController: NSWindowController {

    public static let shared = SettingsWindowController()

    // MARK: - UI 引用

    private var sidebarTableView: NSTableView!
    private var sidebarScrollView: NSScrollView!
    private var contentContainer: NSView!
    /// 当前显示的内容视图（侧边栏选中项切换时替换）
    private var currentContentView: NSView?
    /// 玻璃背景视图（macOS 26+ NSGlassEffectView，旧版 NSVisualEffectView）
    private var glassEffectView: NSView?
    /// 快捷键分区数据源（强引用持有，避免被释放导致 tableView 失去 dataSource）
    private var shortcutsDataSource: ShortcutsDataSource?

    // MARK: - 数据

    private let sidebarItems: [SettingsSection] = SettingsSection.allCases

    // MARK: - Init

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        self.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }

        // 窗口透明以支持玻璃效果
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        // 左侧边栏（180pt）
        sidebarScrollView = makeSidebarScrollView()
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false

        // 侧边栏玻璃背景（FFGlassView .panel .sidebar）
        let sidebarGlass = FFGlassView(level: .panel, cornerRadius: 0, material: .sidebar)
        sidebarGlass.translatesAutoresizingMaskIntoConstraints = false
        sidebarGlass.addSubview(sidebarScrollView)

        // 右侧内容区容器（滚动）
        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor

        // 主分栏视图
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor
        splitView.addArrangedSubview(sidebarGlass)
        splitView.addArrangedSubview(contentContainer)

        // 主容器（透明背景以透出玻璃效果）
        let mainContainer = NSView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        mainContainer.layer?.backgroundColor = NSColor.clear.cgColor
        mainContainer.addSubview(splitView)
        mainContainer.appearance = NSApp.effectiveAppearance

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
        ])

        // 窗口级玻璃架构（参照 MainWindowController）
        if #available(macOS 26.0, *) {
            let containerView = SettingsOpaqueContainerView()
            containerView.wantsLayer = true
            containerView.translatesAutoresizingMaskIntoConstraints = false

            let glassView = NSGlassEffectView()
            glassView.style = .clear
            glassView.cornerRadius = 0
            glassView.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(glassView)
            containerView.addSubview(mainContainer)

            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                glassView.topAnchor.constraint(equalTo: containerView.topAnchor),
                glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                mainContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                mainContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                mainContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
                mainContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            glassEffectView = glassView
            window.contentView = containerView
        } else {
            // macOS 12-25 回退：NSVisualEffectView
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .underWindowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.addSubview(mainContainer)
            NSLayoutConstraint.activate([
                mainContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                mainContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                mainContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                mainContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            ])
            glassEffectView = nil
            window.contentView = visualEffectView
        }

        // 侧边栏宽度固定 180pt
        sidebarGlass.widthAnchor.constraint(equalToConstant: 180).isActive = true
        splitView.setPosition(180, ofDividerAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        // 默认选中第一项（通用）
        selectSection(.general)
    }

    private func makeSidebarScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true

        let tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.backgroundColor = .clear
        tableView.rowHeight = 32
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        sidebarTableView = tableView
        return scrollView
    }

    // MARK: - Section 切换

    private func selectSection(_ section: SettingsSection) {
        // 选中对应行
        sidebarTableView.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)

        // 移除旧内容视图
        currentContentView?.removeFromSuperview()

        // 构建新内容视图
        let newView = buildSectionView(section)
        newView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(newView)
        NSLayoutConstraint.activate([
            newView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            newView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            newView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentContentView = newView
    }

    /// 构建各分区的内容视图
    private func buildSectionView(_ section: SettingsSection) -> NSView {
        switch section {
        case .general:      return buildGeneralSection()
        case .appearance:   return buildAppearanceSection()
        case .fileManage:   return buildFileManageSection()
        case .smb:          return buildSMBSection()
        case .shortcuts:    return buildShortcutsSection()
        case .about:        return buildAboutSection()
        }
    }

    // MARK: - 内容构建：通用

    private func buildGeneralSection() -> NSView {
        let container = makeScrollContainer()

        // 启动 section
        let startupSection = SettingsSectionView(title: "启动")
        startupSection.addRow(.popupRow(title: "打开位置", items: ["上次打开的位置", "主目录", "自定义..."], action: nil).also { $0.setDisabled() })
        startupSection.addRow(.toggleRow(title: "自动恢复 SMB 连接", desc: "启动时重新连接上次的服务器", state: false, action: nil).also { $0.setDisabled() })
        startupSection.addRow(.toggleRow(title: "启动时检查更新", state: true, action: nil).also { $0.setDisabled() })

        // 文件操作 section
        let fileOpsSection = SettingsSectionView(title: "文件操作")
        fileOpsSection.addRow(.segmentedRow(title: "默认视图", labels: ["列表", "图标"], selected: 0) { idx in
            UserDefaults.standard.set(idx == 0 ? "list" : "grid", forKey: "default_view_mode")
        })
        fileOpsSection.addRow(.toggleRow(title: "显示隐藏文件", desc: "显示以 . 开头的文件和系统隐藏文件", state: UserDefaults.standard.bool(forKey: "show_hidden_files")) { state in
            UserDefaults.standard.set(state, forKey: "show_hidden_files")
            NotificationCenter.default.post(name: NSNotification.Name("refreshHiddenFiles"), object: nil)
        })
        fileOpsSection.addRow(.toggleRow(title: "双击打开", desc: "双击文件时在默认应用中打开", state: true, action: nil).also { $0.setDisabled() })
        fileOpsSection.addRow(.toggleRow(title: "删除前确认", state: false, action: nil).also { $0.setDisabled() })
        fileOpsSection.addRow(.toggleRow(title: "空废纸篓前警告", state: true, action: nil).also { $0.setDisabled() })

        // 双面板 section
        let dualPaneSection = SettingsSectionView(title: "双面板")
        dualPaneSection.addRow(.toggleRow(title: "默认显示双面板", state: UserDefaults.standard.bool(forKey: "default_dual_pane")) { state in
            UserDefaults.standard.set(state, forKey: "default_dual_pane")
        })
        dualPaneSection.addRow(.toggleRow(title: "同目录浏览", desc: "两个面板同步浏览同一目录", state: false, action: nil).also { $0.setDisabled() })
        dualPaneSection.addRow(.popupRow(title: "面板分隔条位置", items: ["居中", "上次位置"], action: nil).also { $0.setDisabled() })

        // 存储 section
        let storageSection = SettingsSectionView(title: "存储")
        storageSection.addRow(.popupRow(title: "默认下载位置", items: ["~/Downloads", "桌面", "自定义..."], action: nil).also { $0.setDisabled() })
        storageSection.addRow(.popupRow(title: "缓存大小限制", items: ["500 MB", "1 GB", "2 GB", "无限制"], action: nil).also { $0.setDisabled() })
        storageSection.addRow(.toggleRow(title: "自动清理缓存", desc: "超过限制时自动清理最旧缓存", state: true, action: nil).also { $0.setDisabled() })

        let stack = NSStackView(views: [startupSection, fileOpsSection, dualPaneSection, storageSection])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：外观

    private func buildAppearanceSection() -> NSView {
        let container = makeScrollContainer()

        let appearanceView = AppearanceSettingsView(frame: .zero)
        appearanceView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [appearanceView])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：文件管理（预留，合并到通用）

    private func buildFileManageSection() -> NSView {
        let container = makeScrollContainer()

        let section = SettingsSectionView(title: "文件管理")
        section.addRow(.toggleRow(title: "智能排序", desc: "文件夹自动置顶", state: true, action: nil).also { $0.setDisabled() })
        section.addRow(.toggleRow(title: "显示文件扩展名", state: true, action: nil).also { $0.setDisabled() })
        section.addRow(.toggleRow(title: "保留选择位置", desc: "刷新后保持已选文件", state: true, action: nil).also { $0.setDisabled() })

        let placeholder = NSTextField(labelWithString: "更多文件管理选项即将支持")
        placeholder.font = NSFont.systemFont(ofSize: 11)
        placeholder.textColor = NSColor.tertiaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [section, placeholder])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：SMB

    private func buildSMBSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let smbPanel = SMBManagerPanel(frame: .zero)
        smbPanel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(smbPanel)

        NSLayoutConstraint.activate([
            smbPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            smbPanel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            smbPanel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            smbPanel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
        return container
    }

    // MARK: - 内容构建：快捷键

    private func buildShortcutsSection() -> NSView {
        let container = makeScrollContainer()

        let titleLabel = NSTextField(labelWithString: "键盘快捷键")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.backgroundColor = .clear

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "操作"
        actionCol.width = 240
        tableView.addTableColumn(actionCol)

        let shortcutCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutCol.title = "快捷键"
        shortcutCol.width = 120
        tableView.addTableColumn(shortcutCol)

        let shortcuts: [(String, String)] = [
            ("新建文件夹", "⌘N"), ("打开文件", "⌘O"), ("关闭窗口", "⌘W"),
            ("复制", "⌘C"), ("剪切", "⌘X"), ("粘贴", "⌘V"), ("全选", "⌘A"),
            ("移动到废纸篓", "⌘⌫"), ("撤销", "⌘Z"), ("重做", "⌘⇧Z"),
            ("列表视图", "⌘1"), ("图标视图", "⌘2"), ("刷新", "⌘R"), ("搜索", "⌘F"),
            ("重复文件扫描", "⌘⇧D"), ("任务面板", "⌘0"), ("QuickLook 预览", "空格键"),
            ("复制选中项", "⌘D"), ("连接服务器", "⌘K"), ("偏好设置", "⌘,"),
        ]
        let dataSource = ShortcutsDataSource(shortcuts: shortcuts)
        self.shortcutsDataSource = dataSource  // 强引用持有，避免被释放
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        scrollView.documentView = tableView

        let section = SettingsSectionView(title: "快捷键")
        // 将 tableView 嵌入 section 内需要直接作为行控件，这里简化为独立布局
        let stack = NSStackView(views: [titleLabel, scrollView])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：关于

    private func buildAboutSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = true

        let appIcon = NSImageView()
        appIcon.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        appIcon.imageScaling = .scaleProportionallyDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let appName = NSTextField(labelWithString: "FlowFinder")
        appName.font = NSFont.boldSystemFont(ofSize: 22)
        appName.translatesAutoresizingMaskIntoConstraints = false

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "版本 \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.textColor = NSColor.secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyrightLabel = NSTextField(labelWithString: "© 2026 FlowFinder. 保留所有权利。")
        copyrightLabel.font = NSFont.systemFont(ofSize: 11)
        copyrightLabel.textColor = NSColor.tertiaryLabelColor
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = NSTextField(labelWithString: "原生 macOS 文件管理器，双面板、标签、查重、AI 智能分类")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(appIcon)
        container.addSubview(appName)
        container.addSubview(versionLabel)
        container.addSubview(descLabel)
        container.addSubview(copyrightLabel)

        NSLayoutConstraint.activate([
            appIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            appIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            appIcon.widthAnchor.constraint(equalToConstant: 96),
            appIcon.heightAnchor.constraint(equalToConstant: 96),

            appName.topAnchor.constraint(equalTo: appIcon.bottomAnchor, constant: 16),
            appName.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: appName.bottomAnchor, constant: 6),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            descLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            copyrightLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 24),
            copyrightLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        return container
    }

    // MARK: - 滚动容器辅助

    private func makeScrollContainer() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // 留出内容边距（顶部 20pt）
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        return scrollView
    }

    /// 在 NSScrollView 中约束 stackView 宽度并允许垂直滚动
    private func constrainStackInScroll(_ stack: NSStackView, in scrollView: NSScrollView) {
        guard let clipView = scrollView.contentView as? NSClipView else { return }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: clipView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: clipView.widthAnchor, constant: -48),
        ])
    }

    // MARK: - Public API

    public func showWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return sidebarItems.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < sidebarItems.count else { return nil }
        let section = sidebarItems[row]

        let cellID = NSUserInterfaceItemIdentifier("sectionCell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = cellID

        // 清除旧子视图
        cell.subviews.forEach { $0.removeFromSuperview() }
        cell.imageView = nil
        cell.textField = nil

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: section.iconName, accessibilityDescription: section.title)
        icon.contentTintColor = NSColor.secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: section.title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        ])

        return cell
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row < sidebarItems.count else { return false }
        selectSection(sidebarItems[row])
        return true
    }
}

// MARK: - ShortcutsDataSource

private class ShortcutsDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let shortcuts: [(String, String)]

    init(shortcuts: [(String, String)]) {
        self.shortcuts = shortcuts
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return shortcuts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < shortcuts.count else { return nil }

        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "")
        let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = cellID

        if cellView.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
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
        case "action":
            cellView.textField?.stringValue = shortcuts[row].0
        case "shortcut":
            cellView.textField?.stringValue = shortcuts[row].1
            cellView.textField?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        default:
            break
        }

        return cellView
    }
}

// MARK: - 便捷扩展

/// 用于在工厂方法链式调用中应用配置（如 setDisabled）
private extension SettingsRowView {
    @discardableResult
    func `also`(_ config: (SettingsRowView) -> Void) -> SettingsRowView {
        config(self)
        return self
    }
}
