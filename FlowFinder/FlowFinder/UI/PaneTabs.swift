import Cocoa

// MARK: - 标签会话

/// 一个浏览标签的完整快照。
/// 标签 = 面板的一次独立浏览会话（路径 + 返回栈 + 排序 / 视图模式 / 分组 / 标签筛选）。
struct PaneTabSession {
    let id: UUID
    var state: PaneState
    /// 2026-10-20 #4：占位标签标记。面板被搬空后只剩占位，
    /// 用它判断「这个面板空了 → 该关窗」。
    var isPlaceholder: Bool = false

    init(id: UUID = UUID(), state: PaneState) {
        self.id = id
        self.state = state
    }

    /// 标签标题：根路径显示卷名，其余取最后一段
    var title: String {
        if state.path == "/" { return "Macintosh HD" }
        let name = (state.path as NSString).lastPathComponent
        if !name.isEmpty { return name }
        return state.path.isEmpty ? "新标签页" : state.path
    }
}

/// 单个面板的标签集合与激活索引。
/// 纯数据 + 纯函数（新建 / 关闭 / 移动 / 选择），不依赖 AppKit，便于单测。
final class PaneTabsStore {
    private(set) var tabs: [PaneTabSession]
    private(set) var activeIndex: Int = 0

    init(initial: PaneTabSession) {
        tabs = [initial]
    }

    var count: Int { tabs.count }
    var canClose: Bool { tabs.count > 1 }
    var active: PaneTabSession { tabs[activeIndex] }

    /// 把当前面板状态写回激活标签（导航 / 换排序 / 切视图后调用）
    func updateActiveState(_ state: PaneState) {
        guard tabs.indices.contains(activeIndex) else { return }
        tabs[activeIndex].state = state
    }

    @discardableResult
    func add(_ session: PaneTabSession, at index: Int? = nil) -> Int {
        removeLonePlaceholder()
        let target = min(max(index ?? tabs.count, 0), tabs.count)
        tabs.insert(session, at: target)
        activeIndex = target
        return target
    }

    @discardableResult
    func close(at index: Int) -> Bool {
        guard tabs.count > 1, tabs.indices.contains(index) else { return false }
        tabs.remove(at: index)
        if index < activeIndex {
            activeIndex -= 1
        } else if index == activeIndex {
            activeIndex = min(index, tabs.count - 1)
        }
        return true
    }

    @discardableResult
    func select(_ index: Int) -> Bool {
        guard tabs.indices.contains(index), index != activeIndex else { return false }
        activeIndex = index
        return true
    }

    /// 拖动重排：`to` 为插入位置（0...count）
    @discardableResult
    func move(from: Int, to: Int) -> Bool {
        guard tabs.indices.contains(from), to >= 0, to <= tabs.count, from != to else { return false }
        let item = tabs.remove(at: from)
        var target = to
        if from < target { target -= 1 }
        target = min(max(target, 0), tabs.count)
        tabs.insert(item, at: target)
        if activeIndex == from {
            activeIndex = target
        } else {
            if from < activeIndex { activeIndex -= 1 }
            if target <= activeIndex { activeIndex += 1 }
        }
        return true
    }

    func insert(_ session: PaneTabSession, at index: Int, activate: Bool = true) {
        removeLonePlaceholder()
        let target = min(max(index, 0), tabs.count)
        tabs.insert(session, at: target)
        if activate || tabs.count == 1 {
            activeIndex = target
        } else if target <= activeIndex {
            activeIndex += 1
        }
    }

    /// 占位标签只代表「这个面板空了」。真实标签进来时填回占位，
    /// 而不是留下「占位 + 标签」——否则单标签拖回自己的标签条会多出一个标签。
    private func removeLonePlaceholder() {
        guard tabs.count == 1, tabs[0].isPlaceholder else { return }
        tabs.removeAll()
        activeIndex = 0
    }

    // MARK: B5 整组合并 / 拆分

    /// 整组合并（#5b）：把 other 的全部标签按原顺序追加到末尾，
    /// 激活被拖组的激活标签。other 清空后由调用方补占位。
    /// 追加后被拖激活标签位于返回的 index。
    @discardableResult
    func absorb(_ other: PaneTabsStore) -> Int {
        let moved = other.tabs
        let movedActive = other.activeIndex
        other.tabs.removeAll()
        other.activeIndex = 0
        let base = tabs.count
        tabs.append(contentsOf: moved)
        activeIndex = base + movedActive
        return activeIndex
    }

