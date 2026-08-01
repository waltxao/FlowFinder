import Cocoa

// MARK: - TagSelectorDialog

/// 标签选择对话框：搜索框 + 已选药丸区 + 推荐药丸区
/// 继承 FFModalSheet，确定后调用 TagBridge.shared.setTags
class TagSelectorDialog: FFModalSheet {

    /// 当前已选标签
    private var selectedTags: [Tag] = []
    /// 所有可用标签
    private var allTags: [Tag] = []
    /// 目标文件路径
    private let filePath: String

    // UI 引用
    private var searchField: NSSearchField!
    private var selectedContainer: NSStackView!
    private var suggestedContainer: NSStackView!

    /// 初始化
    /// - Parameters:
    ///   - filePath: 目标文件路径
    ///   - currentTags: 当前文件已有的标签
    ///   - allTags: 所有可用标签
    init(filePath: String, currentTags: [Tag] = [], allTags: [Tag] = []) {
        self.filePath = filePath
        self.selectedTags = currentTags
        // 合并侧边栏标签与默认标签，按名称去重（侧边栏标签优先）
        var merged = allTags
        let existingNames = Set(merged.map { $0.name })
        for def in TagSelectorDialog.defaultAvailableTags() {
            if !existingNames.contains(def.name) {
                merged.append(def)
            }
        }
        self.allTags = merged.isEmpty ? TagSelectorDialog.defaultAvailableTags() : merged

        let bodyView = NSView()
        // 使用闭包持有盒延迟注入 self 依赖（Swift 6 严格模式禁止 super.init 前捕获 self）
        let box = FFClosureBox()
        super.init(title: "选择标签",
                   bodyView: bodyView,
                   primaryButton: ("确定", .default),
                   secondaryButton: "取消",
                   primaryAction: { box.closure?() })

        box.closure = { [weak self] in
            guard let self = self else { return }
            _ = TagBridge.shared.setTags(self.selectedTags, path: self.filePath)
            // 同步到侧边栏标签列表：通知 TagsSidebarDataSource 添加新标签
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Body 构建

    private func setupBody(bodyView: NSView) {
        // 搜索框
        searchField = NSSearchField()
        searchField.placeholderString = "搜索标签..."
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // 已选区标题
        let selectedTitle = NSTextField(labelWithString: "已选")
        selectedTitle.font = .systemFont(ofSize: 11, weight: .medium)
        selectedTitle.textColor = .secondaryLabelColor
        selectedTitle.translatesAutoresizingMaskIntoConstraints = false

        // 已选药丸容器（横向 wrap）
        selectedContainer = NSStackView()
        selectedContainer.orientation = .horizontal
        selectedContainer.alignment = .centerY
        selectedContainer.spacing = 6
        selectedContainer.detachesHiddenViews = false
        selectedContainer.translatesAutoresizingMaskIntoConstraints = false

        // 推荐区标题
        let suggestedTitle = NSTextField(labelWithString: "推荐")
        suggestedTitle.font = .systemFont(ofSize: 11, weight: .medium)
        suggestedTitle.textColor = .secondaryLabelColor
        suggestedTitle.translatesAutoresizingMaskIntoConstraints = false

        // 推荐药丸容器
        suggestedContainer = NSStackView()
        suggestedContainer.orientation = .horizontal
        suggestedContainer.alignment = .centerY
        suggestedContainer.spacing = 6
        suggestedContainer.detachesHiddenViews = false
        suggestedContainer.translatesAutoresizingMaskIntoConstraints = false

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
        selectedContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tag in selectedTags {
            selectedContainer.addArrangedSubview(makeSelectedPill(tag: tag))
        }
        if selectedTags.isEmpty {
            let empty = NSTextField(labelWithString: "未选择标签")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            selectedContainer.addArrangedSubview(empty)
        }

        // 推荐药丸（过滤搜索词 + 排除已选）
        suggestedContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
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
            empty.textColor = .tertiaryLabelColor
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
        removeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "移除")
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
        let pill = NSButton()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
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
