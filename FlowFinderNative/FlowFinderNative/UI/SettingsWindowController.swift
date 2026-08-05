import Cocoa

// MARK: - OpaqueContainerView（设置窗口专用）

// FFOpaqueContainerView 已提取到 FFCommon.swift（统一实体背景容器）
// 原 SettingsOpaqueContainerView 已由 FFOpaqueContainerView 替代

// MARK: - SolidSidebarContainer（设置窗口侧边栏实体背景容器）

/// 任务 F11-2: 侧边栏实体背景容器（替代 FFGlassView .panel .sidebar，v0.6.7）。
/// 仅承载 sidebarScrollView，背景色使用系统动态 NSColor.windowBackgroundColor。
/// 注意：isOpaque 必须返回 false——isOpaque=true 会告知 AppKit「本视图内容不变，可缓存」，
/// 主题切换时系统会跳过该视图及子树的自动重绘，导致深色模式下侧边栏不跟随（视觉不变）。
/// 背景色由 layer.backgroundColor 提供（我们自行在主题刷新时重设），isOpaque 无需为 true。
private class SolidSidebarContainer: NSView {
    override var isOpaque: Bool { return false }
}

// MARK: - SettingsSection

/// 设置侧边栏分区枚举
enum SettingsSection: Int, CaseIterable {
    case general = 0      // 通用
    case appearance = 1   // 外观
    case fileManage = 2   // 文件管理
    case tagManage = 3    // 标签管理
    case smb = 4          // 网络存储 SMB
    case shortcuts = 5    // 快捷键
    case about = 6        // 关于

    var title: String {
        switch self {
        case .general:      return "通用"
        case .appearance:   return "外观"
        case .fileManage:   return "文件管理"
        case .tagManage:    return "标签管理"
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
        case .tagManage:    return "tag"
        case .smb:          return "network"
        case .shortcuts:    return "keyboard"
        case .about:        return "info.circle"
        }
    }
}

// MARK: - SettingsWindowController

/// 设置窗口控制器：左侧边栏（180pt，6 分区）+ 右侧滚动内容区
/// 任务 F11-2: 窗口实体背景（windowBackgroundColor），移除 FFGlassView 透明玻璃架构（v0.6.7）。
/// 用户反馈"完全看不清里面什么内容，透明度太高了"——实体背景后内容清晰可读。
public class SettingsWindowController: NSWindowController {

    public static let shared = SettingsWindowController()

    // MARK: - UI 引用

    private var sidebarTableView: NSTableView!
    private var sidebarScrollView: NSScrollView!
    private var contentContainer: NSView!
    /// 搜索框（内容区顶部，过滤设置项）
    private var searchField: NSSearchField!
    /// 主题变更时需重设背景色的容器（修复夜间模式适配：cgColor 静态值不随系统刷新）
    private var bgContainers: [NSView] = []
    /// 当前显示的内容视图（侧边栏选中项切换时替换）
    private var currentContentView: NSView?
    /// 当前分区所有行视图（用于搜索过滤）
    private var currentRows: [(section: SettingsSectionView, rows: [SettingsRowView])] = []

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

    // 修复夜间模式适配：监听主题变更，刷新所有容器背景色 + 窗口 appearance
    public override func windowDidLoad() {
        super.windowDidLoad()
        registerAppearanceObserver()
    }

