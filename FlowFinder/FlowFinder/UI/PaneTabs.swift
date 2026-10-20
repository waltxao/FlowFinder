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
        let target = min(max(index, 0), tabs.count)
        tabs.insert(session, at: target)
        if activate {
            activeIndex = target
        } else if target <= activeIndex {
            activeIndex += 1
        }
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

// MARK: - 单个标签

final class PaneTabItemView: NSView, FFRegionAware {

    /// 标签标题（诊断用）
    var titleText: String { titleLabel.stringValue }

    /// 标签本体：唯一能拖面板的把手（条内重排 / 出缓冲搬整块面板）
    var ffRegion: FFRegion { .tab }

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var mouseDownPoint: NSPoint?
    /// 高度约束：活动 28（焊死）/ 非活动 22（上浮）
    private var heightConstraint: NSLayoutConstraint!

    var tabSession: PaneTabSession
    var index: Int
    /// 所在标签条的面板侧（拖拽时写入上下文，供跨面板移交判定）
    var side: PaneSide = .left
    /// 所在标签条（2026-10-20 #1：拖动统一由窗口级控制器处理，需要反查标签条）
    weak var strip: PaneTabStripView?
    /// B5：源面板只剩 1 个标签时禁止拖出（拖走了面板就没有会话可显示）。
    /// 由标签条在每次 refresh 时按当前数量写入。
    var canDragOut: Bool = true
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
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = FFIcon.template(.x, size: 9)
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        // 2026-10-20 #4：活动标签 28（底边焊在面板顶边）、非活动 22（上浮 6pt）。
        // 高度在这里建、在 updateAppearance 里切换。
        heightConstraint = heightAnchor.constraint(
            equalToConstant: FFInteractionPolicy.inactiveTabHeight)

        NSLayoutConstraint.activate([
            heightConstraint,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    func update(session: PaneTabSession, index: Int, active: Bool) {
        self.tabSession = session
        self.index = index
        titleLabel.stringValue = session.title
        isActive = active
    }

    private func updateAppearance() {
        // 2026-10-20 #4：活动标签与面板同色，**形状与填充由标签条背板统一绘制**
        // （背板在标签之下，画的是一条「面板 + 凸起 + 两处内凹」的合并轮廓）。
        // 这里必须保持透明，否则会盖住背板、在接缝处留一条色差。
        heightConstraint?.constant = isActive
            ? FFInteractionPolicy.activeTabHeight
            : FFInteractionPolicy.inactiveTabHeight
        layer?.cornerRadius = isActive ? 0 : 8

        // 颜色必须在当前外观下解析：CALayer.backgroundColor 是静态 CGColor，
        // 直接取色会定格在创建时的明暗模式上，夜间模式下就成了「白底 + 白字」。
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isActive
                ? NSColor.clear.cgColor
                : NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        }
        if isActive {
            titleLabel.textColor = NSColor.labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        } else {
            titleLabel.textColor = NSColor.secondaryLabelColor
            titleLabel.font = NSFont.systemFont(ofSize: 12)
        }
        closeButton.isHidden = !isActive
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
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
    private let addButton = NSButton()
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

        // 背板铺满整条，位于所有标签之下
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        stack.orientation = .horizontal
        // 2026-10-20 #4：改为顶部对齐——活动标签 28、非活动 22，
        // 顶部对齐后非活动自然比活动矮 6pt、底边离面板 6pt。
        stack.alignment = .top
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.imagePosition = .imageOnly
        addButton.image = FFIcon.template(.plus, size: 11)
        addButton.contentTintColor = NSColor.secondaryLabelColor
        addButton.toolTip = "新建标签页"
        addButton.target = self
        addButton.action = #selector(handleNewTab)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 首标签左缘：面板左缘（卡片留白 8）+ 20。
            // 面板圆角是 16，再近的话根部内凹（r2=8）会与圆角打架。
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: FFActivePaneBorderView.edgeOutset + FFInteractionPolicy.tabInsetFromPanel),
            // 顶部留出「标签上方间隙」（标题带 36 − 活动标签 28 = 8）
            stack.topAnchor.constraint(
                equalTo: topAnchor,
                constant: FFInteractionPolicy.tabTopGap),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            // 「+」紧跟最后一个标签（Chrome 式），而不是钉在面板最右侧
            addButton.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 6),
            addButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            addButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            addButton.widthAnchor.constraint(equalToConstant: 20),
            addButton.heightAnchor.constraint(equalToConstant: 20),
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

    /// 取第 index 个标签的视图（拖动浮层用）
    func itemView(at index: Int) -> PaneTabItemView? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// 当前所有标签项（自检用）
    func allTabItems() -> [PaneTabItemView] { items }

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
            item.canDragOut = sessions.count > 1
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
            item.canDragOut = sessions.count > 1
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

    /// 在指定插入位置显示一条竖线指示
    func showInsertionIndicator(atIndex index: Int) {
        guard let x = insertionIndicatorX(forIndex: index) else { return }
        if insertionIndicator == nil {
            let view = FFTabInsertionIndicator()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor, constant: 3),
                view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
                view.widthAnchor.constraint(equalToConstant: 2),
                view.centerXAnchor.constraint(equalTo: leadingAnchor, constant: x),
            ])
            insertionIndicator = view
        } else if let view = insertionIndicator {
            for c in view.constraints where c.firstAttribute == .centerX {
                c.constant = x
            }
        }
    }

    /// 移除插入指示线
    func hideInsertionIndicator() {
        insertionIndicator?.removeFromSuperview()
        insertionIndicator = nil
    }

    /// 插入指示线的 x（相对本视图左缘）
    private func insertionIndicatorX(forIndex index: Int) -> CGFloat? {
        guard !items.isEmpty else { return 8 }
        if index <= 0 { return items[0].frame.minX }
        if index >= items.count { return items.last!.frame.maxX }
        return items[index].frame.minX
    }

    /// 把窗口坐标点换算成插入索引；返回 nil 表示该点不在本标签条内。
    /// 标签条本身不再注册为拖拽目标——统一由 `PaneTabDropReceiver` 判定，
    /// 避免「叠在最上层的接收器抢走本该落到标签条上的 drop」。
    func insertionIndex(atWindowPoint point: NSPoint) -> Int? {
        guard !isHidden, window != nil else { return nil }
        let local = convert(point, from: nil)
        guard bounds.contains(local) else {
            FFDebug.log("[TAB] strip hit miss side=\(side) winPoint=\(point) local=\(local) bounds=\(bounds)")
            return nil
        }
        let stackPoint = stack.convert(point, from: nil)
        for (i, item) in items.enumerated() where stackPoint.x < item.frame.midX {
            FFDebug.log("[TAB] strip hit side=\(side) index=\(i) stackX=\(stackPoint.x)")
            return i
        }
        FFDebug.log("[TAB] strip hit side=\(side) index=\(items.count) (append) stackX=\(stackPoint.x)")
        return items.count
    }
}
