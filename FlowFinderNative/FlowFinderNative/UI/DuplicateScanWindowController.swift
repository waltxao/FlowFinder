import Cocoa
import Combine

// MARK: - DuplicateOpaqueContainerView

/// 重写 isOpaque 返回 true 的 NSView 子类（与 MainWindowController 同架构）
private class DuplicateOpaqueContainerView: NSView {
    override var isOpaque: Bool { return true }
}

// MARK: - DuplicateScanWindowController

/// 重复文件扫描窗口控制器：720x560，工具栏+选项条+分栏(左列表+右预览)+操作栏+任务栏
/// 窗口级玻璃架构：OpaqueContainerView + NSGlassEffectView + mainContainer
public class DuplicateScanWindowController: NSWindowController {

    public static let shared = DuplicateScanWindowController()

    // MARK: - UI 引用

    private var pathField: NSTextField!
    /// 当前选中的扫描路径 URL（与 pathField 显示同步）
    private var selectedURL: URL?
    private var browseButton: NSButton!
    private var startButton: NSButton!
    private var stopButton: NSButton!
    /// 选项条控件
    private var scanModeSegmented: NSSegmentedControl!
    private var fileTypePopup: NSPopUpButton!
    private var minSizePopup: NSPopUpButton!
    /// 结果列表区
    private var resultsScrollView: NSScrollView!
    private var resultsStack: NSStackView!
    private var sectionHeader: NSTextField!
    /// 预览面板
    private var previewPanel: DuplicatePreviewPanel!
    /// 操作栏
    private var selectionCountLabel: NSTextField!
    private var spaceLabel: NSTextField!
    private var clearSelectionButton: NSButton!
    private var confirmDeleteButton: NSButton!
    /// 任务栏
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var progressPercentLabel: NSTextField!

    // MARK: - 数据

