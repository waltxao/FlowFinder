import Cocoa
import Combine
import QuickLook

// MARK: - MainWindowController

public class MainWindowController: NSWindowController {

    // MARK: - Properties

    private let leftPaneViewModel = PaneViewModel()
    private let rightPaneViewModel = PaneViewModel()
    private var activePane: PaneSide = .left
    private var cancellables = Set<AnyCancellable>()

    private var sidebarView: SidebarView!
    private var leftPaneContainer: NSView!
    private var rightPaneContainer: NSView!
    private var detailsBar: DetailsBar!
    private var mainSplitView: NSSplitView!
    private var paneSplitView: NSSplitView!

    private var leftPaneToolbar: PaneToolbar!
    private var rightPaneToolbar: PaneToolbar!
    private var leftFileListView: FileListView!
    private var rightFileListView: FileListView!

    // MARK: - Initialization

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FlowFinder"
        window.minSize = NSSize(width: 1000, height: 700)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.isRestorable = true

        super.init(window: window)

        setupUI()
        setupBindings()
        setupNotifications()
        loadInitialDirectories()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }

        // Sidebar
        sidebarView = SidebarView()
        sidebarView.translatesAutoresizingMaskIntoConstraints = false

        // Left Pane
        leftPaneToolbar = PaneToolbar()
        leftPaneToolbar.delegate = self
        leftPaneToolbar.translatesAutoresizingMaskIntoConstraints = false

        leftFileListView = FileListView()
        leftFileListView.identifier = NSUserInterfaceItemIdentifier("left")
        leftFileListView.translatesAutoresizingMaskIntoConstraints = false
        leftFileListView.onDoubleClick = { [weak self] entry in
            self?.handleDoubleClick(entry, side: .left)
        }
        leftFileListView.onSelectionChanged = { [weak self] files in
            self?.handleSelectionChanged(side: .left, files: files)
        }

        leftPaneContainer = NSView()
        leftPaneContainer.translatesAutoresizingMaskIntoConstraints = false
        leftPaneContainer.wantsLayer = true
        leftPaneContainer.layer?.cornerRadius = 8
        leftPaneContainer.addSubview(leftPaneToolbar)
        leftPaneContainer.addSubview(leftFileListView)

        NSLayoutConstraint.activate([
            leftPaneToolbar.topAnchor.constraint(equalTo: leftPaneContainer.topAnchor),
            leftPaneToolbar.leadingAnchor.constraint(equalTo: leftPaneContainer.leadingAnchor),
            leftPaneToolbar.trailingAnchor.constraint(equalTo: leftPaneContainer.trailingAnchor),

            leftFileListView.topAnchor.constraint(equalTo: leftPaneToolbar.bottomAnchor),
            leftFileListView.leadingAnchor.constraint(equalTo: leftPaneContainer.leadingAnchor),
            leftFileListView.trailingAnchor.constraint(equalTo: leftPaneContainer.trailingAnchor),
            leftFileListView.bottomAnchor.constraint(equalTo: leftPaneContainer.bottomAnchor),
        ])

        // Right Pane
        rightPaneToolbar = PaneToolbar()
        rightPaneToolbar.delegate = self
        rightPaneToolbar.translatesAutoresizingMaskIntoConstraints = false

        rightFileListView = FileListView()
        rightFileListView.identifier = NSUserInterfaceItemIdentifier("right")
        rightFileListView.translatesAutoresizingMaskIntoConstraints = false
        rightFileListView.onDoubleClick = { [weak self] entry in
            self?.handleDoubleClick(entry, side: .right)
        }
        rightFileListView.onSelectionChanged = { [weak self] files in
            self?.handleSelectionChanged(side: .right, files: files)
        }

        rightPaneContainer = NSView()
        rightPaneContainer.translatesAutoresizingMaskIntoConstraints = false
        rightPaneContainer.wantsLayer = true
        rightPaneContainer.layer?.cornerRadius = 8
        rightPaneContainer.addSubview(rightPaneToolbar)
        rightPaneContainer.addSubview(rightFileListView)

        NSLayoutConstraint.activate([
            rightPaneToolbar.topAnchor.constraint(equalTo: rightPaneContainer.topAnchor),
            rightPaneToolbar.leadingAnchor.constraint(equalTo: rightPaneContainer.leadingAnchor),
            rightPaneToolbar.trailingAnchor.constraint(equalTo: rightPaneContainer.trailingAnchor),

            rightFileListView.topAnchor.constraint(equalTo: rightPaneToolbar.bottomAnchor),
            rightFileListView.leadingAnchor.constraint(equalTo: rightPaneContainer.leadingAnchor),
            rightFileListView.trailingAnchor.constraint(equalTo: rightPaneContainer.trailingAnchor),  // 修复 bug: 原来错误地约束到 leadingAnchor
            rightFileListView.bottomAnchor.constraint(equalTo: rightPaneContainer.bottomAnchor),
        ])

        // Pane Split View (left/right panes)
        paneSplitView = NSSplitView()
        paneSplitView.isVertical = true
        paneSplitView.dividerStyle = .thin
        paneSplitView.autosaveName = "PaneSplitView"
        paneSplitView.translatesAutoresizingMaskIntoConstraints = false
        paneSplitView.addArrangedSubview(leftPaneContainer)
        paneSplitView.addArrangedSubview(rightPaneContainer)

        // Main Split View (sidebar + panes)
        mainSplitView = NSSplitView()
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.autosaveName = "MainSplitView"
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false
        mainSplitView.addArrangedSubview(sidebarView)
        mainSplitView.addArrangedSubview(paneSplitView)

        // Details Bar
        detailsBar = DetailsBar()
        detailsBar.translatesAutoresizingMaskIntoConstraints = false

        // Main container
        let mainContainer = NSView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.addSubview(mainSplitView)
        mainContainer.addSubview(detailsBar)

        window.contentView?.addSubview(mainContainer)

        NSLayoutConstraint.activate([
            mainContainer.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            mainContainer.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),

            mainSplitView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            mainSplitView.bottomAnchor.constraint(equalTo: detailsBar.topAnchor),

            detailsBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            detailsBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            detailsBar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            detailsBar.heightAnchor.constraint(equalToConstant: 120),
        ])

        // Sidebar width
        sidebarView.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // Pane holding priorities
        mainSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        mainSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        paneSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        // Set initial active pane
        updateActivePaneVisual()
    }

    private func setupBindings() {
        leftPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updatePaneUI(side: .left, state: state) }
            .store(in: &cancellables)

        rightPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updatePaneUI(side: .right, state: state) }
            .store(in: &cancellables)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSidebarDirectorySelected(_:)),
            name: .sidebarDidSelectDirectory, object: nil
        )
    }

    // MARK: - UI Updates

    private func updatePaneUI(side: PaneSide, state: PaneState) {
        let toolbar = side == .left ? leftPaneToolbar : rightPaneToolbar
        let fileListView = side == .left ? leftFileListView : rightFileListView

        toolbar?.setPath(state.path)
        toolbar?.setCanGoBack(state.historyIndex > 0)
        toolbar?.setCanGoForward(state.historyIndex < state.history.count - 1)
        toolbar?.setViewMode(state.viewMode)

        fileListView?.viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
        fileListView?.reloadData()
    }

    private func updateActivePaneVisual() {
        leftPaneContainer.layer?.borderWidth = activePane == .left ? 2 : 0
        leftPaneContainer.layer?.borderColor = NSColor.controlAccentColor.cgColor
        rightPaneContainer.layer?.borderWidth = activePane == .right ? 2 : 0
        rightPaneContainer.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    private func loadInitialDirectories() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let desktopPath = (homePath as NSString).appendingPathComponent("Desktop")
        let documentsPath = (homePath as NSString).appendingPathComponent("Documents")

        leftPaneViewModel.state.path = desktopPath
        leftPaneViewModel.state.history = [desktopPath]
        leftPaneViewModel.state.historyIndex = 0

        rightPaneViewModel.state.path = documentsPath
        rightPaneViewModel.state.history = [documentsPath]
        rightPaneViewModel.state.historyIndex = 0

        leftPaneViewModel.refresh()
        rightPaneViewModel.refresh()
    }

    // MARK: - Actions

    private func handleDoubleClick(_ entry: FileEntry, side: PaneSide) {
        if entry.isDirectory {
            let vm = side == .left ? leftPaneViewModel : rightPaneViewModel
            vm.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    private func handleSelectionChanged(side: PaneSide, files: [FileEntry]) {
        // 只有活跃面板的选择才更新 DetailsBar
        guard side == activePane else { return }
        if let first = files.first {
            detailsBar.update(file: first, selectedCount: files.count)
        } else {
            detailsBar.update(file: nil, selectedCount: 0)
        }
    }

    func activatePane(_ side: PaneSide) {
        activePane = side
        updateActivePaneVisual()
    }

    @objc private func handleSidebarDirectorySelected(_ notification: Notification) {
        guard let entry = notification.object as? FileEntry else { return }
        let vm = activePane == .left ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: entry.path)
    }
}

// MARK: - PaneToolbarDelegate

extension MainWindowController: PaneToolbarDelegate {
    func paneToolbarDidClickBack(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        _ = vm.goBack()
    }

    func paneToolbarDidClickForward(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        _ = vm.goForward()
    }

    func paneToolbarDidClickUp(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.goUp()
    }

    func paneToolbarDidClickRefresh(_ toolbar: PaneToolbar) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.refresh()
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeSearchQuery query: String) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setSearchQuery(query)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeSortField field: SortField, ascending: Bool) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setSortField(field, ascending: ascending)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeGroupBy groupBy: String) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setGroupBy(groupBy)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeViewMode mode: ViewMode) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.setViewMode(mode)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didClickPath path: String) {
        let vm = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        vm.navigate(to: path)
    }
}

// MARK: - PaneSide

enum PaneSide {
    case left
    case right
}
