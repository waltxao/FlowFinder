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
}

// MARK: - PaneToolbar

class PaneToolbar: NSView {
    weak var delegate: PaneToolbarDelegate?

    private var path: String = ""
    private var cancellables = Set<AnyCancellable>()

    // UI Components
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var upButton: NSButton!
    private var refreshButton: NSButton!
    private var breadcrumbStack: NSStackView!
    private var searchField: NSSearchField!
    private var sortPopup: NSPopUpButton!
    private var sortDirectionButton: NSButton!
    private var groupPopup: NSPopUpButton!
    private var listViewButton: NSButton!
    private var gridViewButton: NSButton!

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

        // Navigation buttons
        backButton = createIconButton(imageName: NSImage.goBackTemplateName, action: #selector(backClicked))
        forwardButton = createIconButton(imageName: NSImage.goForwardTemplateName, action: #selector(forwardClicked))
        upButton = createIconButton(systemSymbol: "chevron.up", action: #selector(upClicked))
        refreshButton = createIconButton(imageName: NSImage.refreshTemplateName, action: #selector(refreshClicked))

        // Breadcrumb (clickable segments)
        breadcrumbStack = NSStackView()
        breadcrumbStack.orientation = .horizontal
        breadcrumbStack.alignment = .centerY
        breadcrumbStack.spacing = 2
        breadcrumbStack.detachesHiddenViews = false
        breadcrumbStack.translatesAutoresizingMaskIntoConstraints = false

        // Search
        searchField = NSSearchField()
        searchField.placeholderString = "搜索当前目录"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        // Sort popup
        sortPopup = NSPopUpButton()
        sortPopup.addItems(withTitles: SortField.allCases.map { $0.rawValue })
        sortPopup.target = self
        sortPopup.action = #selector(sortSelected(_:))
        sortPopup.translatesAutoresizingMaskIntoConstraints = false

        // Sort direction toggle
        sortDirectionButton = NSButton()
        sortDirectionButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "升序")
        sortDirectionButton.bezelStyle = .texturedRounded
        sortDirectionButton.target = self
        sortDirectionButton.action = #selector(sortDirectionToggled)
        sortDirectionButton.translatesAutoresizingMaskIntoConstraints = false

        // Group popup
        groupPopup = NSPopUpButton()
        groupPopup.addItems(withTitles: ["无分组", "按种类", "按日期", "按大小"])
        groupPopup.target = self
        groupPopup.action = #selector(groupSelected(_:))
        groupPopup.translatesAutoresizingMaskIntoConstraints = false

        // View mode buttons (mutually exclusive)
        listViewButton = createIconButton(imageName: NSImage.listViewTemplateName, action: #selector(listViewClicked))
        listViewButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "列表视图")
        gridViewButton = createIconButton(imageName: NSImage.iconViewTemplateName, action: #selector(gridViewClicked))
        gridViewButton.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "网格视图")

        // Set initial view mode highlight
        updateViewModeHighlight(.list)

        // Layout: single row
        let mainStack = NSStackView(views: [
            backButton, forwardButton, upButton, refreshButton,
            breadcrumbStack,
            searchField,
            sortPopup, sortDirectionButton,
            groupPopup,
            listViewButton, gridViewButton,
        ])
        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 4
        mainStack.detachesHiddenViews = false
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        // Make breadcrumb flexible
        mainStack.setHuggingPriority(.defaultLow, for: .horizontal)
        breadcrumbStack.setHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setHuggingPriority(.defaultHigh, for: .horizontal)

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func createIconButton(imageName: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(named: imageName) ?? NSImage()
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func createIconButton(systemSymbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil) ?? NSImage()
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Public API

    func setPath(_ path: String) {
        self.path = path
        // Rebuild breadcrumb segments
        breadcrumbStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let segments = path.split(separator: "/").map(String.init)
        var accumulatedPath = ""

        // Root button
        let rootButton = createBreadcrumbButton(title: "Macintosh HD", path: "/")
        breadcrumbStack.addArrangedSubview(rootButton)

        for segment in segments {
            accumulatedPath += "/" + segment
            // Separator
            let sep = NSTextField(labelWithString: "›")
            sep.textColor = NSColor.secondaryLabelColor
            sep.translatesAutoresizingMaskIntoConstraints = false
            breadcrumbStack.addArrangedSubview(sep)

            let btn = createBreadcrumbButton(title: segment, path: accumulatedPath)
            breadcrumbStack.addArrangedSubview(btn)
        }
    }

    private func createBreadcrumbButton(title: String, path: String) -> NSButton {
        let button = NSButton()
        button.title = title
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        button.target = self
        button.action = #selector(breadcrumbClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        // Store path in identifier
        button.identifier = NSUserInterfaceItemIdentifier(path)
        return button
    }

    func setCanGoBack(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func setCanGoForward(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func setViewMode(_ mode: ViewMode) {
        updateViewModeHighlight(mode)
    }

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
        delegate?.paneToolbar(self, didChangeSearchQuery: searchField.stringValue)
    }

    @objc private func sortSelected(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem,
              let field = SortField(rawValue: title) else { return }
        let isAscending = sortDirectionButton.image == NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        delegate?.paneToolbar(self, didChangeSortField: field, ascending: isAscending)
    }

    @objc private func sortDirectionToggled() {
        let isAscending = sortDirectionButton.image == NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        sortDirectionButton.image = NSImage(systemSymbolName: isAscending ? "chevron.down" : "chevron.up", accessibilityDescription: isAscending ? "降序" : "升序")

        guard let title = sortPopup.titleOfSelectedItem,
              let field = SortField(rawValue: title) else { return }
        delegate?.paneToolbar(self, didChangeSortField: field, ascending: !isAscending)
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

    @objc private func breadcrumbClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        delegate?.paneToolbar(self, didClickPath: path)
    }
}
