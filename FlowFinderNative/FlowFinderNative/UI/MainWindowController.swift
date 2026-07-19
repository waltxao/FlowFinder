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
    private var leftPaneView: NSView!
    private var rightPaneView: NSView!
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

        // Toolbars
        leftPaneToolbar = PaneToolbar()
        leftPaneToolbar.delegate = self
        leftPaneToolbar.translatesAutoresizingMaskIntoConstraints = false

        rightPaneToolbar = PaneToolbar()
        rightPaneToolbar.delegate = self
        rightPaneToolbar.translatesAutoresizingMaskIntoConstraints = false

        // File List Views
        leftFileListView = FileListView()
        leftFileListView.translatesAutoresizingMaskIntoConstraints = false
        leftFileListView.onDoubleClick = { [weak self] entry in
            self?.handleDoubleClick(entry, side: .left)
        }

        rightFileListView = FileListView()
        rightFileListView.translatesAutoresizingMaskIntoConstraints = false
        rightFileListView.onDoubleClick = { [weak self] entry in
            self?.handleDoubleClick(entry, side: .right)
        }

        // Left Pane
        let leftPaneContainer = NSView()
        leftPaneContainer.translatesAutoresizingMaskIntoConstraints = false
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
        let rightPaneContainer = NSView()
        rightPaneContainer.translatesAutoresizingMaskIntoConstraints = false
        rightPaneContainer.addSubview(rightPaneToolbar)
        rightPaneContainer.addSubview(rightFileListView)

        NSLayoutConstraint.activate([
            rightPaneToolbar.topAnchor.constraint(equalTo: rightPaneContainer.topAnchor),
            rightPaneToolbar.leadingAnchor.constraint(equalTo: rightPaneContainer.leadingAnchor),
            rightPaneToolbar.trailingAnchor.constraint(equalTo: rightPaneContainer.trailingAnchor),

            rightFileListView.topAnchor.constraint(equalTo: rightPaneToolbar.bottomAnchor),
            rightFileListView.leadingAnchor.constraint(equalTo: rightPaneContainer.leadingAnchor),
            rightFileListView.trailingAnchor.constraint(equalTo: rightPaneContainer.leadingAnchor),
            rightFileListView.bottomAnchor.constraint(equalTo: rightPaneContainer.bottomAnchor),
        ])

        // Pane Split View (vertical split between top and bottom panes)
        paneSplitView = NSSplitView()
        paneSplitView.isVertical = false
        paneSplitView.dividerStyle = .thin
        paneSplitView.autosaveName = "PaneSplitView"
        paneSplitView.translatesAutoresizingMaskIntoConstraints = false
        paneSplitView.addArrangedSubview(leftPaneContainer)
        paneSplitView.addArrangedSubview(rightPaneContainer)

        // Main Split View (horizontal split between sidebar and panes)
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
        detailsBar.heightAnchor.constraint(equalToConstant: 120).isActive = true

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
        ])

        // Sidebar width
        sidebarView.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // Set initial pane sizes
        mainSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        mainSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
    }

    private func setupBindings() {
        // Left pane bindings
        leftPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updatePaneUI(side: .left, state: state)
            }
            .store(in: &cancellables)

        // Right pane bindings
        rightPaneViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updatePaneUI(side: .right, state: state)
            }
            .store(in: &cancellables)
    }

    private func updatePaneUI(side: PaneSide, state: PaneState) {
        let toolbar = side == .left ? leftPaneToolbar : rightPaneToolbar
        let fileListView = side == .left ? leftFileListView : rightFileListView

        toolbar?.setPath(state.path)
        toolbar?.setCanGoBack(state.historyIndex > 0)
        toolbar?.setCanGoForward(state.historyIndex < state.history.count - 1)

        fileListView?.viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
        fileListView?.reloadData()
    }

    private func loadInitialDirectories() {
        // Load default directories
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let desktopPath = (homePath as NSString).appendingPathComponent("Desktop")
        let documentsPath = (homePath as NSString).appendingPathComponent("Documents")

        leftPaneViewModel.navigate(to: desktopPath)
        rightPaneViewModel.navigate(to: documentsPath)
    }

    // MARK: - Actions

    private func handleDoubleClick(_ entry: FileEntry, side: PaneSide) {
        if entry.isDirectory {
            let viewModel = side == .left ? leftPaneViewModel : rightPaneViewModel
            viewModel.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    private func activatePane(_ side: PaneSide) {
        activePane = side
        // Update visual feedback
        leftPaneView.layer?.borderColor = side == .left ? NSColor.controlAccentColor.cgColor : nil
        rightPaneView.layer?.borderColor = side == .right ? NSColor.controlAccentColor.cgColor : nil
    }
}

// MARK: - PaneToolbarDelegate

extension MainWindowController: PaneToolbarDelegate {
    func paneToolbarDidClickBack(_ toolbar: PaneToolbar) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        _ = viewModel.goBack()
    }

    func paneToolbarDidClickForward(_ toolbar: PaneToolbar) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        _ = viewModel.goForward()
    }

    func paneToolbarDidClickUp(_ toolbar: PaneToolbar) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.goUp()
    }

    func paneToolbarDidClickRefresh(_ toolbar: PaneToolbar) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.refresh()
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeSearchQuery query: String) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.setSearchQuery(query)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeSortField field: String) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.setSortField(field)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeGroupBy groupBy: String) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.setGroupBy(groupBy)
    }

    func paneToolbar(_ toolbar: PaneToolbar, didChangeViewMode mode: String) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.setViewMode(mode)
    }

    func paneToolbarDidClickPath(_ toolbar: PaneToolbar, path: String) {
        let viewModel = toolbar == leftPaneToolbar ? leftPaneViewModel : rightPaneViewModel
        viewModel.navigate(to: path)
    }
}

// MARK: - PaneSide

enum PaneSide {
    case left
    case right
}
