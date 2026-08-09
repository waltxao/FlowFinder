import Cocoa
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import PDFKit

// MARK: - ExpandableDetailsBar

/// 可展开的文件详情面板
///
/// 收起状态（高度 54pt）：
///   - 左侧：选中文件的高清预览图标（32x32，`NSWorkspace.shared.icon(forFile:)`）
///   - 中间：文件名 + 大小（单行，13pt medium）
///   - 右侧：展开按钮（chevron.up SF Symbol）
///
/// 展开状态（高度 210pt）：
///   - 左侧：大尺寸预览图标（96x96，异步加载 QuickLook 缩略图，垂直居中）
///   - 右侧两列信息：
///     - 第一列：种类 / 大小 / 位置 / 创建日期 / 修改日期
///     - 第二列：标签（药丸，可点击筛选 / 右键移除）/ 文件说明（双击编辑）/ 文件来源
///   - 底部：文件类型专属信息（分辨率 / 色彩空间 / EXIF / 时长 / 编码 等）
///
/// 接口：
///   - `update(with entry: FileEntry?)` 更新显示的文件信息
///   - `isExpanded: Bool` 展开/收起状态
class ExpandableDetailsBar: NSView {

    // MARK: - Constants

    /// 收起态高度 36pt + 状态栏 18pt = 54pt
    private let collapsedHeight: CGFloat = 54
    /// 展开态高度 192pt + 状态栏 18pt = 210pt
    private let expandedHeight: CGFloat = 210
    /// 状态栏高度
    private let statusBarHeight: CGFloat = 18

    // MARK: - State

    private var entry: FileEntry?
    private var selectedCount: Int = 0
    /// v0.7.4 修订: 完整选中数组（多选时用于汇总显示）
    private var selectedFiles: [FileEntry] = []

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
    /// 1.6 收起态副字段：12pt secondary，显示 "大小 · 类型"
    private weak var compactSubField: NSTextField?

    // expanded
    private let bigIconView = NSImageView()
    // 1.6 字段顺序：种类 / 大小 / 位置 / 创建日期 / 修改日期 / 标签
    // v0.7.4 项 3：新增"名称"行（第一列最上方），单击可改名
    private let nameField = NSTextField(labelWithString: "")
    private let typeField = NSTextField(labelWithString: "")
    private let sizeField = NSTextField(labelWithString: "")
    private let locationField = NSTextField(labelWithString: "")
    private let createdField = NSTextField(labelWithString: "")
    private let modifiedField = NSTextField(labelWithString: "")
    private let tagsContainer = NSStackView()
    /// v0.7.4 项 4：标签行编辑按钮（点击弹出标签选择弹窗）
    private let tagsEditButton = NSButton()

    // 第二列字段：文件说明 / 文件来源
    private let descriptionField = NSTextField(labelWithString: "")
    private let sourceField = NSTextField(labelWithString: "")
    /// 文件类型专属信息容器（展开态底部，两列下方）
    private let fileTypeInfoContainer = NSStackView()
    /// 第一列信息容器（种类/大小/位置/日期 + 文件类型专属信息合并追加）
    /// 问题 7：提升为存储属性，使 updateFileTypeSpecificInfo 能把专属信息行追加到主信息列，
    /// 不再单独开两列（视觉上与其他列对齐、连贯）
    private var mainColumn1: NSStackView!
    /// 第二列信息容器（标签/文件说明/文件来源）
    private var mainColumn2: NSStackView!

    // v0.7.4 项 7：所有信息行的引用（多选/未选时隐藏空白条目，单选时显示）
    private var infoRows: [NSView] = []

    // v0.7.4 修订 4：单选内容行（图标 + 两列）与多选内容行（图标 + 两列汇总）
    private var singleContentRow: NSStackView!
    private var multiContentRow: NSStackView!
    /// 多选大图标（缩略图堆叠）
    private var multiIconView: FFMiniThumbnailStackView!

    /// v0.7.4 项 3：文件名编辑回调（由 MainWindowController 注入，调用 PaneViewModel.renameFile）。
    /// 参数：旧路径、新名字。详情栏不直接持有 viewModel，通过此闭包让控制器执行改名。
    var onRename: ((String, String) -> Void)?

    /// v0.7.4 修订 2：标签变更回调（用于注册撤销）。由 MainWindowController 注入。
    /// - .add: 添加了标签；.remove: 移除了标签
    var onUndoableTagChange: ((TagChangeKind, Tag, String) -> Void)?

    /// v0.7.4 修订 4：当前所在文件夹路径（未选中时显示该文件夹图标）
    private var currentDirectoryPath: String?

    /// E2: 缩略图是否已成功加载（置位后工作区图标回调不再覆盖大图标）
    private var didReceiveThumbnail = false

    /// E3: 多选汇总异步计算代次（快速切换选择时旧任务结果被丢弃）
    private var multiSelectGeneration: Int = 0

    /// 标签变更类型（用于撤销注册）
    enum TagChangeKind {
        case add
        case remove
    }

    /// 当前正在请求缩略图的路径（用于避免过期回调覆盖）
    private var thumbnailLoadPath: String?

    /// 任务 F11-7: 当前正在请求工作区图标的路径（用于避免过期回调覆盖）。
    /// 点击选中时 refresh() -> setRealFileIcon 会异步获取图标，用户快速切换选中项时
    /// 需校验回调返回时仍显示同一文件，否则会闪烁/显示错误图标。
    private var iconLoadPath: String?

    /// 问题7: 状态栏标签（项目数 + 磁盘可用空间），由 updateStatus(itemCount:diskFree:) 更新
    private var statusLabel: NSTextField?

    // v0.7.4 项 4: 多选汇总字段（放入与单选同布局的 multiContentRow 两列中）
    /// 多选汇总：数量行
    private let multiCountField = NSTextField(labelWithString: "")
    /// 多选汇总：总大小行
    private let multiSizeField = NSTextField(labelWithString: "")
    /// 多选汇总：包含类型行（带数量）
    private let multiTypesField = NSTextField(labelWithString: "")
    /// 多选汇总：包含标签行（药丸）
    private let multiTagsContainer = NSStackView()

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
        // 匹配 glassBackground 的 12pt 圆角，使阴影（由 MainWindowController 设置）也呈圆角
        layer?.cornerRadius = 12