    /// 注册主题变更监听（windowDidLoad 可能不在 NSWindowController 单例 + setupUI 已建 contentView
    /// 的场景下被调用——即使首次 show 也可能跳过 windowDidLoad。改在 setupUI 末尾也注册一次确保挂上）。
    private var appearanceObserverRegistered = false
    private func registerAppearanceObserver() {
        guard !appearanceObserverRegistered else { return }
        appearanceObserverRegistered = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppearanceChanged),
            name: .appearanceChanged, object: nil
        )
        FFDebug.log("SettingsWindowController: 已注册 .appearanceChanged 监听")
    }

    @objc private func handleAppearanceChanged() {
        FFDebug.log("Settings.handleAppearanceChanged: 收到通知，准备刷背景与 appearance")
        // 容器背景已改为透明（由窗口动态背景色透出，系统自动跟随主题），无需再刷 cgColor 快照。
        // 仅同步各容器 appearance 跟随 NSApp.appearance + 强制子树重绘（isOpaque 已改 false，
        // 重绘应能正常触发）。
        window?.backgroundColor = NSColor.windowBackgroundColor
        window?.appearance = NSApp.appearance
        for v in bgContainers { v.appearance = NSApp.appearance }
        func markNeedsDisplay(_ view: NSView) {
            view.needsDisplay = true
            for sub in view.subviews { markNeedsDisplay(sub) }
        }
        if let content = window?.contentView {
            markNeedsDisplay(content)
        }
        window?.displayIfNeeded()
        let effNames = bgContainers.map { String(describing: $0.effectiveAppearance.name) }.joined(separator: ", ")
        FFDebug.log("Settings.handleAppearanceChanged: 刷新完成，容器数=\(bgContainers.count), winEffective=\(String(describing: window?.effectiveAppearance.name)), containerEffective=[\(effNames)], NSApp=\(String(describing: NSApp.appearance?.name))")
    }

    /// 诊断：首次布局后记录搜索栏 / newView / stack 的 frame，定位"搜索栏下方空白"层级
    private var hasLoggedSettingsLayout = false
    func logSettingsLayoutOnce() {
        guard !hasLoggedSettingsLayout, let sf = searchField, let cv = currentContentView, !sf.frame.isEmpty else { return }
        hasLoggedSettingsLayout = true
        let ccFrame = contentContainer?.frame ?? .zero
        let sfFrame = sf.frame
        let nvFrame = cv.frame
        // scrollView 内 stackFrame（从 cv 是 scrollView 取 documentView.frame）
        var stackFrame = NSRect.zero
        if let sc = cv as? NSScrollView, let doc = sc.documentView { stackFrame = doc.frame }
        FFDebug.log("SettingsLayout: contentContainer=\(ccFrame) searchField=\(sfFrame) newView=\(nvFrame) docStack=\(stackFrame)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .appearanceChanged, object: nil)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }

        // 任务 F11-2: 窗口实体背景（v0.6.7）
        // 移除透明窗口配置（isOpaque=false + backgroundColor=.clear），
        // 改为实体窗口背景。windowBackgroundColor 为系统动态色（日间浅灰/夜间深灰）。
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true

        // 左侧边栏（180pt）
        sidebarScrollView = makeSidebarScrollView()
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false

        // 任务 F11-2: 侧边栏容器（背景透明，让窗口动态背景色透出）
        // 修复夜间模式：此前 sidebarContainer.layer.backgroundColor 用 windowBackgroundColor 的
        // cgColor 快照（浅色值），切深色后不跟随；改为透明让窗口动态背景色自动适配主题。
        let sidebarContainer = SolidSidebarContainer()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.wantsLayer = true
        sidebarContainer.layer?.backgroundColor = NSColor.clear.cgColor
        sidebarContainer.addSubview(sidebarScrollView)
        bgContainers.append(sidebarContainer)
        // 任务 F11-2: sidebarScrollView 撑满 sidebarContainer（v0.6.7）
        NSLayoutConstraint.activate([
            sidebarScrollView.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            sidebarScrollView.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
        ])

        // 右侧内容区容器（滚动）
        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor

        // 搜索框（内容区顶部，过滤设置项）
        searchField = NSSearchField()
        searchField.placeholderString = "搜索设置..."
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.sendsSearchStringImmediately = true
        contentContainer.addSubview(searchField)

        // 主分栏视图
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor
        splitView.addArrangedSubview(sidebarContainer)
        splitView.addArrangedSubview(contentContainer)

        // 主容器（透明背景，让窗口动态背景色透出；主题切换由窗口系统自动处理）
        let mainContainer = NSView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        mainContainer.layer?.backgroundColor = NSColor.clear.cgColor
        mainContainer.addSubview(splitView)
        // 修复夜间模式根因：原设 `mainContainer.appearance = NSApp.effectiveAppearance` 把
        // mainContainer 锁死在启动时的浅色 appearance 上（NSApp.effectiveAppearance 在
        // applyMode 切夜间后延迟更新，仍返回浅色），导致切夜间后设置页内容仍按浅色渲染 →
        // 看似"一片空白"。去掉这行，让 mainContainer 跟随 NSApp.appearance 自动适配。
        bgContainers.append(mainContainer)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
        ])

        // 顶层容器（透明背景，让窗口动态背景色透出；主题切换由窗口系统自动处理）
        let containerView = FFOpaqueContainerView()
        containerView.wantsLayer = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        bgContainers.append(containerView)
        // 窗口使用 .fullSizeContentView + titlebarAppearsTransparent=true，
        // FFOpaqueContainerView 的 isOpaque=true 会导致 safeAreaLayoutGuide 不提供正确的顶部 inset。
        // 手动补充 28pt 顶部安全区域，确保内容不被红绿灯/标题栏遮挡。
        containerView.additionalSafeAreaInsets = NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0)

        containerView.addSubview(mainContainer)
        NSLayoutConstraint.activate([
            mainContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            // 修复：窗口使用 .fullSizeContentView + titlebarAppearsTransparent=true，
            // 内容从 y=0 开始会被标题栏/红绿灯区域遮挡。改用 safeAreaLayoutGuide
            // 让主容器从标题栏下方开始，避免侧边栏与内容区被遮挡。
            mainContainer.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        window.contentView = containerView

        // 侧边栏宽度固定 180pt
        sidebarContainer.widthAnchor.constraint(equalToConstant: 180).isActive = true
        splitView.setPosition(180, ofDividerAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        // 修复夜间模式适配：windowDidLoad 在单例+setupUI 已建 contentView 场景不可靠，
        // 这里 setupUI 末尾再注册一次确保监听挂上（registerAppearanceObserver 用 flag 防重复）。
        registerAppearanceObserver()

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
        tableView.rowHeight = 36
        tableView.headerView = nil
        tableView.selectionHighlightStyle = .none
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
        currentRows = []

        // 构建新内容视图
        let newView = buildSectionView(section)
        newView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(newView)

        // 搜索框约束（固定在内容区顶部）
        NSLayoutConstraint.deactivate(contentContainer.constraints.filter {
            $0.firstItem === searchField || $0.secondItem === searchField
        })
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            searchField.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 12),
            searchField.heightAnchor.constraint(equalToConstant: 28),
        ])

        NSLayoutConstraint.activate([
            newView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            // 修复搜索栏下方大片空白：newView.top 紧贴 searchField.bottom（间距 0），
            // 内部 stack 距 clipView.top 也只留 4pt——叠合为搜索框下方仅 4pt 视觉间距，
            // 内容紧贴搜索栏。
            newView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 0),
            newView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentContentView = newView

        // 诊断：内容视图布局完成后再记录各层 frame（异步到下一 runloop 确保布局已结算）
        DispatchQueue.main.async { [weak self] in
            self?.logSettingsLayoutOnce()
        }
    }

    // MARK: - 搜索过滤

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        // 过滤当前分区行
        for entry in currentRows {
            // 无行的分区（如外观主题区的全宽内容视图）不参与行级过滤，保持可见
            guard !entry.rows.isEmpty else {
                entry.section.isHidden = false
                continue
            }
            var hasVisibleRow = false
            for row in entry.rows {
                let match = query.isEmpty
                    || row.title.lowercased().contains(query)
                    || row.desc.lowercased().contains(query)
                row.isHidden = !match
                if match { hasVisibleRow = true }
            }
            // 整个分区无匹配行时隐藏分区
            entry.section.isHidden = !hasVisibleRow && !query.isEmpty
        }
    }

    /// 注册分区和行到搜索过滤系统
    private func registerForSearch(_ section: SettingsSectionView, rows: [SettingsRowView]) {
        currentRows.append((section: section, rows: rows))
    }

    /// 构建各分区的内容视图
    private func buildSectionView(_ section: SettingsSection) -> NSView {
        switch section {
        case .general:      return buildGeneralSection()
        case .appearance:   return buildAppearanceSection()
        case .fileManage:   return buildFileManageSection()
        case .tagManage:    return buildTagManageSection()
        case .smb:          return buildSMBSection()
        case .shortcuts:    return buildShortcutsSection()
        case .about:        return buildAboutSection()
        }
    }

    // MARK: - 内容构建：通用

    private func buildGeneralSection() -> NSView {
        let container = makeScrollContainer()

        // 启动 section
        let startupSection = SettingsSectionView(title: "启动", iconName: "power")
        let startupRow = SettingsRowView.popupRow(
            title: "启动时打开",
            desc: "应用启动时显示的初始位置",
            items: ["上次打开的位置", "主目录", "桌面"],
            selectedIndex: UserDefaults.standard.integer(forKey: "startup_location"),
            action: { idx in
                UserDefaults.standard.set(idx, forKey: "startup_location")
            }
        )
        startupSection.addRow(startupRow)
        let checkUpdateRow = SettingsRowView.toggleRow(
            title: "启动时检查更新",
            desc: "自动检查应用新版本",
            state: UserDefaults.standard.object(forKey: "check_update_on_startup") as? Bool ?? true,
            action: { state in
                UserDefaults.standard.set(state, forKey: "check_update_on_startup")
            }
        )
        startupSection.addRow(checkUpdateRow)
        registerForSearch(startupSection, rows: [startupRow, checkUpdateRow])

        // 文件操作 section
        let fileOpsSection = SettingsSectionView(title: "文件操作", iconName: "doc.on.doc")
        let defaultViewRow = SettingsRowView.segmentedRow(
            title: "默认视图",
            desc: "新窗口的默认文件展示方式",
            labels: ["列表", "图标"],
            selected: (UserDefaults.standard.string(forKey: "default_view_mode") == "grid") ? 1 : 0
        ) { idx in
            UserDefaults.standard.set(idx == 0 ? "list" : "grid", forKey: "default_view_mode")
        }
        fileOpsSection.addRow(defaultViewRow)

        let showHiddenRow = SettingsRowView.toggleRow(
            title: "显示隐藏文件",
            desc: "显示以 . 开头的文件和系统隐藏文件",
            state: UserDefaults.standard.bool(forKey: FFUserDefaultsKeys.showHiddenFiles)
        ) { state in
            UserDefaults.standard.set(state, forKey: FFUserDefaultsKeys.showHiddenFiles)
            NotificationCenter.default.post(name: .refreshHiddenFiles, object: nil)
        }
        fileOpsSection.addRow(showHiddenRow)

        // 暂时隐藏「默认显示双面板」与「关闭窗口时记住面板状态」：
        // 这两项功能尚未接线（主窗口固定双面板，无单/双切换机制，也无面板状态持久化）。
        // 在接线完成前隐藏，避免作为摆设误导用户。
        // let dualPaneRow = SettingsRowView.toggleRow(...)  // 保留定义供未来接线恢复
        // let rememberPaneRow = SettingsRowView.toggleRow(...)

        let confirmOpsRow = SettingsRowView.toggleRow(
            title: "文件操作确认",
            desc: "移动或删除文件前弹出确认对话框",
            state: UserDefaults.standard.object(forKey: "confirm_file_operations") as? Bool ?? false,
            action: { state in
                UserDefaults.standard.set(state, forKey: "confirm_file_operations")
            }
        )
        fileOpsSection.addRow(confirmOpsRow)

        let defaultBehaviorRow = SettingsRowView.segmentedRow(
            title: "默认操作行为",
            desc: "同盘拖拽时移动，跨盘拖拽时复制（Finder 风格）",
            labels: ["同盘移动", "跨盘复制"],
            selected: UserDefaults.standard.integer(forKey: "default_file_behavior")
        ) { idx in
            UserDefaults.standard.set(idx, forKey: "default_file_behavior")
        }
        fileOpsSection.addRow(defaultBehaviorRow)
        registerForSearch(fileOpsSection, rows: [defaultViewRow, showHiddenRow, confirmOpsRow, defaultBehaviorRow])

        let stack = NSStackView(views: [startupSection, fileOpsSection])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：外观

    private func buildAppearanceSection() -> NSView {
        let container = makeScrollContainer()

        // 主题切换 section：AppearanceSettingsView 自带标题/三个主题按钮/说明文字，
        // 作为全宽内容嵌入分区卡片。
        // 修复 T8：原实现把 appearanceView 塞进 SettingsRowView 的 controlContainer
        // （controlContainer 无宽度约束，且 appearanceView 无 intrinsic size），
        // 导致整个外观分区塌缩为空白/按钮溢出。改为全宽 content 布局后，
        // 在任何窗口宽度下都能完整显示 3 个 100×100 按钮。
        let themeSection = SettingsSectionView(title: "主题", iconName: "circle.lefthalf.filled")
        let appearanceView = AppearanceSettingsView(frame: .zero)
        appearanceView.translatesAutoresizingMaskIntoConstraints = false
        themeSection.addContentView(appearanceView)
        registerForSearch(themeSection, rows: [])

        // 强调色 section
        let accentSection = SettingsSectionView(title: "强调色", iconName: "paintpalette")
        let accentColors = ["#0a84ff", "#bf5af2", "#ff375f", "#ff453a", "#ff9f0a", "#30d158", "#8e8e93"]
        let accentRow = SettingsRowView.colorRow(
            title: "强调色",
            desc: "应用于按钮、选中状态等界面元素",
            colors: accentColors,
            selectedHex: FFAccent.currentHex
        ) { hex in
            // 接线 FFAccent.set：写 UserDefaults + 广播 .accentColorChanged，
            // 全应用所有 FFAccent.current 引用下次读取即生效。
            FFAccent.set(hex: hex)
        }
        accentSection.addRow(accentRow)
        registerForSearch(accentSection, rows: [accentRow])

        let stack = NSStackView(views: [themeSection, accentSection])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：文件管理

    private func buildFileManageSection() -> NSView {
        let container = makeScrollContainer()

        // 排序与显示 section
        let sortSection = SettingsSectionView(title: "排序与显示", iconName: "arrow.up.arrow.down")
        let folderFirstRow = SettingsRowView.toggleRow(
            title: "智能排序",
            desc: "文件夹自动置顶",
            state: UserDefaults.standard.object(forKey: "folder_first_sort") as? Bool ?? true,
            action: { state in
                UserDefaults.standard.set(state, forKey: "folder_first_sort")
            }
        )
        sortSection.addRow(folderFirstRow)

        let keepSelectionRow = SettingsRowView.toggleRow(
            title: "保留选择位置",
            desc: "刷新后保持已选文件",
            state: UserDefaults.standard.object(forKey: "keep_selection_position") as? Bool ?? true,
            action: { state in
                UserDefaults.standard.set(state, forKey: "keep_selection_position")
            }
        )
        sortSection.addRow(keepSelectionRow)
        registerForSearch(sortSection, rows: [folderFirstRow, keepSelectionRow])

        let stack = NSStackView(views: [sortSection])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：标签管理

    private func buildTagManageSection() -> NSView {
        let container = makeScrollContainer()

        let tagSection = SettingsSectionView(title: "标签列表", iconName: "tag")
        let tagListRow = TagManagementRowView()
        tagSection.addRow(tagListRow)
        registerForSearch(tagSection, rows: [tagListRow])

        let stack = NSStackView(views: [tagSection])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：SMB

    private func buildSMBSection() -> NSView {
        let container = makeScrollContainer()

        // SMB 配置 section
        let configSection = SettingsSectionView(title: "SMB 配置", iconName: "gearshape.2")
        let domainRow = SettingsRowView.textFieldRow(
            title: "默认域",
            desc: "SMB 连接时使用的默认域",
            placeholder: "WORKGROUP",
            value: UserDefaults.standard.string(forKey: "smb_default_domain") ?? ""
        ) { val in
            UserDefaults.standard.set(val, forKey: "smb_default_domain")
        }
        configSection.addRow(domainRow)

        let autoReconnectRow = SettingsRowView.toggleRow(
            title: "自动重连",
            desc: "启动时自动重新连接上次的服务器",
            state: UserDefaults.standard.bool(forKey: "smb_auto_reconnect"),
            action: { state in
                UserDefaults.standard.set(state, forKey: "smb_auto_reconnect")
            }
        )
        configSection.addRow(autoReconnectRow)
        registerForSearch(configSection, rows: [domainRow, autoReconnectRow])

        // 服务器列表（使用现有 SMBManagerPanel，直接添加到堆栈，全宽显示）
        // 修复 T8：SMBManagerPanel 无 intrinsic size，原实现仅 heightAnchor >= 220，
        // 嵌入 centerX 对齐的垂直 stack 后宽度歧义 → 分区空白。
        // 宽度现由 constrainStackInScroll 对每个 arranged subview 的 leading/trailing
        // 钉到 stack 边缘统一处理（全宽），此处仅保留最小高度。
        let smbPanel = SMBManagerPanel(frame: .zero)
        smbPanel.translatesAutoresizingMaskIntoConstraints = false
        // 为 SMBManagerPanel 设置最小高度
        smbPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let stack = NSStackView(views: [configSection, smbPanel])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
        return container
    }

    // MARK: - 内容构建：快捷键

    private func buildShortcutsSection() -> NSView {
        let container = makeScrollContainer()

        let shortcuts: [(String, String, String)] = [
            ("新建文件夹", "⌘N", "shortcut_new_folder"),
            ("打开文件", "⌘O", "shortcut_open_file"),
            ("关闭窗口", "⌘W", "shortcut_close_window"),
            ("复制", "⌘C", "shortcut_copy"),
            ("剪切", "⌘X", "shortcut_cut"),
            ("粘贴", "⌘V", "shortcut_paste"),
            ("全选", "⌘A", "shortcut_select_all"),
            ("移动到废纸篓", "⌘⌫", "shortcut_trash"),
            ("撤销", "⌘Z", "shortcut_undo"),
            ("重做", "⌘⇧Z", "shortcut_redo"),
            ("列表视图", "⌘1", "shortcut_list_view"),
            ("图标视图", "⌘2", "shortcut_grid_view"),
            ("刷新", "⌘R", "shortcut_refresh"),
            ("搜索", "⌘F", "shortcut_search"),
            ("重复文件扫描", "⌘⇧D", "shortcut_duplicate_scan"),
            ("任务面板", "⌘0", "shortcut_task_panel"),
            ("QuickLook 预览", "空格键", "shortcut_quicklook"),
            ("复制选中项", "⌘D", "shortcut_duplicate"),
            ("连接服务器", "⌘K", "shortcut_connect_server"),
            ("偏好设置", "⌘,", "shortcut_preferences"),
        ]

        // 文件操作快捷键 section
        let fileShortcutSection = SettingsSectionView(title: "文件操作", iconName: "doc.on.doc")
        var fileRows: [SettingsRowView] = []
        let fileShortcuts = shortcuts.filter { item in
            ["shortcut_new_folder", "shortcut_open_file", "shortcut_copy", "shortcut_cut", "shortcut_paste", "shortcut_trash", "shortcut_duplicate"].contains(item.2)
        }
        for (name, defaultKey, key) in fileShortcuts {
            let saved = UserDefaults.standard.string(forKey: key) ?? defaultKey
            let row = SettingsRowView(title: name, desc: "")
            let recorder = ShortcutRecorderView(storageKey: key, shortcut: saved)
            row.setControl(recorder)
            fileShortcutSection.addRow(row)
            fileRows.append(row)
        }
        registerForSearch(fileShortcutSection, rows: fileRows)

        // 窗口与视图快捷键 section
        let viewShortcutSection = SettingsSectionView(title: "窗口与视图", iconName: "rectangle.3.group")
        var viewRows: [SettingsRowView] = []
        let viewShortcuts = shortcuts.filter { item in
            ["shortcut_close_window", "shortcut_list_view", "shortcut_grid_view", "shortcut_refresh", "shortcut_quicklook", "shortcut_task_panel"].contains(item.2)
        }
        for (name, defaultKey, key) in viewShortcuts {
            let saved = UserDefaults.standard.string(forKey: key) ?? defaultKey
            let row = SettingsRowView(title: name, desc: "")
            let recorder = ShortcutRecorderView(storageKey: key, shortcut: saved)
            row.setControl(recorder)
            viewShortcutSection.addRow(row)
            viewRows.append(row)
        }
        registerForSearch(viewShortcutSection, rows: viewRows)

        // 其他快捷键 section
        let otherShortcutSection = SettingsSectionView(title: "其他", iconName: "ellipsis.circle")
        var otherRows: [SettingsRowView] = []
        let otherShortcuts = shortcuts.filter { item in
            ["shortcut_select_all", "shortcut_undo", "shortcut_redo", "shortcut_search", "shortcut_duplicate_scan", "shortcut_connect_server", "shortcut_preferences"].contains(item.2)
        }
        for (name, defaultKey, key) in otherShortcuts {
            let saved = UserDefaults.standard.string(forKey: key) ?? defaultKey
            let row = SettingsRowView(title: name, desc: "")
            let recorder = ShortcutRecorderView(storageKey: key, shortcut: saved)
            row.setControl(recorder)
            otherShortcutSection.addRow(row)
            otherRows.append(row)
        }
        registerForSearch(otherShortcutSection, rows: otherRows)

        let stack = NSStackView(views: [fileShortcutSection, viewShortcutSection, otherShortcutSection])
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
        let container = makeScrollContainer()

        let aboutSection = SettingsSectionView(title: "关于 FlowFinder", iconName: "info.circle")

        // 应用图标（64x64pt）
        let appIcon = NSImageView()
        appIcon.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        appIcon.imageScaling = .scaleProportionallyDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let appName = NSTextField(labelWithString: "FlowFinder")
        appName.font = NSFont.boldSystemFont(ofSize: 20)
        appName.translatesAutoresizingMaskIntoConstraints = false

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "版本 \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = NSColor.secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = NSTextField(labelWithString: "原生 macOS 文件管理器，双面板、标签、查重、AI 智能分类")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyrightLabel = NSTextField(labelWithString: "© 2026 FlowFinder. 保留所有权利。")
        copyrightLabel.font = NSFont.systemFont(ofSize: 11)
        copyrightLabel.textColor = NSColor.tertiaryLabelColor
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false

        // 信息卡片内容容器
        let infoContainer = NSView()
        infoContainer.translatesAutoresizingMaskIntoConstraints = false

        let infoStack = NSStackView(views: [appIcon, appName, versionLabel, descLabel, copyrightLabel])
        infoStack.orientation = .vertical
        infoStack.spacing = 8
        infoStack.alignment = .centerX
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(infoStack)

        NSLayoutConstraint.activate([
            infoStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor),
            infoStack.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 16),
            infoStack.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: -16),
        ])

        let aboutRow = SettingsRowView(title: "", desc: "")
        aboutRow.setControl(infoContainer)
        aboutSection.addRow(aboutRow)
        registerForSearch(aboutSection, rows: [aboutRow])

        let stack = NSStackView(views: [aboutSection])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = stack

        constrainStackInScroll(stack, in: container)
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
        // 边距改由 constrainStackInScroll 中 stack.top/bottom 常量提供。
        // 修复 T8：contentInsets 与 autolayout documentView 叠加时顶部 20pt 内容会被
        // 裁到可视区外/首行偏移，故移除 contentInsets 改用显式约束。
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        // 修复搜索栏下方留白：NSScrollView 默认 scrollerInsets 可能在顶部留位，
        // 显式置零让 clipView 顶紧贴 scrollView 顶，内容无额外偏移。
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return scrollView
    }

    /// 在 NSScrollView 中约束 stackView 宽度并允许垂直滚动
    private func constrainStackInScroll(_ stack: NSStackView, in scrollView: NSScrollView) {
        // 最终方案（多次反复后的结论）：NSScrollView 的 documentView 若 isFlipped=true
        // （y=0 在顶部），滚动方向与视觉一致——内容天然贴可视区顶部，无"搜索栏下方空白"，
        // 且事件坐标由系统正确处理。此前 Auto Layout 方案（非 flipped + topAnchor）会把
        // 内容钉到视觉底部；flipped 容器 + Auto Layout 又导致事件错乱。现在用
        // frame-based + flipped 容器：FlippedStackContainer(isFlipped=true) 作为 documentView，
        // stack 以 frame 布局放进去，高度用 fittingSize 结算。
        let container = FlippedStackContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        scrollView.documentView = container

        let clipWidth = scrollView.contentView.bounds.width
        stack.layoutSubtreeIfNeeded()
        let contentHeight = max(stack.fittingSize.height, 1)
        stack.frame = NSRect(x: 24, y: 4, width: max(clipWidth - 48, 300), height: contentHeight)
        // 容器高度 = 内容高度（flipped 下 y=0 在顶，容器顶即可视区顶）
        container.frame = NSRect(x: 0, y: 0, width: max(clipWidth, 300), height: contentHeight + 8)

        // 修复 T8（根因）：NSStackView 垂直方向默认 .centerX 对齐，对无 intrinsic size 的
        // 分区视图（SettingsSectionView / SMBManagerPanel / 自定义内容视图）宽度产生歧义，
        // 约束求解后可能塌缩为 0 宽 → 分区"空白"。
        // 显式将每个 arranged subview 的 leading/trailing 钉到 stack 边缘，撑满整行宽度。
        for view in stack.arrangedSubviews {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            ])
        }

        // 窗口 resize 时保持容器/stack 宽度跟随（frame-based 需手动同步）
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsScrollFrameChanged(_:)),
            name: NSView.frameDidChangeNotification, object: scrollView
        )
    }

    @objc private func settingsScrollFrameChanged(_ note: Notification) {
        guard let scrollView = note.object as? NSScrollView,
              let container = scrollView.documentView as? FlippedStackContainer,
              let stack = container.subviews.first else { return }
        let clipWidth = scrollView.contentView.bounds.width
        stack.layoutSubtreeIfNeeded()
        let contentHeight = max(stack.fittingSize.height, 1)
        stack.frame = NSRect(x: 24, y: 4, width: max(clipWidth - 48, 300), height: contentHeight)
        container.frame = NSRect(x: 0, y: 0, width: max(clipWidth, 300), height: contentHeight + 8)
        scrollView.reflectScrolledClipView(scrollView.contentView)
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

        // 选中态玻璃背景层
        let selectionBackground = FFGlassView(level: .component, cornerRadius: 8)
        selectionBackground.translatesAutoresizingMaskIntoConstraints = false
        selectionBackground.isHidden = (tableView.selectedRow != row)
        selectionBackground.identifier = NSUserInterfaceItemIdentifier("selectionBg")

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: section.iconName, accessibilityDescription: section.title)
        icon.contentTintColor = NSColor.secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: section.title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(selectionBackground)
        cell.addSubview(icon)
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            selectionBackground.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            selectionBackground.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            selectionBackground.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
            selectionBackground.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),

            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        ])

        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        // 更新所有可见行的选中态玻璃背景
        let selectedRow = tableView.selectedRow
        for row in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { continue }
            if let bg = cell.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("selectionBg") }) {
                bg.isHidden = (row != selectedRow)
            }
        }
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row < sidebarItems.count else { return false }
        selectSection(sidebarItems[row])
        return true
    }
}

