import Cocoa

// MARK: - F4: 可换行药丸容器（NSStackView 不 wrap，标签多时溢出被裁剪）

/// 简单的流式换行布局容器：子视图按行排列，超宽自动换行，高度自适应。
/// 替代横向 NSStackView 解决"标签多时溢出"问题。
final class FFWrapContainerView: NSView {
    private(set) var arrangedSubviews: [NSView] = []
    var spacing: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureWrapBehavior()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureWrapBehavior()
    }

    private func configureWrapBehavior() {
        translatesAutoresizingMaskIntoConstraints = false
        // 高度必须优先贴合内容（R4-31）。FFModalSheet 用 defaultHigh 把 footer 钉在
        // 窗口底边，约束求解拿不定主意时会把本容器拉高，药丸周围就出现大片空白。
        // 不能设成 required：调用方还会加 `height >= 26` 的最小高度约束，required 会和它冲突。
        setContentHuggingPriority(NSLayoutConstraint.Priority.defaultHigh + 1, for: .vertical)
    }

    override func layout() {
        super.layout()
        layoutItems()
    }

    /// 行从容器顶边往下摆（R4-31）。
    /// NSView 默认原点在左下，`calculateLayout` 算出的 y=0 会被解释成底边，
    /// 容器被拉高时药丸全部沉底、上方留下一整块空白。
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let size = calculateLayout().size
        return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
    }

    /// 把 subview 加入容器并触发布局
    func addArrangedSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        arrangedSubviews.append(view)
        addSubview(view)
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    /// 移除所有子视图
    func removeAllArrangedSubviews() {
        for v in arrangedSubviews {
            v.removeFromSuperview()
        }
        arrangedSubviews.removeAll()
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    private struct WrapLayout {
        let size: NSSize
        let frames: [NSRect]
    }

    private func calculateLayout() -> WrapLayout {
        let width = bounds.width
        var frames: [NSRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in arrangedSubviews {
            if view.isHidden { continue }
            let itemSize = view.fittingSize
            if x > 0 && x + itemSize.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(NSRect(x: x, y: y, width: itemSize.width, height: itemSize.height))
            x += itemSize.width + spacing
            rowHeight = max(rowHeight, itemSize.height)
        }
        let totalHeight = y + rowHeight
        return WrapLayout(size: NSSize(width: width, height: totalHeight), frames: frames)
    }

    private func layoutItems() {
        let layout = calculateLayout()
        for (i, view) in arrangedSubviews.enumerated() {
            if view.isHidden { continue }
            view.frame = layout.frames[i]
        }
    }
}

// MARK: - TagSelectorDialog

/// 标签选择对话框：搜索框 + 已选药丸区 + 推荐药丸区
/// 继承 FFModalSheet，确定后调用 TagBridge.shared.setTags
class TagSelectorDialog: FFModalSheet {

    /// 当前已选标签
    private var selectedTags: [Tag] = []
    /// 所有可用标签
    private var allTags: [Tag] = []
    /// 目标文件路径（多选时批量应用差异，不覆盖各自的其它标签）
    private let paths: [String]
    /// 打开时的公共标签（多选取交集），用于计算增删差异
    private let initialTags: [Tag]

    // UI 引用
    private var searchField: NSSearchField!
    private var selectedContainer: FFWrapContainerView!
    private var suggestedContainer: FFWrapContainerView!

    /// 推荐区当前的药丸（供回归测试检查视觉状态）
    var suggestedChipsForTesting: [NSView] { suggestedContainer?.arrangedSubviews ?? [] }

    /// 初始化
    /// - Parameters:
    ///   - paths: 目标文件路径（1 个 = 精确覆盖；多个 = 只应用增删差异）
    ///   - currentTags: 当前公共标签
    ///   - allTags: 所有可用标签
    init(paths: [String], currentTags: [Tag] = [], allTags: [Tag] = []) {
        self.paths = paths
        self.initialTags = currentTags
        self.selectedTags = currentTags
        let catalogTags = allTags.isEmpty ? TagCatalog.shared.tags : allTags
        self.allTags = catalogTags.isEmpty ? TagSelectorDialog.defaultAvailableTags() : catalogTags

        let bodyView = NSView()
        // 使用闭包持有盒延迟注入 self 依赖（Swift 6 严格模式禁止 super.init 前捕获 self）
        let box = FFClosureBox()
        super.init(title: FFNaming.editTagsBase,
                   bodyView: bodyView,
                   primaryButton: ("确定", .default),
                   secondaryButton: "取消",
                   primaryAction: { box.closure?() })

        box.closure = { [weak self] in
            guard let self = self else { return }
            if self.paths.count <= 1 {
                if let path = self.paths.first {
                    _ = TagBridge.shared.setTags(self.selectedTags, path: path)
                }
            } else {
                let initialNames = Set(self.initialTags.map { $0.name })
                let finalNames = Set(self.selectedTags.map { $0.name })
                for path in self.paths {
                    var tags = TagBridge.shared.getTags(path: path)
                    tags.removeAll { initialNames.contains($0.name) && !finalNames.contains($0.name) }
                    for tag in self.selectedTags where !tags.contains(where: { $0.name == tag.name }) {
                        tags.append(tag)
                    }
                    _ = TagBridge.shared.setTags(tags, path: path)
                }
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("FileTagsDidChange"),
                object: nil,
                userInfo: ["tags": self.selectedTags]
            )
        }

        setupBody(bodyView: bodyView)
        refreshPills()
    }

    /// 默认可用标签（从 DesignTokens.tagColors 生成）
    private static func defaultAvailableTags() -> [Tag] {
        // 颜色名→hex 映射（与 DesignTokens.tagColors 对应）
        let colorHexMap: [String: String] = [
            "red": "#FF453A", "orange": "#FF9F0A", "yellow": "#FFD60A",
            "green": "#30D158", "blue": "#0A84FF", "purple": "#BF5AF2", "gray": "#8E8E93",
        ]
        return colorHexMap.map { (name, hex) in
            Tag(id: name, name: name, color: hex)
        }
    }

    convenience init(filePath: String, currentTags: [Tag] = [], allTags: [Tag] = []) {
        self.init(paths: [filePath], currentTags: currentTags, allTags: allTags)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Body 构建

    private func setupBody(bodyView: NSView) {
        // 搜索框
        searchField = NSSearchField()
        searchField.placeholderString = "搜索标签…"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // 已选区标题
        let selectedTitle = NSTextField(labelWithString: "已选")
        selectedTitle.font = .systemFont(ofSize: 11, weight: .medium)
        selectedTitle.textColor = .secondaryLabelColor
        selectedTitle.translatesAutoresizingMaskIntoConstraints = false

        // 已选药丸容器（F4: 流式换行，标签多时不溢出）
        selectedContainer = FFWrapContainerView()
        selectedContainer.spacing = 6

        // 推荐区标题
        let suggestedTitle = NSTextField(labelWithString: "推荐")
        suggestedTitle.font = .systemFont(ofSize: 11, weight: .medium)
        suggestedTitle.textColor = .secondaryLabelColor
        suggestedTitle.translatesAutoresizingMaskIntoConstraints = false

        // 推荐药丸容器（F4: 流式换行）
        suggestedContainer = FFWrapContainerView()
        suggestedContainer.spacing = 6

        bodyView.addSubview(searchField)
        bodyView.addSubview(selectedTitle)
        bodyView.addSubview(selectedContainer)
        bodyView.addSubview(suggestedTitle)
        bodyView.addSubview(suggestedContainer)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: bodyView.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 24),

            selectedTitle.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            selectedTitle.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),

            selectedContainer.topAnchor.constraint(equalTo: selectedTitle.bottomAnchor, constant: 6),
            selectedContainer.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            selectedContainer.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            selectedContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),

            suggestedTitle.topAnchor.constraint(equalTo: selectedContainer.bottomAnchor, constant: 16),
            suggestedTitle.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),

            suggestedContainer.topAnchor.constraint(equalTo: suggestedTitle.bottomAnchor, constant: 6),
            suggestedContainer.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            suggestedContainer.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            suggestedContainer.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
            suggestedContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
        ])
    }

    // MARK: - 药丸渲染

    private func refreshPills() {
        // 已选药丸
        selectedContainer.removeAllArrangedSubviews()
        for tag in selectedTags {
            selectedContainer.addArrangedSubview(makeSelectedPill(tag: tag))
        }
        if selectedTags.isEmpty {
            let empty = NSTextField(labelWithString: "未选择标签")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = FFVisualTokens.hint
            empty.translatesAutoresizingMaskIntoConstraints = false
            selectedContainer.addArrangedSubview(empty)
        }

        // 推荐药丸（过滤搜索词 + 排除已选）
        suggestedContainer.removeAllArrangedSubviews()
        let selectedNames = Set(selectedTags.map { $0.name })
        let query = searchField?.stringValue.lowercased() ?? ""
        let suggested = allTags.filter { tag in
            !selectedNames.contains(tag.name) &&
            (query.isEmpty || tag.name.lowercased().contains(query))
        }
        for tag in suggested {
            suggestedContainer.addArrangedSubview(makeSuggestedPill(tag: tag))
        }
        if suggested.isEmpty {
            let empty = NSTextField(labelWithString: "无可用标签")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = FFVisualTokens.hint
            empty.translatesAutoresizingMaskIntoConstraints = false
            suggestedContainer.addArrangedSubview(empty)
        }
    }

    /// 已选药丸：圆点 + 名 + X 移除按钮
    private func makeSelectedPill(tag: Tag) -> NSView {
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
        pill.squircleRadius = 11
        pill.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: tag.name)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let removeBtn = NSButton()
        removeBtn.image = FFIcon.template(.circleX, size: 13)
        removeBtn.contentTintColor = .secondaryLabelColor
        removeBtn.isBordered = false
        removeBtn.imagePosition = .imageOnly
        removeBtn.controlSize = .small
        removeBtn.target = self
        removeBtn.action = #selector(removePill(_:))
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        removeBtn.toolTip = tag.name

        pill.addSubview(dot)
        pill.addSubview(label)
        pill.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            removeBtn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            removeBtn.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            removeBtn.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            removeBtn.widthAnchor.constraint(equalToConstant: 14),
            removeBtn.heightAnchor.constraint(equalToConstant: 14),
            pill.heightAnchor.constraint(equalToConstant: 22),
        ])
        return pill
    }

    /// 推荐药丸：圆点 + 名（点击添加）
    private func makeSuggestedPill(tag: Tag) -> NSView {
        let base = NSColor(hex: tag.color) ?? .systemBlue
        let pill = NSButton()
        pill.wantsLayer = true
        // 描边 + 标签色浅淡染色（R4-31）：
        // 此前只有近透明的 controlBackgroundColor 底色，推荐项读起来像图例而不是可点选项。
        pill.layer?.backgroundColor = base.withAlphaComponent(0.10).cgColor
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = base.withAlphaComponent(0.55).cgColor
        pill.applySquircleCornerRadius(11)
        pill.isBordered = false
        pill.font = .systemFont(ofSize: 11)
        pill.title = "  • \(tag.name)"
        pill.target = self
        pill.action = #selector(addPill(_:))
        pill.toolTip = tag.name
        pill.contentTintColor = .labelColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.heightAnchor.constraint(equalToConstant: 22).isActive = true
        // 添加左侧彩色圆点（通过 attribute title）
        let attrString = NSMutableAttributedString(string: "● \(tag.name)")
        attrString.addAttribute(.foregroundColor, value: NSColor(hex: tag.color) ?? .systemBlue, range: NSRange(location: 0, length: 1))
        attrString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 1, length: attrString.length - 1))
        attrString.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: NSRange(location: 0, length: attrString.length))
        pill.attributedTitle = attrString
        return pill
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        refreshPills()
    }

    @objc private func removePill(_ sender: NSButton) {
        guard let name = sender.toolTip else { return }
        selectedTags.removeAll { $0.name == name }
        refreshPills()
    }

    @objc private func addPill(_ sender: NSButton) {
        guard let name = sender.toolTip else { return }
        if let tag = allTags.first(where: { $0.name == name }) {
            selectedTags.append(tag)
            refreshPills()
        }
    }
}