    /// 清空并补一个占位标签（被并侧在单窗期间不可见，切回双窗时保底有会话）
    func resetToPlaceholder(_ session: PaneTabSession) {
        tabs = [session]
        activeIndex = 0
    }

    /// 按 id 移除标签（拆分时从活动组取走被拖标签）
    @discardableResult
    func remove(sessionID: UUID) -> Bool {
        guard let i = tabs.firstIndex(where: { $0.id == sessionID }) else { return false }
        tabs.remove(at: i)
        if i < activeIndex {
            activeIndex -= 1
        } else if i == activeIndex {
            activeIndex = min(i, tabs.count - 1)
        }
        return true
    }

    /// 整组替换（拆分时对侧组直接换成被拖标签）
    func replaceAll(_ newTabs: [PaneTabSession], activeAt index: Int = 0) {
        tabs = newTabs
        activeIndex = min(max(index, 0), max(tabs.count - 1, 0))
    }
}

// MARK: - 标签重排的插入位置

/// 标签条重排的纯几何判定。
/// 指针允许落在标签条外扩 `buffer` 的缓冲区内，超出缓冲才算离开。
enum FFTabMetrics {
    static let closeVisualSize: CGFloat = 20
    static let closeHitSize: CGFloat = 24
}

/// 标签关闭按钮：命中 24×24，悬停时绘制 20×20 的柔和底色。
final class FFTabCloseButton: NSButton {
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            let visual = FFTabMetrics.closeVisualSize
            let rect = NSRect(x: (bounds.width - visual) / 2,
                              y: (bounds.height - visual) / 2,
                              width: visual, height: visual)
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        super.draw(dirtyRect)
    }
}

enum FFTabReorder {
    static func insertionIndex(localPoint: NSPoint,
                               stripBounds: NSRect,
                               buffer: CGFloat,
                               itemMidXs: [CGFloat]) -> Int? {
        let zone = stripBounds.insetBy(dx: -buffer, dy: -buffer)
        guard zone.contains(localPoint) else { return nil }
        let x = min(max(localPoint.x, stripBounds.minX), stripBounds.maxX)
        for (i, midX) in itemMidXs.enumerated() where x < midX {
            return i
        }
        return itemMidXs.count
    }
}

// MARK: - 单个标签

final class PaneTabItemView: NSView, FFRegionAware {

    /// 标签标题（诊断用）
    var titleText: String { titleLabel.stringValue }

    /// 标签本体：唯一能拖面板的把手（条内重排 / 出缓冲搬整块面板）
    var ffRegion: FFRegion { .tab }

    private let folderIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = FFTabCloseButton()
    private var mouseDownPoint: NSPoint?
    /// 高度约束：活动 28（焊死）/ 非活动 24（在 28pt 栈内垂直居中）
    private var heightConstraint: NSLayoutConstraint!
    private var isHovering = false {
        didSet { if isHovering != oldValue { updateAppearance() } }
    }

