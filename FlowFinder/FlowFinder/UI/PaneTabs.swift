import Cocoa

// MARK: - 标签会话

/// 一个浏览标签的完整快照。
/// 标签 = 面板的一次独立浏览会话（路径 + 返回栈 + 排序 / 视图模式 / 分组 / 标签筛选）。
struct PaneTabSession {
    let id: UUID
    var state: PaneState

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

// MARK: - 跨面板拖动上下文

/// 标签拖动期间的临时上下文。
/// 会话对象本身不进 pasteboard（PaneState 含文件数组，序列化成本高），
/// pasteboard 只承担拖拽类型与命中，真实数据从这里取。
final class PaneTabDragContext {
    static let shared = PaneTabDragContext()
    static let pasteboardType = NSPasteboard.PasteboardType("com.flowfinder.panetab")

    var session: PaneTabSession?
    var sourceSide: PaneSide?
    var sourceIndex: Int?
    /// B5 #5b：true = 拖的是工具栏空白（整个面板合并），此时 session 无意义
    var isGroupMerge = false
    /// 2026-10-20 #1：true = 拖的是「操作面板」——语义上等于拖当前那个标签
    var isPaneDrag = false

    func clear() {
        session = nil
        sourceSide = nil
        sourceIndex = nil
        isGroupMerge = false
        isPaneDrag = false
    }
}

// MARK: - 单个标签

final class PaneTabItemView: NSView, NSDraggingSource {

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var mouseDownPoint: NSPoint?

    var tabSession: PaneTabSession
    var index: Int
    /// 所在标签条的面板侧（拖拽时写入上下文，供跨面板移交判定）
    var side: PaneSide = .left
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
        layer?.cornerRadius = 6
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

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        // 颜色必须在当前外观下解析：CALayer.backgroundColor 是静态 CGColor，
        // 直接取 NSColor.controlBackgroundColor.cgColor 会定格在创建时的明暗模式上，
        // 夜间模式下就成了「白底 + 白字」（2026-10-18 实测）。
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isActive
                ? NSColor.controlBackgroundColor.cgColor
                : NSColor.clear.cgColor
        }
        if isActive {
            titleLabel.textColor = NSColor.labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
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

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        FFDebug.log("[TAB] mouseDown index=\(index) side=\(side) local=\(mouseDownPoint ?? .zero) frame=\(frame)")
        onSelect?()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        // B5：面板最后一个标签不允许拖出（拖到别的面板会导致源面板无会话）
        guard canDragOut else {
            FFDebug.log("[TAB] mouseDragged blocked: canDragOut=false index=\(index)")
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        FFDebug.log("[TAB] drag start index=\(index) side=\(side)")

        PaneTabDragContext.shared.session = tabSession
        PaneTabDragContext.shared.isGroupMerge = false
        PaneTabDragContext.shared.sourceSide = side
        PaneTabDragContext.shared.sourceIndex = index

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tabSession.id.uuidString, forType: PaneTabDragContext.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    /// 拖拽结束（无论落点有效、被取消还是 Esc）都必须清掉上下文——
    /// PaneTabDropReceiver 以 `session != nil` 判定是否参与命中，
    /// 残留会让窗口级接收器永久吞掉点击。
    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        PaneTabDragContext.shared.clear()
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

/// 操作区顶部的浏览器式标签条（高 32pt）
final class PaneTabStripView: NSView, FFPaneDragSource {

    weak var delegate: PaneTabStripDelegate?
    var side: PaneSide = .left

    private let stack = NSStackView()
    private let addButton = NSButton()
    private var items: [PaneTabItemView] = []
    private var sessions: [PaneTabSession] = []
    private var activeIndex: Int = 0

    // MARK: - 面板拖拽（2026-10-20 #1）


    /// 被拖起的面板卡片（由 MainWindowController 注入）
    var paneCard: NSView?

    /// 标签条只在「标签数 ≥ 2」时出现，永远有第二个标签可搬，不会退化成拖窗口
    var dragsWindowInstead: Bool { false }

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

        stack.orientation = .horizontal
        stack.alignment = .bottom
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
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            // 「+」紧跟最后一个标签（Chrome 式），而不是钉在面板最右侧
            addButton.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 6),
            addButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            addButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            addButton.widthAnchor.constraint(equalToConstant: 20),
            addButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @objc private func handleNewTab() {
        delegate?.tabStripDidRequestNewTab(self)
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
    }

    private func rebuildItems() {
        items.forEach { $0.removeFromSuperview() }
        items.removeAll()
        for (i, session) in sessions.enumerated() {
            let item = PaneTabItemView(session: session, index: i)
            item.side = side
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
    }

    // MARK: - 拖放命中（由窗口级接收器调用）

    /// 最后一个标签之后一点的窗口坐标（自检用）
    func windowPointPastLastTab() -> NSPoint? {
        guard let last = items.last else { return nil }
        let local = NSPoint(x: last.frame.maxX + 1, y: last.frame.midY)
        return stack.convert(local, to: nil)
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

// MARK: - 面板合并拖放接收器（B5）

/// 承接「拖到面板内容区 / 标签条 / 窗口边缘」的标签落点。
/// 铺满内容层、置于最上层；仅在标签拖动会话期间参与命中
/// （平时 hitTest 返回 nil 完全穿透，不干扰文件拖放与点击）。
///
/// 标签条**不再**单独注册拖拽类型：落点判定统一在这里做，
/// 由挂载方按坐标决定「组内重排 / 跨组接收 / 拆分 / 整组合并」。
final class PaneTabDropReceiver: NSView {

    /// 参数为 window 坐标（draggingLocation 原样透传）
    var onReceive: ((NSPoint) -> Void)?
    /// B5 拆分投放区提示：由挂载方根据当前模式算出应高亮的区域（window 坐标）；
    /// 返回 nil 表示该落点不拆分（如拖在自己半区），不高亮。
    var dropZoneRectProvider: ((NSPoint) -> NSRect?)?
    private var highlightRect: NSRect?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = highlightRect else { return }
        let local = convert(rect, from: nil)
        let path = NSBezierPath(roundedRect: local.insetBy(dx: 10, dy: 10), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }

    private func refreshHighlight(at windowPoint: NSPoint) {
        let rect = dropZoneRectProvider?(windowPoint)
        if rect != highlightRect {
            highlightRect = rect
            needsDisplay = true
        }
    }

    private func clearHighlight() {
        if highlightRect != nil {
            highlightRect = nil
            needsDisplay = true
        }
    }

    /// 标签拖动进行中（单标签或整组合并均算）
    static var isTabDragActive: Bool {
        PaneTabDragContext.shared.session != nil
            || PaneTabDragContext.shared.isGroupMerge
            || PaneTabDragContext.shared.isPaneDrag
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 拖动标签/整组期间完全接管命中：保证 drop 一定落到本接收器，
        // 由 onReceive 按坐标分流（标签条内的精确插入也由它算）。
        Self.isTabDragActive ? self : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.availableType(from: [PaneTabDragContext.pasteboardType]) != nil ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = draggingEntered(sender)
        if op.isEmpty { clearHighlight() } else { refreshHighlight(at: sender.draggingLocation) }
        return op
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearHighlight()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        clearHighlight()
        guard Self.isTabDragActive,
              sender.draggingPasteboard.availableType(from: [PaneTabDragContext.pasteboardType]) != nil else {
            return false
        }
        onReceive?(sender.draggingLocation)
        return true
    }
}
