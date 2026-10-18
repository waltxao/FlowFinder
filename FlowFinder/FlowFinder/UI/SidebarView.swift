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
    /// v0.8.0 P1: 收藏右键菜单三项窗口级动作（object 携带发起方 outlineView，userInfo["path"]）
    /// 窗口的创建/持有归 MainWindowController，SidebarView 只发意图，不直接建窗
    static let sidebarDidRequestOpenInNewTab = Notification.Name("sidebarDidRequestOpenInNewTab")
    static let sidebarDidRequestOpenInNewWindow = Notification.Name("sidebarDidRequestOpenInNewWindow")
    static let sidebarDidRequestShowFavoriteInfo = Notification.Name("sidebarDidRequestShowFavoriteInfo")
    /// 2026-10-18 #3：侧栏顶部单/双窗口切换按钮
    static let sidebarDidTogglePaneMode = Notification.Name("sidebarDidTogglePaneMode")
}

// MARK: - 侧边栏布局度量（v0.8.0 P1）

/// 侧边栏行高度量：outline 行高、内容高度计算与测试共用，避免魔法数字分叉
enum SidebarMetrics {
    /// 分区标题行（访达 group row：11pt 灰色小字）
    static let sectionHeaderHeight: CGFloat = 22
    /// 收藏项行高
    static let rowHeight: CGFloat = 28
    /// 空态引导行
    static let emptyHintHeight: CGFloat = 26
}

// MARK: - 侧边栏分区节点（v0.8.0 P1）

/// outline 分区节点（group row）
///
/// P1 只有「个人收藏」一个分区；P2 标签并入后在此枚举增加 `.tags`，
/// 数据结构无需再改（设计稿 §3 单一 outline 分区模型）。
enum SidebarSectionKind {
    case favorites
    case places
    case tags

    var title: String {
        switch self {
        case .favorites: return "个人收藏"
        case .places: return "位置"
        case .tags: return "标签"
        }
    }
}

/// 分区标题节点（NSOutlineView 的 group item，需为引用类型以便展开态稳定）
final class SidebarSectionNode: NSObject {
    let kind: SidebarSectionKind

    init(kind: SidebarSectionKind) {
        self.kind = kind
    }
}

/// 空态引导行（访达同款：分区下显示一行次要文字，不参与选中/拖拽）
final class SidebarEmptyHintNode: NSObject {
    let text: String