    var tabSession: PaneTabSession
    var index: Int
    /// 所在标签条的面板侧（拖拽时写入上下文，供跨面板移交判定）
    var side: PaneSide = .left
    /// 所在标签条（2026-10-20 #1：拖动统一由窗口级控制器处理，需要反查标签条）
    weak var strip: PaneTabStripView?
    var isActive: Bool = false {
        didSet { updateAppearance() }
    }
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    init(session: PaneTabSession, index: Int) {
        self.tabSession = session
        self.index = index
        super.init(frame: .zero)
        setupUI()
        titleLabel.stringValue = session.title
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        // 标签本身不再画背景：A1 焊接轮廓由 PaneTabStripBackdrop 统一绘制，
        // 否则活动标签的直角底边会盖住内凹肩线。
        folderIcon.image = FFIcon.template(.folder, size: 14)
        folderIcon.contentTintColor = NSColor.secondaryLabelColor
        folderIcon.imageScaling = .scaleProportionallyDown
        folderIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(folderIcon)

        titleLabel.font = NSFont.systemFont(ofSize: FFSizePreference.current.bodyFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = FFIcon.template(.x, size: FFInteractionPolicy.closeGlyphSize)
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        heightConstraint = heightAnchor.constraint(
            equalToConstant: FFInteractionPolicy.inactiveTabHeight)

        NSLayoutConstraint.activate([
            heightConstraint,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),

            // 标签在 NSStackView（flipped）里：正 constant 向下。
            // 内容需要比标签框中心高 3pt 才能落在 22pt 共用中线，因此用负值。
            folderIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            folderIcon.centerYAnchor.constraint(equalTo: centerYAnchor,
                                                constant: -FFTopBarMetrics.tabContentOffset),
            folderIcon.widthAnchor.constraint(equalToConstant: 14),
            folderIcon.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: folderIcon.trailingAnchor, constant: 5),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor,
                                                constant: -FFTopBarMetrics.tabContentOffset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor,
                                                constant: -FFTopBarMetrics.tabContentOffset),
            closeButton.widthAnchor.constraint(equalToConstant: FFTabMetrics.closeHitSize),
            closeButton.heightAnchor.constraint(equalToConstant: FFTabMetrics.closeHitSize),
        ])
    }

    func update(session: PaneTabSession, index: Int, active: Bool) {
        self.tabSession = session
        self.index = index
        titleLabel.stringValue = session.title
        isActive = active
    }

    private func updateAppearance() {
        heightConstraint?.constant = isActive
            ? FFInteractionPolicy.activeTabHeight
            : FFInteractionPolicy.inactiveTabHeight

        if isActive {
            titleLabel.textColor = NSColor.labelColor
            titleLabel.font = NSFont.systemFont(ofSize: FFSizePreference.current.bodyFontSize,
                                                weight: .medium)
            folderIcon.contentTintColor = FFAccent.current
        } else {
            titleLabel.textColor = NSColor.secondaryLabelColor
            titleLabel.font = NSFont.systemFont(ofSize: FFSizePreference.current.bodyFontSize)
            folderIcon.contentTintColor = NSColor.secondaryLabelColor
        }
        // 活动标签常显关闭；非活动标签 hover 时才出现（与访达/浏览器一致）。
        closeButton.isHidden = !(isActive || isHovering)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshAppearance() { updateAppearance() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    @objc private func handleClose() {
        onClose?()
    }

    /// 标题 label 会吞掉 mouseDown（NSTextField 自身处理点击），导致点标签文字无法切换。
    /// 除关闭按钮外，命中一律归标签本身。
    ///
    /// 注意：`point` 是**父视图坐标系**的点，必须先做 `frame.contains` 判定。
    /// 早期实现直接 `return self`，越界的点也被本视图认领——由于 NSStackView 按
    /// 逆序（最后添加的先问）派发 hitTest，结果是**最后一个标签吞掉整条标签栏**：
    /// 点任何标签都选中最后一个、拖任何标签拖走的也是最后一个。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        if let hit = super.hitTest(point), hit === closeButton || hit.isDescendant(of: closeButton) {
            return hit
        }
        return self
    }

    /// 点击选中由窗口级拖拽控制器在 mouseUp 时统一派发（这里不再自己处理 mouseDown，
    /// 否则会与「拖标签」的判定抢事件）。
    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

}

// MARK: - 标签条

protocol PaneTabStripDelegate: AnyObject {
    func tabStripDidRequestNewTab(_ strip: PaneTabStripView)
    func tabStrip(_ strip: PaneTabStripView, didSelect index: Int)
    func tabStrip(_ strip: PaneTabStripView, didClose index: Int)
    func tabStrip(_ strip: PaneTabStripView, didMoveTabFrom from: Int, to: Int)
    func tabStrip(_ strip: PaneTabStripView, didReceive session: PaneTabSession, at index: Int)
}

/// 标签条背板：画「活动标签 + 两处根部内凹」的合并轮廓并填面板色。
///
/// 2026-10-20 #4：为什么需要这一层——
/// 根部内凹（r2=8）位于「标签左缘再往左」与「面板顶边再往上」的那块区域里，
/// 既不属于标签视图，也不属于面板卡片（卡片有 masksToBounds 画不出来）。
/// 于是单独一层背板，位于所有标签之下、标签条之内，负责把这块填成面板色，
/// 视觉上标签就与面板连成一体。
final class PaneTabStripBackdrop: NSView {