// MARK: - ShortcutRecorderView

/// 快捷键录制器：点击进入录制模式，捕获下一次按键组合，存储到 UserDefaults
class ShortcutRecorderView: NSView {

    private let storageKey: String
    private let button = NSButton()
    private var isRecording = false
    private var currentShortcut: String

    init(storageKey: String, shortcut: String) {
        self.storageKey = storageKey
        self.currentShortcut = shortcut
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        button.title = currentShortcut
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(startRecording)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
    }

    @objc private func startRecording() {
        if isRecording {
            // 已在录制中，点击则取消
            cancelRecording()
            return
        }
        isRecording = true
        button.title = "按下快捷键..."
        button.highlight(true)
        // 让当前窗口接受键盘事件
        window?.makeFirstResponder(self)
    }

    private func cancelRecording() {
        isRecording = false
        button.title = currentShortcut
        button.highlight(false)
        window?.makeFirstResponder(nil)
    }

    // MARK: - 键盘捕获

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // ESC 取消录制
        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        // 解析修饰键 + 按键
        let modifiers = event.modifierFlags
        let shortcutStr = ShortcutRecorderView.formatShortcut(modifiers: modifiers, keyCode: event.keyCode)

        // 必须至少包含一个修饰键（除功能键外）
        let hasModifier = modifiers.contains(.command) || modifiers.contains(.control) ||
                          modifiers.contains(.option) || modifiers.contains(.shift)
        let isFunctionKey = (event.keyCode >= 122 && event.keyCode <= 140) // F1-F13