    init(text: String) {
        self.text = text
    }
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
    // 恢复 canBecomeKeyView=true：使 outlineView 能成为 key view，
    // NSTableRowView 选中绘制走标准强调蓝色（而非 de-emphasized 灰色），
    // 解决"高亮未完全包裹内容/颜色过淡"问题。焦点环由 focusRingType=.none 抑制。
    override var canBecomeKeyView: Bool {
        return true
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

    // MARK: - v0.8.0 P1：滚动容器内的自适应高度

    /// 内容高度由数据源写入。
    ///
    /// 分区模型下行高混合（标题 22 / 空态 26 / 收藏 28），不能用 numberOfRows × rowHeight；
    /// 用 intrinsicContentSize 而非 NSLayoutConstraint 定高——outline 位于滚动文档内，
    /// 高度由内容驱动，不再与兄弟视图的定高约束互相钳制（v0.7.x 定高冲突的结构性根因）。
    var explicitContentHeight: CGFloat = 0 {
        didSet {
            guard abs(oldValue - explicitContentHeight) > 0.5 else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: explicitContentHeight)
    }

    /// Enter 激活选中行（导航到收藏目录）
    var onActivateRow: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Enter 自带 .numericPad 标志，不能用 modifiers.isEmpty 判定
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.control) {
            onActivateRow?()
            return
        }
        super.keyDown(with: event)
    }

    /// 侧边栏整体滚动：outline 本身不带滚动条，滚轮必须转交外层 NSScrollView，
    /// 否则光标停在收藏列表上时侧边栏不滚动（P1 验收标准 1）
    override func scrollWheel(with event: NSEvent) {
        if let outer = enclosingScrollView {
            outer.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - FFSidebarRowView（自绘选中高亮）

/// 自定义行视图：自绘选中高亮，精确覆盖行内容区域（图标+文字）。
/// 系统 NSTableRowView 的选中绘制与 cell 内容存在偏移，导致"高亮未完全包裹内容"。
/// 此子类在 drawSelection 中用强调色绘制覆盖整行内容区域的圆角矩形，
/// 高亮范围与内容精确对齐；行间无缝隙（intercellSpacing 由 makeOutlineView 设为 0）。
private class FFSidebarRowView: NSTableRowView {
    /// 高亮左右内边距（覆盖 cell 内容：图标左缘 x=0 到文字右缘）
    private let highlightInsetH: CGFloat = 3
    /// 高亮圆角
    private let highlightRadius: CGFloat = 6

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        // 高亮覆盖整行内容区域：左右各留 3pt，上下铺满（消除行间缝隙）
        let highlightRect = NSRect(
            x: bounds.minX + highlightInsetH,
            y: bounds.minY,
            width: bounds.width - highlightInsetH * 2,
            height: bounds.height
        )
        let path = NSBezierPath(roundedRect: highlightRect, xRadius: highlightRadius, yRadius: highlightRadius)
        // 选中时用强调色；窗口失焦时用「未强调选中」系统灰（与列表同一令牌，C-05）
        let color: NSColor = isEmphasized ? FFAccent.current : .unemphasizedSelectedContentBackgroundColor
        color.setFill()
        path.fill()
    }
}

// MARK: - SidebarView

class SidebarView: NSView {
    /// 任务 R3: 侧边栏顶部应用名称 + 版本号（红绿灯下方，2026-10-18 移除图标）
    private var brandView: NSView!
    /// 2026-10-18：应用名称下方的版本行
    private var brandVersionLabel: NSTextField!
    /// 任务 T1: 工具栏行（夜间切换 + 设置 + 工具）
    /// 任务 F10-3: 设备区域已移出侧边栏（浮动在窗口左下角），toolBarRow 现位于标签下方
    private var toolBarRow: NSStackView!
    /// 任务 T1: 主题切换按钮（用于切换图标）
    private var themeToggleBtn: NSButton!

    /// v0.8.0 P1: 侧边栏滚动容器——品牌区与底部工具行固定，中间内容整体滚动
    /// （访达同构：工具栏与底部不动，中间滚动；收藏 20+ 项不再溢出重叠）
    private var sidebarScrollView: NSScrollView!
    /// 滚动内容栈（收藏分区 + 标签分区）
    private var scrollContentStack: NSStackView!
    /// 标签分区标题行（标题 + "+" 按钮）；P2 标签并入 outline 后整体移除
    private var tagsHeaderView: NSView!

    private var favoritesOutlineView: FFFNoDisclosureOutlineView!
    /// 任务 F10-5: 标签视图（垂直纵向排列：圆点 + 完整标签名，每行一个）（v0.6.6）
    private var tagFlowView: TagFlowView!
    private var tagsTitleLabel: NSTextField!
    /// 标签标题旁"+"按钮
    private var tagsAddButton: NSButton!
    /// 2026-10-18 #4：位置分区（设备从窗口左下角浮层迁回侧栏，排在标签上方）
    private let placesDataSource = DeviceSidebarDataSource()
    /// 位置分区容器（标题 + 设备行）
    private var placesSectionView: NSStackView!
    /// 设备行纵向 stack
    private var placesRowsStack: NSStackView!
    /// 位置分区标题行
    private var placesHeaderView: NSView!
    /// 2026-10-18 #3：单/双窗口切换按钮（红绿灯同一水平带的最右侧）
    private var paneModeButton: NSButton!
    /// v0.8.0 P1: 收藏数据层（顺序 / 失效状态 / 持久化）
    private let favoritesStore = SidebarFavoritesStore()
    private lazy var favoritesDataSource = FavoritesSidebarDataSource(store: favoritesStore)
    private let tagsDataSource = TagsSidebarDataSource()

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

        // 任务 R3: 侧边栏顶部应用名称 + 版本号（红绿灯下方）
        // 2026-10-18：移除 32pt 应用图标，仅保留名称，名称下方显示版本号
        brandView = NSView()
        brandView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(brandView)

        let appNameLabel = NSTextField(labelWithString: "FlowFinder")
        appNameLabel.font = NSFont.boldSystemFont(ofSize: 15)
        appNameLabel.textColor = NSColor.labelColor
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        brandView.addSubview(appNameLabel)

        // 版本号：0.7.9 (7901)。打包进 .app 后读 Info.plist；测试宿主等无 bundle 场景回退占位
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        brandVersionLabel = NSTextField(labelWithString: "\(shortVersion) (\(buildVersion))")
        brandVersionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        brandVersionLabel.textColor = NSColor.secondaryLabelColor
        brandVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        brandView.addSubview(brandVersionLabel)

        // 点击 brandView 弹出关于对话框
        let brandClick = NSClickGestureRecognizer(target: self, action: #selector(showAboutWindow))
        brandView.addGestureRecognizer(brandClick)

        NSLayoutConstraint.activate([
            // 红绿灯下方（topAnchor 32pt 留给红绿灯）
            brandView.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            brandView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            brandView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            brandView.heightAnchor.constraint(equalToConstant: 44),

            appNameLabel.leadingAnchor.constraint(equalTo: brandView.leadingAnchor),
            appNameLabel.topAnchor.constraint(equalTo: brandView.topAnchor, constant: 2),

            brandVersionLabel.leadingAnchor.constraint(equalTo: brandView.leadingAnchor),
            brandVersionLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 2),
        ])

        // 2026-10-18 #3：单/双窗口切换按钮——与红绿灯同一水平带，贴侧栏最右侧
        paneModeButton = NSButton()
        paneModeButton.bezelStyle = .inline
        paneModeButton.isBordered = false
        paneModeButton.imagePosition = .imageOnly
        paneModeButton.contentTintColor = NSColor.secondaryLabelColor
        paneModeButton.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "切换到单窗口")
        paneModeButton.toolTip = "切换到单窗口"
        paneModeButton.target = self
        paneModeButton.action = #selector(handlePaneModeToggle)
        paneModeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(paneModeButton)
        NSLayoutConstraint.activate([
            paneModeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            paneModeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            paneModeButton.widthAnchor.constraint(equalToConstant: 24),
            paneModeButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        // v0.8.0 P1：「个人收藏」标题改为 outline 分区标题行（group row），不再用外置 label。
        // 2026-10-18 #4/#5：位置与标签也用同一套分区标题视图——同字号、同缩进、同行高，
        // 三个栏目标题因此严格对齐（此前标签标题比收藏标题少 6pt 缩进）。
        tagsAddButton = NSButton()
        tagsAddButton.bezelStyle = .inline
        tagsAddButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")
        tagsAddButton.imagePosition = .imageOnly
        tagsAddButton.isBordered = false
        tagsAddButton.contentTintColor = NSColor.secondaryLabelColor
        tagsAddButton.target = self
        tagsAddButton.action = #selector(showCreateTagDialog)
        tagsAddButton.translatesAutoresizingMaskIntoConstraints = false

        placesHeaderView = makeSidebarSectionHeader(SidebarSectionKind.places.title)
        tagsHeaderView = makeSidebarSectionHeader(SidebarSectionKind.tags.title, accessory: tagsAddButton)
        tagsTitleLabel = tagsHeaderView.subviews.compactMap { $0 as? NSTextField }.first

        // 位置分区：标题 + 设备行（设备数据由 DeviceSidebarDataSource 后台加载）
        placesRowsStack = NSStackView()
        placesRowsStack.orientation = .vertical
        placesRowsStack.alignment = .leading
        placesRowsStack.spacing = 0
        placesRowsStack.translatesAutoresizingMaskIntoConstraints = false

        placesSectionView = NSStackView(views: [placesHeaderView, placesRowsStack])
        placesSectionView.orientation = .vertical
        placesSectionView.alignment = .leading
        placesSectionView.spacing = 0
        placesSectionView.translatesAutoresizingMaskIntoConstraints = false

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

        // v0.8.0 P1: 收藏分区——单一 outline 的分区模型（「个人收藏」group row + 收藏项）
        favoritesOutlineView = makeOutlineView()
        favoritesOutlineView.dataSource = favoritesDataSource
        favoritesOutlineView.delegate = favoritesDataSource
        // 拖拽类型：外部文件夹（添加收藏）+ 内部重排（自定义粘贴板类型）
        favoritesOutlineView.registerForDraggedTypes([.fileURL, FavoritesSidebarDataSource.dragType])
        // 内部拖拽仅允许移动语义（重排），不对外导出文件副本
        favoritesOutlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        favoritesOutlineView.setDraggingSourceOperationMask([], forLocal: false)
        favoritesOutlineView.onActivateRow = { [weak self] in
            self?.navigateToSelectedFavorite()
        }
        // 右键菜单（多窗口/失效态均在 menuNeedsUpdate 中动态生成）
        let favoritesMenu = NSMenu()
        favoritesMenu.delegate = self
        favoritesOutlineView.menu = favoritesMenu

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
        // Wave2 P0-4（多窗口）：object 携带本侧边栏实例身份，接收方据此过滤本窗口通知
        tagFlowView.onTagSelected = { [weak self] tag in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .sidebarDidSelectTag, object: self, userInfo: ["tag": tag])
        }

        // 任务 F11-8: 监听面板标签筛选变化，更新标签行高亮（当前筛选的标签高亮显示）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePaneTagFilterChanged(_:)),
            name: .paneTagFilterChanged, object: nil
        )

        // 任务 F10-3: 设备区域相关视图（deviceHeaderView/deviceScrollView/deviceOutlineView）
        // 已迁移至 MainWindowController 的 createDevicePanel 浮层，此处不再创建

        // A1: 收藏变化（增删/外部拖入/内部重排）后重建 outline
        favoritesDataSource.onFavoritesChanged = { [weak self] in
            self?.reloadFavorites()
        }

        // 初始化标签数据
        tagFlowView.updateTags(tagsDataSource.allTags())

        // v0.8.0 P1: 品牌区与底部工具行固定，中间内容整体滚动
        sidebarScrollView = makeSidebarScrollView()
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebarScrollView)

        scrollContentStack = NSStackView(views: [favoritesOutlineView, placesSectionView, tagsHeaderView, tagFlowView])
        scrollContentStack.orientation = .vertical
        scrollContentStack.alignment = .leading
        scrollContentStack.distribution = .fill
        scrollContentStack.spacing = 0
        scrollContentStack.translatesAutoresizingMaskIntoConstraints = false
        // 三个分区之间留 16pt 区块间距（收藏 → 位置 → 标签），访达同构
        scrollContentStack.setCustomSpacing(16, after: favoritesOutlineView)
        scrollContentStack.setCustomSpacing(16, after: placesSectionView)

        // 滚动文档视图：isFlipped=true，内容天然贴顶（非 flipped 会导致内容贴底/顶部空白）
        let scrollContainer = FlippedSidebarContainer()
        scrollContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollContainer.addSubview(scrollContentStack)
        sidebarScrollView.documentView = scrollContainer

        let padding: CGFloat = 12

        NSLayoutConstraint.activate([
            // 滚动内容：宽度跟随可视区，高度由内容撑开（不钉死，内容少时不留空白）
            scrollContentStack.topAnchor.constraint(equalTo: scrollContainer.topAnchor, constant: 4),
            scrollContentStack.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor, constant: padding),
            scrollContentStack.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor, constant: -padding),
            scrollContentStack.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor, constant: -12),
            scrollContainer.widthAnchor.constraint(equalTo: sidebarScrollView.contentView.widthAnchor),

            // 滚动区：品牌区下方 → 工具行上方
            sidebarScrollView.topAnchor.constraint(equalTo: brandView.bottomAnchor, constant: 4),
            sidebarScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: toolBarRow.topAnchor, constant: -6),

            // 工具栏行（固定在底部，不随内容滚动）
            toolBarRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            toolBarRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            toolBarRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            toolBarRow.heightAnchor.constraint(equalToConstant: 28),
        ])

        // 每个分区视图铺满滚动内容宽度。
        // 不依赖 NSStackView alignment 的隐式行为——v0.7.4 设置页已证实 .width alignment
        // 与卡片内部约束冲突导致右对齐塌缩，改由显式 leading/trailing 约束接管。
        for subview in scrollContentStack.arrangedSubviews {
            subview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: scrollContentStack.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: scrollContentStack.trailingAnchor),
            ])
        }

        // 位置分区内部：标题与设备行铺满分区宽度（行内再按图标/名称/容量排布）
        NSLayoutConstraint.activate([
            placesHeaderView.leadingAnchor.constraint(equalTo: placesSectionView.leadingAnchor),
            placesHeaderView.trailingAnchor.constraint(equalTo: placesSectionView.trailingAnchor),
            placesRowsStack.leadingAnchor.constraint(equalTo: placesSectionView.leadingAnchor),
            placesRowsStack.trailingAnchor.constraint(equalTo: placesSectionView.trailingAnchor),
        ])

        // 首次加载设备列表（后台采集，回调在主线程重建行）
        refreshPlaces()

        // 任务 F10-3: 卷挂载/卸载监听已迁移至 MainWindowController（设备浮层负责刷新）（v0.6.6）

        // 首次布局：同步展开分区并同步内容高度（避免首帧收藏区高度为 0）；
        // 可用性校验另行异步（文件系统 I/O 不上主线程）
        reloadFavorites()
        validateFavoritesAvailability()
        // 监听标签数据源刷新通知，更新标签显示
        NotificationCenter.default.addObserver(self, selector: #selector(refreshTagDisplay), name: NSNotification.Name("SidebarTagsDidRefresh"), object: nil)

        // v0.6.9: 监听工具面板状态同步通知（覆盖页关闭时由 MainWindowController 回传状态）
        // 避免 isToolPanelExpanded 与实际显示状态不同步导致需点击两次才能重新打开
        NotificationCenter.default.addObserver(self, selector: #selector(handleToolPanelStateSync(_:)), name: NSNotification.Name("SidebarToolPanelDidToggle"), object: nil)

        // 监听主题变更，更新主题切换按钮图标
        ThemeManager.shared.onModeChanged = { [weak self] _ in
            self?.themeToggleBtn.image = NSImage(systemSymbolName: ThemeManager.shared.currentMode.iconName, accessibilityDescription: "切换主题")
        }

        // v0.8.0 P1: 卷挂载/卸载后重新校验收藏可用性（外置卷重插后失效项自动恢复）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleVolumesChanged(_:)),
            name: NSWorkspace.didMountNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleVolumesChanged(_:)),
            name: NSWorkspace.didUnmountNotification, object: nil
        )
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

    /// 统一的分区标题视图（2026-10-18 #5）
    ///
    /// 与「个人收藏」outline 组行逐项对齐：行高 22、11pt medium、secondaryLabel、
    /// 相对行左缘 6pt、基线距底 2pt。位置 / 标签两个外置标题由此与收藏标题严格对齐，
    /// 不再各写一套约束（此前标签标题少 6pt 缩进、行高 20）。
    private func makeSidebarSectionHeader(_ title: String, accessory: NSView? = nil) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = makeSectionTitleLabel(title)
        container.addSubview(label)

        var constraints: [NSLayoutConstraint] = [
            container.heightAnchor.constraint(equalToConstant: SidebarMetrics.sectionHeaderHeight),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ]
        if let accessory = accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(accessory)
            constraints += [
                accessory.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                accessory.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                accessory.widthAnchor.constraint(equalToConstant: 16),
                accessory.heightAnchor.constraint(equalToConstant: 16),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    /// v0.8.0 P1：侧边栏滚动容器
    ///
    /// overlay 细滚动条 + 透明背景 + 零 contentInsets。侧边栏中间内容（收藏 + 标签）
    /// 整体滚动，品牌区与底部工具行固定不动（访达同构）。
    private func makeSidebarScrollView() -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        // 任务 S1: 强制使用自定义细滚动条
        sv.verticalScroller = FFScroller()
        sv.scrollerStyle = .overlay
        sv.drawsBackground = false
        sv.backgroundColor = .clear
        sv.borderType = .noBorder
        // NSClipView 默认绘制 controlBackgroundColor（浅灰），必须显式清除
        sv.contentView.drawsBackground = false
        sv.contentView.backgroundColor = .clear
        // 顶部偏移会让首行内容压在品牌区下方留白（v0.7.2 设置页同类问题）
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets()
        sv.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return sv
    }

    private func makeOutlineView() -> FFFNoDisclosureOutlineView {
        let ov = FFFNoDisclosureOutlineView()
        ov.allowsMultipleSelection = false
        ov.headerView = nil  // 无表头
        // 收藏项行高 28pt（分区标题 22pt / 空态行 26pt 由数据源按行指定）
        ov.rowHeight = SidebarMetrics.rowHeight
        // 任务 F1: 收藏夹贴左边缘（Finder 风格，无缩进）
        ov.indentationPerLevel = 0
        // 行间距：水平无间距，垂直 0 间距——选中高亮由 FFSidebarRowView 自绘铺满整行，
        // 相邻选中行之间不留白色缝隙（自绘高亮上下铺满行框）
        ov.intercellSpacing = NSSize(width: 0, height: 0)
        // 选中样式：.regular——必须保留系统选中绘制机制，否则 NSTableRowView.drawSelection
        // 不会被调用（即便自定义了 FFSidebarRowView 子类也会被 .none 静默跳过 →「无高亮」根因）。
        // FFSidebarRowView.drawSelection 会绘制覆盖行内容区域的圆角矩形。
        ov.selectionHighlightStyle = .regular
        ov.backgroundColor = NSColor.clear
        // 禁止默认选中，避免启动时出现高亮
        ov.allowsEmptySelection = true
        ov.deselectAll(nil)
        // 禁用焦点框（蓝色边框），NSOutlineView 获得键盘焦点时不再显示蓝色 ring
        ov.focusRingType = .none
        // 行高由数据源按行指定，不使用自动行高
        ov.usesAutomaticRowHeights = false
        ov.translatesAutoresizingMaskIntoConstraints = false
        // 委托方法 rowViewForItem 在 SidebarDataSourceBase 中实现

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
        FFDebug.log("SidebarView.toggleTheme: 当前=\(ThemeManager.shared.currentMode.title) 新=\(newMode.title)")
        ThemeManager.shared.applyMode(newMode)
        FFDebug.log("SidebarView.toggleTheme: applyMode 返回后 NSApp.appearance=\(String(describing: NSApp.appearance?.name))")
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
        toolBtn.contentTintColor = isToolPanelExpanded ? FFAccent.current : .secondaryLabelColor

        // 通知 MainWindowController 显示/隐藏 ToolOverlayView + 设备浮层联动
        // Wave2 P0-4（多窗口）：object 携带本侧边栏实例身份，接收方据此过滤本窗口通知
        NotificationCenter.default.post(
            name: NSNotification.Name("SidebarToolPanelDidToggle"),
            object: self,
            userInfo: ["isExpanded": isToolPanelExpanded]
        )
    }

    /// v0.6.9: 同步工具面板状态（覆盖页通过关闭按钮/Esc 关闭时，MainWindowController 回传 isExpanded=false）
    /// 避免 isToolPanelExpanded 与实际显示状态不同步，导致下次点击需 toggle 两次才能重新打开
    @objc private func handleToolPanelStateSync(_ notification: Notification) {
        // Wave2 P0-4（多窗口）：仅响应本窗口发出（object=本侧边栏或所属窗口）的通知
        if let source = notification.object as? AnyObject, !(source === self), !(source === window) { return }
        guard let isExpanded = notification.userInfo?["isExpanded"] as? Bool else { return }
        // 仅同步状态不同步的情况（覆盖页关闭时回传 false）
        if isToolPanelExpanded != isExpanded {
            isToolPanelExpanded = isExpanded
            toolBtn.contentTintColor = isToolPanelExpanded ? FFAccent.current : .secondaryLabelColor
        }
    }

    // MARK: - 收藏操作（v0.8.0 P1）

    /// 右键菜单作用的收藏 id：优先取 clickedRow（右键点中的行），其次当前选中行
    private func clickedFavoriteID() -> String? {
        let row = favoritesOutlineView.clickedRow >= 0
            ? favoritesOutlineView.clickedRow
            : favoritesOutlineView.selectedRow
        guard row >= 0,
              case .favorite(let fav)? = favoritesOutlineView.item(atRow: row) as? SidebarItem else {
            return nil
        }
        return fav.id
    }

    /// 当前选中的收藏 id（重排/重校验后恢复选中用）
    private var selectedFavoriteID: String? {
        let row = favoritesOutlineView.selectedRow
        guard row >= 0,
              case .favorite(let fav)? = favoritesOutlineView.item(atRow: row) as? SidebarItem else {
            return nil
        }
        return fav.id
    }

    @objc private func removeFavorite(_ sender: Any?) {
        let id = (sender as? NSMenuItem)?.representedObject as? String ?? clickedFavoriteID()
        guard let favoriteID = id, favoritesStore.remove(id: favoriteID) else { return }
        reloadFavorites()
    }

    @objc private func moveFavoriteUp(_ sender: Any?) {
        let id = (sender as? NSMenuItem)?.representedObject as? String ?? clickedFavoriteID()
        guard let favoriteID = id, let index = favoritesStore.index(of: favoriteID),
              favoritesStore.moveUp(index: index) != nil else { return }
        reloadFavorites(selecting: favoriteID)
    }

    @objc private func moveFavoriteDown(_ sender: Any?) {
        let id = (sender as? NSMenuItem)?.representedObject as? String ?? clickedFavoriteID()
        guard let favoriteID = id, let index = favoritesStore.index(of: favoriteID),
              favoritesStore.moveDown(index: index) != nil else { return }
        reloadFavorites(selecting: favoriteID)
    }

    /// 在新标签页中打开（窗口级动作交由 MainWindowController）
    @objc private func openFavoriteInNewTab(_ sender: Any?) {
        guard let path = (sender as? NSMenuItem)?.representedObject as? String else { return }
        NotificationCenter.default.post(name: .sidebarDidRequestOpenInNewTab,
                                        object: favoritesOutlineView,
                                        userInfo: ["path": path])
    }

    /// 在新窗口中打开
    @objc private func openFavoriteInNewWindow(_ sender: Any?) {
        guard let path = (sender as? NSMenuItem)?.representedObject as? String else { return }
        NotificationCenter.default.post(name: .sidebarDidRequestOpenInNewWindow,
                                        object: favoritesOutlineView,
                                        userInfo: ["path": path])
    }

    /// 显示简介
    @objc private func showFavoriteInfo(_ sender: Any?) {
        guard let path = (sender as? NSMenuItem)?.representedObject as? String else { return }
        NotificationCenter.default.post(name: .sidebarDidRequestShowFavoriteInfo,
                                        object: favoritesOutlineView,
                                        userInfo: ["path": path])
    }

    // MARK: - 收藏刷新与校验

    /// 重建收藏 outline：展开分区、同步内容高度、按需恢复选中（不触发导航）
    /// 强调色变更后刷新选中态（选中底色由 FFSidebarRowView 自绘，需重载行才重绘）
    func refreshSelectionAppearance() {
        favoritesOutlineView?.reloadData()
        needsDisplay = true
    }

    private func reloadFavorites(selecting favoriteID: String? = nil) {
        favoritesOutlineView.reloadData()
        // 分区为 group item，需显式展开才会显示子行
        favoritesOutlineView.expandItem(nil, expandChildren: true)
        favoritesOutlineView.explicitContentHeight = favoritesDataSource.contentHeight
        if let favoriteID = favoriteID {
            selectFavorite(id: favoriteID)
        }
    }

    /// 按收藏 id 定位并选中（抑制导航副作用）
    private func selectFavorite(id: String) {
        for row in 0..<favoritesOutlineView.numberOfRows {
            guard case .favorite(let fav)? = favoritesOutlineView.item(atRow: row) as? SidebarItem else { continue }
            guard fav.id == id else { continue }
            favoritesDataSource.suppressSelectionNotification = true
            favoritesOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            favoritesDataSource.suppressSelectionNotification = false
            return
        }
    }

    /// Enter / 双击激活当前选中收藏
    private func navigateToSelectedFavorite() {
        guard let favoriteID = selectedFavoriteID,
              let favorite = favoritesStore.favorite(id: favoriteID) else { return }
        guard !favoritesStore.isMissing(id: favoriteID) else {
            NSSound.beep()
            return
        }
        let entry = FileEntry(path: favorite.path, name: favorite.name, isDirectory: true)
        NotificationCenter.default.post(name: .sidebarDidSelectDirectory,
                                        object: favoritesOutlineView,
                                        userInfo: ["entry": entry])
    }

    /// 后台校验收藏路径可用性（去抖 500ms，避免与首屏渲染争用主线程）
    private func validateFavoritesAvailability() {
        let store = favoritesStore
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            var result: [String: FavoriteAvailability] = [:]
            for item in store.items {
                result[item.id] = FileManager.default.fileExists(atPath: item.path) ? .available : .missing
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                for (id, state) in result {
                    store.setAvailability(state, for: id)
                }
                self.reloadFavorites(selecting: self.selectedFavoriteID)
            }
        }
    }

    /// 卷挂载/卸载后重新校验（外置卷重插后失效收藏自动恢复，不删除）
    @objc private func handleVolumesChanged(_ notification: Notification) {
        validateFavoritesAvailability()
        // 2026-10-18 #4：位置分区随卷变化刷新
        refreshPlaces()
    }

    // MARK: - 位置分区（2026-10-18 #4）

    /// 后台加载设备列表，回调在主线程重建行（采集期间保留上次结果，不闪烁）
    private func refreshPlaces() {
        placesDataSource.loadDevices { [weak self] in
            self?.rebuildPlaceRows()
        }
    }

    private func rebuildPlaceRows() {
        placesRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for dev in placesDataSource.devices {
            let row = makePlaceRow(dev)
            placesRowsStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: SidebarMetrics.rowHeight),
                row.widthAnchor.constraint(equalTo: placesRowsStack.widthAnchor),
            ])
        }
    }

    /// 设备行复用 DeviceCellView（图标 + 名称 + 可用空间 + 悬停气泡），点击在活动面板打开该卷根目录
    private func makePlaceRow(_ dev: DeviceItem) -> NSView {
        let cell = DeviceCellView()
        cell.configure(dev: dev, extInfo: placesDataSource.deviceExtendedInfo[dev.path])
        cell.identifier = NSUserInterfaceItemIdentifier(dev.path)
        cell.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handlePlaceRowClick(_:))))
        return cell
    }

    @objc private func handlePlaceRowClick(_ sender: NSClickGestureRecognizer) {
        guard let path = sender.view?.identifier?.rawValue else { return }
        let name = (path as NSString).lastPathComponent
        let entry = FileEntry(path: path, name: name.isEmpty ? path : name, isDirectory: true)
        // 复用收藏导航通知：MainWindowController 收到后在活动面板打开该路径
        NotificationCenter.default.post(name: .sidebarDidSelectDirectory, object: self, userInfo: ["entry": entry])
    }

    // MARK: - 单/双窗口切换（2026-10-18 #3）

    @objc private func handlePaneModeToggle() {
        NotificationCenter.default.post(name: .sidebarDidTogglePaneMode, object: self)
    }

    /// 由 MainWindowController 在模式变化/启动恢复时回写按钮外观
    func setSinglePaneMode(_ single: Bool) {
        let symbol = single ? "rectangle" : "rectangle.split.2x1"
        paneModeButton?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: single ? "切换到双窗口" : "切换到单窗口"
        )
        paneModeButton?.toolTip = single ? "切换到双窗口" : "切换到单窗口"
    }

    @objc private func removeTag(_ sender: NSMenuItem?) {
        guard let tagId = sender?.representedObject as? String else { return }
        tagsDataSource.removeTag(id: tagId)
        tagFlowView.updateTags(tagsDataSource.allTags())
    }

    /// 标签数据源刷新后更新标签流视图显示
    @objc private func refreshTagDisplay() {
        tagFlowView.updateTags(tagsDataSource.allTags())
    }

    /// 更新标签计数（DESIGN-SPEC §5.2）。
    /// 由 MainWindowController 在活动面板目录/内容变化后推送，key 为标签名。
    /// 空字典表示「本目录不统计」（超上限或统计失败），侧栏不显示数字。
    func updateTagCounts(_ counts: [String: Int]) {
        tagFlowView.updateCounts(counts)
    }

    /// 任务 F11-8: 处理面板标签筛选变化通知，更新标签行高亮。
    /// userInfo["tagFilter"] 为当前活动面板的 tagFilter（Tag 或 nil），用于高亮对应标签行。
    @objc private func handlePaneTagFilterChanged(_ notification: Notification) {
        // Wave2 P0-4（多窗口）：仅响应本窗口面板发出的筛选变化（object=所属窗口），
        // object 为 nil 时兼容旧 poster。避免 A 窗口的面板激活高亮到 B 窗口侧边栏。
        if let owner = notification.object as? NSWindow, !(owner === window) { return }
        let tagFilter = notification.userInfo?["tagFilter"] as? Tag
        tagFlowView.setHighlightedTagId(tagFilter?.id)
    }

    /// 任务 F11-8: 清理通知观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 添加收藏夹（供外部调用）
    func addFavorite(name: String, path: String) {
        let favorite = favoritesStore.add(name: name, path: path)
        // 新增项立即可用（路径刚由用户选中/拖入，无需等待异步校验）
        favoritesStore.setAvailability(.available, for: favorite.id)
        reloadFavorites(selecting: favorite.id)
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
        // v0.7.4 项 1：统一改用共享模块 FFCreateTagDialog（预设色块 + 自定义系统颜色选择器）
        FFCreateTagDialog.showCreateTagDialogAndSave(on: window) { [weak self] _ in
            guard let self = self else { return }
            self.tagFlowView.updateTags(self.tagsDataSource.allTags())
        }
    }

    // MARK: - Refresh

    // 任务 F10-3: 设备刷新逻辑（refreshDevices/updateDeviceHeight）已迁移至 MainWindowController 浮层（v0.6.6）
    //
    // v0.8.0 P1: updateFavoritesHeight / updateTagsHeight 与两条定高约束一并移除。
    // 高度改由内容驱动（outline.intrinsicContentSize + TagFlowView.intrinsicContentSize），
    // 收藏 20+ 项时侧边栏整体滚动，不再出现"定高溢出重叠"与"required 约束瞬态无解"。
}