    private var duplicateGroups: [FFDuplicateGroup] = []
    private var groupViews: [DuplicateGroupView] = []
    /// 所有待删除的文件路径（跨组汇总）
    private var allDeleteFilePaths: Set<String> = []
    /// 所有可释放空间
    private var totalReleasableSpace: UInt64 = 0
    private var isScanning = false

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "查重扫描"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.setFrameAutosaveName("DuplicateScanWindow")
        self.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }

        // 窗口透明以支持玻璃效果
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        // ===== 顶部工具栏（路径标签+输入框+浏览+开始/停止） =====
        let toolbar = makeToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // ===== 选项条（按内容匹配/包含子目录/按文件名匹配 + 文件类型 popup） =====
        let optionsStrip = makeOptionsStrip()
        optionsStrip.translatesAutoresizingMaskIntoConstraints = false

        // ===== 中部分栏内容（左列表+右预览） =====
        // 左侧结果列表区
        let resultsPane = NSView()
        resultsPane.translatesAutoresizingMaskIntoConstraints = false
        resultsPane.wantsLayer = true
        resultsPane.layer?.backgroundColor = NSColor.clear.cgColor

        sectionHeader = NSTextField(labelWithString: "就绪")
        sectionHeader.font = NSFont.systemFont(ofSize: 11)
        sectionHeader.textColor = NSColor.secondaryLabelColor
        sectionHeader.translatesAutoresizingMaskIntoConstraints = false

        let sectionHeaderContainer = FFGlassView(level: .component, cornerRadius: 0)
        sectionHeaderContainer.translatesAutoresizingMaskIntoConstraints = false
        sectionHeaderContainer.addSubview(sectionHeader)

        resultsScrollView = NSScrollView()
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.autohidesScrollers = true
        resultsScrollView.drawsBackground = false
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false

        resultsStack = NSStackView()
        resultsStack.orientation = .vertical
        resultsStack.spacing = 8
        resultsStack.detachesHiddenViews = false
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        resultsStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        resultsScrollView.documentView = resultsStack

        resultsPane.addSubview(sectionHeaderContainer)
        resultsPane.addSubview(resultsScrollView)

        // 右侧预览面板（240pt，FFGlassView .panel .headerView 包裹）
        previewPanel = DuplicatePreviewPanel(frame: .zero)
        previewPanel.translatesAutoresizingMaskIntoConstraints = false
        let previewGlass = FFGlassView(level: .panel, cornerRadius: 10, material: .headerView)
        previewGlass.translatesAutoresizingMaskIntoConstraints = false
        previewGlass.addSubview(previewPanel)

        // 主分栏视图
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor
        splitView.addArrangedSubview(resultsPane)
        splitView.addArrangedSubview(previewGlass)

        // ===== 底部操作栏 =====
        let actionbar = makeActionbar()
        actionbar.translatesAutoresizingMaskIntoConstraints = false

        // ===== 任务栏（进度条+状态） =====
        let taskbar = makeTaskbar()
        taskbar.translatesAutoresizingMaskIntoConstraints = false

        // 组装主容器
        let mainContainer = NSView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.wantsLayer = true
        mainContainer.layer?.backgroundColor = NSColor.clear.cgColor
        mainContainer.addSubview(toolbar)
        mainContainer.addSubview(optionsStrip)
        mainContainer.addSubview(splitView)
        mainContainer.addSubview(actionbar)
        mainContainer.addSubview(taskbar)
        mainContainer.appearance = NSApp.effectiveAppearance

        NSLayoutConstraint.activate([
            // 顶部工具栏
            toolbar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),

            // 选项条
            optionsStrip.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            optionsStrip.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            optionsStrip.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            optionsStrip.heightAnchor.constraint(equalToConstant: 32),

            // 分栏内容
            splitView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: optionsStrip.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: actionbar.topAnchor),

            // 操作栏
            actionbar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            actionbar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            actionbar.bottomAnchor.constraint(equalTo: taskbar.topAnchor),
            actionbar.heightAnchor.constraint(equalToConstant: 48),

            // 任务栏
            taskbar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            taskbar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            taskbar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            taskbar.heightAnchor.constraint(equalToConstant: 28),

            // 预览面板宽度 240pt
            previewGlass.widthAnchor.constraint(equalToConstant: 240),
        ])

        // 结果区内部约束
        NSLayoutConstraint.activate([
            sectionHeaderContainer.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor),
            sectionHeaderContainer.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor),
            sectionHeaderContainer.topAnchor.constraint(equalTo: resultsPane.topAnchor),
            sectionHeaderContainer.heightAnchor.constraint(equalToConstant: 22),
            sectionHeader.leadingAnchor.constraint(equalTo: sectionHeaderContainer.leadingAnchor, constant: 12),
            sectionHeader.centerYAnchor.constraint(equalTo: sectionHeaderContainer.centerYAnchor),

            resultsScrollView.leadingAnchor.constraint(equalTo: resultsPane.leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: resultsPane.trailingAnchor),
            resultsScrollView.topAnchor.constraint(equalTo: sectionHeaderContainer.bottomAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: resultsPane.bottomAnchor),

            resultsStack.leadingAnchor.constraint(equalTo: resultsScrollView.contentView.leadingAnchor),
            resultsStack.trailingAnchor.constraint(equalTo: resultsScrollView.contentView.trailingAnchor),
            resultsStack.topAnchor.constraint(equalTo: resultsScrollView.contentView.topAnchor),
            resultsStack.widthAnchor.constraint(equalTo: resultsScrollView.contentView.widthAnchor),

            previewPanel.leadingAnchor.constraint(equalTo: previewGlass.leadingAnchor),
            previewPanel.trailingAnchor.constraint(equalTo: previewGlass.trailingAnchor),
            previewPanel.topAnchor.constraint(equalTo: previewGlass.topAnchor),
            previewPanel.bottomAnchor.constraint(equalTo: previewGlass.bottomAnchor),
        ])

        splitView.setPosition(720 - 240, ofDividerAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        // ===== 窗口级玻璃架构（参照 MainWindowController） =====
        if #available(macOS 26.0, *) {
            let containerView = DuplicateOpaqueContainerView()
            containerView.wantsLayer = true
            containerView.translatesAutoresizingMaskIntoConstraints = false

            let glassView = NSGlassEffectView()
            glassView.style = .clear
            glassView.cornerRadius = 0
            glassView.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(glassView)
            containerView.addSubview(mainContainer)

            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                glassView.topAnchor.constraint(equalTo: containerView.topAnchor),
                glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                mainContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                mainContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                mainContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
                mainContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            window.contentView = containerView
        } else {
            // macOS 12-25 回退：NSVisualEffectView
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .underWindowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.addSubview(mainContainer)
            NSLayoutConstraint.activate([
                mainContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                mainContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                mainContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                mainContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            ])
            window.contentView = visualEffectView
        }
    }

    /// 构建顶部工具栏（FFGlassView .panel .headerView 玻璃背景，36pt 高）
    /// 布局：扫描路径: label + 等宽路径输入框（260px）+ 浏览... + spacer + 开始扫描（accent）+ 停止
    private func makeToolbar() -> NSView {
        let toolbar = FFGlassView(level: .panel, cornerRadius: 0, material: .headerView)

        let pathLabel = NSTextField(labelWithString: "扫描路径:")
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.textColor = NSColor.secondaryLabelColor
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        // 路径文本框：等宽字体 11pt，260px 宽，只读显示
        pathField = NSTextField(string: FileManager.default.homeDirectoryForCurrentUser.path)
        pathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.textColor = NSColor.labelColor
        pathField.isBezeled = true
        pathField.bezelStyle = .squareBezel
        pathField.isEditable = false
        pathField.translatesAutoresizingMaskIntoConstraints = false
        selectedURL = FileManager.default.homeDirectoryForCurrentUser

        browseButton = NSButton(title: "浏览...", target: self, action: #selector(browseClicked))
        browseButton.bezelStyle = .rounded
        browseButton.controlSize = .small
        browseButton.translatesAutoresizingMaskIntoConstraints = false

        startButton = NSButton(title: "开始扫描", target: self, action: #selector(startScan))
        // 设为默认按钮（return 键等效），AppKit 自动渲染为强调色填充
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.controlSize = .small
        startButton.translatesAutoresizingMaskIntoConstraints = false

        stopButton = NSButton(title: "停止", target: self, action: #selector(cancelScan))
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.isEnabled = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [pathLabel, pathField, browseButton, NSView(), startButton, stopButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pathField.widthAnchor.constraint(equalToConstant: 260),
        ])
        return toolbar
    }

    /// 构建选项条（FFGlassView .component 玻璃背景，32pt 高）
    /// 布局：扫描方式: segmented（按内容/按名称）+ 文件类型: popup + 最小大小: popup
    private func makeOptionsStrip() -> NSView {
        let strip = FFGlassView(level: .component, cornerRadius: 0)

        let modeLabel = NSTextField(labelWithString: "扫描方式:")
        modeLabel.font = NSFont.systemFont(ofSize: 12)
        modeLabel.textColor = NSColor.labelColor
        modeLabel.translatesAutoresizingMaskIntoConstraints = false

        scanModeSegmented = NSSegmentedControl(labels: ["按内容", "按名称"], trackingMode: .selectOne, target: self, action: #selector(optionChanged))
        scanModeSegmented.controlSize = .small
        scanModeSegmented.selectedSegment = 0
        scanModeSegmented.translatesAutoresizingMaskIntoConstraints = false

        let typeLabel = NSTextField(labelWithString: "文件类型:")
        typeLabel.font = NSFont.systemFont(ofSize: 12)
        typeLabel.textColor = NSColor.labelColor
        typeLabel.translatesAutoresizingMaskIntoConstraints = false

        fileTypePopup = NSPopUpButton()
        fileTypePopup.addItems(withTitles: ["全部", "图片", "视频", "文档", "音频"])
        fileTypePopup.controlSize = .small
        fileTypePopup.translatesAutoresizingMaskIntoConstraints = false

        let minSizeLabel = NSTextField(labelWithString: "最小大小:")
        minSizeLabel.font = NSFont.systemFont(ofSize: 12)
        minSizeLabel.textColor = NSColor.labelColor
        minSizeLabel.translatesAutoresizingMaskIntoConstraints = false

        minSizePopup = NSPopUpButton()
        minSizePopup.addItems(withTitles: ["任意", "1 KB", "100 KB", "1 MB", "10 MB"])
        minSizePopup.controlSize = .small
        minSizePopup.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [modeLabel, scanModeSegmented, typeLabel, fileTypePopup, minSizeLabel, minSizePopup, NSView()])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: strip.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
        ])
        return strip
    }

    /// 构建操作栏（FFGlassView .panel .headerView 玻璃背景，48pt 高）
    /// 布局：已选择 N 个文件待删除 + spacer + 可释放 X MB + 取消选择 + 确认删除（红色 accent）
    private func makeActionbar() -> NSView {
        let bar = FFGlassView(level: .panel, cornerRadius: 0, material: .headerView)

        selectionCountLabel = NSTextField(labelWithString: "已选择 0 个文件待删除")
        selectionCountLabel.font = NSFont.systemFont(ofSize: 12)
        selectionCountLabel.textColor = NSColor.secondaryLabelColor
        selectionCountLabel.translatesAutoresizingMaskIntoConstraints = false

        spaceLabel = NSTextField(labelWithString: "可释放 0 KB")
        spaceLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        spaceLabel.textColor = NSColor.systemGreen
        spaceLabel.translatesAutoresizingMaskIntoConstraints = false

        clearSelectionButton = NSButton(title: "取消选择", target: self, action: #selector(clearSelection))
        clearSelectionButton.bezelStyle = .rounded
        clearSelectionButton.controlSize = .small
        clearSelectionButton.isEnabled = false
        clearSelectionButton.translatesAutoresizingMaskIntoConstraints = false

        confirmDeleteButton = NSButton(title: "确认删除", target: self, action: #selector(deleteSelected))
        confirmDeleteButton.bezelStyle = .rounded
        confirmDeleteButton.controlSize = .small
        confirmDeleteButton.isEnabled = false
        // 红色危险按钮：systemRed bezelColor 填充
        confirmDeleteButton.bezelColor = NSColor.systemRed
        confirmDeleteButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [selectionCountLabel, NSView(), spaceLabel, clearSelectionButton, confirmDeleteButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    /// 构建任务栏（FFGlassView .component 玻璃背景，28pt 高）
    /// 布局：状态文字 + 进度条 + 百分比（等宽数字）
    private func makeTaskbar() -> NSView {
        let bar = FFGlassView(level: .component, cornerRadius: 0)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressPercentLabel = NSTextField(labelWithString: "0%")
        progressPercentLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        progressPercentLabel.textColor = NSColor.secondaryLabelColor
        progressPercentLabel.alignment = .right
        progressPercentLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [statusLabel, progressIndicator, progressPercentLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 10),
            progressPercentLabel.widthAnchor.constraint(equalToConstant: 36),
        ])
        return bar
    }

    // MARK: - Public API

    public func showWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func optionChanged() {
        // 选项变更：当前仅记录，下次扫描生效
    }

    @objc private func browseClicked() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.selectedURL = url
                self?.pathField.stringValue = url.path
            }
        }
    }

    @objc private func startScan() {
        guard let url = selectedURL else { return }
        let path = url.path

        isScanning = true
        duplicateGroups = []
        allDeleteFilePaths = []
        totalReleasableSpace = 0
        groupViews.forEach { $0.removeFromSuperview() }
        groupViews = []
        startButton.isEnabled = false
        stopButton.isEnabled = true
        confirmDeleteButton.isEnabled = false
        clearSelectionButton.isEnabled = false
        progressIndicator.doubleValue = 0
        progressPercentLabel.stringValue = "0%"
        statusLabel.stringValue = "扫描中..."
        sectionHeader.stringValue = "扫描中..."

        DuplicateScanBridge.shared.scanDuplicates(
            path: path,
            progressHandler: { [weak self] scanned, total in
                DispatchQueue.main.async {
                    let progress = total > 0 ? Double(scanned) / Double(total) * 100 : 0
                    self?.progressIndicator.doubleValue = progress
                    self?.progressPercentLabel.stringValue = "\(Int(progress))%"
                    self?.statusLabel.stringValue = "已扫描 \(scanned) / \(total) 个文件"
                }
            },
            groupHandler: { [weak self] group in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.duplicateGroups.append(group)
                    self.addGroupView(group)
                    self.updateSectionHeader()
                }
            },
            completion: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isScanning = false
                    self?.startButton.isEnabled = true
                    self?.stopButton.isEnabled = false
                    self?.confirmDeleteButton.isEnabled = !(self?.allDeleteFilePaths.isEmpty ?? true)
                    self?.clearSelectionButton.isEnabled = !(self?.allDeleteFilePaths.isEmpty ?? true)

                    if let error = error {
                        self?.statusLabel.stringValue = "错误: \(error.localizedDescription)"
                    } else {
                        let count = self?.duplicateGroups.count ?? 0
                        self?.statusLabel.stringValue = "完成，找到 \(count) 个重复组"
                        self?.progressPercentLabel.stringValue = "100%"
                    }
                    self?.updateSectionHeader()
                }
            }
        )
    }

    @objc private func cancelScan() {
        DuplicateScanBridge.shared.cancelScan()
        isScanning = false
        startButton.isEnabled = true
        stopButton.isEnabled = false
        statusLabel.stringValue = "已取消扫描"
    }

    @objc private func clearSelection() {
        allDeleteFilePaths = []
        totalReleasableSpace = 0
        // 重置所有组视图的选中状态（保留第一项）
        for groupView in groupViews {
            // 触发重置：通过重新构建组视图
            let group = groupView.getGroup()
            let index = groupViews.firstIndex(where: { $0 === groupView })
            if let index = index {
                groupView.removeFromSuperview()
                let newView = DuplicateGroupView(group: group)
                newView.delegate = self
                groupViews[index] = newView
                resultsStack.insertArrangedSubview(newView, at: index)
                constrainGroupView(newView)
                // 收集默认删除项
                for file in group.files.dropFirst() {
                    allDeleteFilePaths.insert(file.path)
                    totalReleasableSpace += file.size
                }
            }
        }
        updateActionbar()
    }

    @objc private func deleteSelected() {
        guard !allDeleteFilePaths.isEmpty else { return }

        let dialog = DeleteConfirmDialog(fileCount: allDeleteFilePaths.count) { [weak self] in
            self?.performDelete()
        }
        if let window = window {
            dialog.beginSheetModal(for: window)
        } else {
            // 无窗口回退（极少见），直接执行
            performDelete()
        }
    }

    private func performDelete() {
        let files = Array(allDeleteFilePaths)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var deletedCount = 0
            var errors: [String] = []

            for path in files {
                do {
                    try CoreBridge.shared.deleteFile(path: path)
                    deletedCount += 1
                } catch {
                    errors.append("\(path): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self?.allDeleteFilePaths = []
                self?.totalReleasableSpace = 0
                self?.updateActionbar()
                // 重新扫描以刷新结果
                self?.startScan()
            }
        }
    }

    // MARK: - 组视图管理

    private func addGroupView(_ group: FFDuplicateGroup) {
        let groupView = DuplicateGroupView(group: group)
        groupView.delegate = self
        groupViews.append(groupView)
        resultsStack.addArrangedSubview(groupView)
        constrainGroupView(groupView)

        // 默认收集删除项（除保留项外的所有文件）
        for file in group.files.dropFirst() {
            allDeleteFilePaths.insert(file.path)
            totalReleasableSpace += file.size
        }
        updateActionbar()

        // 选中第一个组时更新预览
        if groupViews.count == 1 {
            previewPanel.update(with: group)
        }
    }

    private func constrainGroupView(_ view: DuplicateGroupView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: resultsStack.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: resultsStack.trailingAnchor),
        ])
    }

    private func updateSectionHeader() {
        let groupCount = duplicateGroups.count
        let fileCount = duplicateGroups.reduce(0) { $0 + $1.files.count }
        sectionHeader.stringValue = "发现 \(groupCount) 组重复文件 · 共 \(fileCount) 个文件"
    }

    private func updateActionbar() {
        selectionCountLabel.stringValue = "已选择 \(allDeleteFilePaths.count) 个文件待删除"
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        spaceLabel.stringValue = "可释放 \(formatter.string(fromByteCount: Int64(totalReleasableSpace)))"
        confirmDeleteButton.isEnabled = !allDeleteFilePaths.isEmpty
        clearSelectionButton.isEnabled = !allDeleteFilePaths.isEmpty
    }
}

// MARK: - DuplicateGroupViewDelegate

extension DuplicateScanWindowController: DuplicateGroupViewDelegate {

    func duplicateGroupView(_ view: DuplicateGroupView, didChangeSelectionInGroup groupId: String, keepFilePath: String, deleteFilePaths: [String]) {
        // 更新汇总集合
        // 先移除该组之前的所有删除项（通过组 id 过滤），再添加新的
        // 简化实现：重新计算所有组的删除项
        allDeleteFilePaths = []
        totalReleasableSpace = 0
        for groupView in groupViews {
            let group = groupView.getGroup()
            let groupDeletePaths = Set(groupView.deleteFilePaths)
            for file in group.files {
                if groupDeletePaths.contains(file.path) {
                    allDeleteFilePaths.insert(file.path)
                    totalReleasableSpace += file.size
                }
            }
        }
        updateActionbar()
    }

    func duplicateGroupView(_ view: DuplicateGroupView, didSelectGroup group: FFDuplicateGroup) {
        previewPanel.update(with: group)
    }
}