        if !hasModifier && !isFunctionKey && event.keyCode != 49 { // 49 = space
            // 不含修饰键且非功能键，忽略
            return
        }

        currentShortcut = shortcutStr
        button.title = shortcutStr
        UserDefaults.standard.set(shortcutStr, forKey: storageKey)
        isRecording = false
        button.highlight(false)
        window?.makeFirstResponder(nil)
    }

    /// 将修饰键 + keyCode 格式化为可读快捷键字符串
    static func formatShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        // 转换 keyCode 为可读字符
        let keyStr: String
        switch keyCode {
        case 36: keyStr = "↩"       // Return
        case 48: keyStr = "⇥"       // Tab
        case 49: keyStr = "空格键"   // Space
        case 51: keyStr = "⌫"       // Delete
        case 53: keyStr = "⎋"       // Escape
        case 76: keyStr = "↩"       // Enter (numpad)
        case 122...140:
            let fn = keyCode - 122 + 1
            keyStr = "F\(fn)"       // F1-F19
        default:
            // 尝试通过 TIS 转换为字符
            let translated = translateKeyCode(keyCode, modifiers: modifiers)
            keyStr = translated ?? "Key\(keyCode)"
        }
        parts.append(keyStr)
        return parts.joined()
    }

    /// 将 keyCode 转换为可读字符（常见按键映射表）
    private static func translateKeyCode(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        // 常见 keyCode -> 字符映射（基于 ANSI 美式键盘布局）
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "5",
            23: "6", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            50: "`",
            65: ".", 67: "*", 69: "+", 71: "清除", 75: "/", 76: "↩",
            78: "-", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3",
            86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 109: "F10", 111: "F12",
            118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return keyMap[keyCode]
    }
}

