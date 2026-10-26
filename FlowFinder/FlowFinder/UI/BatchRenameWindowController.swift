import Cocoa

/// 批量重命名名称计算（纯函数，便于单测）。
enum FFBatchRenamePattern {
    static func apply(_ pattern: String, entry: FileEntry, index: Int) -> String {
        var result = pattern
        result = result.replacingOccurrences(of: "{name}", with: entry.displayName)

        let ext = entry.fileExtension
        if ext.isEmpty {
            // 避免 {name}.{ext} 在无扩展名时生成尾点。
            result = result.replacingOccurrences(of: ".{ext}", with: "")
        }
        result = result.replacingOccurrences(of: "{ext}", with: ext)

        if let regex = try? NSRegularExpression(pattern: "\\{index:(\\d+)\\}") {
            let nsString = NSMutableString(string: result)
            let fullRange = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: result, range: fullRange)
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let nRange = Range(match.range(at: 1), in: result) else { continue }
                let n = Int(result[nRange]) ?? 1
                let padded = String(format: "%0\(n)d", index + 1)
                nsString.replaceCharacters(in: match.range, with: padded)
            }
            result = nsString as String
        }

        result = result.replacingOccurrences(of: "{index}", with: "\(index + 1)")
        result = result.replacingOccurrences(of: "{index0}", with: "\(index)")
        return sanitize(result)
    }

    static func sanitize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }
}

/// 批量重命名窗口控制器：模式替换 / 序号添加 / 大小写转换 + 实时预览
/// 任务 F11-2: 窗口实体背景（windowBackgroundColor），确保内容清晰可读（v0.6.7）。
public class BatchRenameWindowController: NSWindowController {

    public static let shared = BatchRenameWindowController()

    /// ⌘W 命中批量重命名窗口时关闭自身。
    @objc func menuCloseTab(_ sender: Any?) {
        close()
    }

    // MARK: - State

    private var files: [FileEntry] = []
    private weak var paneViewModel: PaneViewModel?

    /// 计算后的预览结果（与 files 一一对应）
    private var previewNames: [String] = []
    /// 每行的冲突原因（与 files 一一对应；nil 表示该行可用）。红字之外必须能说出撞了谁（R4-12）。
    private var conflictReasons: [String?] = []
    /// 每行的扩展名改写提示（与 files 一一对应；nil 表示扩展名不变）。只提示，不拦下执行。
    private var extensionWarnings: [String?] = []
    /// 预览表当前显示的行号（映射到 files 下标）；「只看冲突」筛选后可能少于 files.count。
    private var visibleIndices: [Int] = []
    /// 各目录里已存在的文件名（不含正在被重命名的原名），按目录分别判定冲突（R4-12）。
    private var existingNamesByDir: [String: Set<String>] = [:]

    /// 文件所在目录，跨目录选择时冲突判定的分组键。
    private func directory(of entry: FileEntry) -> String {
        (entry.path as NSString).deletingLastPathComponent
    }

    private enum RenameMode: Int {
        case pattern = 0
        case sequence = 1
        case caseChange = 2
    }

    private var selectedMode: RenameMode {
        return RenameMode(rawValue: modeSegmentedControl.selectedSegment) ?? .pattern
    }

    private enum CaseOption: String {
        case upper = "大写"
        case lower = "小写"
        case capitalized = "首字母大写"
        case unchanged = "不变"
    }

    // MARK: - UI Elements

    private var modeSegmentedControl: NSSegmentedControl!
    private var patternField: NSTextField!
    private var patternHintLabel: NSTextField!
    private var sequenceContainer: NSView!
    private var patternContainer: NSView!
    private var caseContainer: NSView!
    private var prefixField: NSTextField!
    private var suffixField: NSTextField!
    private var startIndexField: NSTextField!
    private var stepField: NSTextField!
    private var casePopup: NSPopUpButton!
    private var previewTableView: NSTableView!
    private var scrollView: NSScrollView!
    private var renameButton: NSButton!
    private var cancelButton: NSButton!
    private var onlyConflictsSwitch: NSButton!
    private var conflictLegendLabel: NSTextField!