    /// 活动标签在本视图坐标系里的矩形（原点左下）
    var tabRect: NSRect? {
        didSet { if tabRect != oldValue { needsDisplay = true } }
    }

    /// 填充色，必须与面板卡片一致（日间 #F5F5F5 / 夜间 #2D2D2D）
    var fillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    /// 只负责画，不参与命中
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let tab = tabRect, tab.width > 1, tab.height > 1 else { return }
        fillColor.setFill()
        FFTabSilhouette.tabFootprint(tab: tab, baseline: 0).fill()
    }
}

/// 操作区顶部的浏览器式标签条（2026-10-20 #1：提到窗口顶部那一行，高 28pt，常显）
final class PaneTabStripView: NSView, FFRegionAware {

    /// 标签条属于标题区：空白处起手是「拖窗口」（性质等同系统标题栏）
    var ffRegion: FFRegion { .title }

    weak var delegate: PaneTabStripDelegate?
    var side: PaneSide = .left

    private let stack = NSStackView()
    private let addButton = FFHoverIconButton()
    /// 活动标签与面板的焊接背板（在标签之下）
    private let backdrop = PaneTabStripBackdrop()
    private var items: [PaneTabItemView] = []
    private var sessions: [PaneTabSession] = []
    private var activeIndex: Int = 0

    // MARK: - 面板拖拽（2026-10-20 #1）
    //
    // 标签条现在在窗口顶部那一行（与红绿灯同高）：
    //   - 标签条空白 → 拖窗口（性质等同系统标题栏）
    //   - 标签本身   → 拖动由窗口级 FFPaneDragController 统一处理
    //   空白处必须能被识别成「标签条自己」，因此这里把空白归并到标签条视图上。

    /// 标签条不参与窗口拖动：空白处起手的是「拖面板」
    override var mouseDownCanMoveWindow: Bool { false }

