import Cocoa
import Combine

// MARK: - PaneToolbarDelegate

protocol PaneToolbarDelegate: AnyObject {
    func paneToolbarDidClickBack(_ toolbar: PaneToolbar)
    func paneToolbarDidClickForward(_ toolbar: PaneToolbar)
    func paneToolbarDidClickUp(_ toolbar: PaneToolbar)
    func paneToolbarDidClickRefresh(_ toolbar: PaneToolbar)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeSearchQuery query: String)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeSortField field: String)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeGroupBy groupBy: String)
    func paneToolbar(_ toolbar: PaneToolbar, didChangeViewMode mode: String)
    func paneToolbarDidClickPath(_ toolbar: PaneToolbar, path: String)
}

// MARK: - PaneToolbar

class PaneToolbar: NSView {
    weak var delegate: PaneToolbarDelegate?

    private var path: String = ""
    private var canGoBack: Bool = false
    private var canGoForward: Bool = false
    private var cancellables = Set<AnyCancellable>()

    // UI Components
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var upButton: NSButton!
    private var refreshButton: NSButton!
    private var breadcrumbField: NSTextField!
    private var searchField: NSSearchField!
    private var sortButton: NSButton!
    private var groupButton: NSButton!
    private var listViewButton: NSButton!
    private var gridViewButton: NSButton!

    private var sortMenu: NSMenu!
    private var groupMenu: NSMenu!

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
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // Row 1: Navigation
        backButton = createButton(title: "", image: NSImage(named: NSImage.goBackTemplateName)!, target: self, action: #selector(backClicked))
        forwardButton = createButton(title: "", image: NSImage(named: NSImage.goForwardTemplateName)!, target: self, action: #selector(forwardClicked))
        upButton = createButton(title: "", image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(upClicked))
        refreshButton = createButton(title: "", image: NSImage(named: NSImage.refreshTemplateName)!, target: self, action: #selector(refreshClicked))

        breadcrumbField = NSTextField(labelWithString: "")
        breadcrumbField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        breadcrumbField.textColor = NSColor.labelColor
        breadcrumbField.isBezeled = false
        breadcrumbField.isEditable = false
        breadcrumbField.backgroundColor = .clear

        // Row 2: Controls
        searchField = NSSearchField()
        searchField.placeholderString = "搜索"
        searchField.target = self
        searchField.action = #selector(searchChanged)

        sortButton = createMenuButton(title: "排序", menu: createSortMenu())
        groupButton = createMenuButton(title: "分组", menu: createGroupMenu())

        listViewButton = createButton(title: "", image: NSImage(named: NSImage.listViewTemplateName)!, target: self, action: #selector(listViewClicked))
        gridViewButton = createButton(title: "", image: NSImage(named: NSImage.iconViewTemplateName)!, target: self, action: #selector(gridViewClicked))

        // Layout
        let row1 = NSStackView(views: [backButton, forwardButton, upButton, breadcrumbField, refreshButton])
        row1.orientation = .horizontal
        row1.alignment = .centerY
        row1.spacing = 4
        row1.detachesHiddenViews = false

        let row2 = NSStackView(views: [searchField, sortButton, groupButton, listViewButton, gridViewButton])
        row2.orientation = .horizontal
        row2.alignment = .centerY
        row2.spacing = 4
        row2.detachesHiddenViews = false

        let mainStack = NSStackView(views: [row1, row2])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 4
        mainStack.detachesHiddenViews = false
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func createButton(title: String, image: NSImage, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton()
        button.title = title
        button.image = image
        button.bezelStyle = .texturedRounded
        button.target = target
        button.action = action
        button.isBordered = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func createMenuButton(title: String, menu: NSMenu) -> NSButton {
        let button = NSButton()
        button.title = title
        button.bezelStyle = .texturedRounded
        button.showsBorderOnlyWhileMouseInside = true
        button.menu = menu
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func createSortMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "名称", action: #selector(sortSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "修改日期", action: #selector(sortSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "大小", action: #selector(sortSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "类型", action: #selector(sortSelected(_:)), keyEquivalent: "")
        return menu
    }

    private func createGroupMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "无", action: #selector(groupSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "种类", action: #selector(groupSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "修改日期", action: #selector(groupSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "大小", action: #selector(groupSelected(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: - Public API

    func setPath(_ path: String) {
        self.path = path
        let segments = path.split(separator: "/").map(String.init)
        breadcrumbField.stringValue = segments.joined(separator: " / ")
    }

    func setCanGoBack(_ canGoBack: Bool) {
        self.canGoBack = canGoBack
        backButton.isEnabled = canGoBack
    }

    func setCanGoForward(_ canGoForward: Bool) {
        self.canGoForward = canGoForward
        forwardButton.isEnabled = canGoForward
    }

    // MARK: - Actions

    @objc private func backClicked() {
        delegate?.paneToolbarDidClickBack(self)
    }

    @objc private func forwardClicked() {
        delegate?.paneToolbarDidClickForward(self)
    }

    @objc private func upClicked() {
        delegate?.paneToolbarDidClickUp(self)
    }

    @objc private func refreshClicked() {
        delegate?.paneToolbarDidClickRefresh(self)
    }

    @objc private func searchChanged() {
        delegate?.paneToolbar(self, didChangeSearchQuery: searchField.stringValue)
    }

    @objc private func listViewClicked() {
        delegate?.paneToolbar(self, didChangeViewMode: "list")
    }

    @objc private func gridViewClicked() {
        delegate?.paneToolbar(self, didChangeViewMode: "grid")
    }

    @objc private func sortSelected(_ sender: NSMenuItem) {
        let field: String
        switch sender.title {
        case "名称": field = "name"
        case "修改日期": field = "modifiedAt"
        case "大小": field = "size"
        case "类型": field = "extension"
        default: field = "name"
        }
        delegate?.paneToolbar(self, didChangeSortField: field)
    }

    @objc private func groupSelected(_ sender: NSMenuItem) {
        let groupBy: String
        switch sender.title {
        case "无": groupBy = "none"
        case "种类": groupBy = "kind"
        case "修改日期": groupBy = "date"
        case "大小": groupBy = "size"
        default: groupBy = "none"
        }
        delegate?.paneToolbar(self, didChangeGroupBy: groupBy)
    }
}
