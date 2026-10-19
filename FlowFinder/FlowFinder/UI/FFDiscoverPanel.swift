import Cocoa

// MARK: - 条目模型

/// 「发现功能」弹层里的一个工具条目（2026-10-19 #9）。
///
/// 设计取舍：工具不是窗口级功能，而是「针对当前面板/选中项」的动作，
/// 所以不占工具栏常驻位置，收进程序名称旁的药丸里，按需展开。
enum FFDiscoverItem: Int, CaseIterable {
    case dedup = 0
    case batchRename = 1
    case aiTag = 2
    case aiOrganize = 3
    case settings = 4
    case about = 5

    var title: String {
        switch self {
        case .dedup:       return "查重扫描"
        case .batchRename: return "批量重命名"
        case .aiTag:       return "AI 自动打标"
        case .aiOrganize:  return "AI 智能整理"
        case .settings:    return "设置"
        case .about:       return "关于 FlowFinder"
        }
    }

    /// 搜索时参与匹配的关键词（中文标题 + 拼音/英文别名，避免只能打中文才搜得到）
    var keywords: [String] {
        switch self {
        case .dedup:       return ["查重", "重复", "duplicate", "dedup"]
        case .batchRename: return ["批量", "重命名", "rename", "batch"]
        case .aiTag:       return ["ai", "打标", "标签", "tag"]
        case .aiOrganize:  return ["ai", "整理", "分类", "organize"]
        case .settings:    return ["设置", "偏好", "settings", "preferences"]
        case .about:       return ["关于", "版本", "about", "version"]
        }
    }

    var icon: FFIconName {
        switch self {
        case .dedup:       return .scanSearch
        case .batchRename: return .replace
        case .aiTag:       return .wandSparkles
        case .aiOrganize:  return .folderTree
        case .settings:    return .settings
        case .about:       return .info
        }
    }

    /// 还没做完的功能照常列出、灰显并挂「即将推出」——用户能看到后续方向，
    /// 又不会点到一个什么都不发生的按钮。
    var isEnabled: Bool {
        switch self {
        case .aiTag, .aiOrganize: return false
        default: return true
        }
    }

    /// 分组：工具与「设置/关于」之间画一条分隔线
    var isUtility: Bool {
        self == .settings || self == .about
    }
}

// MARK: - 行视图

/// 弹层里的一行：图标 + 标题 +（可选）「即将推出」小标签。
/// 手写 hover 高亮（NSButton 在这个尺寸下拿不到一致的圆角与内边距）。
final class FFDiscoverRowView: NSView {

    var item: FFDiscoverItem = .dedup
    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "即将推出")
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.font = FFDesign.Text.base
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        badgeLabel.font = FFDesign.Text.xs
        badgeLabel.textColor = .tertiaryLabelColor
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isHidden = true
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: FFDiscoverItem) {
        self.item = item
        let enabled = item.isEnabled
        let tint: NSColor = enabled ? .labelColor : .tertiaryLabelColor
        iconView.image = FFIcon.template(item.icon, size: 16)
        iconView.contentTintColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
        titleLabel.stringValue = item.title
        titleLabel.textColor = tint
        badgeLabel.isHidden = enabled
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard item.isEnabled else { return }
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard item.isEnabled else { return }
        isHovered = true
    }

    override func mouseUp(with event: NSEvent) {
        guard item.isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovered, item.isEnabled else { return }
        // 高亮铺满行宽（比行内容左右各缩 4pt，视觉上像一段连续的选区）
        let rect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        FFAccent.current.withAlphaComponent(0.14).setFill()
        path.fill()
    }
}

// MARK: - 弹层内容

/// 「发现功能」弹层：搜索框 + 工具列表 + 设置/关于。
/// 由程序名称旁的药丸按钮 popover 呈现，点击条目后自动关闭。
final class FFDiscoverPanelController: NSViewController {

    /// 条目被选中（弹层会先关闭，再回调）
    var onSelect: ((FFDiscoverItem) -> Void)?
    /// 请求关闭弹层（由 popover 持有方实现）
    var onRequestClose: (() -> Void)?

    private let searchField = NSSearchField()
    private var rows: [FFDiscoverRowView] = []
    private var separator: NSBox!
    private let contentStack = NSStackView()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 280))
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        searchField.placeholderString = "搜索功能"
        searchField.font = FFDesign.Text.sm
        searchField.controlSize = .small
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(filterChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        view.addSubview(searchField)

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 0
        contentStack.detachesHiddenViews = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        for item in FFDiscoverItem.allCases where !item.isUtility {
            contentStack.addArrangedSubview(makeRow(item))
        }
        // 工具与「设置/关于」之间的分隔线
        separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        let separatorHost = NSView()
        separatorHost.translatesAutoresizingMaskIntoConstraints = false
        separatorHost.addSubview(separator)
        NSLayoutConstraint.activate([
            separatorHost.heightAnchor.constraint(equalToConstant: 11),
            separator.leadingAnchor.constraint(equalTo: separatorHost.leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: separatorHost.trailingAnchor, constant: -8),
            separator.centerYAnchor.constraint(equalTo: separatorHost.centerYAnchor),
        ])
        contentStack.addArrangedSubview(separatorHost)
        utilitiesSeparatorHost = separatorHost

        for item in FFDiscoverItem.allCases where item.isUtility {
            contentStack.addArrangedSubview(makeRow(item))
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 26),

            contentStack.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    private var utilitiesSeparatorHost: NSView?

    private func makeRow(_ item: FFDiscoverItem) -> FFDiscoverRowView {
        let row = FFDiscoverRowView()
        row.configure(with: item)
        row.onClick = { [weak self] in
            guard let self else { return }
            self.onRequestClose?()
            self.onSelect?(item)
        }
        rows.append(row)
        return row
    }

    @objc private func filterChanged() {
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var visibleTools = 0
        for row in rows {
            let match = q.isEmpty
                || row.item.title.lowercased().contains(q)
                || row.item.keywords.contains(where: { $0.contains(q) })
            row.isHidden = !match
            if match && !row.item.isUtility { visibleTools += 1 }
        }
        // 只剩「设置/关于」时不需要那条分隔线
        utilitiesSeparatorHost?.isHidden = visibleTools == 0
    }

    /// 首次显示时把焦点给搜索框，直接打字就能筛
    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }
}

extension FFDiscoverPanelController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }
}

// MARK: - 药丸按钮

/// 程序名称旁的「发现功能」药丸（2026-10-19 #9）。
///
/// 用 NSView 自绘而不是 NSButton：无边框 NSButton 拿不到内边距，
/// 图标与文字会贴到胶囊边上；这层只有一条标签和一个图标，自绘更可控。
final class FFPillButton: NSView {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(title: String, icon: FFIconName) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        iconView.image = FFIcon.template(icon, size: 12)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.stringValue = title
        label.font = FFDesign.Text.sm
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let alpha: CGFloat = isPressed ? 0.16 : (isHovered ? 0.12 : 0.07)
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        path.fill()
    }
}