    // 供 XCTest 读取真实控件与真实判定结果（R4-12）。
    var previewTableForTesting: NSTableView? { previewTableView }
    var patternFieldForTesting: NSTextField? { patternField }
    var prefixFieldForTesting: NSTextField? { prefixField }
    var renameButtonForTesting: NSButton? { renameButton }
    var onlyConflictsSwitchForTesting: NSButton? { onlyConflictsSwitch }
    var conflictLegendForTesting: NSTextField? { conflictLegendLabel }

    /// 第 index 行（files 下标）的冲突原因；nil 表示该行可执行。
    func conflictReason(at index: Int) -> String? {
        guard index >= 0, index < conflictReasons.count else { return nil }
        return conflictReasons[index]
    }

    /// 第 index 行的扩展名改写提示；nil 表示扩展名保持不变。
    func extensionWarning(at index: Int) -> String? {
        guard index >= 0, index < extensionWarnings.count else { return nil }
        return extensionWarnings[index]
    }

    // MARK: - Init

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "批量重命名"
        // 任务 F11-2: 实体窗口背景（v0.6.7）
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        window.setFrameAutosaveName("BatchRenameWindow")
        self.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }
        // 任务 F11-2: contentView 实体背景（v0.6.7）
        // R4-32: 动态色不能构建时解析一次钉在 layer 上，主题切换后窗口会停在旧外观底色。
        let contentView = FFDynamicBackgroundView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView

        // 顶部模式切换
        modeSegmentedControl = NSSegmentedControl(
            labels: ["模式替换", "序号添加", "大小写转换"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        modeSegmentedControl.selectedSegment = 0
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

        // 模式容器：模式替换
        patternContainer = NSView()
        patternContainer.translatesAutoresizingMaskIntoConstraints = false

        patternField = NSTextField(string: "{name}.{ext}")
        patternField.placeholderString = "{name}.{ext}"
        patternField.target = self
        patternField.action = #selector(patternFieldChanged)
        patternField.delegate = self
        patternField.translatesAutoresizingMaskIntoConstraints = false

        patternHintLabel = NSTextField(labelWithString: "占位符: {name} 文件名  {ext} 扩展名  {index} 序号(1开始)  {index0} 序号(0开始)  {index:N} 零填充N位")
        patternHintLabel.font = FFVisualTokens.Font.hint
        patternHintLabel.textColor = NSColor.secondaryLabelColor
        patternHintLabel.lineBreakMode = .byTruncatingTail
        patternHintLabel.translatesAutoresizingMaskIntoConstraints = false

        patternContainer.addSubview(patternField)
        patternContainer.addSubview(patternHintLabel)

        NSLayoutConstraint.activate([
            patternField.topAnchor.constraint(equalTo: patternContainer.topAnchor),
            patternField.leadingAnchor.constraint(equalTo: patternContainer.leadingAnchor),
            patternField.trailingAnchor.constraint(equalTo: patternContainer.trailingAnchor),

            patternHintLabel.topAnchor.constraint(equalTo: patternField.bottomAnchor, constant: 4),
            patternHintLabel.leadingAnchor.constraint(equalTo: patternContainer.leadingAnchor),
            patternHintLabel.trailingAnchor.constraint(equalTo: patternContainer.trailingAnchor),
            patternHintLabel.bottomAnchor.constraint(equalTo: patternContainer.bottomAnchor),
        ])

        // 模式容器：序号添加
        sequenceContainer = NSView()
        sequenceContainer.translatesAutoresizingMaskIntoConstraints = false
        sequenceContainer.isHidden = true

        let prefixLabel = NSTextField(labelWithString: "前缀:")
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        // 前缀留空：写死的 IMG_ 会覆盖掉用户自己的命名习惯（R4-12）。
        prefixField = NSTextField(string: "")
        prefixField.placeholderString = "前缀（可空）"
        prefixField.delegate = self
        prefixField.translatesAutoresizingMaskIntoConstraints = false

        let suffixLabel = NSTextField(labelWithString: "后缀:")
        suffixLabel.translatesAutoresizingMaskIntoConstraints = false
        suffixField = NSTextField(string: "")
        suffixField.placeholderString = "后缀（可空）"
        suffixField.delegate = self
        suffixField.translatesAutoresizingMaskIntoConstraints = false

        let startLabel = NSTextField(labelWithString: "起始:")
        startLabel.translatesAutoresizingMaskIntoConstraints = false
        startIndexField = NSTextField(string: "1")
        startIndexField.delegate = self
        startIndexField.translatesAutoresizingMaskIntoConstraints = false

        let stepLabel = NSTextField(labelWithString: "步长:")
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        stepField = NSTextField(string: "1")
        stepField.delegate = self
        stepField.translatesAutoresizingMaskIntoConstraints = false

        sequenceContainer.addSubview(prefixLabel)
        sequenceContainer.addSubview(prefixField)
        sequenceContainer.addSubview(suffixLabel)
        sequenceContainer.addSubview(suffixField)
        sequenceContainer.addSubview(startLabel)
        sequenceContainer.addSubview(startIndexField)
        sequenceContainer.addSubview(stepLabel)
        sequenceContainer.addSubview(stepField)

        NSLayoutConstraint.activate([
            prefixLabel.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            prefixLabel.leadingAnchor.constraint(equalTo: sequenceContainer.leadingAnchor),
            prefixLabel.widthAnchor.constraint(equalToConstant: 40),

            prefixField.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            prefixField.leadingAnchor.constraint(equalTo: prefixLabel.trailingAnchor, constant: 4),
            prefixField.widthAnchor.constraint(equalToConstant: 120),

            suffixLabel.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            suffixLabel.leadingAnchor.constraint(equalTo: prefixField.trailingAnchor, constant: 12),
            suffixLabel.widthAnchor.constraint(equalToConstant: 40),

            suffixField.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            suffixField.leadingAnchor.constraint(equalTo: suffixLabel.trailingAnchor, constant: 4),
            suffixField.widthAnchor.constraint(equalToConstant: 120),

            startLabel.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            startLabel.leadingAnchor.constraint(equalTo: suffixField.trailingAnchor, constant: 12),
            startLabel.widthAnchor.constraint(equalToConstant: 40),

            startIndexField.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            startIndexField.leadingAnchor.constraint(equalTo: startLabel.trailingAnchor, constant: 4),
            startIndexField.widthAnchor.constraint(equalToConstant: 60),

            stepLabel.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            stepLabel.leadingAnchor.constraint(equalTo: startIndexField.trailingAnchor, constant: 12),
            stepLabel.widthAnchor.constraint(equalToConstant: 40),

            stepField.topAnchor.constraint(equalTo: sequenceContainer.topAnchor),
            stepField.leadingAnchor.constraint(equalTo: stepLabel.trailingAnchor, constant: 4),
            stepField.widthAnchor.constraint(equalToConstant: 60),

            sequenceContainer.bottomAnchor.constraint(equalTo: prefixField.bottomAnchor, constant: 8),
        ])

        // 模式容器：大小写转换
        caseContainer = NSView()
        caseContainer.translatesAutoresizingMaskIntoConstraints = false
        caseContainer.isHidden = true

        let caseLabel = NSTextField(labelWithString: "转换方式:")
        caseLabel.translatesAutoresizingMaskIntoConstraints = false
        casePopup = NSPopUpButton()
        casePopup.addItems(withTitles: ["大写", "小写", "首字母大写", "不变"])
        casePopup.selectItem(at: 0)
        casePopup.target = self
        casePopup.action = #selector(casePopupChanged)
        casePopup.translatesAutoresizingMaskIntoConstraints = false

        caseContainer.addSubview(caseLabel)
        caseContainer.addSubview(casePopup)

        NSLayoutConstraint.activate([
            caseLabel.topAnchor.constraint(equalTo: caseContainer.topAnchor),
            caseLabel.leadingAnchor.constraint(equalTo: caseContainer.leadingAnchor),
            caseLabel.bottomAnchor.constraint(equalTo: caseContainer.bottomAnchor),

            casePopup.topAnchor.constraint(equalTo: caseContainer.topAnchor),
            casePopup.leadingAnchor.constraint(equalTo: caseLabel.trailingAnchor, constant: 8),
            casePopup.bottomAnchor.constraint(equalTo: caseContainer.bottomAnchor),
        ])

        // 预览表
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        previewTableView = NSTableView()
        previewTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        // 交替行底色会画到数据行以下，看起来像下面还排着 7 个空行（R4-12）；改用横向分隔线。
        previewTableView.usesAlternatingRowBackgroundColors = false
        previewTableView.gridStyleMask = .solidHorizontalGridLineMask
        previewTableView.rowHeight = 22
        previewTableView.dataSource = self
        previewTableView.delegate = self

        let oldCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("old"))
        oldCol.title = "原名称"
        oldCol.width = 300
        previewTableView.addTableColumn(oldCol)

        let newCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("new"))
        newCol.title = "新名称"
        newCol.width = 300
        previewTableView.addTableColumn(newCol)

        scrollView.documentView = previewTableView

        // 底部按钮栏
        let buttonBar = NSView()
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"  // Esc
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        renameButton = NSButton(title: "重命名", target: self, action: #selector(performRename))
        renameButton.bezelStyle = .rounded
        renameButton.keyEquivalent = "\r"  // Return
        renameButton.translatesAutoresizingMaskIntoConstraints = false

        // 只看冲突：三五百行的批量重命名里，红字散在表里根本找不到（R4-12）。
        onlyConflictsSwitch = NSButton(checkboxWithTitle: "只看冲突",
                                       target: self, action: #selector(onlyConflictsChanged))
        onlyConflictsSwitch.state = .off
        onlyConflictsSwitch.translatesAutoresizingMaskIntoConstraints = false

        // 图例：颜色含义必须写在界面上，不能只靠用户猜。
        conflictLegendLabel = NSTextField(labelWithString: "红字 = 名称冲突（悬停看原因）  橙字 = 扩展名将被改写")
        conflictLegendLabel.font = FFVisualTokens.Font.hint
        conflictLegendLabel.textColor = NSColor.secondaryLabelColor
        conflictLegendLabel.lineBreakMode = .byTruncatingTail
        conflictLegendLabel.translatesAutoresizingMaskIntoConstraints = false

        buttonBar.addSubview(cancelButton)
        buttonBar.addSubview(renameButton)
        buttonBar.addSubview(conflictLegendLabel)
        buttonBar.addSubview(onlyConflictsSwitch)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor),

            renameButton.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            renameButton.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor),
            renameButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),

            onlyConflictsSwitch.trailingAnchor.constraint(equalTo: renameButton.leadingAnchor, constant: -16),
            onlyConflictsSwitch.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),

            conflictLegendLabel.trailingAnchor.constraint(equalTo: onlyConflictsSwitch.leadingAnchor, constant: -12),
            conflictLegendLabel.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
            conflictLegendLabel.leadingAnchor.constraint(greaterThanOrEqualTo: buttonBar.leadingAnchor),
        ])

        // 整体布局
        contentView.addSubview(modeSegmentedControl)
        contentView.addSubview(patternContainer)
        contentView.addSubview(sequenceContainer)
        contentView.addSubview(caseContainer)
        contentView.addSubview(scrollView)
        contentView.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            modeSegmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            modeSegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            modeSegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            patternContainer.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 12),
            patternContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            patternContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            sequenceContainer.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 12),
            sequenceContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            sequenceContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            caseContainer.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 12),
            caseContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            caseContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: patternContainer.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor, constant: -12),

            buttonBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            buttonBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttonBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            buttonBar.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    // MARK: - Public API

    public func showWindow(selectedFiles: [FileEntry], paneViewModel: PaneViewModel?) {
        let fileCount = selectedFiles.filter { !$0.isDirectory }.count
        let ignoredFolders = selectedFiles.count - fileCount
        self.files = selectedFiles.filter { !$0.isDirectory }
        self.paneViewModel = paneViewModel
        window?.title = ignoredFolders > 0
            ? "批量重命名（已忽略 \(ignoredFolders) 个文件夹）"
            : "批量重命名"
        guard !files.isEmpty else {
            if let window {
                let alert = NSAlert()
                alert.messageText = "批量重命名"
                alert.informativeText = "所选项目中没有文件。批量重命名只处理文件，文件夹不会被改名。"
                alert.addButton(withTitle: "好")
                alert.beginSheetModal(for: window)
            }
            return
        }
        computeExistingNames()
        updatePreview()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 收集每个所选目录的现有文件名，用于冲突检测。
    /// 跨目录选择时必须逐目录判定：只看第一个文件的目录会把别的目录一起误报或漏报（R4-12）。
    /// 排除各目录中正在被重命名的原名（这些将被新名替换）。
    private func computeExistingNames() {
        existingNamesByDir = [:]
        for entry in files {
            let dir = directory(of: entry)
            guard existingNamesByDir[dir] == nil else { continue }
            let renamingOldNames = Set(files.filter { directory(of: $0) == dir }.map(\.name))
            var names = Set<String>()
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                for name in entries where !renamingOldNames.contains(name) {
                    names.insert(name)
                }
            }
            existingNamesByDir[dir] = names
        }
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: Any?) {
        let mode = selectedMode
        patternContainer.isHidden = (mode != .pattern)
        sequenceContainer.isHidden = (mode != .sequence)
        caseContainer.isHidden = (mode != .caseChange)
        updatePreview()
    }

    @objc private func patternFieldChanged(_ sender: Any?) {
        updatePreview()
    }

    @objc private func casePopupChanged(_ sender: Any?) {
        updatePreview()
    }

    @objc private func onlyConflictsChanged(_ sender: Any?) {
        rebuildVisibleIndices()
        previewTableView.reloadData()
    }

    @objc private func cancelClicked(_ sender: Any?) {
        close()
    }

    // MARK: - Pattern Engine

    /// 根据当前所选模式计算第 index 个文件的新名称
    private func computeNewName(for entry: FileEntry, index: Int) -> String {
        switch selectedMode {
        case .pattern:
            return applyPattern(patternField.stringValue, entry: entry, index: index)
        case .sequence:
            let start = Int(startIndexField.stringValue) ?? 1
            let step = Int(stepField.stringValue) ?? 1
            let num = start + index * step
            let prefix = prefixField.stringValue
            let suffix = suffixField.stringValue
            // 保留原始扩展名大小写（fileExtension 已 lowercased，会破坏 .JPG 等）
            let nsName = entry.name as NSString
            let origExt = nsName.pathExtension
            let ext = origExt.isEmpty ? "" : ".\(origExt)"
            return "\(prefix)\(num)\(suffix)\(ext)"
        case .caseChange:
            let option = casePopup.selectedItem?.title ?? ""
            // 仅对文件名（不含扩展名）应用大小写转换，保留扩展名原样
            let nsName = entry.name as NSString
            let stem = nsName.deletingPathExtension
            let origExt = nsName.pathExtension
            let casedStem = applyCaseChange(stem, caseOption: option)
            return origExt.isEmpty ? casedStem : "\(casedStem).\(origExt)"
        }
    }

    /// 模式替换占位符：
    /// - {name} 文件名（不含扩展名）
    /// - {ext} 扩展名（不含点，小写）
    /// - {index} 序号从 1 开始
    /// - {index0} 序号从 0 开始
    /// - {index:N} 零填充 N 位（如 {index:3} -> 001, 002, ...）
    ///
    /// 注意：先处理 {index:N}，再处理 {index} 和 {index0}，否则 {index:3}
    /// 会先被 {index} 部分替换为 "1:3" 而破坏后续正则匹配。
    /// {index:N} 使用安全的「先收集所有匹配，再倒序替换」方式，避免在
    /// enumerateMatches 中修改字符串造成的索引错位。
    private func applyPattern(_ pattern: String, entry: FileEntry, index: Int) -> String {
        FFBatchRenamePattern.apply(pattern, entry: entry, index: index)
    }

    private func applyCaseChange(_ name: String, caseOption: String) -> String {
        switch caseOption {
        case CaseOption.upper.rawValue:
            return name.uppercased()
        case CaseOption.lower.rawValue:
            return name.lowercased()
        case CaseOption.capitalized.rawValue:
            return name.capitalized
        default:
            return name
        }
    }

    // MARK: - Preview

    /// 重新计算所有新名称并刷新预览表。任何输入变化都应调用此方法。
    private func updatePreview() {
        previewNames = files.indices.map { computeNewName(for: files[$0], index: $0) }
        computeConflictReasons()
        computeExtensionWarnings()
        rebuildVisibleIndices()
        previewTableView.reloadData()

        let hasConflict = conflictReasons.contains { $0 != nil }
        let hasAnyChange = files.indices.contains { i in
            previewNames[i] != files[i].name && !previewNames[i].isEmpty
        }
        renameButton.isEnabled = !hasConflict && hasAnyChange && !files.isEmpty
        updateLegend()
    }

    /// 图例给出结论 + 颜色含义：勾了「只看冲突」却一场冲突都没有时表格会整片空掉，
    /// 没有「无冲突」这句结论，空表看起来就像又一次静默失效（R4-12）。
    private func updateLegend() {
        let conflicts = conflictReasons.compactMap { $0 }
        conflictLegendLabel.stringValue = conflicts.isEmpty
            ? "无冲突  橙字 = 扩展名将被改写"
            : "\(conflicts.count) 处冲突（红字，悬停看原因）  橙字 = 扩展名将被改写"
    }

    /// 逐行给出冲突原因（R4-12）。重名只在同一目录内互撞才算冲突。
    private func computeConflictReasons() {
        var reasons = [String?](repeating: nil, count: files.count)
        for i in files.indices {
            let newName = previewNames[i]
            if newName.isEmpty {
                reasons[i] = "新名称为空"
                continue
            }
            let dir = directory(of: files[i])
            let rivals = files.indices.filter {
                $0 != i && previewNames[$0] == newName && directory(of: files[$0]) == dir
            }
            if !rivals.isEmpty {
                let involved = ([i] + rivals).map { files[$0].name }.sorted()
                reasons[i] = "与「\(involved.joined(separator: "」「"))」改成了同一个名字：\(newName)"
                continue
            }
            if existingNamesByDir[dir, default: []].contains(newName) {
                reasons[i] = "目录里已有「\(newName)」"
            }
        }
        conflictReasons = reasons
    }

    /// 扩展名被改写（如 {name}.{ext}text 产出 .pytext）只提示，不拦下执行（R4-12）。
    private func computeExtensionWarnings() {
        extensionWarnings = files.indices.map { i in
            let oldExt = (files[i].name as NSString).pathExtension
            let newExt = (previewNames[i] as NSString).pathExtension
            guard oldExt != newExt else { return nil }
            switch (oldExt.isEmpty, newExt.isEmpty) {
            case (true, false): return "将新增扩展名：\(newExt)"
            case (false, true): return "将去掉扩展名：\(oldExt)"
            default: return "扩展名将从 \(oldExt) 变为 \(newExt)"
            }
        }
    }

    /// 默认显示全部行；勾选「只看冲突」后只留下需要处理的行。
    private func rebuildVisibleIndices() {
        let conflictOnly = onlyConflictsSwitch.state == .on
        visibleIndices = conflictOnly
            ? files.indices.filter { conflictReasons[$0] != nil }
            : Array(files.indices)
    }

    // MARK: - Perform Rename

    @objc private func performRename(_ sender: Any?) {
        var items: [(String, String)] = []
        for (i, entry) in files.enumerated() {
            let newName = previewNames[i]
            if newName != entry.name && !newName.isEmpty {
                items.append((entry.path, newName))
            }
        }

        guard !items.isEmpty else {
            close()
            return
        }

        // 在跳到后台线程前，先收集成功后用于撤销的反向重命名对
        let reverseItems: [(String, String)] = items.map { (oldPath, newName) -> (String, String) in
            let dir = (oldPath as NSString).deletingLastPathComponent
            let newPath = (dir as NSString).appendingPathComponent(newName)
            let oldName = (oldPath as NSString).lastPathComponent
            return (newPath, oldName)  // 从新路径 rename 回旧名
        }

        renameButton.isEnabled = false

        let taskID = "rename-\(UUID().uuidString)"
        FFTaskService.shared.upsert(FFTask(id: taskID, title: "批量重命名",
                                           detail: "\(items.count) 个项目",
                                           completedBytes: 0, totalBytes: Int64(items.count),
                                           state: .running, startedAt: Date(),
                                           locationPath: paneViewModel?.state.path))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let success = try CoreBridge.shared.batchRename(items: items)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    var task = FFTaskService.shared.tasks.first(where: { $0.id == taskID })
                        ?? FFTask(id: taskID, title: "批量重命名", detail: "",
                                  completedBytes: 0, totalBytes: Int64(items.count),
                                  state: .running, startedAt: Date())
                    task.completedBytes = Int64(success)
                    task.state = success == items.count ? .finished : .failed("部分项目重命名失败")
                    FFTaskService.shared.upsert(task)

                    // 刷新面板：refresh() 内部异步失效缓存后再重读目录。
                    self.paneViewModel?.refresh()
                    self.registerUndoForBatchRename(items: items, reverseItems: reverseItems)
                    if success < items.count {
                        // 部分失败：提示用户但仍注册撤销（undo 用 try? 跳过失败项）
                        self.showPartialFailure(success: success, total: items.count)
                    } else {
                        self.close()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.renameButton.isEnabled = true
                    if var task = FFTaskService.shared.tasks.first(where: { $0.id == taskID }) {
                        task.state = .failed(error.localizedDescription)
                        FFTaskService.shared.upsert(task)
                    }
                    self.showError(error: error)
                }
            }
        }
    }

    // MARK: - Undo

    private func registerUndoForBatchRename(
        items: [(String, String)],
        reverseItems: [(String, String)]
    ) {
        guard let vm = paneViewModel, let undoManager = vm.undoManager else { return }
        let count = items.count
        let actionName = "批量重命名 \(count) 个项目"

        // 注册撤销：反向 rename（从新路径改回旧名）。undoBatchRename 会同步注册 redo（redoBatchRename），
        // 而 redoBatchRename 处理器内又会注册反向 undo（= undoBatchRename），
        // 从而形成无限撤销/重做闭环。
        undoManager.registerUndo(withTarget: self) { [weak self] ctrl in
            ctrl.undoBatchRename(items: items, reverseItems: reverseItems, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// 撤销"批量重命名"：从新路径改回旧名，并同步注册 redo（redoBatchRename）。
    /// redoBatchRename 处理器内又会注册反向 undo（= undoBatchRename），从而形成无限撤销/重做闭环：
    /// 撤销→重做→撤销→重做…可无限进行。文件操作经 undoRedoQueue 串行化，排队在上一操作之后，避免竞态。
    private func undoBatchRename(items: [(String, String)], reverseItems: [(String, String)], actionName: String) {
        guard let undoManager = paneViewModel?.undoManager else { return }
        // 必须先注册 redo 再排队文件操作：registerUndo 在撤销会话内（isUndoing）会路由到 redo 栈，
        // 而文件操作异步执行，需先建立 redo 栈再排队，否则重做栈可能为空。
        undoManager.registerUndo(withTarget: self) { [weak self] ctrl in
            ctrl.redoBatchRename(items: items, reverseItems: reverseItems, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        MainWindowController.undoRedoQueue.async { [weak self] in
            for (newPath, oldName) in reverseItems {
                let dir = (newPath as NSString).deletingLastPathComponent
                let restorePath = (dir as NSString).appendingPathComponent(oldName)
                try? CoreBridge.shared.renameFile(src: newPath, dst: restorePath)
            }
            if let firstNew = reverseItems.first?.0 {
                let dir = (firstNew as NSString).deletingLastPathComponent
                try? CoreBridge.shared.invalidateCache(path: dir)
            }
            DispatchQueue.main.async {
                self?.paneViewModel?.refresh()
            }
        }
    }

    /// 重做"批量重命名"：再次从旧名改到新名（与初始重命名相同）。
    /// 处理器内同步注册反向 undo（undoBatchRename，路由到 undo 栈，isRedoing == true），
    /// 从而形成无限撤销/重做闭环。
    private func redoBatchRename(items: [(String, String)], reverseItems: [(String, String)], actionName: String) {
        guard let undoManager = paneViewModel?.undoManager else { return }
        // 先注册反向 undo 再排队文件操作：registerUndo 在重做会话内（isRedoing）路由到 undo 栈。
        undoManager.registerUndo(withTarget: self) { [weak self] ctrl in
            ctrl.undoBatchRename(items: items, reverseItems: reverseItems, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        MainWindowController.undoRedoQueue.async { [weak self] in
            for (oldPath, newName) in items {
                let dir = (oldPath as NSString).deletingLastPathComponent
                let newPath = (dir as NSString).appendingPathComponent(newName)
                try? CoreBridge.shared.renameFile(src: oldPath, dst: newPath)
            }
            if let firstOld = items.first?.0 {
                let dir = (firstOld as NSString).deletingLastPathComponent
                try? CoreBridge.shared.invalidateCache(path: dir)
            }
            DispatchQueue.main.async {
                self?.paneViewModel?.refresh()
            }
        }
    }

    // MARK: - Helpers

    private func showError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "批量重命名失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        if let window = window { alert.beginSheetModal(for: window) { _ in } }
    }

    private func showPartialFailure(success: Int, total: Int) {
        let alert = NSAlert()
        alert.messageText = "部分文件重命名失败"
        alert.informativeText = "成功 \(success) / 总计 \(total)。失败项可能因权限不足或路径无效。可通过 ⌘Z 撤销已成功的重命名。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭")
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] _ in
                self?.close()
            }
        }
    }
}

// MARK: - NSTextFieldDelegate / NSControlTextEditingDelegate

extension BatchRenameWindowController: NSTextFieldDelegate, NSControlTextEditingDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        updatePreview()
    }
}