// MARK: - SidebarView + NSMenuDelegate

extension SidebarView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard menu === favoritesOutlineView.menu else { return }
        // 收藏夹右键菜单：分区标题行/空态行不弹业务菜单
        guard let favoriteID = clickedFavoriteID(),
              let index = favoritesStore.index(of: favoriteID) else { return }
        let missing = favoritesStore.isMissing(id: favoriteID)

        let removeItem = menu.addItem(withTitle: "从边栏中移除",
                                      action: #selector(removeFavorite(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = favoriteID

        menu.addItem(.separator())

        // 「在新标签页中打开」：宿主窗口不支持标签页时置灰（设计稿 §4.2）
        let newTabItem = menu.addItem(withTitle: "在新标签页中打开",
                                      action: #selector(openFavoriteInNewTab(_:)), keyEquivalent: "")
        newTabItem.target = self
        newTabItem.representedObject = favoritePath(for: favoriteID)
        newTabItem.isEnabled = (window?.tabbingMode ?? .disallowed) != .disallowed && !missing

        let newWindowItem = menu.addItem(withTitle: "在新窗口中打开",
                                         action: #selector(openFavoriteInNewWindow(_:)), keyEquivalent: "")
        newWindowItem.target = self
        newWindowItem.representedObject = favoritePath(for: favoriteID)
        newWindowItem.isEnabled = !missing

        let infoItem = menu.addItem(withTitle: "显示简介",
                                    action: #selector(showFavoriteInfo(_:)), keyEquivalent: "")
        infoItem.target = self
        infoItem.representedObject = favoritePath(for: favoriteID)
        infoItem.isEnabled = !missing

        menu.addItem(.separator())

        let upItem = menu.addItem(withTitle: "上移",
                                  action: #selector(moveFavoriteUp(_:)), keyEquivalent: "")
        upItem.target = self
        upItem.representedObject = favoriteID
        upItem.isEnabled = index > 0

        let downItem = menu.addItem(withTitle: "下移",
                                    action: #selector(moveFavoriteDown(_:)), keyEquivalent: "")
        downItem.target = self
        downItem.representedObject = favoriteID
        downItem.isEnabled = index < favoritesStore.items.count - 1
    }

    private func favoritePath(for id: String) -> String? {
        favoritesStore.favorite(id: id)?.path
    }
}

// MARK: - TagColorHolder (颜色选择辅助类)

private class TagColorHolder: NSObject {
    private let colors: [String]
    private(set) var selectedHex: String
    /// 颜色圆点引用数组（纯视图无 tag，用数组下标定位点击的 dot）
    var dotDots: [NSView] = []

    init(colors: [String]) {
        self.colors = colors
        self.selectedHex = colors.first ?? "#007AFF"
        super.init()
    }

    @objc func selectDot(_ sender: NSClickGestureRecognizer) {
        guard let dot = sender.view, let idx = dotDots.firstIndex(of: dot), idx < colors.count else { return }
        selectedHex = colors[idx]
        // 更新选中边框
        for (i, d) in dotDots.enumerated() {
            d.layer?.borderWidth = (i == idx) ? 2 : 0
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

    /// v0.8.0 P1: 程序化选中（重排后恢复选中）不应触发导航
    var suppressSelectionNotification = false

    /// v0.8.0 P1: 导航许可判定（失效收藏返回 false，点击/Enter 均无动作）
    var isItemNavigable: ((SidebarItem) -> Bool)?

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

    // MARK: - 自定义行视图（自绘选中高亮）

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowID = NSUserInterfaceItemIdentifier("SidebarRow")
        let row = (outlineView.makeView(withIdentifier: rowID, owner: self) as? FFSidebarRowView)
            ?? FFSidebarRowView()
        row.identifier = rowID
        return row
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
            // 修复问题 1（访达风格内缩）：图标不再贴行最左边（+0），改为往里缩 6pt。
            // 蓝色高亮（FFSidebarRowView.drawSelection）左右各内缩 3pt，是"飘在侧边栏中间"的圆角块。
            // 图标在 +6pt 即落在高亮内部（高亮左缘 +3pt 到图标左缘 +6pt 之间留 3pt 蓝边），
            // 与 macOS 访达侧边栏一致；文字本就在 trailing -6pt（高亮右缘内侧）。
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
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
            // T13: 侧边栏条目无障碍标签（名称 + 选中状态）
            let isSelected = outlineView.selectedRowIndexes.contains(outlineView.row(forItem: item))
            cell.setAccessibilityLabel(FileEntryAccessibility.sidebarLabel(name: fav.name, isSelected: isSelected))
            // 任务 F10-4: 修正 F4 错误 - 收藏夹改回彩色真实图标（v0.6.6）
            // F4 错误地改为蓝色模板 SF Symbols，应使用 NSWorkspace 真实位置图标
            // 放大对齐访达 20pt，contentTintColor = nil 保留彩色（移除 F4 的 controlAccentColor）
            // B-06（v0.8.0）：标准位置改用专属彩色图标——系统文件夹图标在 20pt 下
            // 内嵌符号几乎不可见，桌面/文稿/下载/应用程序看起来完全一样。
            // 非标准位置仍回退真实文件图标（B-05 不变）。
            if let standard = FFStandardLocationIcon.icon(forPath: fav.path) {
                imageView.image = standard
            } else {
                let workspaceIcon = NSWorkspace.shared.icon(forFile: fav.path)
                workspaceIcon.size = NSSize(width: 20, height: 20)
                imageView.image = workspaceIcon
            }
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
        // v0.8.0 P1: 程序化恢复选中（拖拽重排/后台校验后）不得触发导航
        guard !suppressSelectionNotification else { return }
        guard let outlineView = notification.object as? NSOutlineView else { return }
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 else { return }

        let item = outlineView.item(atRow: selectedRow)
        guard let sidebarItem = item as? SidebarItem else { return }
        // 失效收藏拦截（灰显项点击不作导航）
        if let isNavigable = isItemNavigable, !isNavigable(sidebarItem) { return }

        switch sidebarItem {
        case .favorite(let fav):
            let entry = FileEntry(path: fav.path, name: fav.name, isDirectory: true)
            // Wave2 P0-4（多窗口）：object 携带发起选择的 outlineView（本窗口视图），
            // entry 移入 userInfo，接收方按视图归属过滤本窗口通知（避免 A 窗口点击导航到 B 窗口）。
            // 注意：不能发数据源对象（NSObject 非 NSView）——接收方 isOwnSidebarNotification
            // 的视图归属判定会 cast 失败而误杀本窗口导航（「收藏无法点开」根因）
            NotificationCenter.default.post(name: .sidebarDidSelectDirectory, object: outlineView,
                                            userInfo: ["entry": entry])
        case .device(let dev):
            let entry = FileEntry(path: dev.path, name: dev.name, isDirectory: true)
            // B10: 同时附带 userInfo，便于新监听者按需读取；object 携带发起选择的 outlineView（本窗口视图）
            NotificationCenter.default.post(name: .sidebarDidSelectDirectory, object: outlineView,
                                            userInfo: ["entry": entry, "path": dev.path])
        case .tag:
            // 标签点击可选不做导航（未来可筛选同名标签文件）
            break
        }
    }
}

// MARK: - FavoritesSidebarDataSource（收藏分区，v0.8.0 P1 分区模型）

/// 收藏分区数据源
///
/// 结构：root → [「个人收藏」分区标题节点] → [收藏项… / 空态引导行]
/// - 分区标题为 group item：不折叠、不可选中、行高 22pt（访达样式）
/// - 收藏项行高 28pt；失效项灰显但保留（外置卷重插后自动恢复）
/// - 内部拖拽走自定义粘贴板类型，与外部文件拖拽区分（外部文件夹=添加收藏）
private final class FavoritesSidebarDataSource: SidebarDataSourceBase {

    /// 内部重排的粘贴板类型
    static let dragType = NSPasteboard.PasteboardType("com.flowfinder.sidebar.favorite")

    let store: SidebarFavoritesStore

    /// 收藏集合变化回调（增删/重排/外部拖入后通知 SidebarView 重建 outline）
    var onFavoritesChanged: (() -> Void)?

    private let favoritesSection = SidebarSectionNode(kind: .favorites)
    private let emptyHint = SidebarEmptyHintNode(text: "拖入文件夹以添加收藏")

    init(store: SidebarFavoritesStore) {
        self.store = store
        super.init()
        // 失效收藏不导航（灰显项点击/Enter 均无动作）
        isItemNavigable = { [weak self] item in
            guard let self = self, case .favorite(let fav) = item else { return true }
            return !self.store.isMissing(id: fav.id)
        }
    }

    /// outline 内容高度（分区标题 + 收藏行 / 空态行）
    var contentHeight: CGFloat {
        let body = store.items.isEmpty
            ? SidebarMetrics.emptyHintHeight
            : CGFloat(store.items.count) * SidebarMetrics.rowHeight
        return SidebarMetrics.sectionHeaderHeight + body
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        // root 只有一个分区；分区下为收藏项（空收藏时显示一行引导）
        guard let item = item else { return 1 }
        if item is SidebarSectionNode {
            return max(store.items.count, 1)
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard item is SidebarSectionNode else { return favoritesSection }
        if store.items.isEmpty { return emptyHint }
        return SidebarItem.favorite(store.items[index])
    }

    override func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is SidebarSectionNode
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is SidebarSectionNode
    }

    override func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // 分区标题与空态行不可选中
        item is SidebarItem
    }

    override func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is SidebarSectionNode { return SidebarMetrics.sectionHeaderHeight }
        if item is SidebarEmptyHintNode { return SidebarMetrics.emptyHintHeight }
        return SidebarMetrics.rowHeight
    }

    // MARK: - NSOutlineViewDelegate（分区 / 空态 / 失效渲染）

    override func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let section = item as? SidebarSectionNode {
            return makeSectionHeaderCell(title: section.kind.title)
        }
        if let hint = item as? SidebarEmptyHintNode {
            return makeEmptyHintCell(text: hint.text)
        }
        // 收藏项沿用基类「图标 + 文字」布局，再叠加失效态
        let baseCell = super.outlineView(outlineView, viewFor: tableColumn, item: item)
        if case .favorite(let fav)? = item as? SidebarItem, let cell = baseCell as? NSTableCellView {
            let missing = store.isMissing(id: fav.id)
            cell.imageView?.alphaValue = missing ? 0.4 : 1.0
            cell.textField?.textColor = missing ? NSColor.secondaryLabelColor : NSColor.labelColor
            cell.toolTip = missing ? "找不到该文件夹" : fav.path
        }
        return baseCell
    }

    /// 分区标题 cell：11pt medium 次级色，左缘与收藏图标对齐
    private func makeSectionHeaderCell(title: String) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("SidebarSectionCell")
        let cell = NSTableCellView()
        cell.identifier = cellID
        cell.subviews.forEach { $0.removeFromSuperview() }

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            // NSOutlineView 会给组行额外 16pt 缩进（即使 indentationPerLevel=0），
            // 组标题因此比普通行右移 16pt。这里用 -10 抵消（6 − 16），
            // 使「个人收藏」与「位置」「标签」三个外置标题落在同一 x（实测均 290）。
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: -10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),
        ])
        cell.setAccessibilityElement(true)
        cell.setAccessibilityRole(.group)
        cell.setAccessibilityLabel(title)
        return cell
    }

    /// 空态引导 cell：次级色小字，不可选中
    private func makeEmptyHintCell(text: String) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("SidebarEmptyHintCell")
        let cell = NSTableCellView()
        cell.identifier = cellID
        cell.subviews.forEach { $0.removeFromSuperview() }

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - 拖拽（外部添加 + 内部重排）

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard case .favorite(let fav)? = item as? SidebarItem else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fav.id, forType: Self.dragType)
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        // 内部重排：必须落在分区内且给出明确插入位置（落在行上=重新排序的父级调整，忽略）
        if info.draggingPasteboard.availableType(from: [Self.dragType]) != nil {
            guard store.items.count > 1, index != NSOutlineViewDropOnItemIndex else { return [] }
            let target = (item as? SidebarSectionNode) != nil ? item : favoritesSection
            outlineView.setDropItem(target, dropChildIndex: min(max(index, 0), store.items.count))
            return .move
        }
        // 外部拖拽：仅接受文件 URL（是否文件夹由 acceptDrop 过滤）
        guard info.draggingPasteboard.types?.contains(.fileURL) == true else { return [] }
        outlineView.setDropItem(favoritesSection, dropChildIndex: store.items.count)
        return .copy
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        // 内部重排
        if let id = info.draggingPasteboard.string(forType: Self.dragType) {
            guard let from = store.index(of: id) else { return false }
            guard store.move(fromIndex: from, insertionIndex: min(max(index, 0), store.items.count)) else {
                return false
            }
            onFavoritesChanged?()
            return true
        }
        // 外部拖入文件夹 = 添加收藏（设计 D2 默认：不移动文件，防误操作）
        guard let pasteboardItems = info.draggingPasteboard.pasteboardItems else { return false }
        var addedCount = 0
        for pasteboardItem in pasteboardItems {
            guard let urlData = pasteboardItem.data(forType: .fileURL),
                  let url = URL(dataRepresentation: urlData, relativeTo: nil) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let favorite = store.add(name: url.lastPathComponent, path: url.path)
            store.setAvailability(.available, for: favorite.id)
            addedCount += 1
        }
        guard addedCount > 0 else { return false }
        onFavoritesChanged?()
        return true
    }
}

