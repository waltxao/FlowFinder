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

    func clear() {
        session = nil
        sourceSide = nil
        sourceIndex = nil
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
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),

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
        if isActive {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            titleLabel.textColor = NSColor.labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = NSColor.secondaryLabelColor
            titleLabel.font = NSFont.systemFont(ofSize: 12)
        }
        closeButton.isHidden = !isActive
    }

    @objc private func handleClose() {
        onClose?()
    }

    /// 标题 label 会吞掉 mouseDown（NSTextField 自身处理点击），导致点标签文字无法切换。
    /// 除关闭按钮外，命中一律归标签本身。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit = hit, hit === closeButton || hit.isDescendant(of: closeButton) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        onSelect?()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil

        PaneTabDragContext.shared.session = tabSession
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
final class PaneTabStripView: NSView {

    weak var delegate: PaneTabStripDelegate?
    var side: PaneSide = .left

    private let stack = NSStackView()
    private let addButton = NSButton()
    private var items: [PaneTabItemView] = []
    private var sessions: [PaneTabSession] = []
    private var activeIndex: Int = 0

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
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签页")
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

        registerForDraggedTypes([PaneTabDragContext.pasteboardType])
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
        }
    }

    private func rebuildItems() {
        items.forEach { $0.removeFromSuperview() }
        items.removeAll()
        for (i, session) in sessions.enumerated() {
            let item = PaneTabItemView(session: session, index: i)
            item.side = side
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
    }

    // MARK: - 拖放（排序 + 跨面板）

    private func dropIndex(for sender: NSDraggingInfo) -> Int {
        let point = stack.convert(sender.draggingLocation, from: nil)
        for (i, item) in items.enumerated() where point.x < item.frame.midX {
            return i
        }
        return items.count
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.availableType(from: [PaneTabDragContext.pasteboardType]) != nil ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let session = PaneTabDragContext.shared.session else { return false }
        let index = dropIndex(for: sender)
        if let sourceSide = PaneTabDragContext.shared.sourceSide, sourceSide == side,
           let from = PaneTabDragContext.shared.sourceIndex {
            delegate?.tabStrip(self, didMoveTabFrom: from, to: index)
        } else {
            delegate?.tabStrip(self, didReceive: session, at: index)
        }
        PaneTabDragContext.shared.clear()
        return true
    }
}
