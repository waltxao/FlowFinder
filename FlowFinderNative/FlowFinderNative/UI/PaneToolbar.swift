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
    // v0.6.9: 文件夹显示配置菜单回调
    // v0.7.4 修订: 新建文件夹回调携带当前选中数量（未选中建空文件夹，选中>=2 用所选新建文件夹）
    func paneToolbarDidClickNewFolder(_ toolbar: PaneToolbar, selectedCount: Int)
}

// MARK: - PaneToolbarDelegate 默认实现
extension PaneToolbarDelegate {
    func paneToolbarDidClickNewFolder(_ toolbar: PaneToolbar, selectedCount: Int) {}
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
    // v0.7.4 项 2: 新建文件夹独立按钮（原在显示设置菜单里）
    private var newFolderButton: NSButton!
    // v0.7.4 修订: 当前选中数量（决定按钮行为与悬停提示）
    private var currentSelectionCount: Int = 0

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
        // 不设置 masksToBounds：避免裁剪工具栏内容（按钮、搜索框等）

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
        // v0.7.4 修订 1：注册新建文件夹按钮悬停跟踪（鼠标移入立即弹提示气泡）
        setupNewFolderHoverHint()
    }

    // MARK: - Row 1: Navigation

    private func setupRow1() {
        backButton = createNavButton(systemSymbol: "chevron.backward", action: #selector(backClicked), label: "返回")
        forwardButton = createNavButton(systemSymbol: "chevron.forward", action: #selector(forwardClicked), label: "前进")
        upButton = createNavButton(systemSymbol: "chevron.up", action: #selector(upClicked), label: "上级目录")
        refreshButton = createNavButton(systemSymbol: "arrow.clockwise", action: #selector(refreshClicked), label: "刷新")

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
        searchContainer = FFGlassView(level: .component, cornerRadius: 8)
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
        // 任务 F10-10: 设置 delegate，启用 controlTextDidChange 实时搜索（修复问题11）
        // 此前仅有 target/action，searchChanged 仅在按 Enter 时触发，输入过程无反馈
        searchTextField.delegate = self
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
        // 搜索框 hugging 设为最低（1）：弹性吸收 row2 剩余宽度（窗口越宽搜索框越宽），
        // 右侧图标簇（排序/分组/视图/显示设置）因默认 hugging 更高而固定贴最右。
        searchContainer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)

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
        // 防止下拉菜单被横向拉伸：保持固有宽度，剩余宽度全部给搜索框
        sortPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        groupPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        listViewButton = createViewButton(systemSymbol: "list.bullet", action: #selector(listViewClicked), label: "列表视图")
        gridViewButton = createViewButton(systemSymbol: "square.grid.2x2", action: #selector(gridViewClicked), label: "网格视图")

        updateViewModeHighlight(.list)

        // 任务 D15: 工具按钮分隔符（竖线）
        let toolsSeparator = NSBox()
        toolsSeparator.boxType = .separator
        toolsSeparator.translatesAutoresizingMaskIntoConstraints = false
        toolsSeparator.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // v0.6.9+: 文件夹显示配置按钮，使用系统 SF Symbol「slider.horizontal.3」
        // 模板色自动适配浅/深色，与其他导航按钮视觉统一
        toolsButton = createNavButton(systemSymbol: "slider.horizontal.3", action: #selector(showFolderOptionsMenu), label: "文件夹选项")

        // v0.7.4 项 2 + 项 6 合并（v0.7.4 修订）：单一「新建文件夹」按钮。
        // - 未选中任何项目：点击创建空文件夹（默认名"新建文件夹"，重名自动加序号）
        // - 选中 2 个及以上：点击自动"用所选 N 个项目新建文件夹"
        // - 悬停提示随选中状态动态变化（由 setFolderSelectionCount 更新）
        newFolderButton = createNavButton(systemSymbol: "folder.badge.plus", action: #selector(newFolderClicked), label: "新建文件夹")
        newFolderButton.toolTip = "新建文件夹"
        newFolderButton.isEnabled = true

        let row2 = NSStackView(views: [
            searchContainer,
            sortPopup,
            groupPopup,
            listViewButton, gridViewButton,
            newFolderButton,
            toolsSeparator,
            toolsButton,
        ])
        row2.orientation = .horizontal
        row2.alignment = .centerY
        row2.spacing = 4
        // 修复问题 2：默认 distribution 不会拉伸低 hugging 子视图，导致搜索框卡在 120pt 自然宽度、
        // 图标簇挤不到最右、行尾留白。设为 .fill 后，NSStackView 会拉伸水平 hugging 最低的子视图
        // （即 searchContainer，hugging=1）吃掉全部剩余宽度，排序/分组/视图/显示设置等
        // 高 hugging 控件保持固有宽度并整体贴到行最右。
        row2.distribution = .fill
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
    private func createNavButton(systemSymbol: String, action: Selector, label: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: label)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    /// 创建视图切换按钮（访达风格圆形药丸）
    private func createViewButton(systemSymbol: String, action: Selector, label: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: label)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(label)
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

    /// v0.6.9: 点击文件夹配置按钮弹出显示配置菜单
    @objc private func showFolderOptionsMenu() {
        let menu = NSMenu()

        // 读取当前显示配置状态
        let showHidden = UserDefaults.standard.bool(forKey: FFUserDefaultsKeys.showHiddenFiles)
        let showTags = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileTags) as? Bool ?? true
        let showExtensions = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileExtensions) as? Bool ?? true
        let showSystem = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showSystemFiles) as? Bool ?? false

        // 显示/隐藏隐藏文件（文案根据当前状态切换）
        let hiddenItem = NSMenuItem(
            title: showHidden ? "隐藏隐藏文件" : "显示隐藏文件",
            action: #selector(toggleShowHidden),
            keyEquivalent: ""
        )
        hiddenItem.target = self
        hiddenItem.state = showHidden ? .on : .off
        menu.addItem(hiddenItem)

        // 显示/隐藏文件标签
        let tagsItem = NSMenuItem(
            title: showTags ? "隐藏文件标签" : "显示文件标签",
            action: #selector(toggleShowTags),
            keyEquivalent: ""
        )
        tagsItem.target = self
        tagsItem.state = showTags ? .on : .off
        menu.addItem(tagsItem)

        // 显示/隐藏文件后缀
        let extensionsItem = NSMenuItem(
            title: showExtensions ? "隐藏文件后缀" : "显示文件后缀",
            action: #selector(toggleShowExtensions),
            keyEquivalent: ""
        )
        extensionsItem.target = self
        extensionsItem.state = showExtensions ? .on : .off
        menu.addItem(extensionsItem)

        // 显示/隐藏系统文件
        let systemItem = NSMenuItem(
            title: showSystem ? "隐藏系统文件" : "显示系统文件",
            action: #selector(toggleShowSystemFiles),
            keyEquivalent: ""
        )
        systemItem.target = self
        systemItem.state = showSystem ? .on : .off
        menu.addItem(systemItem)

        // v0.7.4 项 2: 「新建文件夹」已从菜单移除，改为工具栏独立按钮（newFolderButton）。
        // 原实现：
        //   menu.addItem(.separator())
        //   let newFolderItem = NSMenuItem(title: "新建文件夹", ...)
        //   menu.addItem(newFolderItem)

        // 在按钮下方弹出菜单
        let location = NSPoint(x: 0, y: toolsButton.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: toolsButton)
    }

    // MARK: - v0.6.9: 显示配置切换回调

    @objc private func toggleShowHidden() {
        let current = UserDefaults.standard.bool(forKey: FFUserDefaultsKeys.showHiddenFiles)
        UserDefaults.standard.set(!current, forKey: FFUserDefaultsKeys.showHiddenFiles)
        NotificationCenter.default.post(name: .refreshHiddenFiles, object: nil)
    }

    @objc private func toggleShowTags() {
        let current = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileTags) as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: FFUserDefaultsKeys.showFileTags)
        NotificationCenter.default.post(name: .refreshFileTags, object: nil)
    }

    @objc private func toggleShowExtensions() {
        let current = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileExtensions) as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: FFUserDefaultsKeys.showFileExtensions)
        NotificationCenter.default.post(name: .refreshFileExtensions, object: nil)
    }

    @objc private func toggleShowSystemFiles() {
        let current = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showSystemFiles) as? Bool ?? false
        UserDefaults.standard.set(!current, forKey: FFUserDefaultsKeys.showSystemFiles)
        NotificationCenter.default.post(name: .refreshSystemFiles, object: nil)
    }

    /// v0.7.4 项 2+6 合并：新建文件夹按钮回调。
    /// 行为由 MainWindowController 决定（未选中建空文件夹；选中>=2 用所选新建文件夹），
    /// 通过新回调把当前选中数量传出去，让控制器按需处理。
    @objc private func newFolderClicked() {
        delegate?.paneToolbarDidClickNewFolder(self, selectedCount: currentSelectionCount)
    }

    /// v0.7.4 修订：外部更新选中数量，用于动态切换按钮行为与悬停提示
    /// - Parameter count: 当前选中项目数（0 = 未选中）
    func setFolderSelectionCount(_ count: Int) {
        currentSelectionCount = count
        // 若悬停提示当前正显示，立即更新文字
        if let label = hoverHintLabel, hoverHintLabel?.window != nil {
            label.stringValue = currentHintText()
            label.sizeToFit()
        }
    }

    // MARK: - v0.7.4 修订：立即显示悬停提示（轻量，鼠标移入即现，移出即隐）

    private var hoverHintLabel: NSTextField?
    private var newFolderHoverTracking: NSTrackingArea?

    /// 给新建文件夹按钮注册悬停跟踪（在按钮创建后调用一次）
    func setupNewFolderHoverHint() {
        guard let btn = newFolderButton else { return }
        // 移除旧的跟踪区域
        if let old = newFolderHoverTracking {
            btn.removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: btn.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        btn.addTrackingArea(area)
        newFolderHoverTracking = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard event.trackingArea === newFolderHoverTracking else { return }
        showHoverHint()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea === newFolderHoverTracking else { return }
        hideHoverHint()
    }

    /// 立即显示悬停提示（轻量小浮层，跟随按钮上方）
    private func showHoverHint() {
        guard let btn = newFolderButton, let window = window else { return }
        hideHoverHint()

        let label = NSTextField(labelWithString: currentHintText())
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.labelColor
        label.backgroundColor = NSColor.windowBackgroundColor
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.layer?.borderWidth = 0.5
        label.layer?.borderColor = NSColor.separatorColor.cgColor
        label.alphaValue = 0.0
        label.sizeToFit()
        // 增加内边距
        let padded = NSSize(width: label.frame.width + 12, height: label.frame.height + 6)
        label.frame.size = padded

        // 位置：按钮上方居中
        let btnFrameInWindow = btn.convert(btn.bounds, to: nil)
        let x = btnFrameInWindow.midX - padded.width / 2
        let y = btnFrameInWindow.maxY + 4
        label.frame.origin = NSPoint(x: x, y: y)

        // 添加到 window 的 contentView 上（浮层，不参与布局）
        window.contentView?.addSubview(label)
        hoverHintLabel = label

        // 立即显示（无需动画延迟）
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = FFMotion.animationDuration(0.08)
            label.animator().alphaValue = 1.0
        }
    }

    private func hideHoverHint() {
        hoverHintLabel?.removeFromSuperview()
        hoverHintLabel = nil
    }

    /// 当前提示文本（随选中数量变化）
    private func currentHintText() -> String {
        if currentSelectionCount >= 2 {
            return "用所选 \(currentSelectionCount) 个项目新建文件夹"
        }
        return "新建文件夹"
    }
}

// MARK: - 任务 F10-10: NSTextFieldDelegate（搜索实时生效，修复问题11）

extension PaneToolbar: NSTextFieldDelegate {
    /// 搜索框文本变化时实时触发搜索（无需按 Enter）。
    /// 修复问题11：此前 searchTextField 仅 target/action，searchChanged 仅 Enter 触发，
    /// 输入过程无反馈。设置 delegate 后，每次按键都触发 controlTextDidChange -> searchChanged。
    public func controlTextDidChange(_ obj: Notification) {
        // 仅响应搜索框（避免将来若有其他 NSTextField 误触）
        guard let textField = obj.object as? NSTextField, textField === searchTextField else { return }
        searchChanged()
    }
}