// MARK: - FlippedSidebarContainer（v0.8.0 P1 滚动文档视图）

/// 侧边栏滚动容器：isFlipped=true，内容天然贴顶。
/// 非 flipped 的 documentView 会让内容贴底并在顶部留白（v0.7.2 设置页同类根因）。
private final class FlippedSidebarContainer: NSView {
    override var isFlipped: Bool { true }
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
        // Wave1 P0-3：不再在 init 内同步 loadDevices（旧实现会在主线程同步
        // spawn mount/df 子进程，可阻塞数秒）。设备数据改为后台加载，由
        // 使用方（MainWindowController 设备浮层）在 setup 时调用
        // refreshDevicePanel() → loadDevices(completion:) 触发首次加载。
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

    /// 加载设备列表（Wave1 P0-3：数据采集整体后台化）
    ///
    /// 旧实现在调用线程（主线程）同步执行 listVolumes（Rust 侧 spawn mount/df
    /// 子进程，挂载失联 SMB/NFS 时 df 可挂起数秒）+ 逐卷 statfs，主线程冻结；
    /// 且设备浮层的挂载/卸载通知路径每次事件都会同步重刷。现将采集移入后台
    /// 队列，主线程仅做数据源赋值与回调刷新：
    /// - 采集期间保留上次结果（浮层不闪烁）；首次加载显示既有空态；
    /// - 数据就绪后在主线程一次性替换 devices / deviceExtendedInfo，
    ///   随后触发 completion 重建 UI（outlineView 数据源仅在主线程读写）。
    /// - Parameter completion: 主线程回调（数据已就绪，可安全重建 UI）；可为 nil
    func loadDevices(completion: (() -> Void)? = nil) {
        // NSHost 文档未保证后台线程安全：主线程先取本机名快照，后台仅做字符串比较
        let currentLocalizedName = Host.current().localizedName

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let volumes = CoreBridge.shared.listVolumes()
            var newDevices: [DeviceItem] = []
            var newInfo: [String: DeviceExtendedInfo] = [:]

            // 1. 始终添加主硬盘（根目录 /）
            let rootURL = URL(fileURLWithPath: "/")
            var rootName = "Macintosh HD"
            if let name = try? rootURL.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName,
               !name.isEmpty, name != currentLocalizedName {
                rootName = name
            }
            let rootSpace = self.getDiskSpace(at: "/")
            let rootFsType = self.getFileSystemType(at: "/") ?? "apfs"
            newDevices.append(DeviceItem(
                name: rootName,
                path: "/",
                isRemovable: false,
                isNetwork: false,
                totalSize: rootSpace?.total ?? 0,
                freeSize: rootSpace?.free ?? 0
            ))
            newInfo["/"] = DeviceExtendedInfo(
                fileSystemType: rootFsType,
                mountPoint: "/",
                totalSize: rootSpace?.total ?? 0,
                freeSize: rootSpace?.free ?? 0
            )

            // 2. 添加用户主目录（作为快捷设备入口）
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            let homeName = homePath.components(separatedBy: "/").last ?? "Home"
            let homeSpace = self.getDiskSpace(at: homePath)
            let homeFsType = self.getFileSystemType(at: homePath) ?? "apfs"
            newDevices.append(DeviceItem(
                name: homeName,
                path: homePath,
                isRemovable: false,
                isNetwork: false,
                totalSize: homeSpace?.total ?? 0,
                freeSize: homeSpace?.free ?? 0
            ))
            newInfo[homePath] = DeviceExtendedInfo(
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
                if self.isSystemHiddenVolume(name: volName, path: vol.path) { continue }

                // B11: 使用 statfs 读取真实磁盘容量（覆盖 Rust 端的值）
                let realSpace = self.getDiskSpace(at: vol.path)
                let totalSize = realSpace?.total ?? vol.totalSize
                let freeSize = realSpace?.free ?? vol.freeSize
                let fsType = self.getFileSystemType(at: vol.path) ?? vol.fsType

                let isNetwork = vol.fsType.lowercased().contains("smb")
                    || vol.fsType.lowercased().contains("nfs")
                    || vol.fsType.lowercased().contains("afp")
                    || fsType.lowercased().contains("smb")
                    || fsType.lowercased().contains("nfs")
                    || fsType.lowercased().contains("afp")

                newDevices.append(DeviceItem(
                    name: volName,
                    path: vol.path,
                    isRemovable: vol.isRemovable,
                    isNetwork: isNetwork,
                    totalSize: totalSize,
                    freeSize: freeSize
                ))
                newInfo[vol.path] = DeviceExtendedInfo(
                    fileSystemType: fsType,
                    mountPoint: vol.path,
                    totalSize: totalSize,
                    freeSize: freeSize
                )
            }

            // 数据就绪：主线程一次性替换数据源（ outlineView 读取均在主线程）
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.devices = newDevices
                self.deviceExtendedInfo = newInfo
                completion?()
            }
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

