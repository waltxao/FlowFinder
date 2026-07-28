import Cocoa
import Combine

// MARK: - PaneToolbarDelegate

protocol PaneToolbarDelegate: AnyObject {
    func paneToolbarDidClickBack(_ toolbar: PaneToolbar)
    func paneToolbarDidClickForward(_ toolbar: PaneToolbar)
    func paneToolbarDidClickUp(_ toolbar: PaneToolbar)
    func paneToolbarDidClickRefresh(_ toolbar: PaneToolbar)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeSearchQuery query: String)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeSortField field: SortField, ascending: Bool)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeGroupBy groupBy: String)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeViewMode mode: ViewMode)
    func paneToolbar(_ toolbar: PaneToolbar, didClickPath path: String)
    // 任务 D15: 工具菜单触发回调
    func paneToolbarDidClickDedupScan(_ toolbar: PaneToolbar)
    func paneToolbarDidClickBatchRename(_ toolbar: PaneToolbar)
}

// MARK: - 任务 D15: PaneToolbarDelegate 默认实现
// 为新增方法提供默认空实现，保证现有实现类（如 MainWindowController）不破坏
extension PaneToolbarDelegate {
    func paneToolbarDidClickDedupScan(_ toolbar: PaneToolbar) {}
    func paneToolbarDidClickBatchRename(_ toolbar: PaneToolbar) {}
}

// MARK: - PaneToolbar

class PaneToolbar: NSView {
    weak var delegate: PaneToolbarDelegate?

    // Row 1: Navigation
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var upButton: NSButton!
    private var refreshButton: NSButton!
    private var row1: NSStackView!

    // Row 2: Search + Sort + Group + View
    /// 1.4 自定义搜索框（替代 NSSearchField）：图标 + 文本框，放入 FFGlassView 容器
    private var searchContainer: FFGlassView!
    private var searchTextField: NSTextField!
    private var sortPopup: NSPopUpButton!
    private var groupPopup: NSPopUpButton!
    private var listViewButton: NSButton!
    private var gridViewButton: NSButton!
    private var toolsButton: NSButton!  // 任务 D15: 工具菜单按钮

    // 任务 F3: BreadcrumbBar 嵌入 Row1（刷新按钮后），紧贴刷新按钮
    private var breadcrumbBar: BreadcrumbBar?

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
        layer?.masksToBounds = true