    /// 命中归并：标签与「+」按钮保留自身命中，
    /// 其余（标签栈留白、标签之间的空隙）一律归标签条自己，
    /// 否则会落到 NSStackView 上——那是纯排版容器，点了没有任何反应。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        guard let hit = super.hitTest(point) else { return self }
        if hit === self { return self }
        if hit === stack { return self }
        return hit
    }

    // 标签条空白处的拖动同样由窗口级 `FFPaneDragController` 接管。

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

        // 背板铺满整条，位于所有标签之下；A1 焊接轮廓（含 9pt 内凹肩线）由它绘制。
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        backdrop.isHidden = false

        stack.orientation = .horizontal
        // 活动 28 填满栈；非活动 24 在栈内垂直居中 → 两者中心线都是 16pt。
        stack.alignment = .centerY
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let plusButton = addButton
        plusButton.bezelStyle = .inline
        plusButton.isBordered = false
        plusButton.imagePosition = .imageOnly
        plusButton.image = FFIcon.template(.plus, size: FFInteractionPolicy.plusGlyphSize)
        plusButton.contentTintColor = NSColor.secondaryLabelColor
        plusButton.hoverCornerRadius = 6
        plusButton.toolTip = "新建标签页"
        plusButton.target = self
        plusButton.action = #selector(handleNewTab)
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plusButton)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 首标签左缘：面板左缘（卡片留白 8）+ 26。
            // 面板圆角 16 + 内凹 9 = 25，26 再留 1pt 平段。
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: FFActivePaneBorderView.edgeOutset + FFInteractionPolicy.tabInsetFromPanel),
            // 顶部留出「标签上方间隙」（标题带 30 − 活动标签 28 = 2）
            stack.topAnchor.constraint(
                equalTo: topAnchor,
                constant: FFInteractionPolicy.tabTopGap),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            // 「+」紧跟最后一个标签（Chrome 式），中心线与标签一致
            plusButton.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 6),
            plusButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            plusButton.bottomAnchor.constraint(equalTo: bottomAnchor,
                                               constant: -FFInteractionPolicy.addButtonBottomInset),
            plusButton.widthAnchor.constraint(equalToConstant: FFInteractionPolicy.topBarHitSize),
            plusButton.heightAnchor.constraint(equalToConstant: FFInteractionPolicy.topBarHitSize),
        ])
    }

    @objc private func handleNewTab() {
        delegate?.tabStripDidRequestNewTab(self)
    }

    // MARK: - 焊接背板（2026-10-20 #4）

    /// 背板填充色 = 面板卡片背景色（由控制器注入，跟随主题）
    func setBackdropColor(_ color: NSColor) {
        backdrop.fillColor = color
    }

    func refreshAppearance() {
        items.forEach { $0.refreshAppearance() }
        addButton.contentTintColor = .secondaryLabelColor
        backdrop.needsDisplay = true
        needsDisplay = true
    }

    /// 取第 index 个标签的视图（拖动浮层用）
    func itemView(at index: Int) -> PaneTabItemView? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// 当前所有标签项（自检用）
    func allTabItems() -> [PaneTabItemView] { items }

    /// “+”按钮在标签条坐标系里的矩形；落点判定把它当无效区。
    var addButtonFrame: NSRect? {
        guard addButton.superview != nil else { return nil }
        return addButton.convert(addButton.bounds, to: self)
    }

    /// 活动标签在本标签条坐标系里的矩形；nil = 没有活动标签
    var activeTabFrame: NSRect? {
        guard let item = items.first(where: { $0.isActive }),
              let parent = item.superview else { return nil }
        return convert(item.frame, from: parent)
    }

    /// 活动标签位置变化时的回调（控制器据此同步发光的合并轮廓）
    var onActiveTabFrameChanged: (() -> Void)?

    /// 把活动标签的位置同步给背板
    private func updateBackdrop() {
        backdrop.tabRect = activeTabFrame
        onActiveTabFrameChanged?()
    }

    override func layout() {
        super.layout()
        // 标签位置由 Auto Layout 决定，布局完才知道最终 frame
        updateBackdrop()
    }

    /// 重绘标签：数量不变时就地更新，避免每次选中变化都重建视图
    func refresh(sessions: [PaneTabSession], activeIndex: Int) {
        self.sessions = sessions
        self.activeIndex = activeIndex

        if items.count != sessions.count {
            rebuildItems()
            return
        }
        for (i, item) in items.enumerated() {
            item.update(session: sessions[i], index: i, active: i == activeIndex)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateBackdrop()
    }

    private func rebuildItems() {
        // 重建后需要重新算背板（活动标签换了视图对象）
        items.forEach { $0.removeFromSuperview() }
        items.removeAll()
        for (i, session) in sessions.enumerated() {
            let item = PaneTabItemView(session: session, index: i)
            item.side = side
            item.strip = self
            item.isActive = (i == activeIndex)
            item.onSelect = { [weak self] in
                guard let self = self else { return }
                self.delegate?.tabStrip(self, didSelect: i)
            }
            item.onClose = { [weak self] in
                guard let self = self else { return }
                self.delegate?.tabStrip(self, didClose: i)
            }
            stack.addArrangedSubview(item)
            items.append(item)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateBackdrop()
    }

    // MARK: - 拖放命中（由窗口级接收器调用）

    /// 最后一个标签之后一点的窗口坐标（自检用）
    func windowPointPastLastTab() -> NSPoint? {
        guard let last = items.last else { return nil }
        let local = NSPoint(x: last.frame.maxX + 1, y: last.frame.midY)
        return stack.convert(local, to: nil)
    }

    /// 标签重排的插入指示线
    private var insertionIndicator: FFTabInsertionIndicator?

    var insertionIndicatorForTesting: FFTabInsertionIndicator? { insertionIndicator }

    /// 在指定插入位置显示一条竖线指示。
    ///
    /// 2026-10-20 第七轮：改为 **frame-based**。旧实现每事件改 `centerX` 约束，
    /// 会让整个窗口布局失效，级联到 FileListView 的列重算——拖动卡顿的主因。
    func showInsertionIndicator(atIndex index: Int) {
        guard let x = insertionIndicatorX(forIndex: index) else { return }
        if insertionIndicator == nil {
            let view = FFTabInsertionIndicator()
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
            insertionIndicator = view
        }
        guard let view = insertionIndicator else { return }
        view.frame = NSRect(x: x - 1, y: 3, width: 2, height: bounds.height - 6)
        view.isHidden = false
        view.needsDisplay = true
    }

    /// 移除插入指示线
    func hideInsertionIndicator() {
        insertionIndicator?.removeFromSuperview()
        insertionIndicator = nil
    }

    /// 插入指示线的 x（相对本视图左缘）
    ///
    /// 标签的 frame 在 `stack` 坐标系里，而指示线挂在标签条上；
    /// 必须换算，否则会画到标签条最左端（被 stack 的 34pt 前导偏移吃掉）。
    private func insertionIndicatorX(forIndex index: Int) -> CGFloat? {
        guard !items.isEmpty else { return 8 }
        let x: CGFloat
        if index <= 0 {
            x = items[0].frame.minX
        } else if index >= items.count {
            x = items.last!.frame.maxX
        } else {
            x = items[index].frame.minX
        }
        return stack.convert(NSPoint(x: x, y: 0), to: self).x
    }

    /// 把窗口坐标点换算成插入索引；返回 nil 表示该点不在本标签条内。
    /// 标签条本身不再注册为拖拽目标——统一由 `PaneTabDropReceiver` 判定，
    /// 避免「叠在最上层的接收器抢走本该落到标签条上的 drop」。
    func insertionIndex(atWindowPoint point: NSPoint) -> Int? {
        guard !isHidden, window != nil else { return nil }
        let local = convert(point, from: nil)
        let itemMidXs = items.map { item in
            stack.convert(NSPoint(x: item.frame.midX, y: 0), to: self).x
        }
        guard let index = FFTabReorder.insertionIndex(
            localPoint: local,
            stripBounds: bounds,
            buffer: FFPaneDrag.stripBuffer,
            itemMidXs: itemMidXs
        ) else {
            return nil
        }
        return index
    }
}

// MARK: - 全局顶栏（2026-10-21 C2）

/// 窗口级顶栏：工具 → 侧栏 → 左标签组 → 右标签组 → 分隔线 → 主题 → 单双栏。
///
/// 标签组按面板实际宽度手动布局（跨 NSSplitView 的 Auto Layout 不可靠），
/// 其余控件同样手动布局，保证所有元素落在 22pt 共用中线上。
final class FFGlobalTopBar: NSView, FFRegionAware {
    var ffRegion: FFRegion { .title }

    let sidebarButton = FFHoverIconButton()
    let themeButton = FFHoverIconButton()
    let paneModeButton = FFHoverIconButton()
    let leftTabStrip: PaneTabStripView
    let rightTabStrip: PaneTabStripView

    var onSidebarToggle: (() -> Void)?
    var onThemeToggle: (() -> Void)?
    var onPaneModeToggle: (() -> Void)?

    /// 单测用：不改变窗口状态，只驱动全屏边距几何。
    var fullScreenOverride: Bool? {
        didSet { needsLayout = true }
    }

    private let controlsDivider = NSView()
    private var leftPaneFrame: NSRect?
    private var rightPaneFrame: NSRect?
    private var isSinglePane = false
    private var activePane: PaneSide = .left

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        leftTabStrip = PaneTabStripView(frame: .zero)
        rightTabStrip = PaneTabStripView(frame: .zero)
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("FFGlobalTopBar 不支持 IB 初始化")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        for strip in [leftTabStrip, rightTabStrip] {
            strip.translatesAutoresizingMaskIntoConstraints = true
            strip.autoresizingMask = []
            strip.wantsLayer = true
            strip.layer?.masksToBounds = true
            addSubview(strip)
        }

        controlsDivider.wantsLayer = true
        controlsDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(controlsDivider)

        configure(sidebarButton, icon: .panelLeftClose, tooltip: "隐藏侧边栏 (⌥⌘S)",
                  action: #selector(sidebarTapped))
        configure(themeButton, icon: SidebarView.themeIcon(for: ThemeManager.shared.currentMode),
                  tooltip: "切换主题", action: #selector(themeTapped))
        configure(paneModeButton, icon: .columns2, tooltip: "切换到单窗口",
                  action: #selector(paneModeTapped))
    }

    private func configure(_ button: FFHoverIconButton,
                           icon: FFIconName,
                           tooltip: String,
                           action: Selector) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = FFIcon.template(icon, size: FFTopBarMetrics.iconSize)
        button.contentTintColor = NSColor.secondaryLabelColor
        button.hoverCornerRadius = 6
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = true
        addSubview(button)
    }

    /// 由控制器在每次布局/切换后写入面板矩形（已换算到顶栏坐标系）。
    func update(paneFrames: (left: NSRect?, right: NSRect?),
                isSinglePane: Bool,
                activePane: PaneSide,
                sidebarVisible: Bool) {
        leftPaneFrame = paneFrames.left
        rightPaneFrame = paneFrames.right
        self.isSinglePane = isSinglePane
        self.activePane = activePane
        setSidebarVisible(sidebarVisible)
        needsLayout = true
    }

    func setSidebarVisible(_ visible: Bool) {
        sidebarButton.image = FFIcon.template(visible ? .panelLeftClose : .panelLeftOpen,
                                              size: FFTopBarMetrics.iconSize)
        sidebarButton.toolTip = visible ? "隐藏侧边栏 (⌥⌘S)" : "显示侧边栏 (⌥⌘S)"
    }

    func setSinglePaneMode(_ single: Bool) {
        paneModeButton.image = FFIcon.template(single ? .square : .columns2,
                                               size: FFTopBarMetrics.iconSize)
        paneModeButton.toolTip = single ? "切换到双窗口" : "切换到单窗口"
    }

    func setThemeIcon(for mode: AppearanceMode) {
        themeButton.image = FFIcon.template(SidebarView.themeIcon(for: mode),
                                            size: FFTopBarMetrics.iconSize)
    }

    func refreshAppearance() {
        controlsDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        for button in [sidebarButton, themeButton, paneModeButton] {
            button.contentTintColor = .secondaryLabelColor
            button.needsDisplay = true
        }
        leftTabStrip.refreshAppearance()
        rightTabStrip.refreshAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.height > 1 else { return }

        let hit = FFInteractionPolicy.topBarHitSize
        let centerY = bounds.height - FFTopBarMetrics.centerline
        let leftInset = contentStartX()
        sidebarButton.frame = NSRect(x: leftInset,
                                     y: centerY - hit / 2, width: hit, height: hit)

        paneModeButton.frame = NSRect(x: bounds.width - FFTopBarMetrics.horizontalMargin - hit,
                                      y: centerY - hit / 2, width: hit, height: hit)
        themeButton.frame = NSRect(x: paneModeButton.frame.minX - 4 - hit,
                                   y: centerY - hit / 2, width: hit, height: hit)
        controlsDivider.frame = NSRect(x: themeButton.frame.minX - 10,
                                       y: centerY - 10, width: 1, height: 20)

        let contentStart = sidebarButton.frame.maxX + 12
        let rightLimit = controlsDivider.frame.minX - 10

        let showLeft = leftPaneFrame != nil && (!isSinglePane || activePane == .left)
        let showRight = rightPaneFrame != nil && (!isSinglePane || activePane == .right)
        leftTabStrip.isHidden = !showLeft
        rightTabStrip.isHidden = !showRight

        if showLeft, let pane = leftPaneFrame {
            leftTabStrip.frame = groupFrame(for: pane, contentStart: contentStart, rightLimit: rightLimit)
        }
        if showRight, let pane = rightPaneFrame {
            rightTabStrip.frame = groupFrame(for: pane, contentStart: contentStart, rightLimit: rightLimit)
        }
    }

    private func groupFrame(for pane: NSRect,
                            contentStart: CGFloat,
                            rightLimit: CGFloat) -> NSRect {
        let normalized = NSRect(x: pane.minX, y: 0,
                                width: pane.width, height: bounds.height)
        return FFTopBarLayout.tabGroupFrame(pane: normalized,
                                            contentStart: contentStart,
                                            rightLimit: rightLimit)
    }

    /// 全屏 16pt；窗口模式紧跟系统红绿灯后的缩放键。
    private func contentStartX() -> CGFloat {
        if fullScreenOverride ?? (window?.styleMask.contains(.fullScreen) ?? false) {
            return FFTopBarMetrics.horizontalMargin
        }
        if let zoom = window?.standardWindowButton(.zoomButton),
           let superview = zoom.superview {
            let rect = superview.convert(zoom.frame, to: nil)
            let inSelf = convert(rect, from: nil)
            if inSelf.maxX.isFinite, inSelf.maxX > 20 {
                return inSelf.maxX + 10
            }
        }
        return 84
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    @objc private func sidebarTapped() { onSidebarToggle?() }
    @objc private func themeTapped() { onThemeToggle?() }
    @objc private func paneModeTapped() { onPaneModeToggle?() }
}