        nameField.font = NSFont.systemFont(ofSize: 13)
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
        freeField.font = NSFont.systemFont(ofSize: 11)
        freeField.textColor = NSColor.secondaryLabelColor
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
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
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
/// 标签行视图（DESIGN-SPEC §5.2）
///
/// 行式布局的三态背景：
/// - 常态：透明
/// - 悬停：`labelColor` 6%
/// - 筛选态：`controlAccentColor` 15%
///
/// 用 layer 背景而非绘制，是因为标签行会在悬停/筛选切换时高频改色；
/// 动态色必须经 `performAsCurrentDrawingAppearance` 解析，否则深浅色切换后
/// `cgColor` 会停留在旧外观（项目内既有同类坑，见 FFPanelView）。
private class TagRowView: NSView {

    var isFiltered: Bool = false {
        didSet { guard isFiltered != oldValue else { return }; applyBackground() }
    }

    private var isHovered: Bool = false {
        didSet { guard isHovered != oldValue else { return }; applyBackground() }
    }

    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 5
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
    }

    private func applyBackground() {
        let color: NSColor
        if isFiltered {
            color = NSColor.controlAccentColor.withAlphaComponent(0.15)
        } else if isHovered {
            color = NSColor.labelColor.withAlphaComponent(0.06)
        } else {
            color = .clear
        }
        var resolved = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = resolved
        CATransaction.commit()
    }
}

