import Cocoa
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import PDFKit

/// 详情栏拖拽条：一段透明热区 + 悬停光标 + 拖拽回调。
/// 上边缘调高（垂直）与内部两条分界线（水平，带 1pt 可见线）共用。
/// 不用 NSSplitView：分隔样式与圆角卡片浮层难融合，且项目有布局约束风险史（设计文档方案 A）。
/// internal：布局回归测试经 @testable 访问 divider 属性需要类型可见（internal 属性不能暴露 fileprivate 类型）
class FFDetailsDragStrip: NSView {
    enum Axis { case horizontal, vertical }

    private let axis: Axis
    private let cursor: NSCursor
    private var tracking: NSTrackingArea?
    private var dragStart: CGPoint?
    /// 拖拽中标记：mouseUp 前划出热区不重置光标/亮线（终审 Minor 7）
    private var isDragging = false

    /// 拖拽回调：参数为本次鼠标拖动事件的位移（视图坐标系，dx 或 dy）
    var onDrag: ((CGFloat) -> Void)?
    /// 拖拽结束回调（松开鼠标）
    var onDragEnd: (() -> Void)?

    /// 1pt 可见线（showsLine = true 时创建，水平分界线用）
    private let lineView = NSView()

    init(axis: Axis, cursor: NSCursor, showsLine: Bool) {
        self.axis = axis
        self.cursor = cursor
        super.init(frame: .zero)
        wantsLayer = true
        if showsLine {
            lineView.wantsLayer = true
            lineView.layer?.backgroundColor = NSColor.separatorColor.cgColor
            lineView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(lineView)
            if axis == .horizontal {
                NSLayoutConstraint.activate([
                    lineView.centerXAnchor.constraint(equalTo: centerXAnchor),
                    lineView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                    lineView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                    lineView.widthAnchor.constraint(equalToConstant: 1),
                ])
            } else {
                NSLayoutConstraint.activate([
                    lineView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    lineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    lineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                    lineView.heightAnchor.constraint(equalToConstant: 1),
                ])
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("FFDetailsDragStrip 不支持 IB 初始化")
    }

    /// 悬停提亮可见线（分界线手柄反馈，与双栏分隔线一致）
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        cursor.set()
        if lineView.superview != nil {
            lineView.layer?.backgroundColor = FFAccent.current.withAlphaComponent(0.6).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // 拖拽中途划出热区保持光标与亮线（终审 Minor 7），松开鼠标后恢复正常重置
        guard !isDragging else { return }
        NSCursor.arrow.set()
        if lineView.superview != nil {
            lineView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let loc = convert(event.locationInWindow, from: nil)
        // 报「相对上次事件的增量」，dragStart 随事件前移；使用方以增量累积更新
        let delta = (axis == .horizontal) ? loc.x - start.x : loc.y - start.y
        dragStart = loc
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        onDragEnd?()
        isDragging = false
    }
}

// MARK: - ExpandableDetailsBar

/// 可展开的文件详情面板
///
/// 收起状态（高度 54pt）：
///   - 左侧：选中文件的高清预览图标（32x32，`NSWorkspace.shared.icon(forFile:)`）
///   - 中间：文件名 + 大小（单行，13pt medium）
///   - 右侧：展开按钮（chevron.up SF Symbol）
///
/// 展开状态（高度用户可拖拽调定并记忆，默认 210pt）：
///   - 左侧：大尺寸预览图标（边长随图标区宽度与内容区高度动态缩放，异步加载 QuickLook 缩略图，垂直居中）
///   - 右侧两列信息（流动填充布局，装不下的行隐藏、空间恢复后归位）：
///     - 第一列：名称 / 种类 / 大小 / 位置 / 创建日期 / 修改日期（+ 文件类型专属信息）
///     - 第二列：标签（药丸，可点击筛选 / 右键移除）/ 文件说明（双击编辑）/ 文件来源
///   - 底部：文件类型专属信息（分辨率 / 色彩空间 / EXIF / 时长 / 编码 等，合并入第一列）
///
/// 接口：
///   - `update(with entry: FileEntry?)` 更新显示的文件信息
///   - `isExpanded: Bool` 展开/收起状态
class ExpandableDetailsBar: NSView {

    // MARK: - Constants

    /// 收起态高度 36pt + 状态栏 18pt = 54pt
    private let collapsedHeight: CGFloat = 54
    /// 状态栏高度
    private let statusBarHeight: CGFloat = 18
    /// 展开态高度下限（图标 + 至少两行信息 + 状态栏）
    private let minExpandedHeight: CGFloat = 100
    /// 展开态高度相对面板高度的最大让位（保证文件列表露出一截）
    private let maxHeightReserve: CGFloat = 120
    /// 上边缘拖拽热区高度
    private let topEdgeHeight: CGFloat = 6
    /// 箭头按钮占位（上边缘热区尾部让出，避免盖住按钮）
    private let chevronReserve: CGFloat = 32

    /// 记忆 key（左右面板共用）
    private static let heightKey = "FFDetailsBarExpandedHeight"
    static let iconWidthKey = "FFDetailsBarIconWidth"
    static let column1WidthKey = "FFDetailsBarColumn1Width"

    // MARK: - State

    private var entry: FileEntry?
    private var selectedCount: Int = 0
    /// v0.7.4 修订: 完整选中数组（多选时用于汇总显示）
    private var selectedFiles: [FileEntry] = []
    /// 用户拖出的展开高度（权威值，computedExpandedHeight 已退役）
    private var userExpandedHeight: CGFloat
    /// 上边缘调高手柄
    private var topEdgeStrip: FFDetailsDragStrip!
    /// 同步应用远端布局时为 true（抑制再次广播造成回环）
    private var isApplyingRemoteLayout = false
    /// 图标区宽度（记忆值；图标边长由此与内容区高度推导）
    private var iconWidth: CGFloat
    /// 列1 宽度（记忆值；列2 兜底剩余宽度）
    private var column1Width: CGFloat
    // 约束引用（Task 3 setupUI 中赋值）
    private var iconWidthC: NSLayoutConstraint!
    private var column1WidthC: NSLayoutConstraint!
    private var bigIconWidthC: NSLayoutConstraint!
    private var bigIconHeightC: NSLayoutConstraint!
    private var multiIconWidthC: NSLayoutConstraint!
    private var multiIconHeightC: NSLayoutConstraint!
    /// 两条内部分界线
    /// internal 以便布局回归测试访问（FFDetailsDragStrip 经 @testable 访问；类型可见性以文件内定义为准）
    var dividerIconToCol1: FFDetailsDragStrip!
    var dividerCol1ToCol2: FFDetailsDragStrip!
    /// 内容模块区（contentModules）：图标区 | 分界线1 | 两列区，手动约束布局
    private var contentModules: NSView!
    private var columnsArea: NSView!

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
    /// internal：回归测试访问
    var mainColumn1: NSStackView!
    /// 第二列信息容器（标签/文件说明/文件来源）
    /// internal：回归测试访问
    var mainColumn2: NSStackView!

    // v0.7.4 项 7：所有信息行的引用（多选/未选时隐藏空白条目，单选时显示）
    /// internal：回归测试访问
    var infoRows: [NSView] = []

    /// 多选汇总行（流动顺序：数量 → 总大小 → 包含类型 → 包含标签）
    /// internal：回归测试访问
    var multiRows: [NSView] = []

    /// 上次流动填充时的 bar 尺寸（layout 中防重复重排）
    private var lastArrangedSize: NSSize = .zero

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

    // v0.7.4 项 4: 多选汇总字段（行由 rearrangeFlow 流动摆放到主信息两列，与单选行同列）
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
        userExpandedHeight = (UserDefaults.standard.object(forKey: Self.heightKey) as? CGFloat) ?? 210
        iconWidth = (UserDefaults.standard.object(forKey: Self.iconWidthKey) as? CGFloat) ?? 112
        column1Width = (UserDefaults.standard.object(forKey: Self.column1WidthKey) as? CGFloat) ?? 220
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        userExpandedHeight = (UserDefaults.standard.object(forKey: Self.heightKey) as? CGFloat) ?? 210
        iconWidth = (UserDefaults.standard.object(forKey: Self.iconWidthKey) as? CGFloat) ?? 112
        column1Width = (UserDefaults.standard.object(forKey: Self.column1WidthKey) as? CGFloat) ?? 220
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // V0.8.0：详情栏改为固定底栏，不再自己做圆角（由外层操作区面板裁剪）。
        layer?.cornerRadius = 0

        // V0.8.0：玻璃浮层 → 实体底栏。
        //
        // 旧实现是 FFGlassView(.panel) + 10pt 圆角 + 浮起阴影，覆盖在文件列表上方；
        // 现在它是操作区面板的固定底栏，层级由「比面板亮一档的底色 + 顶部 1px 分隔线」表达，
        // 与 ZCode 的边框分层立场一致，不再用模糊材质和投影。
        let solidBackground = FFPanelView(tone: .header, cornerRadius: 0)
        solidBackground.showsBorder = false
        solidBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(solidBackground)
        NSLayoutConstraint.activate([
            solidBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackground.topAnchor.constraint(equalTo: topAnchor),
            solidBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

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

        // 1.6 收起态名称：13pt semibold（Wave4 Task 5 改用 Typography.title 令牌，
        // 与展开态名称同档，避免选中数量切换时字号/字重跳变）
        compactNameField.font = FFDesign.Typography.title
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

        // v0.7.4 修订 4: 多选字段（数量/总大小/类型/标签）——由 rearrangeFlow 流动摆放到两列
        // （多选数量行；Wave4 Task 5：字段统一 body(11pt) 档，与标签/值一致）
        multiCountField.font = FFDesign.Typography.body
        multiCountField.textColor = NSColor.labelColor
        multiCountField.translatesAutoresizingMaskIntoConstraints = false

        // 多选总大小行
        multiSizeField.font = FFDesign.Typography.body
        multiSizeField.textColor = NSColor.labelColor
        multiSizeField.translatesAutoresizingMaskIntoConstraints = false

        // 多选类型行（文本：图片 3 · 文档 2）
        multiTypesField.font = FFDesign.Typography.body
        multiTypesField.textColor = NSColor.labelColor
        multiTypesField.translatesAutoresizingMaskIntoConstraints = false

        // 多选标签行（药丸）
        multiTagsContainer.orientation = .horizontal
        multiTagsContainer.spacing = 4
        multiTagsContainer.alignment = .centerY
        multiTagsContainer.translatesAutoresizingMaskIntoConstraints = false

        // 内容模块区（v0.7.6 重设计）：图标区 | 分界线1 | 两列区（列1 | 分界线2 | 列2）
        // 用手动约束替代 NSStackView，为三条可拖边界与图标动态缩放提供锚点
        let modules = NSView()
        modules.translatesAutoresizingMaskIntoConstraints = false
        contentModules = modules

        bigIconView.imageScaling = .scaleProportionallyUpOrDown
        bigIconView.translatesAutoresizingMaskIntoConstraints = false

        // 图标区容器：大图标与多选堆叠图标同槽居中，二选一显示
        let iconSlot = NSView()
        iconSlot.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(bigIconView)
        // 图标区宽度 = 记忆值（分界线1 拖拽 / 远端同步时更新 constant）
        iconWidthC = iconSlot.widthAnchor.constraint(equalToConstant: iconWidth)
        // 999 优先级：窗口/面板过窄时优雅压缩（列2 由 required 边缘约束兜底），
        // 避免 required 宽度在窄窗口下无法同时满足而刷布局冲突日志（审查发现 2）
        iconWidthC.priority = NSLayoutConstraint.Priority(999)

        // 两列区容器（plain NSView；列内垂直流式布局由 Task 4 rearrangeFlow 用 setColumn 管理）
        let area = NSView()
        area.translatesAutoresizingMaskIntoConstraints = false
        columnsArea = area

        // 第一列：名称 / 种类 / 大小 / 位置 / 创建日期 / 修改日期 + 文件类型专属信息
        let column1 = NSStackView()
        column1.orientation = .vertical
        column1.spacing = 4
        column1.alignment = .leading
        column1.translatesAutoresizingMaskIntoConstraints = false
        mainColumn1 = column1

        // v0.7.4 项 3：名称行（可单击改名）。Wave4 Task 5：改用 Typography.title(13 semibold)
        // 令牌，与收起态名称同档（此前 11pt semibold，低于标题档一档且与收起态 13pt 不一致）
        configureValue(nameField)
        nameField.font = FFDesign.Typography.title
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
        // Wave4 Task 5：位置值统一 body(11pt)，与其它详情值同档
        locationField.font = FFDesign.Typography.body
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
        // Wave4 Task 5：说明值统一 body(11pt)，与其它详情值同档
        descriptionField.font = FFDesign.Typography.body
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

        // 列1 宽度约束 = 记忆值（列2 兜底剩余宽度，见大约束数组）
        column1WidthC = column1.widthAnchor.constraint(equalToConstant: column1Width)
        // 999 优先级：窗口/面板过窄时优雅压缩（列2 由 required 边缘约束兜底），
        // 避免 required 宽度在窄窗口下无法同时满足而刷布局冲突日志（审查发现 2）
        column1WidthC.priority = NSLayoutConstraint.Priority(999)

        // 两条内部分界线：图标区|两列区（div1）、列1|列2（div2），带 1pt 可见线
        let div1 = FFDetailsDragStrip(axis: .horizontal, cursor: .resizeLeftRight, showsLine: true)
        let div2 = FFDetailsDragStrip(axis: .horizontal, cursor: .resizeLeftRight, showsLine: true)
        div1.translatesAutoresizingMaskIntoConstraints = false
        div2.translatesAutoresizingMaskIntoConstraints = false
        dividerIconToCol1 = div1
        dividerCol1ToCol2 = div2

        // 手动组装：图标区与两列区挂到模块区，列1/列2 挂到两列区（不再是 stack arranged）
        modules.addSubview(iconSlot)
        modules.addSubview(div1)
        modules.addSubview(area)
        area.addSubview(column1)
        area.addSubview(div2)
        area.addSubview(column2)

        // 多选内容行容器：Task 4 后汇总行由 rearrangeFlow 摆放到主信息两列，
        // 此容器仅保留隐藏占位（避免改动 expandedStack 结构）
        let multiRow = NSStackView()
        multiRow.orientation = .horizontal
        multiRow.spacing = 12
        multiRow.alignment = .top
        multiRow.translatesAutoresizingMaskIntoConstraints = false
        multiRow.isHidden = true

        // 多选大图标：缩略图堆叠容器（仿访达，最多堆叠 4 个选中项的缩略图）
        // Task 3：移入 iconSlot 与大图标同槽居中（互斥可见性由 Task 4 管理）
        let multiIcon = FFMiniThumbnailStackView()
        multiIcon.translatesAutoresizingMaskIntoConstraints = false
        multiIconView = multiIcon
        iconSlot.addSubview(multiIcon)

        // 图标边长约束统一动态（96 仅为初始值，updateIconEdge() 按图标区宽/内容区高推导）
        bigIconWidthC = bigIconView.widthAnchor.constraint(equalToConstant: 96)
        bigIconHeightC = bigIconView.heightAnchor.constraint(equalToConstant: 96)
        multiIconWidthC = multiIcon.widthAnchor.constraint(equalToConstant: 96)
        multiIconHeightC = multiIcon.heightAnchor.constraint(equalToConstant: 96)
        // 注：本 SDK 的 NSLayoutConstraint.activate 仅有数组重载（无可变参数版），故用数组形式逐个传入
        NSLayoutConstraint.activate([
            bigIconWidthC, bigIconHeightC, multiIconWidthC, multiIconHeightC,
            bigIconView.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            bigIconView.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            multiIconView.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            multiIconView.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
        ])

        // 多选两列
        let multiColumns = NSStackView()
        multiColumns.orientation = .horizontal
        multiColumns.spacing = 16
        multiColumns.alignment = .top
        multiColumns.translatesAutoresizingMaskIntoConstraints = false
        multiColumns.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 多选汇总行：仅持有引用，不放入 multiCol1/multiCol2——
        // 行由 rearrangeFlow 统一流动摆放到 mainColumn1/mainColumn2（与单选行同列）
        let multiCountRow = makeInfoRow(label: makeLabel("数量"), value: multiCountField)
        let multiSizeRow = makeInfoRow(label: makeLabel("总大小"), value: multiSizeField)
        let multiTypesRow = makeInfoRow(label: makeLabel("包含类型"), value: multiTypesField)
        let multiTagsRow = makeInfoRow(label: makeLabel("包含标签"), value: multiTagsContainer)

        // 列容器保留为空栈（multiColumns 结构不变，行摆放全权交给 rearrangeFlow）
        let multiCol1 = NSStackView()
        multiCol1.orientation = .vertical
        multiCol1.spacing = 4
        multiCol1.alignment = .leading
        multiCol1.translatesAutoresizingMaskIntoConstraints = false

        let multiCol2 = NSStackView()
        multiCol2.orientation = .vertical
        multiCol2.spacing = 4
        multiCol2.alignment = .leading
        multiCol2.translatesAutoresizingMaskIntoConstraints = false

        multiColumns.addArrangedSubview(multiCol1)
        multiColumns.addArrangedSubview(multiCol2)
        multiRow.addArrangedSubview(multiColumns)

        expandedStack.addArrangedSubview(multiRow)

        // 文件类型专属信息容器（内容行下方）
        fileTypeInfoContainer.orientation = .vertical
        fileTypeInfoContainer.spacing = 4
        fileTypeInfoContainer.alignment = .leading
        fileTypeInfoContainer.translatesAutoresizingMaskIntoConstraints = false

        expandedStack.addArrangedSubview(modules)
        // fileTypeInfoContainer 常年空置——专属信息行在 mainColumn1；从堆栈摘除避免与 modules 等高约束打架。
        // 属性与 clearFileTypeSpecificInfo 保持不动

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

        // 上边缘调高手柄：按住上下拖动调整展开高度（v0.7.6 详情栏重设计）
        let topStrip = FFDetailsDragStrip(axis: .vertical, cursor: .resizeUpDown, showsLine: false)
        topStrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStrip)   // 在 mouseInterceptor 之后添加 → 位于其上层，事件不被拦截
        topEdgeStrip = topStrip

        // 高度约束（由展开状态驱动）
        heightConstraint = heightAnchor.constraint(equalToConstant: collapsedHeight)
        heightConstraint.priority = .required

        NSLayoutConstraint.activate([
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

            // 上边缘热区：尾部让出箭头按钮区域
            topStrip.topAnchor.constraint(equalTo: topAnchor),
            topStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
            topStrip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -chevronReserve),
            topStrip.heightAnchor.constraint(equalToConstant: topEdgeHeight),

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

            // 内容模块区填满 expandedView
            modules.leadingAnchor.constraint(equalTo: expandedView.leadingAnchor),
            modules.trailingAnchor.constraint(equalTo: expandedView.trailingAnchor),
            modules.topAnchor.constraint(equalTo: expandedView.topAnchor),
            // 内容模块区填满 expandedView（高度确定链：分界线/图标区随栏高撑满，状态栏以上）
            modules.bottomAnchor.constraint(equalTo: expandedView.bottomAnchor),

            // 图标区：宽度 = 记忆值，高度撑满（图标在其中居中）
            iconSlot.leadingAnchor.constraint(equalTo: modules.leadingAnchor),
            iconSlot.topAnchor.constraint(equalTo: modules.topAnchor),
            iconSlot.bottomAnchor.constraint(equalTo: modules.bottomAnchor),
            iconWidthC,   // iconSlot.widthAnchor.constraint(equalToConstant: iconWidth)

            // 分界线1：图标区 | 两列区
            div1.leadingAnchor.constraint(equalTo: iconSlot.trailingAnchor),
            div1.topAnchor.constraint(equalTo: modules.topAnchor),
            div1.bottomAnchor.constraint(equalTo: modules.bottomAnchor),
            div1.widthAnchor.constraint(equalToConstant: 8),

            // 两列区：分界线1 右侧到模块区右缘
            area.leadingAnchor.constraint(equalTo: div1.trailingAnchor),
            area.trailingAnchor.constraint(equalTo: modules.trailingAnchor),
            area.topAnchor.constraint(equalTo: modules.topAnchor),
            area.bottomAnchor.constraint(equalTo: modules.bottomAnchor),

            // 列1：宽度 = 记忆值
            column1.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            column1.topAnchor.constraint(equalTo: area.topAnchor),
            column1WidthC,

            // 分界线2：列1 | 列2
            div2.leadingAnchor.constraint(equalTo: column1.trailingAnchor),
            div2.topAnchor.constraint(equalTo: area.topAnchor),
            div2.bottomAnchor.constraint(equalTo: area.bottomAnchor),
            div2.widthAnchor.constraint(equalToConstant: 8),

            // 列2：兜底剩余宽度
            column2.leadingAnchor.constraint(equalTo: div2.trailingAnchor),
            column2.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            column2.topAnchor.constraint(equalTo: area.topAnchor),

            heightConstraint,
        ])

        topStrip.onDrag = { [weak self] dy in
            self?.applyHeightDrag(deltaY: dy)
        }
        topStrip.onDragEnd = { [weak self] in
            guard let self else { return }
            // 尺寸记忆在拖拽结束时一次性落盘（终审 Minor：避免 ~60Hz 的 plist 写入），
            // 落盘后广播——对侧栏按 UserDefaults 重读同步，必须在落盘之后（复核 Important 1）
            UserDefaults.standard.set(self.userExpandedHeight, forKey: Self.heightKey)
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
            // 拖高后内容区高度变化 → 图标边长与流动填充重排
            updateIconEdge()
            rearrangeFlow()
        }

        // 内部分界线拖拽回调（图标区宽度 / 列1 宽度）
        div1.onDrag = { [weak self] dx in self?.applyIconWidthDrag(deltaX: dx) }
        div1.onDragEnd = { [weak self] in
            guard let self else { return }
            // 尺寸记忆在拖拽结束时一次性落盘并广播（同上，复核 Important 1）
            UserDefaults.standard.set(self.iconWidth, forKey: Self.iconWidthKey)
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
            rearrangeFlow()
        }
        div2.onDrag = { [weak self] dx in self?.applyColumn1WidthDrag(deltaX: dx) }
        div2.onDragEnd = { [weak self] in
            guard let self else { return }
            // 尺寸记忆在拖拽结束时一次性落盘并广播（同上，复核 Important 1）
            UserDefaults.standard.set(self.column1Width, forKey: Self.column1WidthKey)
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
            rearrangeFlow()
        }

        // 多选汇总行注册表（顺序即流动顺序；行由 rearrangeFlow 统一摆放）
        multiRows = [multiCountRow, multiSizeRow, multiTypesRow, multiTagsRow]

        applyExpandedState(animated: false)
        observeLayoutChanged()
        refresh()
    }

    /// 按内容区高度与图标区宽度重算图标边长：min(图标区宽 − 16, 内容区高 − 16)，下限 32
    func updateIconEdge() {
        let contentHeight = expandedView.bounds.height
        let edge = max(min(iconWidth - 16, contentHeight - 16), 32)
        bigIconWidthC.constant = edge
        bigIconHeightC.constant = edge
        multiIconWidthC.constant = edge
        multiIconHeightC.constant = edge
    }
    // MARK: - 流动填充

    /// 流动顺序的全部行：单选 = 前 6 常规行 + 类型专属行 + 后 3 行；多选 = 4 汇总行
    /// internal：流动顺序回归测试访问
    var flowOrderedRows: [NSView] {
        if selectedCount > 1 { return multiRows }
        guard entry != nil else { return [] }
        let base = infoRows
        guard base.count >= 9 else { return base }
        return Array(base[0..<6]) + appendedTypeInfoRows + Array(base[6..<base.count])
    }

    /// 按列宽测量行高（locationField 等可换行行随宽度变化），下限 16。
    /// AppKit 没有 UIKit 的 systemLayoutSizeFitting(_:withHorizontalFittingPriority:
    /// verticalFittingPriority:)——改为把行临时全量放入列1、flush 列布局后读取真实
    /// frame 高度（行尚未摆回列2，统一按列1宽度测量，与纯计算核心的输入语义一致）。
    private func measuredRowHeights(of rows: [NSView]) -> [CGFloat] {
        setColumn(mainColumn2, rows: [])
        setColumn(mainColumn1, rows: rows)
        mainColumn1.layoutSubtreeIfNeeded()
        return rows.map { max($0.frame.height, 16) }
    }

    /// 重新摆放一列的行（全量替换 arranged 行；被移除的行从父视图摘除，由注册表数组持有生命周期）
    private func setColumn(_ column: NSStackView, rows: [NSView]) {
        for view in column.arrangedSubviews {
            column.removeArrangedSubview(view)
            view.removeFromSuperview()
            // 不在此注销 appendedTypeInfoRows：注册表生命周期归 updateFileTypeSpecificInfo
            // （每次选中重建），流动重排只摘挂载、不改注册表——否则测量步骤的全量摘除会
            // 清空注册表，后续重排时专属行整段消失（审查 Critical 修复）。
            // 溢出被摘除的行仍留在注册表中（持有生命周期，空间恢复时重新归位）
        }
        for row in rows {
            column.addArrangedSubview(row)
        }
    }

    /// 流动填充重排：按固定顺序把行分配到列1/列2，装不下的隐藏。
    /// 触发点：高度/分界线拖拽、展开切换、refresh 末尾、面板尺寸变化。
    func rearrangeFlow() {
        // 挂载判定：已加入视图层级（含测试用普通容器承载）即可重排；
        // 不强制 window != nil——单元测试避免使用真实 NSWindow
        //（窗口簿记延迟块与测试裸释放竞态，曾致运行器 SIGSEGV）
        guard isExpanded, window != nil || superview != nil else { return }
        layoutSubtreeIfNeeded()
        // 图标边长在布局 flush 后更新：图标尺寸不参与内容行高度推导，flush 后按真实内容区高度算得更精确（终审 Minor 2）
        updateIconEdge()
        let ordered = flowOrderedRows
        guard !ordered.isEmpty else {
            setColumn(mainColumn1, rows: [])
            setColumn(mainColumn2, rows: [])
            // 空分支同样记录尺寸，避免 layout() 因 lastArrangedSize 滞后而反复触发重排（终审 Minor 8）
            lastArrangedSize = bounds.size
            return
        }
        let heights = measuredRowHeights(of: ordered)
        let available = max(expandedView.bounds.height - 4, 32)
        let split = FFDetailsFlowLayout.flowSplit(itemHeights: heights, availableHeight: available)
        let visible = FFDetailsFlowLayout.visibleItemCount(itemHeights: heights, availableHeight: available)
        let firstCount = min(split, ordered.count)
        let first = Array(ordered[0..<firstCount])
        let second = Array(ordered[firstCount..<min(visible, ordered.count)])
        setColumn(mainColumn1, rows: first)
        setColumn(mainColumn2, rows: second)
        for row in ordered where !first.contains(row) && !second.contains(row) {
            row.removeFromSuperview()
        }
        lastArrangedSize = bounds.size
    }

    /// 布局期挂起的重排标记：layout() 中禁止同步重排（layoutSubtreeIfNeeded 在布局中递归
    /// 属非法调用，系统 WarnOnce「already being laid out」）
    private var isFlowDeferred = false

    override func layout() {
        super.layout()
        guard isExpanded, bounds.size != lastArrangedSize, !isFlowDeferred else { return }
        isFlowDeferred = true
        // 布局期的重排与高度重新 clamp 推迟到本次布局结束后执行（去抖合并）
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFlowDeferred else { return }
            self.isFlowDeferred = false
            // 收起态下不应用展开高度（调度与执行之间可能已收起——复核 Minor 1）
            guard self.isExpanded else { return }
            // 窗口/面板缩小后重新 clamp 已应用高度（终审 Important 1）
            let applied = self.appliedExpandedHeight()
            if self.heightConstraint.constant != applied {
                self.heightConstraint.constant = applied
            }
            self.rearrangeFlow()
        }
    }

    // MARK: - Builders

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        // Wave4 Task 5：标签 10pt→body(11pt)，与全局正文基准同档（审计 §3）
        f.font = FFDesign.Typography.body
        f.textColor = NSColor.secondaryLabelColor
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.required, for: .horizontal)
        f.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Wave4 Task 5：44pt 固定宽改弹性 ≥44（历史痕迹：固定宽与字号耦合，换字号即错位；
        // 11pt 下 4 字标签仍容纳，出现 5 字标签时按内容撑开不截断）
        f.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return f
    }

    private func configureValue(_ f: NSTextField) {
        // Wave4 Task 5：值 10pt→body(11pt)，与标签同档提升可读性
        f.font = FFDesign.Typography.body
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

    /// 上边缘拖拽：更新记忆高度并实时应用（clamp [100, 面板高度−120]；落盘延迟到拖拽结束）
    private func applyHeightDrag(deltaY: CGFloat) {
        guard isExpanded else { return }
        let paneHeight = superview?.bounds.height ?? 0
        let maxHeight = max(minExpandedHeight, paneHeight - maxHeightReserve)
        let newHeight = min(max(userExpandedHeight + deltaY, minExpandedHeight), maxHeight)
        guard newHeight != userExpandedHeight else { return }
        userExpandedHeight = newHeight
        heightConstraint.constant = newHeight
        rearrangeFlow()
        if !isApplyingRemoteLayout {
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
        }
    }

    /// 分界线1 拖拽：图标区宽度 = 图标大小（clamp [32, 内容行总宽 − 240]；落盘延迟到拖拽结束）
    private func applyIconWidthDrag(deltaX: CGFloat) {
        guard isExpanded else { return }
        let modulesWidth = contentModules?.bounds.width ?? 0
        let maxIcon = max(32, modulesWidth - 240)
        let newWidth = min(max(iconWidth + deltaX, 32), maxIcon)
        guard newWidth != iconWidth else { return }
        iconWidth = newWidth
        iconWidthC.constant = newWidth
        updateIconEdge()
        rearrangeFlow()
        if !isApplyingRemoteLayout {
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
        }
    }

    /// 分界线2 拖拽：列1 宽度（clamp [120, 总宽 − 图标区 − 240]；落盘延迟到拖拽结束）
    private func applyColumn1WidthDrag(deltaX: CGFloat) {
        guard isExpanded else { return }
        let modulesWidth = contentModules?.bounds.width ?? 0
        let maxCol1 = max(120, modulesWidth - iconWidth - 240)
        let newWidth = min(max(column1Width + deltaX, 120), maxCol1)
        guard newWidth != column1Width else { return }
        column1Width = newWidth
        column1WidthC.constant = newWidth
        rearrangeFlow()
        if !isApplyingRemoteLayout {
            NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: self)
        }
    }

    /// 监听另一侧详情栏的布局变更（拖左栏右栏同步）
    private func observeLayoutChanged() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutChangedRemotely),
            name: .FFDetailsBarLayoutChanged, object: nil
        )
    }

    @objc private func layoutChangedRemotely(_ note: Notification) {
        // object 为 Any? 不能直接 !==（需类约束），先转换为详情栏类型再比较
        guard (note.object as? ExpandableDetailsBar) !== self else { return }
        isApplyingRemoteLayout = true
        defer { isApplyingRemoteLayout = false }
        userExpandedHeight = (UserDefaults.standard.object(forKey: Self.heightKey) as? CGFloat) ?? userExpandedHeight
        if isExpanded {
            // 恢复/同步路径同样 clamp（终审 Important 1：大屏记忆值在小面板上重新收敛）
            heightConstraint.constant = appliedExpandedHeight()
            // Task 3：宽度记忆值同步（另一栏拖分界线后本栏应用同样宽度）
            iconWidth = (UserDefaults.standard.object(forKey: Self.iconWidthKey) as? CGFloat) ?? iconWidth
            column1Width = (UserDefaults.standard.object(forKey: Self.column1WidthKey) as? CGFloat) ?? column1Width
            iconWidthC.constant = iconWidth
            column1WidthC.constant = column1Width
            updateIconEdge()
            rearrangeFlow()
        }
    }

    /// 应用展开高度（统一 clamp 出口）：记忆值仅在拖拽路径产生时已 clamp，
    /// 恢复/同步/窗口缩小路径必须再次 clamp，防止大屏记忆值在小面板上盖满文件列表
    /// （终审 Important 1：栏过高时上边缘手柄与箭头会被推出窗口，无法从窗口内救回）。
    private func appliedExpandedHeight() -> CGFloat {
        let paneHeight = superview?.bounds.height ?? 0
        let maxHeight = paneHeight > 0 ? max(minExpandedHeight, paneHeight - maxHeightReserve) : userExpandedHeight
        return min(max(userExpandedHeight, minExpandedHeight), maxHeight)
    }

    private func applyExpandedState(animated: Bool) {
        let newHeight = isExpanded ? appliedExpandedHeight() : collapsedHeight
        heightConstraint.constant = newHeight
        topEdgeStrip?.isHidden = !isExpanded
        // 内部分界线仅展开态可见（收起态无内容模块区）
        dividerIconToCol1?.isHidden = !isExpanded
        dividerCol1ToCol2?.isHidden = !isExpanded
        compactView.isHidden = isExpanded
        expandedView.isHidden = !isExpanded

        let symbol = isExpanded ? "chevron.down" : "chevron.up"
        chevronButton.image = NSImage(systemSymbolName: symbol,
                                      accessibilityDescription: isExpanded ? "收起" : "展开")

        if isExpanded { loadThumbnail() }

        let performLayout = { [weak self] in
            self?.window?.layoutIfNeeded()
            self?.rearrangeFlow()
            self?.lastArrangedSize = self?.bounds.size ?? .zero
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = FFMotion.animationDuration(0.25)
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                performLayout()
            }
        } else {
            performLayout()
        }
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
            // 无选中：大图标显示（文件夹占位），清空两列并摘除多选汇总行
            bigIconView.isHidden = false
            multiIconView.isHidden = true
            setColumn(mainColumn1, rows: [])
            setColumn(mainColumn2, rows: [])
            multiRows.forEach { $0.removeFromSuperview() }
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
            // 图标槽切换：大图标隐藏、多选堆叠图标显示
            bigIconView.isHidden = true
            multiIconView.isHidden = false
            // 多选图标：缩略图堆叠（取前 4 个选中项的缩略图）
            multiIconView.update(with: Array(selectedFiles.prefix(4)))
            populateMultiSelectSummary()
            rearrangeFlow()
            chevronButton.isEnabled = true
            return
        }

        // 单选：显示所有信息行，图标槽切回大图标并摘除多选汇总行
        for row in infoRows { row.isHidden = false }
        bigIconView.isHidden = false
        multiIconView.isHidden = true
        multiRows.forEach { $0.removeFromSuperview() }
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

        rearrangeFlow()

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
        // 移除上一次的专属信息行。防护：行可能已被流动填充摆到列2或暂时摘除
        // （removeArrangedSubview 对未附着行会抛 NSInternalInconsistencyException，
        // 与 appendFolderSizeRow 的 contains 防护同一模式——审查修复：注册表不再被流动逻辑改动）
        for row in appendedTypeInfoRows {
            if row.superview === mainColumn1 {
                mainColumn1?.removeArrangedSubview(row)
            }
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

    /// 异步计算文件夹总大小，完成后把"总大小"专属信息行追加到主信息列（mainColumn1）
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
        // 异步回填不打断流动顺序（审查 Minor：回填后重排归位）
        rearrangeFlow()
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