// MARK: - TagManagementRowView

/// 标签管理行视图：显示标签列表，支持新建/删除/编辑颜色
/// 使用 UserDefaults "SidebarTags" key 与侧边栏标签同步
class TagManagementRowView: SettingsRowView {

    private let tagsKey = "SidebarTags"
    private var tags: [Tag] = []
    private let tagsStack = NSStackView()
    private let availableColors = ["#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#0A84FF", "#BF5AF2", "#8E8E93"]

    init() {
        super.init(title: "", desc: "")
        loadTags()
        setupTagUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: tagsKey),
           let decoded = try? JSONDecoder().decode([Tag].self, from: data) {
            tags = decoded
        } else {
            tags = [
                Tag(name: "重要", color: "#FF453A"),
                Tag(name: "工作", color: "#0A84FF"),
                Tag(name: "个人", color: "#30D158"),
            ]
            saveTags()
        }
    }

    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: tagsKey)
            // 通知侧边栏刷新
            NotificationCenter.default.post(name: NSNotification.Name("SidebarTagsDidRefresh"), object: nil)
        }
    }

    private func setupTagUI() {
        tagsStack.orientation = .vertical
        tagsStack.spacing = 6
        tagsStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tagsStack)

        NSLayoutConstraint.activate([
            tagsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tagsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tagsStack.topAnchor.constraint(equalTo: container.topAnchor),
            tagsStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        setControl(container)
        refreshTagList()
    }

    /// 生成 16×16 彩色圆点 NSImage（用于下拉菜单 item 的图像，
    /// 让颜色选择直观且不依赖纯文字渲染——避免 macOS 26 窄 popup 显示占位缩写）
    private func makeColorDotImage(hex: String) -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let color = NSColor(hex: hex) ?? .gray
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 14, height: 14)).fill()
        image.unlockFocus()
        return image
    }

    private func refreshTagList() {
        tagsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (idx, tag) in tags.enumerated() {            let row = makeTagRow(tag: tag, index: idx)
            tagsStack.addArrangedSubview(row)
        }

        // 新建标签按钮行
        let addButton = NSButton(title: "＋ 新建标签", target: self, action: #selector(addTagClicked))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        tagsStack.addArrangedSubview(addButton)
    }

    private func makeTagRow(tag: Tag, index: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // 颜色圆点
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 7
        dot.translatesAutoresizingMaskIntoConstraints = false

        // 标签名
        let nameLabel = NSTextField(labelWithString: tag.name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // 编辑颜色按钮
        let editButton = NSButton()
        editButton.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "编辑颜色")
        editButton.contentTintColor = .secondaryLabelColor
        editButton.isBordered = false
        editButton.controlSize = .small
        editButton.tag = index
        editButton.target = self
        editButton.action = #selector(editColorClicked(_:))
        editButton.toolTip = "编辑颜色"
        editButton.translatesAutoresizingMaskIntoConstraints = false

        // 删除按钮
        let deleteButton = NSButton()
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除标签")
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.isBordered = false
        deleteButton.controlSize = .small
        deleteButton.tag = index
        deleteButton.target = self
        deleteButton.action = #selector(deleteTagClicked(_:))
        deleteButton.toolTip = "删除标签"
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(dot)
        row.addSubview(nameLabel)
        row.addSubview(editButton)
        row.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 14),
            dot.heightAnchor.constraint(equalToConstant: 14),

            nameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            deleteButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            editButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            editButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            row.heightAnchor.constraint(equalToConstant: 32),
        ])

        return row
    }

    // MARK: - Actions

    @objc private func addTagClicked() {
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "请输入标签名称"
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input

        // 颜色选择（用带彩色圆点图像的下拉菜单，替代纯文字——避免 macOS 26 上
        // 纯文字 popup item 在窄宽度下渲染异常显示占位缩写）
        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 260, height: 26), pullsDown: false)
        let colorNames = ["红色", "橙色", "黄色", "绿色", "蓝色", "紫色", "灰色"]
        for (i, name) in colorNames.enumerated() {
            colorPopup.addItem(withTitle: name)
            colorPopup.item(at: i)?.tag = i
            // item 加彩色圆点图像（20×20 圆，让选择更直观且不依赖纯文字渲染）
            if let dot = makeColorDotImage(hex: availableColors[i]) {
                colorPopup.item(at: i)?.image = dot
            }
        }
        let colorContainer = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 60))
        colorContainer.addSubview(input)
        colorContainer.addSubview(colorPopup)
        alert.accessoryView = colorContainer

        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let colorIdx = max(0, min(colorPopup.indexOfSelectedItem, availableColors.count - 1))
            let color = availableColors[colorIdx]
            let tag = Tag(name: name, color: color)
            tags.append(tag)
            saveTags()
            refreshTagList()
        }
    }

    @objc private func editColorClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < tags.count else { return }

        let alert = NSAlert()
        alert.messageText = "编辑标签颜色"
        alert.informativeText = "为标签「\(tags[index].name)」选择新颜色"
        alert.alertStyle = .informational

        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        let colorNames = ["红色", "橙色", "黄色", "绿色", "蓝色", "紫色", "灰色"]
        let currentColor = tags[index].color.uppercased()
        var selectedIdx = 0
        for (i, name) in colorNames.enumerated() {
            colorPopup.addItem(withTitle: name)
            if let dot = makeColorDotImage(hex: availableColors[i]) {
                colorPopup.item(at: i)?.image = dot
            }
            if availableColors[i].uppercased() == currentColor {
                selectedIdx = i
            }
        }
        colorPopup.selectItem(at: selectedIdx)
        alert.accessoryView = colorPopup

        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            let colorIdx = max(0, min(colorPopup.indexOfSelectedItem, availableColors.count - 1))
            tags[index].color = availableColors[colorIdx]
            saveTags()
            refreshTagList()
        }
    }

    @objc private func deleteTagClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < tags.count else { return }

        let alert = NSAlert()
        alert.messageText = "删除标签"
        alert.informativeText = "确定要删除标签「\(tags[index].name)」吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            tags.remove(at: index)
            saveTags()
            refreshTagList()
        }
    }
}


// MARK: - FlippedStackContainer

/// 设置页滚动容器：isFlipped=true（y=0 在顶部）的 documentView。
/// NSScrollView 的 documentView 若 flipped，滚动方向与视觉一致——内容天然贴可视区顶部，
/// 无"搜索栏下方空白"，且鼠标事件坐标由系统正确处理（此前非 flipped 方案内容贴底/空白）。
/// 内部 stack 用 frame 布局（constrainStackInScroll 设置），窗口 resize 时由
/// settingsScrollFrameChanged 同步宽度。
private final class FlippedStackContainer: NSView {
    override var isFlipped: Bool { true }
}