private class TagFlowView: NSView {

    // MARK: - Callbacks

    var onAddTagTapped: (() -> Void)?
    var onTagDeleted: ((String) -> Void)?
    var onTagSelected: ((Tag) -> Void)?

    // MARK: - State

    private var tags: [Tag] = []
    /// 任务 F11-8: 当前高亮的标签 id（来自活动面板的 tagFilter），nil 表示无高亮
    private var highlightedTagId: String?
    /// 标签计数：key = 标签名。原生标签（`_kMDItemUserTags`）每次读取生成随机 id，
    /// 不能作 key，故一律按名称匹配（与 TagBridge 的合并去重口径一致）。
    private var counts: [String: Int] = [:]

    // MARK: - UI Elements

    /// 标签行垂直列表容器（NSStackView，vertical）
    private let listContainer: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        // 行式：每行铺满侧栏宽度（计数需右对齐），故用 .width 而非 .leading 对齐
        sv.alignment = .width
        sv.spacing = 2                   // 行式行间距 2pt（DESIGN-SPEC §5.2）
        sv.distribution = .fill           // 各行按内容填充
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.wantsLayer = true
        sv.layer?.backgroundColor = NSColor.clear.cgColor
        return sv
    }()

    // MARK: - Layout Constants (行式，DESIGN-SPEC §5.2)

    /// 行高 24pt
    private let rowHeight: CGFloat = 24
    /// 行间距 2pt
    private let rowSpacing: CGFloat = 2
    private let dotSize: CGFloat = 8
    /// 行左内边距（色点距行左缘）
    private let rowPaddingLeading: CGFloat = 6
    /// 行右内边距（计数距行右缘）
    private let rowPaddingTrailing: CGFloat = 6
    /// 圆点与文字间距
    private let dotLabelGap: CGFloat = 6
    /// 行背景圆角
    private let rowCornerRadius: CGFloat = 5

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

    /// 更新标签计数（DESIGN-SPEC §5.2）。key 为标签名，0 / 缺失一律不显示数字。
    func updateCounts(_ newCounts: [String: Int]) {
        guard newCounts != counts else { return }
        counts = newCounts
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

    /// 计算指定宽度下的理想高度（供外部布局参考）
    /// 无 header：高度 = 行数 × 24pt + 行间距 2pt
    func idealHeight(forWidth width: CGFloat) -> CGFloat {
        let rowsHeight = CGFloat(tags.count) * rowHeight
        let spacing = CGFloat(max(tags.count - 1, 0)) * rowSpacing
        return rowsHeight + spacing
    }

    /// v0.8.0 P1: 高度由内容驱动，替代外部 tagsHeightConstraint 定高约束
    /// （定高约束在标签数超出估算值时必然无解，是 2026-08-28 冲突日志与
    ///  「收藏/标签重叠」缺陷的结构性来源）
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(idealHeight(forWidth: bounds.width), 1))
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
            let row = makeTagRow(tag: tag)
            listContainer.addArrangedSubview(row)
            // 行式：宽度由 listContainer 的 .width 对齐自动铺满，此处只需固定行高
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }
        // 行集合变化后高度随之变化（intrinsicContentSize 驱动外层 stack）
        invalidateIntrinsicContentSize()
    }

    // MARK: - Tag Row Creation (行式：色点 + 名称 + 计数，DESIGN-SPEC §5.2)

    /// 创建标签行：色点 + 名称 + 右侧计数，整行铺满侧栏宽度
    /// 常态透明，悬停 6% 底，筛选态 15% 强调色底 + 名称加粗（不再使用药丸底）
    private func makeTagRow(tag: Tag) -> NSView {
        let isHighlighted = (highlightedTagId == tag.id)
        let tagColor = NSColor(hex: tag.color) ?? .systemBlue

        let row = TagRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.identifier = NSUserInterfaceItemIdentifier(tag.id)
        row.isFiltered = isHighlighted
        row.toolTip = tag.name

        // 圆点（8x8，tag.color）
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tagColor.cgColor
        dot.layer?.cornerRadius = dotSize / 2
        dot.translatesAutoresizingMaskIntoConstraints = false

        // 名称（13pt；筛选态加粗）
        let label = NSTextField(labelWithString: tag.name)
        label.font = isHighlighted
            ? NSFont.boldSystemFont(ofSize: 13)
            : NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        // 名称吸收剩余宽度，把计数推到最右；空间不足时优先截断名称
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 计数（11pt 次级灰，右对齐；0 / 未知不显示）
        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = NSColor.secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let count = counts[tag.name] ?? 0
        countLabel.stringValue = count > 0 ? "\(count)" : ""
        countLabel.isHidden = count <= 0

        row.addSubview(dot)
        row.addSubview(label)
        row.addSubview(countLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowPaddingLeading),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: dotLabelGap),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -rowPaddingTrailing),
            countLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // 右键菜单（删除标签）
        let menu = NSMenu()
        let mi = NSMenuItem(title: "删除标签", action: #selector(handleDeleteTag(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = tag.id
        menu.addItem(mi)
        row.menu = menu

        // 点击选择（整行可点）
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleRowClick(_:)))
        row.addGestureRecognizer(click)

        return row
    }

    @objc private func handleDeleteTag(_ sender: NSMenuItem) {
        guard let tagId = sender.representedObject as? String else { return }
        // 查找标签名用于确认对话框
        guard let tag = tags.first(where: { $0.id == tagId }) else { return }
        // 确认对话框（删除标签不可撤销，将从所有文件中移除）
        let alert = NSAlert()
        alert.messageText = "删除标签"
        alert.informativeText = "此操作将从所有文件中移除「\(tag.name)」标签，且不可撤销。确定继续？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onTagDeleted?(tagId)
    }

    @objc private func handleRowClick(_ sender: NSClickGestureRecognizer) {
        guard let tagId = sender.view?.identifier?.rawValue else { return }
        if let tag = tags.first(where: { $0.id == tagId }) {
            onTagSelected?(tag)
        }
    }
}