        // v0.6.9: 玻璃背景浮层，圆角 12pt（超椭圆由 SquircleView 处理，此处用 FFGlassView 提供材质）
        let glassBackground = FFGlassView(level: .panel, cornerRadius: 12, material: .sidebar)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)

        // 修复鼠标穿透：详情栏作为浮层覆盖在文件列表上方，但空白区域（无子控件的区域）
        // 的鼠标事件会穿透到下方的文件列表——用户反馈"鼠标居然可以穿透详情栏点击下方内容"。
        // 加一个全 bounds 覆盖的鼠标拦截视图，放在玻璃上方、内容下方。
        // 普通NSView不消费mouseDown、hitTest返回最深子视图，事件仍会传到下方兄弟视图——
        // 这里用 FFMouseInterceptorView（重写 mouse* 事件消费 + hitTest 返回 self 兜底），
        // 确保鼠标落到详情栏区域就被详情栏拦截，不再穿透到文件列表。
        // 不影响子控件交互：子视图的 hitTest 优先于父，有控件的区域仍返回控件。
        let mouseInterceptor = FFMouseInterceptorView()
        mouseInterceptor.wantsLayer = true
        mouseInterceptor.layer?.backgroundColor = NSColor.clear.cgColor
        mouseInterceptor.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mouseInterceptor)

        // compact 视图（收起态）
        compactView.translatesAutoresizingMaskIntoConstraints = false
        smallIconView.imageScaling = .scaleProportionallyUpOrDown
        smallIconView.translatesAutoresizingMaskIntoConstraints = false
        compactView.addSubview(smallIconView)

        // 1.6 收起态名称：13pt medium（与 refresh() 单选分支一致，避免选中数量切换时字号跳变）
        compactNameField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        compactNameField.textColor = NSColor.labelColor
        compactNameField.lineBreakMode = .byTruncatingTail
        compactNameField.maximumNumberOfLines = 1
        compactNameField.cell?.truncatesLastVisibleLine = true
        compactNameField.translatesAutoresizingMaskIntoConstraints = false
        compactView.addSubview(compactNameField)
        addSubview(compactView)

        // 1.6 收起态副字段：12pt secondary，显示 "大小 · 类型"
        let compactSubField = NSTextField(labelWithString: "")
        compactSubField.font = NSFont.systemFont(ofSize: 12)
        compactSubField.textColor = NSColor.secondaryLabelColor
        compactSubField.lineBreakMode = .byTruncatingTail
        compactSubField.maximumNumberOfLines = 1
        compactSubField.cell?.truncatesLastVisibleLine = true
        compactSubField.translatesAutoresizingMaskIntoConstraints = false
        compactView.addSubview(compactSubField)
        self.compactSubField = compactSubField

        // expanded 视图（展开态）
        expandedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(expandedView)

        // 展开态内容：垂直堆叠（多选汇总 + 内容行 + 文件类型信息）
        let expandedStack = NSStackView()
        expandedStack.orientation = .vertical
        expandedStack.spacing = 8
        expandedStack.alignment = .leading
        expandedStack.translatesAutoresizingMaskIntoConstraints = false
        expandedView.addSubview(expandedStack)

        // v0.7.4 修订 4: 多选字段（数量/总大小/类型/标签）——放入与单选同布局的 multiContentRow
        // （多选数量行）
        multiCountField.font = NSFont.systemFont(ofSize: 10)
        multiCountField.textColor = NSColor.labelColor
        multiCountField.translatesAutoresizingMaskIntoConstraints = false

        // 多选总大小行
        multiSizeField.font = NSFont.systemFont(ofSize: 10)
        multiSizeField.textColor = NSColor.labelColor
        multiSizeField.translatesAutoresizingMaskIntoConstraints = false

        // 多选类型行（文本：图片 3 · 文档 2）
        multiTypesField.font = NSFont.systemFont(ofSize: 10)
        multiTypesField.textColor = NSColor.labelColor
        multiTypesField.translatesAutoresizingMaskIntoConstraints = false

        // 多选标签行（药丸）
        multiTagsContainer.orientation = .horizontal
        multiTagsContainer.spacing = 4
        multiTagsContainer.alignment = .centerY
        multiTagsContainer.translatesAutoresizingMaskIntoConstraints = false

        // 内容行：图标 + 两列信息（单选）
        let contentRow = NSStackView()
        contentRow.orientation = .horizontal
        contentRow.spacing = 12
        contentRow.alignment = .top
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        singleContentRow = contentRow

        bigIconView.imageScaling = .scaleProportionallyUpOrDown
        bigIconView.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addArrangedSubview(bigIconView)

        // 两列信息容器
        let columnsContainer = NSStackView()
        columnsContainer.orientation = .horizontal
        columnsContainer.spacing = 16
        columnsContainer.alignment = .top
        columnsContainer.translatesAutoresizingMaskIntoConstraints = false
        columnsContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 第一列：名称 / 种类 / 大小 / 位置 / 创建日期 / 修改日期 + 文件类型专属信息
        let column1 = NSStackView()
        column1.orientation = .vertical
        column1.spacing = 4
        column1.alignment = .leading
        column1.translatesAutoresizingMaskIntoConstraints = false
        mainColumn1 = column1

        // v0.7.4 项 3：名称行（可单击改名）。文件名以 11pt semibold 显示，与其它字段区分
        configureValue(nameField)
        nameField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        nameField.textColor = NSColor.labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 1
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.cell?.wraps = false
        nameField.delegate = self
        // 单击进入改名编辑（与 descriptionField 双击不同：名称单击即编辑）
        let nameClickGesture = NSClickGestureRecognizer(target: self, action: #selector(beginEditingName))
        nameClickGesture.numberOfClicksRequired = 1
        nameField.addGestureRecognizer(nameClickGesture)
        nameField.toolTip = "点击编辑文件名"

        configureValue(typeField)
        configureValue(sizeField)
        configureValue(locationField)
        // 问题 9：路径多行完整显示（换行而非截断），蓝色链接色区分可交互
        locationField.lineBreakMode = .byWordWrapping
        locationField.maximumNumberOfLines = 3
        locationField.cell?.wraps = true
        locationField.cell?.truncatesLastVisibleLine = false
        locationField.textColor = NSColor.systemBlue
        locationField.font = NSFont.systemFont(ofSize: 10)
        // 点击跳转所在文件夹
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(locationClicked))
        locationField.addGestureRecognizer(clickGesture)
        // 右键复制路径菜单
        let locationMenu = NSMenu()
        let copyItem = NSMenuItem(title: "复制路径", action: #selector(copyLocationPath), keyEquivalent: "")
        copyItem.target = self
        locationMenu.addItem(copyItem)
        locationField.menu = locationMenu
        configureValue(createdField)
        configureValue(modifiedField)

        let nameRow = makeInfoRow(label: makeLabel("名称"), value: nameField)
        let typeRow = makeInfoRow(label: makeLabel("种类"), value: typeField)
        let sizeRow = makeInfoRow(label: makeLabel("大小"), value: sizeField)
        let locationRow = makeInfoRow(label: makeLabel("位置"), value: locationField)
        let createdRow = makeInfoRow(label: makeLabel("创建日期"), value: createdField)
        let modifiedRow = makeInfoRow(label: makeLabel("修改日期"), value: modifiedField)
        column1.addArrangedSubview(nameRow)
        column1.addArrangedSubview(typeRow)
        column1.addArrangedSubview(sizeRow)
        column1.addArrangedSubview(locationRow)
        column1.addArrangedSubview(createdRow)
        column1.addArrangedSubview(modifiedRow)

        // 第二列：标签 / 文件说明 / 文件来源
        let column2 = NSStackView()
        column2.orientation = .vertical
        column2.spacing = 4
        column2.alignment = .leading
        column2.translatesAutoresizingMaskIntoConstraints = false
        mainColumn2 = column2

        // 标签容器（药丸，横向排列，单击筛选 / 右键移除）+ 编辑按钮
        tagsContainer.orientation = .horizontal
        tagsContainer.spacing = 4
        tagsContainer.alignment = .centerY
        tagsContainer.translatesAutoresizingMaskIntoConstraints = false
        tagsContainer.heightAnchor.constraint(equalToConstant: 18).isActive = true

        // v0.7.4 项 4：标签行编辑按钮（铅笔图标），点击弹出标签选择弹窗
        tagsEditButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "编辑标签")
        tagsEditButton.contentTintColor = NSColor.secondaryLabelColor
        tagsEditButton.isBordered = false
        tagsEditButton.controlSize = .small
        tagsEditButton.target = self
        tagsEditButton.action = #selector(editTagsClicked)
        tagsEditButton.toolTip = "编辑标签"
        tagsEditButton.translatesAutoresizingMaskIntoConstraints = false
        tagsEditButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        tagsEditButton.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // 标签值视图 = 药丸容器 + 编辑按钮（水平排列）
        let tagsValueView = NSStackView(views: [tagsContainer, tagsEditButton])
        tagsValueView.orientation = .horizontal
        tagsValueView.alignment = .centerY
        tagsValueView.spacing = 6
        tagsValueView.translatesAutoresizingMaskIntoConstraints = false

        // 文件说明：可编辑文本字段（双击进入编辑，回车保存至 UserDefaults）
        descriptionField.font = NSFont.systemFont(ofSize: 10)
        descriptionField.textColor = NSColor.labelColor
        descriptionField.isEditable = false
        descriptionField.isSelectable = true
        descriptionField.isBezeled = false
        descriptionField.drawsBackground = false
        descriptionField.lineBreakMode = .byTruncatingTail
        descriptionField.maximumNumberOfLines = 1
        descriptionField.cell?.truncatesLastVisibleLine = true
        descriptionField.cell?.wraps = false
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        descriptionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        descriptionField.delegate = self
        let descGesture = NSClickGestureRecognizer(target: self, action: #selector(beginEditingDescription))
        descGesture.numberOfClicksRequired = 2
        descriptionField.addGestureRecognizer(descGesture)

        configureValue(sourceField)

        // v0.7.4 项 4：标签行 value 用 tagsValueView（药丸 + 编辑按钮）
        let tagsRow = makeInfoRow(label: makeLabel("标签"), value: tagsValueView)
        let descRow = makeInfoRow(label: makeLabel("文件说明"), value: descriptionField)
        let sourceRow = makeInfoRow(label: makeLabel("文件来源"), value: sourceField)
        column2.addArrangedSubview(tagsRow)
        column2.addArrangedSubview(descRow)
        column2.addArrangedSubview(sourceRow)

        // v0.7.4 项 7：收集所有信息行引用（多选/未选时隐藏）
        infoRows = [nameRow, typeRow, sizeRow, locationRow, createdRow, modifiedRow, tagsRow, descRow, sourceRow]

        columnsContainer.addArrangedSubview(column1)
        columnsContainer.addArrangedSubview(column2)
        contentRow.addArrangedSubview(columnsContainer)

        // v0.7.4 修订 4：多选内容行（图标 + 两列汇总信息，与单选布局一致）
        let multiRow = NSStackView()
        multiRow.orientation = .horizontal
        multiRow.spacing = 12
        multiRow.alignment = .top
        multiRow.translatesAutoresizingMaskIntoConstraints = false
        multiRow.isHidden = true
        multiContentRow = multiRow

        // 多选大图标：缩略图堆叠容器（仿访达，最多堆叠 4 个选中项的缩略图）
        let multiIcon = FFMiniThumbnailStackView()
        multiIcon.translatesAutoresizingMaskIntoConstraints = false
        multiIconView = multiIcon
        multiRow.addArrangedSubview(multiIcon)
        NSLayoutConstraint.activate([
            multiIcon.widthAnchor.constraint(equalToConstant: 96),
            multiIcon.heightAnchor.constraint(equalToConstant: 96),
        ])

        // 多选两列
        let multiColumns = NSStackView()
        multiColumns.orientation = .horizontal
        multiColumns.spacing = 16
        multiColumns.alignment = .top
        multiColumns.translatesAutoresizingMaskIntoConstraints = false
        multiColumns.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 左列：数量 / 总大小 / 包含类型
        let multiCol1 = NSStackView()
        multiCol1.orientation = .vertical
        multiCol1.spacing = 4
        multiCol1.alignment = .leading
        multiCol1.translatesAutoresizingMaskIntoConstraints = false
        multiCol1.addArrangedSubview(makeInfoRow(label: makeLabel("数量"), value: multiCountField))
        multiCol1.addArrangedSubview(makeInfoRow(label: makeLabel("总大小"), value: multiSizeField))
        multiCol1.addArrangedSubview(makeInfoRow(label: makeLabel("包含类型"), value: multiTypesField))

        // 右列：包含标签
        let multiCol2 = NSStackView()
        multiCol2.orientation = .vertical
        multiCol2.spacing = 4
        multiCol2.alignment = .leading
        multiCol2.translatesAutoresizingMaskIntoConstraints = false
        multiCol2.addArrangedSubview(makeInfoRow(label: makeLabel("包含标签"), value: multiTagsContainer))

        multiColumns.addArrangedSubview(multiCol1)
        multiColumns.addArrangedSubview(multiCol2)
        multiRow.addArrangedSubview(multiColumns)

        expandedStack.addArrangedSubview(multiRow)

        // 文件类型专属信息容器（内容行下方）
        fileTypeInfoContainer.orientation = .vertical
        fileTypeInfoContainer.spacing = 4
        fileTypeInfoContainer.alignment = .leading
        fileTypeInfoContainer.translatesAutoresizingMaskIntoConstraints = false

        expandedStack.addArrangedSubview(contentRow)
        expandedStack.addArrangedSubview(fileTypeInfoContainer)

        // 顶部细分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // chevron 按钮（最后添加，确保在最上层不被覆盖）
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

        // 高度约束（由展开状态驱动）
        heightConstraint = heightAnchor.constraint(equalToConstant: collapsedHeight)
        heightConstraint.priority = .required

        NSLayoutConstraint.activate([
            // 1.6 玻璃背景填满整个 bar
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 鼠标拦截层撑满（修复穿透：确保详情栏区域内的点击不穿到下方文件列表）
            mouseInterceptor.leadingAnchor.constraint(equalTo: leadingAnchor),
            mouseInterceptor.trailingAnchor.constraint(equalTo: trailingAnchor),
            mouseInterceptor.topAnchor.constraint(equalTo: topAnchor),
            mouseInterceptor.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 分隔线
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            // chevron
            chevronButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            chevronButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevronButton.widthAnchor.constraint(equalToConstant: 20),
            chevronButton.heightAnchor.constraint(equalToConstant: 20),

            // compact 填充 bar 顶部区域，底部留出 statusBarHeight 给状态栏
            compactView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            compactView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            compactView.topAnchor.constraint(equalTo: topAnchor),
            compactView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -statusBarHeight),

            // 收起态图标 32x32，垂直居中
            smallIconView.leadingAnchor.constraint(equalTo: compactView.leadingAnchor),
            smallIconView.centerYAnchor.constraint(equalTo: compactView.centerYAnchor),
            smallIconView.widthAnchor.constraint(equalToConstant: 32),
            smallIconView.heightAnchor.constraint(equalToConstant: 32),

            // 名称：图标右侧 10px，垂直居中
            compactNameField.leadingAnchor.constraint(equalTo: smallIconView.trailingAnchor, constant: 10),
            compactNameField.centerYAnchor.constraint(equalTo: compactView.centerYAnchor),

            // 副字段：名称右侧 10px，垂直居中（单行布局，设计稿 "2.4 MB · PDF 文档"）
            compactSubField.leadingAnchor.constraint(equalTo: compactNameField.trailingAnchor, constant: 10),
            compactSubField.centerYAnchor.constraint(equalTo: compactView.centerYAnchor),
            compactSubField.trailingAnchor.constraint(lessThanOrEqualTo: compactView.trailingAnchor, constant: -32),

            // expanded
            expandedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            expandedView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            expandedView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            expandedView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -statusBarHeight),

            // expandedStack 填满 expandedView
            expandedStack.leadingAnchor.constraint(equalTo: expandedView.leadingAnchor),
            expandedStack.trailingAnchor.constraint(equalTo: expandedView.trailingAnchor),
            expandedStack.topAnchor.constraint(equalTo: expandedView.topAnchor),
            expandedStack.bottomAnchor.constraint(lessThanOrEqualTo: expandedView.bottomAnchor),

            // 大图标 96×96
            bigIconView.widthAnchor.constraint(equalToConstant: 96),
            bigIconView.heightAnchor.constraint(equalToConstant: 96),

            // 两列容器最小宽度，确保信息完整显示
            column1.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            column2.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            // 问题 9：限制第一列最大宽度（容器 60%），防止路径字段撑宽第一列
            // 把第二列（标签/文件说明/来源）挤出到右缘截断
            column1.widthAnchor.constraint(lessThanOrEqualTo: columnsContainer.widthAnchor, multiplier: 0.60),

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
        // 44pt 宽度容纳 4 字标签（创建日期 / 文件说明 / 文件来源）
        f.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return f
    }

    private func configureValue(_ f: NSTextField) {
        f.font = NSFont.systemFont(ofSize: 10)
        f.textColor = NSColor.labelColor
        f.lineBreakMode = .byTruncatingTail
        f.maximumNumberOfLines = 1
        f.cell?.truncatesLastVisibleLine = true
        f.cell?.wraps = false
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    /// 创建一行信息：固定宽度标签 + 可扩展值视图（水平排列）
    private func makeInfoRow(label: NSTextField, value: NSView) -> NSStackView {
        value.translatesAutoresizingMaskIntoConstraints = false
        value.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// 创建已配置的值文本标签（用于文件类型专属信息行）
    private func makeValueField(_ text: String = "") -> NSTextField {
        let f = NSTextField(labelWithString: text)
        configureValue(f)
        return f
    }

    // MARK: - Public API

    /// 更新显示的文件信息（任务要求接口）
    func update(with entry: FileEntry?) {
        self.entry = entry
        self.selectedFiles = entry.map { [$0] } ?? []
        self.selectedCount = (entry != nil) ? 1 : 0
        refresh()
    }

    /// v0.7.4 修订: 更新完整选中数组（单选/多选/未选统一入口）
    /// - Parameter files: 当前选中的文件数组（空 = 未选中；1 个 = 单选；>=2 = 多选）
    func update(with files: [FileEntry]) {
        self.selectedFiles = files
        self.selectedCount = files.count
        self.entry = files.count == 1 ? files.first : (files.isEmpty ? nil : files.first)
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
        self.selectedFiles = file.map { [$0] } ?? []
        refresh()
    }

    /// 问题7: 更新状态栏文字（项目数 + 磁盘可用空间）
    /// - Parameters:
    ///   - itemCount: 当前文件夹的项目数
    ///   - diskFree: 磁盘可用空间描述（如 "42.8 GB 可用"），为 nil 时仅显示项目数
    func updateStatus(itemCount: Int, diskFree: String? = nil, currentDirectoryPath: String? = nil) {
        // v0.7.4 修订 4：记录当前所在文件夹路径（未选中时显示该文件夹图标）
        if let path = currentDirectoryPath {
            self.currentDirectoryPath = path
        }
        if statusLabel == nil {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = NSColor.secondaryLabelColor
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            // 状态栏位于 bar 底部独立区域，与上方详情内容不重叠
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                label.heightAnchor.constraint(equalToConstant: statusBarHeight),
            ])
            statusLabel = label
        }
        var text = "\(itemCount) 项"
        if let diskFree = diskFree {
            text += "    \(diskFree)"
        }
        statusLabel?.stringValue = text
    }

    // MARK: - Toggle

    @objc private func toggleExpanded() {
        isExpanded.toggle()
    }

    private func applyExpandedState(animated: Bool) {
        let newHeight = isExpanded ? computedExpandedHeight() : collapsedHeight
        heightConstraint.constant = newHeight
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

    /// 展开态高度：基础 192pt（图标 96 + 两列信息约 6 行）+ 文件类型专属信息高度
    /// 图片/视频信息行多时按行数扩展，确保完整显示（问题 9 根因：固定 210 截断图片信息）
    private func computedExpandedHeight() -> CGFloat {
        // 问题 7：专属信息合并到主信息列后按单列计算——主信息 5 行 + 专属信息行数
        var extra: CGFloat = 0
        if selectedCount > 1 {
            // v0.7.4 修订 4：多选与单选同布局（图标 + 两列），行数约 4 行（数量/总大小/类型/标签），
            // 基准高度与单选一致，略加高容纳标签药丸行
            return 192 + 16
        }
        if let entry = entry {
            let infoRows = gatherFileInfo(entry: entry).count
            let totalRows = 5 + infoRows  // 种类/大小/位置/创建/修改 + 专属信息
            if totalRows > 7 {
                // 基准 192pt 容纳约 7 行（两列布局时），单列合并后每行 +16pt
                extra = CGFloat(totalRows - 7) * 16
            }
        }
        return 192 + extra
    }

    // MARK: - 路径交互（问题 9：点击跳转 / 右键复制）

    /// 点击路径：在访达中显示该文件所在文件夹（NSWorkspace 打开父目录并选中）
    @objc private func locationClicked() {
        guard let path = entry?.path else { return }
        let parent = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        _ = parent  // 保留：activateFileViewerSelecting 已在 Finder 中显示父目录并选中文件
    }

    /// 右键复制路径到剪贴板
    @objc private func copyLocationPath() {
        guard let path = entry?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    // MARK: - Refresh

    private func refresh() {
        // 文件变化时取消上一次的缩略图请求
        if let oldPath = thumbnailLoadPath, oldPath != entry?.path {
            ThumbnailManager.shared.cancelGeneration(for: oldPath)
            thumbnailLoadPath = nil
            bigIconView.image = nil
            // E2: 文件切换时重置缩略图标志，允许新文件的工作区图标显示
            didReceiveThumbnail = false
        }
        // 任务 F11-7: 文件变化时也清除工作区图标请求标记，避免旧回调覆盖新选中项图标
        if iconLoadPath != nil && iconLoadPath != entry?.path {
            iconLoadPath = nil
        }

        // compact 行：名称字号在 setupUI 中统一为 13pt medium；副字段 12pt secondary "大小 · 类型"
        // 任务 F11-6: 占位图标统一使用灰色（tertiaryLabelColor），未选中时显示空白文件夹占位
        if selectedCount > 1 {
            compactNameField.stringValue = "已选中 \(selectedCount) 项"
            compactSubField?.stringValue = ""
            setPlaceholderIcon(symbol: "doc.on.doc")
        } else if let entry = entry {
            compactNameField.stringValue = entry.name
            compactSubField?.stringValue = "\(entry.formattedSize) · \(entry.kindDescription)"
            // 真实文件图标：使用系统工作区图标（多色非模板，contentTintColor 不影响其渲染）
            setRealFileIcon(for: entry.path)
        } else {
            compactNameField.stringValue = "未选择文件"
            compactSubField?.stringValue = ""
            // v0.7.4 修订 4：未选中时显示当前所在文件夹的图标（而非通用占位图标）
            if let dirPath = currentDirectoryPath {
                setRealFileIcon(for: dirPath)
            } else {
                setPlaceholderIcon(symbol: "tray.full.fill")
            }
        }

        // expanded 字段：名称 / 种类 / 大小 / 位置 / 创建日期 / 修改日期
        // 第二列：标签 / 文件说明 / 文件来源
        // 底部：文件类型专属信息
        // 任务 F11-6: bigIconView 已在 setPlaceholderIcon/setRealFileIcon 中与 smallIconView 同步设置
        guard let entry = entry else {
            // v0.7.4 修订 项 4：未选中任何项目 → 隐藏所有信息与多选汇总，自动收起且不可展开
            for row in infoRows { row.isHidden = true }
            singleContentRow.isHidden = true
            multiContentRow.isHidden = true
            clearFileTypeSpecificInfo()
            clearTags()
            showNoTagsPlaceholder()
            if isExpanded {
                isExpanded = false
            }
            chevronButton.isEnabled = false
            return
        }

        // 多选（2 个及以上）：与单选同布局（图标 + 两列），内容为汇总信息
        if selectedCount > 1 {
            for row in infoRows { row.isHidden = true }
            clearFileTypeSpecificInfo()
            clearTags()
            showNoTagsPlaceholder()
            singleContentRow.isHidden = true
            multiContentRow.isHidden = false
            // 多选图标：缩略图堆叠（取前 4 个选中项的缩略图）
            multiIconView.update(with: Array(selectedFiles.prefix(4)))
            populateMultiSelectSummary()
            chevronButton.isEnabled = true
            if isExpanded {
                heightConstraint.constant = computedExpandedHeight()
            }
            return
        }

        // 单选：显示所有信息行，隐藏多选汇总
        for row in infoRows { row.isHidden = false }
        singleContentRow.isHidden = false
        multiContentRow.isHidden = true
        chevronButton.isEnabled = true

        nameField.stringValue = entry.name
        typeField.stringValue = entry.kindDescription
        sizeField.stringValue = entry.formattedSize
        locationField.stringValue = entry.path
        locationField.toolTip = entry.path
        createdField.stringValue = entry.formattedCreationDate
        modifiedField.stringValue = entry.formattedModificationDate
        // bigIconView 已在上方 setRealFileIcon 中同步设置真实文件图标

        // 文件说明（从 UserDefaults 读取，双击可编辑）
        descriptionField.stringValue = getFileDescription(path: entry.path)

        // 文件来源（kMDItemWhereFroms xattr，Finder "下载来源"信息）
        sourceField.stringValue = getWhereFrom(path: entry.path)

        updateTags(path: entry.path)

        // 文件类型专属信息（分辨率 / EXIF / 时长 / 编码 等）
        updateFileTypeSpecificInfo(entry: entry)
        // 动态高度：信息行数变化时更新展开高度（行数多时更高，避免截断）
        if isExpanded {
            heightConstraint.constant = computedExpandedHeight()
        }

        if isExpanded { loadThumbnail() }
    }

    // MARK: - v0.7.4 项 4: 多选汇总

    /// 计算并填充多选汇总信息：数量 / 总大小 / 包含类型（带数量）/ 包含标签
    /// E3: 总大小（目录递归）与标签读取（xattr）在后台队列计算，避免大目录/多文件卡主线程；
    /// 数量与类型聚合是纯内存操作，留在主线程即时显示。
    private func populateMultiSelectSummary() {
        let files = selectedFiles
        let count = files.count

        // 数量行
        multiCountField.stringValue = "已选中 \(count) 项"

        // 包含类型（带数量）：按 kindDescription 聚合（纯内存，主线程即时）
        var typeCounts: [String: Int] = [:]
        for f in files {
            typeCounts[f.kindDescription, default: 0] += 1
        }
        let typeText = typeCounts.sorted { $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " · ")
        multiTypesField.stringValue = "包含类型：\(typeText.isEmpty ? "无" : typeText)"

        // E3: 总大小 + 标签读取放后台（目录递归扫描 + getxattr 是磁盘 I/O）
        multiSelectGeneration += 1
        let generation = multiSelectGeneration
        let dirPaths = files.filter { $0.isDirectory }.map { $0.path }
        let fileSizes = files.reduce(into: 0 as UInt64) { total, f in
            if !f.isDirectory { total += f.size }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var totalSize = fileSizes
            for dir in dirPaths {
                totalSize += self.directorySize(path: dir)
            }
            var tagSet: [String: Tag] = [:]
            for f in files {
                for tag in TagBridge.shared.getTags(path: f.path) {
                    tagSet[tag.name] = tag
                }
            }
            DispatchQueue.main.async { [self] in
                guard self.multiSelectGeneration == generation else { return }
                self.multiSizeField.stringValue = "总大小：\(self.formatBytes(totalSize))"
                // 包含标签：去重后显示药丸
                for v in self.multiTagsContainer.arrangedSubviews {
                    self.multiTagsContainer.removeArrangedSubview(v)
                    v.removeFromSuperview()
                }
                if tagSet.isEmpty {
                    let none = NSTextField(labelWithString: "包含标签：无")
                    none.font = NSFont.systemFont(ofSize: 10)
                    none.textColor = NSColor.tertiaryLabelColor
                    none.translatesAutoresizingMaskIntoConstraints = false
                    self.multiTagsContainer.addArrangedSubview(none)
                } else {
                    let label = NSTextField(labelWithString: "包含标签：")
                    label.font = NSFont.systemFont(ofSize: 10)
                    label.textColor = NSColor.secondaryLabelColor
                    label.translatesAutoresizingMaskIntoConstraints = false
                    self.multiTagsContainer.addArrangedSubview(label)
                    for tag in tagSet.values.sorted(by: { $0.name < $1.name }) {
                        self.multiTagsContainer.addArrangedSubview(self.makeSummaryTagPill(tag: tag))
                    }
                }
            }
        }
    }

    /// 多选汇总标签药丸（小号，仅展示）
    private func makeSummaryTagPill(tag: Tag) -> NSView {
        let pillHeight: CGFloat = 16
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        let tagColor = NSColor(hex: tag.color) ?? .systemBlue
        pill.layer?.backgroundColor = tagColor.withAlphaComponent(0.15).cgColor
        pill.squircleRadius = pillHeight / 2
        pill.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tagColor.cgColor
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 9)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        pill.addSubview(dot)
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 5),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -5),
            pill.heightAnchor.constraint(equalToConstant: pillHeight),
        ])
        return pill
    }

    /// 递归计算文件夹大小
    private func directorySize(path: String) -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0
        if let enumerator = fm.enumerator(atPath: path) {
            while let file = enumerator.nextObject() as? String {
                let fullPath = (path as NSString).appendingPathComponent(file)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? UInt64 {
                    total += size
                }
            }
        }
        return total
    }

    /// 字节数格式化（B/KB/MB/GB）
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Icon Helpers

    /// 任务 F11-6: 设置占位 SF Symbol 图标（compact 与 expanded 同步）
    /// SF Symbol 默认为模板图像，通过 contentTintColor 染为灰色（tertiaryLabelColor）
    /// - Parameter symbol: SF Symbol 名称（如 "folder" / "doc.on.doc"）
    private func setPlaceholderIcon(symbol: String) {
        // 小图标(24pt)与大图标(64pt light)视觉协调，适配 96×96 展开态图标视图
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let bigConfig = NSImage.SymbolConfiguration(pointSize: 64, weight: .light)

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        smallIconView.image = image?.withSymbolConfiguration(config)
        bigIconView.image = image?.withSymbolConfiguration(bigConfig)

        // 占位图标使用次级标签色（tertiaryLabelColor），与"未选择文件"等占位文本视觉一致
        // 问题6: 改用 systemBlue 色 0.6 透明度，比纯灰色更有视觉层次
        let tintColor = NSColor.systemBlue.withAlphaComponent(0.5)
        smallIconView.contentTintColor = tintColor
        bigIconView.contentTintColor = tintColor
    }

    /// 任务 F11-6: 设置真实文件图标（compact 与 expanded 同步）
    /// 任务 F11-7: 改为异步获取 + 缓存，避免点击选中时主线程同步调用
    /// NSWorkspace.shared.icon(forFile:) 造成卡顿。原实现每次选中都同步调用，
    /// 快速连续点击不同文件时主线程被 LaunchServices 查询阻塞。
    /// 现改为：缓存命中同步显示；未命中先清 tint（保留占位），后台异步获取后回调更新。
    /// contentTintColor 置 nil 避免多色非模板图标被染色。
    /// E2: 缩略图已加载时不覆盖 bigIconView（避免工作区图标回调覆盖缩略图）。
    /// - Parameter path: 文件绝对路径
    private func setRealFileIcon(for path: String) {
        // 真实图标为多色非模板图像，清除占位灰色 tint，确保显示原生色彩
        smallIconView.contentTintColor = nil
        bigIconView.contentTintColor = nil

        // 缓存命中：同步显示
        let iconPointSize: CGFloat = 96
        if let cached = ThumbnailManager.shared.cachedWorkspaceIcon(for: path, pointSize: iconPointSize) {
            iconLoadPath = nil
            smallIconView.image = cached
            // E2: 缩略图已显示时不覆盖大图标（小图标始终用工作区图标）
            if !didReceiveThumbnail {
                bigIconView.image = cached
            }
            return
        }

        // 未命中：记录当前请求路径，后台异步获取
        iconLoadPath = path
        ThumbnailManager.shared.fetchWorkspaceIcon(for: path, pointSize: iconPointSize) { [weak self] image in
            guard let self = self, let image = image else { return }
            // 校验仍显示同一文件（避免快速切换选中时旧回调覆盖）
            guard self.iconLoadPath == path else { return }
            self.smallIconView.image = image
            // E2: 缩略图已显示时不覆盖大图标
            if !self.didReceiveThumbnail {
                self.bigIconView.image = image
            }
        }
    }

    // MARK: - Thumbnail

    private func loadThumbnail() {
        guard let entry = entry, !entry.isDirectory, selectedCount <= 1 else { return }
        let path = entry.path
        thumbnailLoadPath = path
        ThumbnailManager.shared.generateThumbnail(
            path: path,
            size: CGSize(width: 96, height: 96)
        ) { [weak self] image in
            guard let self = self, let image = image else { return }
            // 防止过期回调覆盖当前显示
            guard self.thumbnailLoadPath == path, self.isExpanded else { return }
            // E2: 缩略图成功加载后置位标志，阻止工作区图标回调覆盖
            self.didReceiveThumbnail = true
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
            let pill = makeTagPill(tag: tag)
            // 每个药丸独立右键菜单：右键任意位置 → "移除标签"（仅移除该文件的此标签）
            let menu = NSMenu()
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "移除标签", action: #selector(removeTagFromDetailsBar(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["tagName": tag.name, "path": path]
            menu.addItem(item)
            pill.menu = menu
            tagsContainer.addArrangedSubview(pill)
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
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        // 标签色浅色背景，与文件列表药丸风格一致
        let tagColor = NSColor(hex: tag.color) ?? .systemBlue
        pill.layer?.backgroundColor = tagColor.withAlphaComponent(0.15).cgColor
        pill.squircleRadius = pillHeight / 2
        pill.translatesAutoresizingMaskIntoConstraints = false
        // 存储标签名用于单击筛选
        pill.identifier = NSUserInterfaceItemIdentifier(tag.name)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tagColor.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(dot)

        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        // 单击：发送通知，按标签筛选文件列表（与侧边栏标签点击行为一致）
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(tagPillClicked(_:)))
        pill.addGestureRecognizer(clickGesture)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            pill.heightAnchor.constraint(equalToConstant: pillHeight),
        ])
        return pill
    }

    /// 单击标签药丸：发送 sidebarDidSelectTag 通知，按标签筛选当前面板文件列表
    /// 再次点击同一标签可取消筛选（由 PaneState.setTagFilter 内部处理）
    @objc private func tagPillClicked(_ gesture: NSClickGestureRecognizer) {
        guard let pill = gesture.view, let tagName = pill.identifier?.rawValue else { return }
        guard let path = entry?.path else { return }
        let tags = TagBridge.shared.getTags(path: path)
        if let tag = tags.first(where: { $0.name == tagName }) {
            NotificationCenter.default.post(name: .sidebarDidSelectTag, object: tag, userInfo: nil)
        }
    }

    /// 右键药丸移除标签（详情栏，按名称移除，兼容原生标签随机 id）
    /// 移除后刷新详情栏标签显示并通知文件列表刷新
    @objc private func removeTagFromDetailsBar(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagName = info["tagName"],
              let path = info["path"] else { return }
        // 移除前找到该标签（用于撤销恢复）
        let tag = TagBridge.shared.getTags(path: path).first(where: { $0.name == tagName })
        _ = TagBridge.shared.removeTagByName(tagName, path: path)
        if let tag = tag {
            onUndoableTagChange?(.remove, tag, path)
        }
        // 刷新详情栏标签药丸显示
        updateTags(path: path)
        // 通知文件列表刷新（文件列表中的内联药丸需同步更新）
        let tags = TagBridge.shared.getTags(path: path)
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": tags])
    }

    // MARK: - 文件说明（UserDefaults 存储）

    /// 从 UserDefaults 读取文件说明（以文件路径为 key）
    private func getFileDescription(path: String) -> String {
        let dict = UserDefaults.standard.dictionary(forKey: "fileDescriptions") ?? [:]
        return dict[path] as? String ?? ""
    }

    /// 保存文件说明到 UserDefaults
    private func setFileDescription(path: String, description: String) {
        var dict = UserDefaults.standard.dictionary(forKey: "fileDescriptions") ?? [:]
        dict[path] = description
        UserDefaults.standard.set(dict, forKey: "fileDescriptions")
    }

    /// 双击文件说明文本字段，进入编辑模式
    @objc private func beginEditingDescription() {
        guard entry != nil else { return }
        descriptionField.isEditable = true
        descriptionField.isBezeled = true
        descriptionField.drawsBackground = true
        descriptionField.backgroundColor = NSColor.textBackgroundColor
        window?.makeFirstResponder(descriptionField)
        descriptionField.selectText(nil)
    }

    // MARK: - v0.7.4 项 3：文件名编辑（单击改名）

    /// 单击名称字段，进入编辑模式（与文件说明的交互一致，仅触发方式为单击）
    @objc private func beginEditingName() {
        guard entry != nil else { return }
        nameField.isEditable = true
        nameField.isBezeled = true
        nameField.drawsBackground = true
        nameField.backgroundColor = NSColor.textBackgroundColor
        window?.makeFirstResponder(nameField)
        // 默认选中不含后缀部分（与访达重命名一致）
        if let editor = nameField.currentEditor() {
            let name = nameField.stringValue as NSString
            let extRange = name.range(of: ".", options: .backwards)
            if extRange.location == NSNotFound || extRange.location == 0 {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: 0, length: extRange.location)
            }
        }
    }

    /// 名称编辑结束（回车或失焦）：通过 onRename 回调执行改名
    private func commitNameEditing() {
        guard let entry = entry else { return }
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != entry.name else {
            // 名字为空或未变：还原显示并退出编辑
            nameField.isEditable = false
            nameField.isBezeled = false
            nameField.drawsBackground = false
            nameField.stringValue = entry.name
            return
        }
        // 退出编辑样式（数据由回调更新，refresh 会重绘名称）
        nameField.isEditable = false
        nameField.isBezeled = false
        nameField.drawsBackground = false
        onRename?(entry.path, newName)
    }

    // MARK: - v0.7.4 项 4：标签编辑按钮

    /// 点击标签行编辑按钮：弹出下拉菜单（与右键菜单标签子菜单同款样式）。
    /// - 顶部：列出所有标签（彩色圆点 + 名称，当前文件已有的打勾 ✓）
    /// - 分隔线
    /// - "新建标签..."（统一走 FFCreateTagDialog）
    @objc private func editTagsClicked() {
        guard let entry = entry, let window = window else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let currentTags = TagBridge.shared.getTags(path: entry.path)
        let currentTagIds = Set(currentTags.map { $0.id })
        let currentTagNames = Set(currentTags.map { $0.name })

        let allTags = FFCreateTagDialog.loadAllSidebarTags()
        for tag in allTags {
            let item = NSMenuItem(title: tag.name, action: #selector(toggleTagFromDetailsBar(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["tagName": tag.name, "path": entry.path]
            item.image = makeMenuDotImage(colorHex: tag.color)
            if currentTagIds.contains(tag.id) || currentTagNames.contains(tag.name) {
                item.state = .on
            }
            menu.addItem(item)
        }

        if !allTags.isEmpty {
            menu.addItem(.separator())
        }

        let createItem = NSMenuItem(title: "新建标签...", action: #selector(createTagFromDetailsBar(_:)), keyEquivalent: "")
        createItem.target = self
        createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
        menu.addItem(createItem)

        // v0.7.4 修订：菜单从按钮右下角弹出。
        // 历史 Bug：convert(_:to: nil) 返回的是窗口坐标，但 popUp 的 at: 需要
        // in: 视图（tagsEditButton）的本地坐标——混用导致菜单偏移。
        // 修复：直接传按钮本地坐标（右下角 = 按钮宽度, 高度处向下弹出）。
        menu.popUp(positioning: nil, at: NSPoint(x: tagsEditButton.bounds.width, y: 0), in: tagsEditButton)
    }

    /// 创建彩色圆点 NSImage（菜单项图标）
    private func makeMenuDotImage(colorHex: String) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let color = NSColor(hex: colorHex) ?? .systemBlue
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 8, height: 8)).fill()
        image.unlockFocus()
        return image
    }

    /// 下拉菜单项：勾选/取消标签（与右键菜单 toggleTagOnFile 同逻辑）
    @objc private func toggleTagFromDetailsBar(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagName = info["tagName"],
              let path = info["path"] else { return }

        let currentTags = TagBridge.shared.getTags(path: path)
        let tag = currentTags.first(where: { $0.name == tagName })
            ?? FFCreateTagDialog.loadAllSidebarTags().first(where: { $0.name == tagName })

        if let tag = tag, currentTags.contains(where: { $0.name == tagName }) {
            _ = TagBridge.shared.removeTagByName(tagName, path: path)
            onUndoableTagChange?(.remove, tag, path)
        } else if let tag = tag {
            _ = TagBridge.shared.addTag(tag, path: path)
            onUndoableTagChange?(.add, tag, path)
        }

        // 刷新详情栏标签显示
        updateTags(path: path)
        let updatedTags = TagBridge.shared.getTags(path: path)
        // 通知文件列表刷新
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                        userInfo: ["tags": updatedTags])
    }

    /// 下拉菜单项：新建标签（统一走 FFCreateTagDialog，创建后应用到当前文件）
    @objc private func createTagFromDetailsBar(_ sender: Any?) {
        guard let entry = entry, let window = window else { return }
        FFCreateTagDialog.showCreateTagDialogAndSave(on: window) { [weak self] tag in
            guard let self = self else { return }
            _ = TagBridge.shared.addTag(tag, path: entry.path)
            self.onUndoableTagChange?(.add, tag, entry.path)
            self.updateTags(path: entry.path)
            let updatedTags = TagBridge.shared.getTags(path: entry.path)
            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                            userInfo: ["tags": updatedTags])
        }
    }

    // MARK: - 文件来源（kMDItemWhereFroms）

    /// 读取文件的"来源"信息（macOS 下载文件时写入的 xattr）
    /// 格式为 plist 数组，通常包含下载 URL 和引用页 URL
    private func getWhereFrom(path: String) -> String {
        let xattrName = "com.apple.metadata:kMDItemWhereFroms"
        let length = getxattr(path, xattrName, nil, 0, 0, 0)
        guard length > 0 else { return "—" }

        var buffer = [UInt8](repeating: 0, count: length)
        let result = getxattr(path, xattrName, &buffer, length, 0, 0)
        guard result > 0 else { return "—" }
        let data = Data(buffer)

        // 尝试解析为 plist 数组
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            if let array = plist as? [String] {
                if let first = array.first {
                    // 仅显示域名部分，完整 URL 在 tooltip 中
                    if let url = URL(string: first), let host = url.host {
                        return host
                    }
                    return first
                }
            }
            if let array = plist as? [Any] {
                let strings = array.map { String(describing: $0) }
                if let first = strings.first {
                    if let url = URL(string: first), let host = url.host {
                        return host
                    }
                    return first
                }
            }
        }
        return "—"
    }

    // MARK: - 文件类型专属信息

    /// 清除文件类型专属信息容器中的所有子视图
    private func clearFileTypeSpecificInfo() {
        for v in fileTypeInfoContainer.arrangedSubviews {
            fileTypeInfoContainer.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    /// 问题 7：记录已追加到主信息列（mainColumn1）的专属信息行，用于清除
    private var appendedTypeInfoRows: [NSView] = []

    /// 根据文件类型更新专属信息（分辨率 / EXIF / 时长 / 编码 等）。
    /// 问题 7 修复：专属信息行**合并到主信息列**（mainColumn1，与种类/大小/位置/日期同一列），
    /// 不再单独开两列——与主信息对齐、视觉连贯（用户反馈"单开两列很不协调"）。
    private func updateFileTypeSpecificInfo(entry: FileEntry) {
        // 先移除上一次追加的专属信息行
        for row in appendedTypeInfoRows {
            mainColumn1?.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        appendedTypeInfoRows.removeAll()
        // 同步清空总大小行引用（避免异步回调 appendFolderSizeRow 重复移除已清除的视图崩溃）
        folderSizeRow = nil

        let infoRows = gatherFileInfo(entry: entry)
        guard !infoRows.isEmpty else { return }

        // 在种类/大小/位置/日期之后追加专属信息行（同一列）
        for (label, value) in infoRows {
            let row = makeInfoRow(label: makeLabel(label), value: makeValueField(value))
            mainColumn1?.addArrangedSubview(row)
            appendedTypeInfoRows.append(row)
        }
    }

    /// 收集文件类型专属信息行，返回 [(标签, 值)] 数组
    private func gatherFileInfo(entry: FileEntry) -> [(String, String)] {
        let url = URL(fileURLWithPath: entry.path)
        let ext = entry.fileExtension.lowercased()

        // .app 是 bundle（isDir=true），必须先于 isDirectory 分支判断，
        // 否则永远命中目录分支、版本号永远不显示（问题 9 根因）
        if ext == "app" || entry.path.hasSuffix(".app") {
            return gatherAppInfo(path: entry.path)
        }
        if entry.isDirectory {
            return gatherFolderInfo(path: entry.path)
        }
        if isImageExtension(ext) {
            return gatherImageInfo(url: url, path: entry.path)
        }
        if isVideoExtension(ext) {
            return gatherVideoInfo(url: url)
        }
        if isAudioExtension(ext) {
            return gatherAudioInfo(url: url)
        }
        if isDocumentExtension(ext) {
            return gatherDocumentInfo(url: url, ext: ext)
        }
        return []
    }

    // MARK: - 图片信息

    private func gatherImageInfo(url: URL, path: String) -> [(String, String)] {
        var result: [(String, String)] = []

        // 使用 ImageIO 一次性读取所有图片属性（分辨率 / DPI / 色彩空间 / 色彩深度 / EXIF）
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return result
        }

        // 分辨率 + 打印/显示尺寸（按 DPI 换算厘米，访达同款）
        // 用 NSNumber 显式取值，兼容 HEIC/WebP 等属性结构（比 as? Int 桥接更稳）
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        if let w = width, let h = height, w > 0, h > 0 {
            result.append(("分辨率", "\(w) × \(h) 像素"))
            // DPI 缺省按 72 计算（访达默认行为）；有元数据则用之
            let dpiW = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
            let dpiH = (props[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
            let cmW = Double(w) / max(dpiW, 1) * 2.54
            let cmH = Double(h) / max(dpiH, 1) * 2.54
            result.append(("尺寸", String(format: "%.1f × %.1f 厘米", cmW, cmH)))
        }

        // 文件大小（访达图片详情必显示）
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            result.append(("文件大小", ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)))
        }

        // 色彩空间（kCGImagePropertyColorSpace 在新版 SDK 中不可用，使用字符串字面量兜底）
        if let cs = props["ColorSpace" as CFString] as? String, !cs.isEmpty {
            result.append(("色彩空间", cs))
        }
        // 色彩深度（同上）
        if let bps = (props["BitsPerSample" as CFString] as? NSNumber)?.intValue, bps > 0 {
            result.append(("色彩深度", "\(bps) 位"))
        }

        // TIFF 字典：相机制造商与型号
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake] as? String {
                result.append(("相机制造商", make))
            }
            if let model = tiff[kCGImagePropertyTIFFModel] as? String {
                result.append(("相机型号", model))
            }
        }

        // EXIF 字典：焦距 / 光圈 / ISO
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let focal = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue {
                result.append(("焦距", "\(Int(focal)) mm"))
            }
            if let aperture = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue {
                result.append(("光圈", "f/\(String(format: "%.1f", aperture))"))
            }
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = isoArray.first {
                result.append(("ISO", "ISO \(iso.intValue)"))
            }
        }

        return result
    }

    // MARK: - 视频信息

    private func gatherVideoInfo(url: URL) -> [(String, String)] {
        var result: [(String, String)] = []

        // 使用 AVFoundation 读取所有视频属性
        let asset = AVURLAsset(url: url)

        // 时长
        let duration = CMTimeGetSeconds(asset.duration)
        if duration > 0 {
            result.append(("时长", formatDuration(duration)))
        }

        // 分辨率 / 编码 / 帧率
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            let w = abs(size.width)
            let h = abs(size.height)
            if w > 0 && h > 0 {
                result.append(("分辨率", "\(Int(w)) × \(Int(h))"))
            }
            if let desc = videoTrack.formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription)
                result.append(("编码", fourCCToString(codecType)))
            }
            result.append(("帧率", String(format: "%.1f fps", videoTrack.nominalFrameRate)))
        }

        return result
    }

    // MARK: - 音频信息

    private func gatherAudioInfo(url: URL) -> [(String, String)] {
        var result: [(String, String)] = []

        // 使用 AVFoundation 读取所有音频属性
        let asset = AVURLAsset(url: url)

        // 时长
        let duration = CMTimeGetSeconds(asset.duration)
        if duration > 0 {
            result.append(("时长", formatDuration(duration)))
        }

        // 格式 / 比特率
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            if let desc = audioTrack.formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription)
                result.append(("格式", fourCCToString(codecType)))
            }
            let bitrate = Int(audioTrack.estimatedDataRate / 1000)
            if bitrate > 0 {
                result.append(("比特率", "\(bitrate) kbps"))
            }
        }

        return result
    }

    // MARK: - 应用程序信息

    private func gatherAppInfo(path: String) -> [(String, String)] {
        let infoPlistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: infoPlistPath) as? [String: Any] else {
            return []
        }
        var result: [(String, String)] = []
        if let version = dict["CFBundleShortVersionString"] as? String {
            result.append(("版本", version))
        }
        if let build = dict["CFBundleVersion"] as? String {
            result.append(("内部版本", build))
        }
        if let bundleId = dict["CFBundleIdentifier"] as? String {
            result.append(("Bundle ID", bundleId))
        }
        return result
    }

    // MARK: - 文档信息

    private func gatherDocumentInfo(url: URL, ext: String) -> [(String, String)] {
        var result: [(String, String)] = []

        // PDF: 使用 PDFKit 读取页数
        if ext == "pdf" {
            if let document = PDFDocument(url: url) {
                result.append(("页数", "\(document.pageCount) 页"))
            }
        }

        // 纯文本: 尝试读取字数
        if ["txt", "md", "rtf"].contains(ext) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let wordCount = text.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .count
                result.append(("字数", "\(wordCount) 字"))
            }
        }

        return result
    }

    // MARK: - 文件夹信息

    private func gatherFolderInfo(path: String) -> [(String, String)] {
        var result: [(String, String)] = []

        // 顶层子项数量
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
            result.append(("项目数", "\(contents.count) 项"))
        }

        // 异步计算总大小（此处仅启动计算，结果通过异步回调更新）
        calculateFolderSizeAsync(path: path)

        return result
    }

    /// 异步计算文件夹总大小，完成后更新 fileTypeInfoContainer
    private func calculateFolderSizeAsync(path: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: []
            ) else { return }

            var total: Int64 = 0
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                ) else { continue }
                if values.isRegularFile == true, let size = values.fileSize {
                    total += Int64(size)
                }
            }

            let sizeString = FFFormat.fileSize(UInt64(total))
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.entry?.path == path else { return }
                self.appendFolderSizeRow(sizeString)
            }
        }
    }

    /// 在文件类型专属信息区追加"总大小"行（合并到主信息列，问题 7 结构）
    /// 去重：异步计算可能重复回调（同路径多次选中/竞态），追加前先移除已有的"总大小"行，
    /// 避免多个"总大小"堆积把"修改日期"挤出可视区（问题：文件夹详情多个总大小）。
    /// 崩溃防护：updateFileTypeSpecificInfo 清除时可能已把旧行移出 stack——此时
    /// removeArrangedSubview 对不在 stack 的视图触发 NSStackView 断言崩溃（SIGABRT），
    /// 故移除前先检查 old 是否仍在 arrangedSubviews 中。
    private var folderSizeRow: NSView?
    private func appendFolderSizeRow(_ sizeString: String) {
        if let old = folderSizeRow {
            if mainColumn1?.arrangedSubviews.contains(old) == true {
                mainColumn1?.removeArrangedSubview(old)
                old.removeFromSuperview()
            }
            appendedTypeInfoRows.removeAll { $0 === old }
            folderSizeRow = nil
        }
        let row = makeInfoRow(label: makeLabel("总大小"), value: makeValueField(sizeString))
        mainColumn1?.addArrangedSubview(row)
        appendedTypeInfoRows.append(row)
        folderSizeRow = row
    }

    // MARK: - 工具方法

    private func isImageExtension(_ ext: String) -> Bool {
        return ["jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "heic", "webp", "psd"].contains(ext)
    }

    private func isVideoExtension(_ ext: String) -> Bool {
        return ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm"].contains(ext)
    }

    private func isAudioExtension(_ ext: String) -> Bool {
        return ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma", "aiff"].contains(ext)
    }

    private func isDocumentExtension(_ ext: String) -> Bool {
        return ["pdf", "doc", "docx", "txt", "md", "rtf", "pages"].contains(ext)
    }

    /// 格式化时长（秒 -> "H:MM:SS" 或 "M:SS"）
    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    /// FourCharCode (UInt32) -> 可读字符串（如 "h264" / "aac "）
    private func fourCCToString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "未知"
    }

    // MARK: - (权限字段已在 1.6 重设计中移除，如需恢复可参考 git 历史)
}

// MARK: - NSTextFieldDelegate（文件说明编辑）

extension ExpandableDetailsBar: NSTextFieldDelegate {

    /// 文件说明编辑结束（焦点离开或按回车）：保存到 UserDefaults 并退出编辑模式
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === descriptionField else {
            // v0.7.4 项 3：名称字段编辑结束 → 提交改名
            if let field = obj.object as? NSTextField, field === nameField {
                commitNameEditing()
            }
            return
        }
        let path = entry?.path ?? ""
        if !path.isEmpty {
            setFileDescription(path: path, description: field.stringValue)
        }
        // 退出编辑模式：恢复为无边框标签样式
        field.isEditable = false
        field.isBezeled = false
        field.drawsBackground = false
    }
}