        // 1.9 工具栏玻璃背景：FFGlassView(.panel, .headerView, cornerRadius: 0)
        // 与窗口玻璃形成层次感（工具栏玻璃比窗口背景略亮）
        let glassBackground = FFGlassView(level: .panel, cornerRadius: 0, material: .headerView)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)
        NSLayoutConstraint.activate([
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 固定双行高度 72pt（每行 32 + 间距 4 + 边距 4）
        heightAnchor.constraint(equalToConstant: 72).isActive = true

        setupRow1()
        setupRow2()
    }

    // MARK: - Row 1: Navigation

    private func setupRow1() {
        backButton = createNavButton(systemSymbol: "chevron.backward", action: #selector(backClicked))
        forwardButton = createNavButton(systemSymbol: "chevron.forward", action: #selector(forwardClicked))
        upButton = createNavButton(systemSymbol: "chevron.up", action: #selector(upClicked))
        refreshButton = createNavButton(systemSymbol: "arrow.clockwise", action: #selector(refreshClicked))

        row1 = NSStackView(views: [backButton, forwardButton, upButton, refreshButton])
        row1.orientation = .horizontal
        row1.alignment = .centerY
        row1.spacing = 4
        row1.detachesHiddenViews = false
        row1.translatesAutoresizingMaskIntoConstraints = false
        row1.setContentHuggingPriority(.defaultHigh, for: .vertical)
        addSubview(row1)

        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row1.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row1.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    // MARK: - 任务 F3: BreadcrumbBar 嵌入

    /// 接收外部 BreadcrumbBar 并嵌入 Row1（刷新按钮之后，紧贴刷新按钮 4pt）
    /// 由 MainWindowController.createPaneContainer 调用
    func setBreadcrumbBar(_ bar: BreadcrumbBar) {
        breadcrumbBar = bar
        bar.translatesAutoresizingMaskIntoConstraints = false
        // 插入到 row1 的 refreshButton 之后（index 4）
        row1.insertArrangedSubview(bar, at: 4)
        // 面包屑 flex 撑满 Row1 剩余空间
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    // MARK: - Row 2: Search + Sort + Group + View

    private func setupRow2() {
        // 1.4 自定义搜索框：FFGlassView(.component) 容器 + 搜索图标 + 无边框文本框
        searchContainer = FFGlassView(level: .component, cornerRadius: 4)
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        let searchIcon = NSImageView()
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")
        searchIcon.contentTintColor = NSColor.secondaryLabelColor
        searchIcon.imageScaling = .scaleProportionallyDown
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchTextField = NSTextField()
        searchTextField.placeholderString = "搜索"
        searchTextField.isBordered = false
        searchTextField.isBezeled = false
        searchTextField.drawsBackground = false
        searchTextField.focusRingType = .none
        searchTextField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        searchTextField.target = self
        searchTextField.action = #selector(searchChanged)
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let searchStack = NSStackView(views: [searchIcon, searchTextField])
        searchStack.orientation = .horizontal
        searchStack.alignment = .centerY
        searchStack.spacing = 6
        searchStack.detachesHiddenViews = false
        searchStack.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchStack)

        NSLayoutConstraint.activate([
            searchStack.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 8),
            searchStack.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -8),
            searchStack.topAnchor.constraint(equalTo: searchContainer.topAnchor, constant: 2),
            searchStack.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: -2),
            searchIcon.widthAnchor.constraint(equalToConstant: 13),
            searchIcon.heightAnchor.constraint(equalToConstant: 13),
            searchContainer.heightAnchor.constraint(equalToConstant: 24),
        ])
        searchContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        searchContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        sortPopup = NSPopUpButton()
        sortPopup.addItems(withTitles: SortField.allCases.map { $0.rawValue })
        sortPopup.target = self
        sortPopup.action = #selector(sortSelected(_:))
        sortPopup.translatesAutoresizingMaskIntoConstraints = false

        groupPopup = NSPopUpButton()
        groupPopup.addItems(withTitles: ["无分组", "按种类", "按日期", "按大小"])
        groupPopup.target = self
        groupPopup.action = #selector(groupSelected(_:))
        groupPopup.translatesAutoresizingMaskIntoConstraints = false

        listViewButton = createViewButton(systemSymbol: "list.bullet", action: #selector(listViewClicked))
        gridViewButton = createViewButton(systemSymbol: "square.grid.2x2", action: #selector(gridViewClicked))

        updateViewModeHighlight(.list)

        // 任务 D15: 工具按钮分隔符（竖线）
        let toolsSeparator = NSBox()
        toolsSeparator.boxType = .separator
        toolsSeparator.translatesAutoresizingMaskIntoConstraints = false
        toolsSeparator.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // 任务 D15: 工具按钮（点击弹出下拉菜单）
        toolsButton = createNavButton(systemSymbol: "slider.horizontal.3", action: #selector(showToolsMenu))

        let row2 = NSStackView(views: [
            searchContainer,
            sortPopup,
            groupPopup,
            listViewButton, gridViewButton,
            toolsSeparator,
            toolsButton,
        ])
        row2.orientation = .horizontal
        row2.alignment = .centerY
        row2.spacing = 4
        row2.detachesHiddenViews = false
        row2.translatesAutoresizingMaskIntoConstraints = false
        row2.setContentHuggingPriority(.defaultHigh, for: .vertical)
        addSubview(row2)

        NSLayoutConstraint.activate([
            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 4),
            row2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row2.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row2.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    // MARK: - Button Factory

    /// 创建访达风格的圆形药丸按钮
    private func createNavButton(systemSymbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    /// 创建视图切换按钮（访达风格圆形药丸）
    private func createViewButton(systemSymbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    // MARK: - Public API

    func setPath(_ path: String) {
        // 面包屑已移至 BreadcrumbBar，此方法保留为空以兼容现有调用
    }

    func setCanGoBack(_ canGoBack: Bool) { backButton.isEnabled = canGoBack }
    func setCanGoForward(_ canGoForward: Bool) { forwardButton.isEnabled = canGoForward }
    func setViewMode(_ mode: ViewMode) { updateViewModeHighlight(mode) }

    private func updateViewModeHighlight(_ mode: ViewMode) {
        listViewButton.highlight(mode == .list)
        gridViewButton.highlight(mode == .grid)
    }

    // MARK: - Actions

    @objc private func backClicked() { delegate?.paneToolbarDidClickBack(self) }
    @objc private func forwardClicked() { delegate?.paneToolbarDidClickForward(self) }
    @objc private func upClicked() { delegate?.paneToolbarDidClickUp(self) }
    @objc private func refreshClicked() { delegate?.paneToolbarDidClickRefresh(self) }
    @objc private func searchChanged() {
        delegate?.paneToolbar(self, didChangeSearchQuery: searchTextField.stringValue)
    }

    @objc private func sortSelected(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem,
              let field = SortField(rawValue: title) else { return }
        // 任务 F10-7: 排序方向改由列头点击控制（移除 sortDirectionButton 后）
        // 切换排序字段时默认升序；用户可点击列头切换升降序
        delegate?.paneToolbar(self, didChangeSortField: field, ascending: true)
    }

    @objc private func groupSelected(_ sender: NSPopUpButton) {
        let groupBy: String
        switch sender.titleOfSelectedItem {
        case "无分组": groupBy = "none"
        case "按种类": groupBy = "kind"
        case "按日期": groupBy = "date"
        case "按大小": groupBy = "size"
        default: groupBy = "none"
        }
        delegate?.paneToolbar(self, didChangeGroupBy: groupBy)
    }

    @objc private func listViewClicked() {
        updateViewModeHighlight(.list)
        delegate?.paneToolbar(self, didChangeViewMode: .list)
    }

    @objc private func gridViewClicked() {
        updateViewModeHighlight(.grid)
        delegate?.paneToolbar(self, didChangeViewMode: .grid)
    }

    // MARK: - 任务 D15/D17: 工具菜单

    /// 点击工具按钮弹出下拉菜单
    @objc private func showToolsMenu() {
        let menu = NSMenu()

        // 查重扫描
        let dedupItem = NSMenuItem(title: "查重扫描", action: #selector(dedupScanClicked), keyEquivalent: "")
        dedupItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "查重扫描")
        dedupItem.target = self
        menu.addItem(dedupItem)

        menu.addItem(.separator())

        // AI 打标 Beta（任务 D17: 置灰不可点击）
        let aiTagItem = NSMenuItem(title: "AI 打标 Beta", action: nil, keyEquivalent: "")
        aiTagItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        aiTagItem.isEnabled = false
        menu.addItem(aiTagItem)

        // AI 整理 Beta（任务 D17: 置灰不可点击）
        let aiOrganizeItem = NSMenuItem(title: "AI 整理 Beta", action: nil, keyEquivalent: "")
        aiOrganizeItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        aiOrganizeItem.isEnabled = false
        menu.addItem(aiOrganizeItem)

        menu.addItem(.separator())

        // 批量重命名
        let renameItem = NSMenuItem(title: "批量重命名", action: #selector(batchRenameClicked), keyEquivalent: "")
        renameItem.image = NSImage(systemSymbolName: "pencil.and.list.rectangle", accessibilityDescription: "批量重命名")
        renameItem.target = self
        menu.addItem(renameItem)

        // 在按钮下方弹出菜单（y 略大于按钮高度，菜单会自动向下展开）
        let location = NSPoint(x: 0, y: toolsButton.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: toolsButton)
    }

    @objc private func dedupScanClicked() {
        delegate?.paneToolbarDidClickDedupScan(self)
    }

    @objc private func batchRenameClicked() {
        delegate?.paneToolbarDidClickBatchRename(self)
    }
}