// MARK: - NSTableViewDataSource

extension BatchRenameWindowController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleIndices.count
    }
}

// MARK: - NSTableViewDelegate

extension BatchRenameWindowController: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let columnID = tableColumn?.identifier.rawValue ?? "old"
        let cellID = NSUserInterfaceItemIdentifier("\(columnID)_cell")
        let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = cellID

        if cellView.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(tf)
            cellView.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        guard row >= 0, row < visibleIndices.count else { return cellView }
        let index = visibleIndices[row]
        let entry = files[index]

        switch columnID {
        case "old":
            cellView.textField?.stringValue = entry.name
            cellView.textField?.textColor = NSColor.labelColor
            cellView.textField?.toolTip = nil
        case "new":
            cellView.textField?.stringValue = index < previewNames.count ? previewNames[index] : ""
            let reason = conflictReason(at: index)
            let warning = extensionWarning(at: index)
            if reason != nil {
                cellView.textField?.textColor = NSColor.systemRed
            } else if warning != nil {
                cellView.textField?.textColor = NSColor.systemOrange
            } else {
                cellView.textField?.textColor = NSColor.labelColor
            }
            // 颜色之外必须说出原因，否则用户只知道有问题、不知道改哪里（R4-12）。
            cellView.textField?.toolTip = reason ?? warning
        default:
            break
        }

        return cellView
    }
}
