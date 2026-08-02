import Cocoa
import Combine

// MARK: - FileGridCollectionViewItem

class FileGridCollectionViewItem: NSCollectionViewItem {
    private var thumbnailImageView: NSImageView!
    /// 名称标签：内联重命名时需设为可编辑并获取焦点（与 FileListView 一致）。
    /// 设为 internal 以便 FileGridView.beginInlineRename() 访问。
    var nameLabel: NSTextField!
    private var pathLabel: NSTextField!
    /// 标签药丸容器（横向排列，位于文件名下方）
    private var tagPillContainer: NSStackView!

    /// 标签移除回调（tagName, path），由 FileGridView 设置
    var onRemoveTag: ((String, String) -> Void)?

    /// 任务 F10-9: 记录该 item 当前显示文件的完整路径（F8 遗漏修复，v0.6.6）。
    /// 用于缩略图异步回调时校验 item 仍显示同一文件（避免旧请求覆盖新 item），
    /// 以及 prepareForReuse 取消上一次未完成的缩略图请求。
    /// 注意：不能用 item.identifier 记录路径--identifier 用于 NSCollectionView
    /// 的复用匹配，覆写会破坏 item 复用机制（与 FileListView FFTableCellView 对称）。
    private var currentPath: String?

    /// 任务 F11-7: 标记是否已收到缩略图。
    /// 工作区图标回调若在此之后返回则跳过覆盖（缩略图优先级更高，避免用工作区图标盖掉缩略图）。
    /// entry 重新绑定 / prepareForReuse 时复位。
    private var didReceiveThumbnail: Bool = false

    var entry: FileEntry? {
        didSet {
            guard let entry = entry else { return }
            // v0.6.9: 根据 showFileExtensions 设置决定是否显示文件后缀
            let showExtensions = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileExtensions) as? Bool ?? true
            nameLabel.stringValue = showExtensions ? entry.name : entry.displayName
            pathLabel.stringValue = entry.path
            // 任务 F11-7: 复位缩略图标志（item 重新绑定文件）
            didReceiveThumbnail = false

            // 设置图标
            if entry.isDirectory {
                // 任务 F10-9: 目录不加载缩略图，清除路径标记避免旧回调误覆盖目录图标
                currentPath = nil
                // 任务 F11-7: 目录图标也走缓存（避免每次都构造 SF Symbol）
                if let cached = ThumbnailManager.shared.cachedWorkspaceIcon(for: entry.path, pointSize: 48) {
                    thumbnailImageView.image = cached
                } else {
                    let placeholder = NSImage(systemSymbolName: "folder", accessibilityDescription: "文件夹")
                        ?? NSImage(named: NSImage.folderName)
                    thumbnailImageView.image = placeholder
                    ThumbnailManager.shared.fetchWorkspaceIcon(for: entry.path, pointSize: 48) { [weak self] image in
                        guard let self = self, self.currentPath == nil else { return }
                        if let image = image { self.thumbnailImageView.image = image }
                    }
                }
            } else {
                // 任务 F10-9: 缩略图复用校验（F8 遗漏修复，v0.6.6）
                // 1) 取消该 item 上一次的缩略图请求（避免旧请求覆盖新 item）
                // 2) 更新 currentPath 标记，回调中校验 item 仍显示同一文件
                // 3) 先显示占位图标，缩略图返回后再替换
                let path = entry.path
                if let oldPath = currentPath, oldPath != path {
                    ThumbnailManager.shared.cancelGeneration(for: oldPath)
                }
                currentPath = path

                // 任务 F11-7: 占位图标优先用缓存的工作区图标（比 SF Symbol 更接近最终视觉），
                // 缓存未命中再用通用 doc 符号，并后台异步获取真实工作区图标作为缩略图返回前的过渡。
                // 这样即使缩略图生成慢，用户也能快速看到正确的文件类型图标而非通用 doc。
                let placeholderPointSize: CGFloat = 48
                if let cachedIcon = ThumbnailManager.shared.cachedWorkspaceIcon(for: path, pointSize: placeholderPointSize) {
                    thumbnailImageView.image = cachedIcon
                } else {
                    thumbnailImageView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
                        ?? NSImage(named: NSImage.multipleDocumentsName)
                    // 后台异步获取真实工作区图标作为过渡（缩略图返回前先显示真实类型图标）
                    ThumbnailManager.shared.fetchWorkspaceIcon(for: path, pointSize: placeholderPointSize) { [weak self] image in
                        guard let self = self, self.currentPath == path else { return }
                        if let image = image {
                            // 缩略图优先级更高：若缩略图已返回则不覆盖
                            guard !self.didReceiveThumbnail else { return }
                            self.thumbnailImageView.image = image
                        }
                    }
                }

                // 使用 ThumbnailManager 获取缩略图
                ThumbnailManager.shared.generateThumbnail(path: path, size: CGSize(width: 96, height: 96)) { [weak self] image in
                    guard let self = self else { return }
                    // 校验 item 仍显示同一文件（用完整路径而非文件名）
                    guard self.currentPath == path else { return }
                    // 任务 F11-7: 标记已收到缩略图，阻止后续工作区图标回调覆盖
                    self.didReceiveThumbnail = true
                    if let image = image {
                        self.thumbnailImageView.image = image
                    } else {
                        self.thumbnailImageView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
                            ?? NSImage(named: NSImage.multipleDocumentsName)
                    }
                }
            }

            // 隐藏文件灰色
            if entry.isHidden {
                nameLabel.textColor = NSColor.tertiaryLabelColor
            } else if entry.isSystemProtected {
                nameLabel.textColor = NSColor.systemRed
            } else {
                nameLabel.textColor = NSColor.labelColor
            }

            // 配置标签药丸（文件名下方）
            configureTagPills()
        }
    }

    /// 任务 F10-9: 复用时取消上一次未完成的缩略图请求并重置标记（F8 遗漏修复，v0.6.6）。
    /// NSCollectionView 复用 item 前会调用 prepareForReuse，此时若不取消旧请求，
    /// 旧请求回调可能在新 item 已绑定其他文件后才返回，覆盖新 item 的图标。
    override func prepareForReuse() {
        super.prepareForReuse()
        // 取消上一次未完成的缩略图请求
        if let oldPath = currentPath {
            ThumbnailManager.shared.cancelGeneration(for: oldPath)
        }
        currentPath = nil
        // 任务 F11-7: 复位缩略图标志
        didReceiveThumbnail = false
        // 重置图标，避免复用瞬间显示上一个文件的缩略图
        thumbnailImageView.image = nil
        // 重置选中背景（防止复用 item 残留选中样式）
        view.layer?.backgroundColor = NSColor.clear.cgColor
        // squircle 圆角：0 时自动移除 mask（SquircleMaskedView）
        (view as? SquircleMaskedView)?.squircleRadius = 0
        // 清除旧标签药丸
        tagPillContainer?.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    override func loadView() {
        // 高度从 120 增至 140，为标签药丸行预留空间
        let view = SquircleMaskedView(frame: NSRect(x: 0, y: 0, width: 120, height: 140))
        view.wantsLayer = true

        thumbnailImageView = NSImageView()
        thumbnailImageView.imageScaling = .scaleProportionallyDown
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.alignment = .center
        nameLabel.maximumNumberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel = NSTextField(labelWithString: "")
        pathLabel.isHidden = true
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        // 标签药丸容器（横向排列，位于文件名下方）
        tagPillContainer = NSStackView()
        tagPillContainer.orientation = .horizontal
        tagPillContainer.alignment = .centerY
        tagPillContainer.spacing = 4
        tagPillContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(thumbnailImageView)
        view.addSubview(nameLabel)
        view.addSubview(pathLabel)
        view.addSubview(tagPillContainer)

        NSLayoutConstraint.activate([
            thumbnailImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnailImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),

            // 标签药丸位于文件名下方 4pt，水平居中
            tagPillContainer.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            tagPillContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 4),
            tagPillContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -4),
            tagPillContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tagPillContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4),
        ])

        self.view = view
    }

    override var isSelected: Bool {
        didSet {
            // 任务 F10-9: 访达风格实心蓝半透明选中（v0.6.6）
            // alpha 0.15->0.25 增强可见性（问题10），圆角 6->8 与访达网格一致
            view.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                : NSColor.clear.cgColor
            // squircle 圆角（选中 8，未选中 0 自动移除 mask）
            (view as? SquircleMaskedView)?.squircleRadius = isSelected ? 8 : 0
        }
    }

    // MARK: - Tag Pills（标签药丸）

    /// 配置标签药丸（文件名下方显示，最多 3 个 + "+N"）
    /// 药丸不响应左键点击，右键可弹出移除标签菜单
    private func configureTagPills() {
        guard let entry = entry else { return }
        // v0.6.9: 根据 showFileTags 设置决定是否显示标签药丸
        let showTags = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileTags) as? Bool ?? true
        if !showTags {
            tagPillContainer.isHidden = true
            return
        }
        // 清除旧药丸
        tagPillContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let tags = TagBridge.shared.getTags(path: entry.path)
        if tags.isEmpty {
            tagPillContainer.isHidden = true
            return
        }
        tagPillContainer.isHidden = false
        for tag in tags.prefix(3) {
            if let pill = makeTagPill(tag: tag) {
                // 每个药丸独立右键菜单：右键任意位置 → "移除标签"（仅移除该文件的此标签）
                let menu = NSMenu()
                menu.autoenablesItems = false
                let item = NSMenuItem(title: "移除标签", action: #selector(removeTagFromGrid(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["tagName": tag.name, "path": entry.path]
                menu.addItem(item)
                pill.menu = menu
                tagPillContainer.addArrangedSubview(pill)
            }
        }
        if tags.count > 3 {
            if let countPill = makeCountPill(count: tags.count - 3) {
                tagPillContainer.addArrangedSubview(countPill)
            }
        }
    }

    /// 右键移除标签回调
    @objc private func removeTagFromGrid(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagName = info["tagName"],
              let path = info["path"] else { return }
        onRemoveTag?(tagName, path)
    }

    /// 创建单个标签药丸（与 FileListView 样式一致）
    private func makeTagPill(tag: Tag) -> NSView? {
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        let tagColor = NSColor(hex: tag.color) ?? .systemBlue
        pill.layer?.backgroundColor = tagColor.withAlphaComponent(0.15).cgColor
        pill.squircleRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(dot)

        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 18),
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        return pill
    }

    /// 创建 "+N" 计数药丸（无圆点，仅文字）
    private func makeCountPill(count: Int) -> NSView? {
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        if #available(macOS 14.0, *) {
            pill.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor
        } else {
            pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
        pill.squircleRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "+\(count)")
        label.font = NSFont.systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        return pill
    }
}

// MARK: - FFGridSectionHeaderView

/// 任务 F10-8: 网格视图分组标题补充视图。
/// 仿访达网格视图分组：浅灰背景、小字号标题（分组名 + 数量）。
private final class FFGridSectionHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // 任务 F11-5: 计数徽章（与列表视图样式一致：次级字号 + 三级标签色，无括号）
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = NSColor.tertiaryLabelColor
        countLabel.backgroundColor = .clear
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // 浅灰背景（次级填充色，仿访达网格分组标题）
        if #available(macOS 14.0, *) {
            NSColor.tertiarySystemFill.setFill()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.6).setFill()
        }
        dirtyRect.fill()
        // 任务 F11-5: 底部分隔线（与列表视图分组标题一致）
        if #available(macOS 14.0, *) {
            NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        } else {
            NSColor.gridColor.withAlphaComponent(0.5).setFill()
        }
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
        super.draw(dirtyRect)
    }

    /// 设置标题文本（分组名 + 数量徽章，与列表视图样式一致）
    func configure(title: String, count: Int) {
        titleLabel.stringValue = title
        countLabel.stringValue = count > 0 ? "\(count)" : ""
    }
}

// MARK: - DraggingCollectionView

/// 自定义 NSCollectionView 子类：覆盖拖拽源操作掩码，支持同卷移动/跨卷复制
private class DraggingCollectionView: NSCollectionView {
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move, .delete]
    }
}

// MARK: - FileGridView

/// NSCollectionView-based grid view with thumbnails
public class FileGridView: NSView {
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var cancellables = Set<AnyCancellable>()

    private var lastFilesCount: Int = -1

    // 任务 F10-8: 分组渲染缓存。
    // - displayEntries: 按分组顺序拼接的所有文件条目（与各 section item 顺序一致）
    // - sectionKeys: 每个 section 的分组名（与 displayEntries 的 section 切片对应）
    // - sectionStarts: 每个 section 在 displayEntries 中的起始下标（用于 indexPath -> flatIndex 映射）
    // groupBy == "none" 时为单 section（无分组标题），displayEntries == viewModel.files 顺序
    private var displayEntries: [FileEntry] = []
    private var sectionKeys: [String] = []
    private var sectionStarts: [Int] = []

    // 任务 F10-8: 上次刷新记录的分组维度（检测变化决定是否刷新）
    private var currentGroupBy: String = "none"
    private var currentSortField: SortField = .name
    private var currentSortAscending: Bool = true

    // 任务 F10-8: reload 期间标志位，防止 restoreSelection -> didSelectItemsAt ->
    // state.selectedFiles 变更 -> @Published 发射形成循环（与 FileListView.isReloading 对称）
    private var isReloading: Bool = false

    public var viewModel: PaneViewModel? {
        didSet {
            // 清空旧订阅，防止累积泄漏
            cancellables.removeAll()
            collectionView.dataSource = self
            collectionView.delegate = self
            // 任务 F10-8: 初始构建分组缓存
            rebuildDisplayEntries()
            viewModel?.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    // 任务 F10-8: files 数量变化 / 分组维度变化 / 排序变化时刷新
                    let needReload = self.lastFilesCount != state.files.count
                        || self.currentGroupBy != state.groupBy
                        || self.currentSortField != state.sortField
                        || self.currentSortAscending != state.sortAscending
                    if needReload {
                        self.lastFilesCount = state.files.count
                        self.currentGroupBy = state.groupBy
                        self.currentSortField = state.sortField
                        self.currentSortAscending = state.sortAscending
                        self.reloadData()
                    }
                }
                .store(in: &cancellables)
            reloadData()
        }
    }

    /// 任务 F10-8: 根据 viewModel.groupedFiles 重建分组缓存。
    /// 将各分组的 entries 按顺序拼接为 displayEntries，并记录每个 section 的起始下标。
    private func rebuildDisplayEntries() {
        guard let viewModel = viewModel else {
            displayEntries = []
            sectionKeys = []
            sectionStarts = []
            return
        }
        let groups = viewModel.groupedFiles
        var entries: [FileEntry] = []
        var keys: [String] = []
        var starts: [Int] = []
        for group in groups {
            keys.append(group.key)
            starts.append(entries.count)
            entries.append(contentsOf: group.entries)
        }
        displayEntries = entries
        sectionKeys = keys
        sectionStarts = starts

        // 任务 F10-8: groupBy == "none" 时隐藏分组标题（headerReferenceSize = 0），
        // 避免网格顶部出现 24pt 空白标题条；分组时恢复 24pt 标题高度。
        if let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout {
            let newSize: CGFloat = (viewModel.state.groupBy == "none") ? 0 : 24
            if layout.headerReferenceSize.height != newSize {
                layout.headerReferenceSize = NSSize(width: 0, height: newSize)
                // invalidateLayout 确保 layout 重新计算（headerReferenceSize 变化需失效缓存）
                layout.invalidateLayout()
            }
        }
    }

    /// 任务 F10-8: indexPath -> displayEntries 中的扁平下标
    private func flatIndex(for indexPath: IndexPath) -> Int {
        guard indexPath.section < sectionStarts.count else { return indexPath.item }
        return sectionStarts[indexPath.section] + indexPath.item
    }

    /// 任务 F10-8: displayEntries 扁平下标 -> (section, item)
    private func indexPath(forFlatIndex flatIndex: Int) -> IndexPath {
        guard !sectionStarts.isEmpty else { return IndexPath(item: flatIndex, section: 0) }
        // 找到最后一个 sectionStarts[s] <= flatIndex 的 section
        var section = 0
        for (s, start) in sectionStarts.enumerated() where start <= flatIndex {
            section = s
        }
        let item = flatIndex - sectionStarts[section]
        return IndexPath(item: item, section: section)
    }

    /// 对侧面板的 ViewModel（由 MainWindowController 在 setupUI 中注入），
    /// 用于拖拽 undo/redo 后刷新对侧面板（跨面板拖拽时源面板需同步更新）
    weak var counterpartViewModel: PaneViewModel?

    /// 面板方向（由 MainWindowController 注入），用于右键菜单"移动/复制到另一面板"的箭头方向。
    /// 与 FileListView.panelSide 对称（P0#7 修复）。
    /// 注：PaneSide 为 internal 类型，故此属性为 internal（同模块内可访问）
    var panelSide: PaneSide?

    /// 当前面板方向（优先使用 panelSide，否则根据 identifier 推断）
    private var effectiveSide: PaneSide {
        if let panelSide = panelSide { return panelSide }
        return identifier?.rawValue == "right" ? .right : .left
    }

    // 内联重命名状态（P0#1 修复：与 FileListView 对齐）
    private var renamingIndexPath: IndexPath?
    private var renamingOriginalName: String = ""
    private var renamingPath: String = ""
    private weak var renamingTextField: NSTextField?
    private var renameCancelled: Bool = false

    /// 标签二级菜单（动态构建：每次显示前由 NSMenuDelegate 重建内容）
    private lazy var tagsSubmenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    public var onDoubleClick: ((FileEntry) -> Void)?
    public var onSelectionChanged: (([FileEntry]) -> Void)?
    /// 点击 item 时激活面板（与 FileListView 一致）
    public var onActivatePane: (() -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // 任务 F11-1: 操作区实体背景（v0.6.7）
        // 此前为透明背景透出 NSVisualEffectView 玻璃态；现改为实体（日间#F5F5F5/夜间#2D2D2D），
        // 与 MainWindowController.createPaneContainer 的容器实体背景一致，
        // 实体背景上选中蓝色清晰可见（解决 v0.6.6 问题14 的最终方案）
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear

        // 任务 F10-8: 改用 NSCollectionViewFlowLayout 以支持分组 section header（补充视图）。
        // NSCollectionViewGridLayout 不支持补充视图，无法渲染分组标题。
        // FlowLayout 横向排列填满一行后换行，与网格视觉效果一致，且支持 headerReferenceSize。
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 120, height: 140)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        // 分组标题高度（仿访达网格视图分组标题）
        layout.headerReferenceSize = NSSize(width: 0, height: 24)

        collectionView = DraggingCollectionView()
        collectionView.collectionViewLayout = layout
        // 任务 F11-1: collectionView 实体背景（v0.6.7）
        // 配合操作区容器实体背景，不再透明。实体背景上选中蓝色清晰可见（解决 v0.6.6 问题14 的最终方案）
        let isDark = ThemeManager.shared.resolvedIsDark
        collectionView.backgroundColors = [isDark
            ? NSColor(srgbRed: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D
            : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)]  // #F5F5F5
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.isSelectable = true
        collectionView.dataSource = self
        collectionView.delegate = self

        // 注册 item
        collectionView.register(FileGridCollectionViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("GridItem"))
        // 任务 F10-8: 注册分组标题补充视图。
        // 使用 NSCollectionView.elementKindSectionHeader（Swift 名称，macOS 11+）。
        collectionView.register(FFGridSectionHeaderView.self,
                                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: NSUserInterfaceItemIdentifier("GridSectionHeader"))

        scrollView.documentView = collectionView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 注册为拖拽目标（接收拖入的文件 URL）
        registerForDraggedTypes([.fileURL])

        setupContextMenu()
    }

    // MARK: - Context Menu

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // 1. 打开
        menu.addItem(withTitle: "打开", action: #selector(openSelected(_:)), keyEquivalent: "")
        // 2. 分隔线
        menu.addItem(.separator())
        // 3. 复制
        let copyItem = menu.addItem(withTitle: "复制", action: #selector(copySelected(_:)), keyEquivalent: "c")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
        // 4. 剪切
        let cutItem = menu.addItem(withTitle: "剪切", action: #selector(cutSelected(_:)), keyEquivalent: "x")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "剪切")
        // 5. 粘贴
        let pasteItem = menu.addItem(withTitle: "粘贴", action: #selector(pasteSelected(_:)), keyEquivalent: "v")
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "粘贴")
        // 6. 分隔线
        menu.addItem(.separator())
        // 7. 移动到另一面板
        let moveItem = menu.addItem(withTitle: "移动到另一面板", action: #selector(moveToOtherPane(_:)), keyEquivalent: "")
        moveItem.image = NSImage(systemSymbolName: effectiveSide == .left ? "arrow.right" : "arrow.left",
                                 accessibilityDescription: "移动到另一面板")
        // 8. 复制到另一面板
        let copyOtherItem = menu.addItem(withTitle: "复制到另一面板", action: #selector(copyToOtherPane(_:)), keyEquivalent: "")
        copyOtherItem.image = NSImage(systemSymbolName: effectiveSide == .left ? "arrow.right.square" : "arrow.left.square",
                                      accessibilityDescription: "复制到另一面板")
        // 9. 在对侧面板打开
        let openOtherItem = menu.addItem(withTitle: "在对侧面板打开", action: #selector(openInOtherPane(_:)), keyEquivalent: "")
        openOtherItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "在对侧面板打开")
        openOtherItem.isHidden = true
        // 10. 分隔线
        menu.addItem(.separator())
        // 11. 重命名
        let renameItem = menu.addItem(withTitle: "重命名", action: #selector(renameSelected(_:)), keyEquivalent: "")
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "重命名")
        // 12. 移到废纸篓（红色文字）
        let deleteItem = menu.addItem(withTitle: "移到废纸篓", action: #selector(deleteSelected(_:)), keyEquivalent: "\u{7F}")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "移到废纸篓")
        let redAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        deleteItem.attributedTitle = NSAttributedString(string: "移到废纸篓", attributes: redAttrs)
        // 13. 分隔线
        menu.addItem(.separator())
        // 14. 新建文件夹
        let newFolderItem = menu.addItem(withTitle: "新建文件夹", action: #selector(createDirectory(_:)), keyEquivalent: "n")
        newFolderItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "新建文件夹")
        // 15. 分隔线
        menu.addItem(.separator())
        // 16. 添加到我的收藏
        let favItem = menu.addItem(withTitle: "添加到我的收藏", action: #selector(addToFavorites(_:)), keyEquivalent: "")
        favItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: "添加到我的收藏")
        // 17. 标签（二级子菜单）
        let tagsItem = menu.addItem(withTitle: "标签", action: nil, keyEquivalent: "")
        tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "标签")
        tagsItem.submenu = tagsSubmenu
        // 18. AI 自动打标签
        let aiTagItem = menu.addItem(withTitle: "AI 自动打标签", action: #selector(generateAITags(_:)), keyEquivalent: "")
        aiTagItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 自动打标签")
        // 19. 查重扫描
        let dupItem = menu.addItem(withTitle: "查重扫描", action: #selector(duplicateScan(_:)), keyEquivalent: "")
        dupItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "查重扫描")
        // 20. 分隔线
        menu.addItem(.separator())
        // 21. 显示简介
        let infoItem = menu.addItem(withTitle: "显示简介", action: #selector(showInfoMenu(_:)), keyEquivalent: "i")
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")

        for item in menu.items where item.action != nil {
            item.target = self
            if item.keyEquivalent == "n" {
                item.keyEquivalentModifierMask = [.command, .shift]
            } else if !item.keyEquivalent.isEmpty {
                item.keyEquivalentModifierMask = .command
            }
        }
        collectionView.menu = menu
    }

    // MARK: - Context Menu Helpers

    private var clickedEntry: FileEntry? {
        // Bug 4 修复：NSEvent.mouseLocation 返回的是屏幕坐标（NSScreen 系），
        // 而 convert(_:from:nil) 期望窗口坐标。坐标系不匹配会导致 indexPath 解析错误。
        // 改用当前事件的 locationInWindow（窗口坐标），再转换到 collectionView 坐标系。
        guard let event = NSApp.currentEvent else { return nil }
        let point = collectionView.convert(event.locationInWindow, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return nil }
        // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
        let flatIdx = flatIndex(for: indexPath)
        guard flatIdx < displayEntries.count else { return nil }
        return displayEntries[flatIdx]
    }

    private func getSide() -> String {
        return identifier?.rawValue ?? "left"
    }

    private func showError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        if let window = window { alert.beginSheetModal(for: window) { _ in } }
    }

    // MARK: - Keyboard (P0#1 修复：与 FileListView.keyDown 对齐)

    /// 重写 keyDown：Enter/Return 触发内联重命名，空格触发 QuickLook 预览，
    /// Cmd+Down/Cmd+O 打开选中项，Cmd+Up 上级目录（macOS Finder 风格）。
    /// 此前 FileGridView 无 keyDown 重写，按 Enter 无响应（P0#1）。
    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // Space：QuickLook 预览（交由 MainWindowController 处理）
        if event.keyCode == 49 && modifiers.isEmpty {
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": getSide()])
            return
        }

        // Enter / Return：触发内联重命名（拦截事件，不再沿响应链传递）
        // macOS Finder 风格：Enter=重命名，Cmd+O/Cmd+Down=打开
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
            beginInlineRename()
            return
        }

        // Cmd+Down (keyCode 125) / Cmd+O (keyCode 31) 打开选中项（Finder 风格）
        let isPureCommand = modifiers.contains(.command)
            && !modifiers.contains(.shift)
            && !modifiers.contains(.option)
            && !modifiers.contains(.control)
        if isPureCommand && (event.keyCode == 125 || event.keyCode == 31) {
            openSelectedEntry()
            return
        }

        // Cmd+Up (keyCode 126) 上级目录（Finder 风格）
        if isPureCommand && event.keyCode == 126 {
            viewModel?.goUp()
            return
        }

        // 其他键传给 nextResponder（沿响应链传递到 MainWindowController）
        super.keyDown(with: event)
    }

    /// 打开当前选中的条目（Cmd+O / Cmd+Down 触发，与双击行为一致）
    private func openSelectedEntry() {
        guard let entry = viewModel?.selectedFiles.first else { return }
        onDoubleClick?(entry)
    }

    // MARK: - Inline Rename（P0#1 修复：内联重命名，与 FileListView 对齐）

    /// 开始内联重命名：选中单个文件时按 Enter 触发。
    /// 将选中 item 的 nameLabel 设为可编辑并获取焦点。
    private func beginInlineRename() {
        // 正在重命名时不重复触发
        guard renamingIndexPath == nil else { return }
        guard let viewModel = viewModel else { return }

        // 仅单选时触发重命名
        let selectedIndexPaths = collectionView.selectionIndexPaths
        guard selectedIndexPaths.count == 1, let indexPath = selectedIndexPaths.first else { return }
        // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
        let flatIdx = flatIndex(for: indexPath)
        guard flatIdx < displayEntries.count else { return }

        let entry = displayEntries[flatIdx]

        // 获取选中 item 的 nameLabel
        guard let gridItem = collectionView.item(at: indexPath) as? FileGridCollectionViewItem,
              let textField = gridItem.nameLabel else { return }

        // 记录重命名上下文
        renamingIndexPath = indexPath
        renamingOriginalName = entry.name
        renamingPath = entry.path
        renamingTextField = textField
        renameCancelled = false

        // 进入编辑模式：将 nameLabel 设为可编辑并获取焦点
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self
        textField.target = self
        textField.action = #selector(renameTextFieldDidEndEditing(_:))

        guard window?.makeFirstResponder(textField) == true else {
            // 无法进入编辑模式，清理状态
            textField.isEditable = false
            textField.delegate = nil
            textField.target = nil
            textField.action = nil
            renamingIndexPath = nil
            renamingOriginalName = ""
            renamingPath = ""
            renamingTextField = nil
            renameCancelled = false
            return
        }

        // 选中文件名（不含扩展名），与访达/FileListView 行为一致
        if let editor = textField.currentEditor() {
            let name = entry.name as NSString
            let extRange = name.range(of: ".", options: .backwards)
            if entry.isDirectory || extRange.location == NSNotFound || extRange.location == 0 {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: 0, length: extRange.location)
            }
        }
    }

    /// 结束内联重命名，根据取消标志决定是否提交
    private func endInlineRename() {
        guard let _ = renamingIndexPath else { return }
        let textField = renamingTextField
        let originalName = renamingOriginalName
        let path = renamingPath
        let cancelled = renameCancelled

        // 清理状态
        renamingIndexPath = nil
        renamingOriginalName = ""
        renamingPath = ""
        renamingTextField = nil
        renameCancelled = false

        // 恢复 textField 为非编辑状态
        textField?.delegate = nil
        if let tf = textField {
            tf.isEditable = false
            tf.target = nil
            tf.action = nil
            // 取消时恢复原名称显示
            if cancelled {
                tf.stringValue = originalName
            }
        }

        // 取消则不重命名
        guard !cancelled else { return }

        // 提交重命名（复用 viewModel.renameFile，与右键菜单重命名一致）
        guard let tf = textField else { return }
        let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != originalName else { return }
        viewModel?.renameFile(path, to: newName)
    }

    /// nameLabel 结束编辑（失焦/Enter 确认时触发）
    @objc private func renameTextFieldDidEndEditing(_ sender: NSTextField) {
        // action 在 Enter 时触发，但实际提交通过 controlTextDidEndEditing 完成。
        // 这里仅作为 action 占位，避免无 action 时 NSTextField 在 Enter 下可能不交还焦点。
    }

    // MARK: - Context Menu Actions

    @objc private func openSelected(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        if entry.isDirectory {
            onDoubleClick?(entry)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    @objc private func copySelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidCopy, object: nil, userInfo: ["side": getSide()])
    }

    @objc private func cutSelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidCut, object: nil, userInfo: ["side": getSide()])
    }

    @objc private func pasteSelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidPaste, object: nil, userInfo: ["side": getSide()])
    }

    @objc private func copyToOtherPane(_ sender: Any?) {
        // 任务 F10-10: 入口日志（修复问题15/16 诊断）
        FFLog.debug("[F10-10] copyToOtherPane clicked, side=\(getSide()), clickedEntry=\(clickedEntry?.path ?? "nil"), selectedCount=\(viewModel?.selectedFiles.count ?? 0)", log: FFLog.ui)
        // 问题12修复：传递右键点击文件路径，供空选兜底使用
        NotificationCenter.default.post(name: .fileListDidCopyToOther, object: nil, userInfo: ["side": getSide(), "clickedPath": clickedEntry?.path])
    }

    @objc private func moveToOtherPane(_ sender: Any?) {
        // 任务 F10-10: 入口日志（修复问题15/16 诊断）
        FFLog.debug("[F10-10] moveToOtherPane clicked, side=\(getSide()), clickedEntry=\(clickedEntry?.path ?? "nil"), selectedCount=\(viewModel?.selectedFiles.count ?? 0)", log: FFLog.ui)
        // 问题12修复：传递右键点击文件路径，供空选兜底使用
        NotificationCenter.default.post(name: .fileListDidMoveToOther, object: nil, userInfo: ["side": getSide(), "clickedPath": clickedEntry?.path])
    }

    @objc private func openInOtherPane(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListDidOpenInOther, object: nil, userInfo: ["side": getSide(), "path": entry.path])
    }

    @objc private func renameSelected(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        let alert = NSAlert()
        alert.messageText = "重命名 \"\(entry.name)\""
        alert.informativeText = "输入新名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = entry.name
        alert.accessoryView = textField
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !newName.isEmpty, newName != entry.name else { return }
                self?.viewModel?.renameFile(entry.path, to: newName)
            }
        }
    }

    @objc private func deleteSelected(_ sender: Any?) {
        let entries = viewModel?.selectedFiles ?? []
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = entries.count == 1 ? "删除\"\(entries[0].name)\"？" : "删除 \(entries.count) 个项目？"
        alert.informativeText = "此操作可通过 ⌘Z 撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.viewModel?.deleteSelected()
            }
        }
    }

    @objc private func createDirectory(_ sender: Any?) {
        guard let currentPath = viewModel?.currentPath else { return }
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "未命名文件夹"
        alert.accessoryView = textField
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !folderName.isEmpty else { return }
                let newPath = (currentPath as NSString).appendingPathComponent(folderName)
                do {
                    try CoreBridge.shared.createDirectory(path: newPath)
                    self?.viewModel?.refresh()
                } catch {
                    let errAlert = NSAlert()
                    errAlert.messageText = "错误"
                    errAlert.informativeText = error.localizedDescription
                    errAlert.alertStyle = .critical
                    errAlert.addButton(withTitle: "好")
                    errAlert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }

    @objc private func addToFavorites(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListDidAddFavorite, object: nil, userInfo: ["name": entry.name, "path": entry.path])
    }

    @objc private func generateAITags(_ sender: Any?) {
        // 任务 F11-11: 复用公共入口（供侧边栏工具面板 AI 工具入口调用，C1）
        triggerAITagGeneration()
    }

    /// 任务 F11-11: AI 自动打标签公共入口（C1）。
    /// 供 MainWindowController 在收到侧边栏工具面板 AI 工具点击通知后调用。
    /// 优先使用当前选中文件列表，无选中时回退到右键点击的文件；两者皆无则不执行。
    public func triggerAITagGeneration() {
        // 优先使用选中的文件列表，无选中时回退到右键点击的文件
        var entries = viewModel?.selectedFiles ?? []
        if entries.isEmpty {
            if let entry = clickedEntry {
                entries = [entry]
            } else {
                return
            }
        }

        let paths = entries.map { $0.path }
        let totalCount = paths.count

        // 后台线程批量生成标签并写入 xattr
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var successCount = 0
            var totalTagsAdded = 0
            var xattrFailCount = 0
            var firstError: String?

            for path in paths {
                do {
                    let generatedTags = try CoreBridge.shared.generateAITags(path: path)
                    for genTag in generatedTags {
                        let tag = Tag(name: genTag.name, color: genTag.color)
                        if TagBridge.shared.addTag(tag, path: path) {
                            totalTagsAdded += 1
                        } else {
                            xattrFailCount += 1
                        }
                    }
                    successCount += 1
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self = self, let window = self.window else { return }

                if successCount == 0 {
                    let alert = NSAlert()
                    alert.messageText = "AI 标签生成失败"
                    alert.informativeText = firstError ?? "未知错误"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "关闭")
                    alert.beginSheetModal(for: window)
                    return
                }

                let alert = NSAlert()
                if successCount == totalCount {
                    alert.messageText = "已为 \(successCount) 个文件生成 AI 标签"
                    if totalTagsAdded > 0 {
                        var info = "共添加 \(totalTagsAdded) 个标签。"
                        if xattrFailCount > 0 {
                            info += "\n\(xattrFailCount) 个标签写入失败（权限不足或不支持扩展属性）。"
                        }
                        alert.informativeText = info
                    } else if xattrFailCount > 0 {
                        alert.informativeText = "标签写入失败（权限不足或不支持扩展属性）。"
                    } else {
                        alert.informativeText = "未识别到可分类的文件类型。"
                    }
                } else {
                    alert.messageText = "部分文件标签生成失败"
                    alert.informativeText = "成功 \(successCount) / 总计 \(totalCount)。\n\(firstError ?? "")"
                }
                alert.alertStyle = totalTagsAdded > 0 ? .informational : .warning
                alert.addButton(withTitle: "关闭")
                alert.beginSheetModal(for: window)

                self.reloadData()
            }
        }
    }

    @objc private func addTagMenu(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListAddTag, object: nil,
                                        userInfo: ["path": entry.path])
    }

    @objc private func showInfoMenu(_ sender: Any?) {
        // F9-C: 弹出独立 FileInfoWindow（仿访达 Get Info）。
        // 优先取右键点击的文件，回退到当前选中项的第一项（访达行为：显示第一个文件信息）。
        let targetPath = clickedEntry?.path ?? viewModel?.selectedFiles.first?.path
        // 任务 F10-10: 入口日志（修复问题15/16 诊断）+ path 空回退提示
        FFLog.debug("[F10-10] showInfoMenu clicked, clickedEntry=\(clickedEntry?.path ?? "nil"), fallback selectedFirst=\(viewModel?.selectedFiles.first?.path ?? "nil"), final=\(targetPath ?? "nil")", log: FFLog.ui)
        // 若无目标路径（既无右键点击项也无选中项），给出提示而非静默无响应
        if targetPath == nil || (targetPath?.isEmpty ?? true) {
            let alert = NSAlert()
            alert.messageText = "显示简介"
            alert.informativeText = "请先选择一个文件后再查看简介。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }
        NotificationCenter.default.post(name: .fileListShowInfo, object: nil, userInfo: ["path": targetPath ?? ""])
    }

    // MARK: - Layout

    // 任务 F10-9: 显式同步 appearance，确保选中色解析正确（F7 遗漏修复，v0.6.6）
    // FileGridView 是 NSView（非 NSViewController），无 viewDidLayout；改用 layout()。
    // layout() 在布局变更时被频繁调用，appearance 赋值是轻量指针赋值，开销可忽略。
    // 与 FileListView.layout() 对称实现。
    public override func layout() {
        super.layout()
        collectionView.appearance = NSApp.appearance
    }

    /// 任务 F10-9: 供外部（MainWindowController 主题监听）显式刷新 appearance（F7 遗漏修复，v0.6.6）
    /// 任务 F11-1: 同时刷新 collectionView 实体背景色（日间/夜间切换，v0.6.7）
    /// 与 FileListView.refreshAppearance() 对称实现。
    public func refreshAppearance() {
        collectionView.appearance = NSApp.appearance
        // 任务 F11-1: 主题切换时同步刷新 collectionView 实体背景色
        let isDark = ThemeManager.shared.resolvedIsDark
        collectionView.backgroundColors = [isDark
            ? NSColor(srgbRed: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D
            : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)]  // #F5F5F5
    }

    public func reloadData() {
        // 任务 F10-8: 重建分组缓存后 reload，并恢复选中
        rebuildDisplayEntries()
        isReloading = true
        collectionView?.reloadData()
        // 任务 F10-8: 分组渲染后恢复选中（基于 viewModel.state.selectedFiles 的路径）
        restoreSelectionFromViewModel()
        DispatchQueue.main.async { [weak self] in
            self?.isReloading = false
        }
    }

    /// 任务 F10-8: 根据 viewModel.state.selectedFiles 恢复 collectionView 选中。
    /// 分组后 indexPath.item 不再等于 viewModel.files 下标，需通过 displayEntries 路径匹配。
    private func restoreSelectionFromViewModel() {
        guard let viewModel = viewModel, !viewModel.state.selectedFiles.isEmpty else { return }
        let selectedPaths = Set(viewModel.state.selectedFiles.map { $0.path })
        var indexPaths: Set<IndexPath> = []
        for (flatIdx, entry) in displayEntries.enumerated() where selectedPaths.contains(entry.path) {
            indexPaths.insert(indexPath(forFlatIndex: flatIdx))
        }
        if !indexPaths.isEmpty {
            collectionView?.selectItems(at: indexPaths, scrollPosition: [])
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension FileGridView: NSCollectionViewDataSource {
    // 任务 F10-8: 分组渲染 - 多 section
    public func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return sectionKeys.count
    }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section < sectionStarts.count else { return 0 }
        // 本 section item 数 = 下一个 section 起始 - 本 section 起始（最后一个 section 用 displayEntries.count）
        let start = sectionStarts[section]
        let end = section + 1 < sectionStarts.count ? sectionStarts[section + 1] : displayEntries.count
        return end - start
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("GridItem"), for: indexPath) as? FileGridCollectionViewItem else {
            // 安全回退：类型转换失败时返回空 item，避免崩溃
            return NSCollectionViewItem()
        }
        // 设置标签移除回调（在 entry 设置前设置，确保菜单可用时回调已就绪）
        item.onRemoveTag = { [weak self] tagName, path in
            _ = TagBridge.shared.removeTagByName(tagName, path: path)
            self?.reloadData()
            let updatedTags = TagBridge.shared.getTags(path: path)
            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": updatedTags])
        }
        // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
        let flatIdx = flatIndex(for: indexPath)
        if flatIdx < displayEntries.count {
            item.entry = displayEntries[flatIdx]
        }
        return item
    }

    // 任务 F10-8: 分组标题补充视图
    public func collectionView(_ collectionView: NSCollectionView,
                               viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                               at indexPath: IndexPath) -> NSView {
        // 使用 NSCollectionView.elementKindSectionHeader（Swift 名称）
        guard kind == NSCollectionView.elementKindSectionHeader,
              let header = collectionView.makeSupplementaryView(ofKind: kind,
                                                                withIdentifier: NSUserInterfaceItemIdentifier("GridSectionHeader"),
                                                                for: indexPath) as? FFGridSectionHeaderView else {
            return NSView()
        }
        let section = indexPath.section
        let title = section < sectionKeys.count ? sectionKeys[section] : ""
        let count = self.collectionView(collectionView, numberOfItemsInSection: section)
        // groupBy == "none" 时隐藏标题（返回空内容，但视图仍存在以满足 FlowLayout）
        if viewModel?.state.groupBy == "none" {
            header.configure(title: "", count: 0)
        } else {
            header.configure(title: title, count: count)
        }
        return header
    }
}

// MARK: - NSCollectionViewDelegate

extension FileGridView: NSCollectionViewDelegate {
    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let viewModel = viewModel else { return }
        // 任务 F10-8: reload 期间触发的选择回调应忽略（避免与 restoreSelection 形成循环）
        if isReloading { return }
        // 点击 item 时激活当前面板（与 FileListView 一致）
        onActivatePane?()
        // Bug 1 修复：使用 collectionView.selectionIndexPaths 获取所有当前选中项
        // （indexPaths 参数仅包含本次新选中的项，不能代表完整选择状态）
        // 同时同步更新 viewModel.state.selectedFiles，否则选中状态不生效
        // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
        let selectedIndexPaths = collectionView.selectionIndexPaths
        var selected: [FileEntry] = []
        for indexPath in selectedIndexPaths {
            let flatIdx = flatIndex(for: indexPath)
            if flatIdx < displayEntries.count {
                selected.append(displayEntries[flatIdx])
            }
        }
        viewModel.state.selectedFiles = selected
        onSelectionChanged?(selected)
    }

    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        // 任务 F10-8: reload 期间触发的选择回调应忽略
        if isReloading { return }
        // 更新选择状态
        guard let viewModel = viewModel else { return }
        let selectedIndexPaths = collectionView.selectionIndexPaths
        var selected: [FileEntry] = []
        for indexPath in selectedIndexPaths {
            // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
            let flatIdx = flatIndex(for: indexPath)
            if flatIdx < displayEntries.count {
                selected.append(displayEntries[flatIdx])
            }
        }
        // Bug 1 修复：同步更新 viewModel.state.selectedFiles
        viewModel.state.selectedFiles = selected
        onSelectionChanged?(selected)
    }

    public func collectionView(_ collectionView: NSCollectionView, doubleClickItemAt indexPath: IndexPath) {
        // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
        let flatIdx = flatIndex(for: indexPath)
        guard flatIdx < displayEntries.count else { return }
        onDoubleClick?(displayEntries[flatIdx])
    }

    // MARK: - Drag Source（拖出文件）

    public func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return true
    }

    /// 为每个被拖拽的 item 提供 pasteboard writer（文件 URL）
    /// NSCollectionView 会对所有选中项调用此方法，从而发送选中文件的完整路径数组
    public func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        // 任务 F10-8: 通过 flatIndex 映射到 displayEntries
        let flatIdx = flatIndex(for: indexPath)
        guard flatIdx < displayEntries.count else { return nil }
        let entry = displayEntries[flatIdx]
        return NSURL(fileURLWithPath: entry.path)
    }

    public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        // 拖拽即将开始（占位，便于后续扩展）
    }

    public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation: NSDragOperation) {
        // 拖拽结束：若为移动/删除操作，源文件可能已被移走，需刷新当前目录
        if dragOperation == .move || dragOperation == .delete {
            viewModel?.refresh()
        }
    }
}

// MARK: - NSTextFieldDelegate（内联重命名编辑事件，P0#1 修复）

extension FileGridView: NSTextFieldDelegate {
    /// 处理编辑中的特殊按键（Enter 确认 / Esc 取消），与 FileListView 行为一致
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc：取消重命名
            renameCancelled = true
            window?.makeFirstResponder(collectionView)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Enter/Return：确认重命名（交还焦点触发 controlTextDidEndEditing）
            window?.makeFirstResponder(collectionView)
            return true
        default:
            return false
        }
    }

    /// 编辑结束（Enter 确认 / 失焦自动确认 / Esc 取消）
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard renamingIndexPath != nil else { return }
        endInlineRename()
    }
}

// MARK: - NSMenuDelegate（P0#7 修复：动态更新跨面板箭头方向 + 打开项图标）

extension FileGridView: NSMenuDelegate {
    /// 菜单即将显示时更新：
    /// - "打开"项图标根据选中项是文件夹还是文件动态切换（folder / doc）
    /// - "移动/复制到另一面板"箭头方向：panelSide 可能在 init 后才被设置，每次显示菜单时同步
    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === collectionView.menu else {
            if menu === tagsSubmenu {
                rebuildTagsSubmenu(menu)
            }
            return
        }
        let isLeftPane = effectiveSide == .left

        // "打开"项图标：文件夹用 folder，文件用 doc
        if let openItem = menu.items.first(where: { $0.title == "打开" }) {
            let isOpenFolder = clickedEntry?.isDirectory == true
            openItem.image = NSImage(systemSymbolName: isOpenFolder ? "folder" : "doc",
                                     accessibilityDescription: "打开")
        }

        // "复制到另一面板"箭头方向（左面板 -> arrow.right.square，右面板 -> arrow.left.square）
        if let copyOtherItem = menu.items.first(where: { $0.title == "复制到另一面板" }) {
            copyOtherItem.image = NSImage(systemSymbolName: isLeftPane ? "arrow.right.square" : "arrow.left.square",
                                          accessibilityDescription: "复制到另一面板")
        }

        // "移动到另一面板"箭头方向（左面板 -> arrow.right，右面板 -> arrow.left）
        if let moveItem = menu.items.first(where: { $0.title == "移动到另一面板" }) {
            moveItem.image = NSImage(systemSymbolName: isLeftPane ? "arrow.right" : "arrow.left",
                                     accessibilityDescription: "移动到另一面板")
        }

        // 任务 F10-10: "在对侧面板打开"仅当右键点击项为文件夹时显示（修复问题13）
        // 文件无此操作意义（文件无法被"打开"为目录导航目标）
        if let openOtherItem = menu.items.first(where: { $0.title == "在对侧面板打开" }) {
            openOtherItem.isHidden = !(clickedEntry?.isDirectory ?? false)
        }
    }

    /// 重建标签二级子菜单
    private func rebuildTagsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let targetEntry = clickedEntry ?? viewModel?.selectedFiles.first
        guard let entry = targetEntry else {
            let createItem = NSMenuItem(title: "新建标签...", action: #selector(showCreateTagDialog(_:)), keyEquivalent: "")
            createItem.target = self
            createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
            menu.addItem(createItem)
            return
        }
        let currentTags = TagBridge.shared.getTags(path: entry.path)
        let currentTagIds = Set(currentTags.map { $0.id })
        let currentTagNames = Set(currentTags.map { $0.name })
        let allTags = loadAllSidebarTags()
        for tag in allTags {
            let item = NSMenuItem(title: tag.name, action: #selector(toggleTagOnFile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["tagId": tag.id, "tagName": tag.name, "tagColor": tag.color, "path": entry.path]
            item.image = makeDotImage(colorHex: tag.color)
            if currentTagIds.contains(tag.id) || currentTagNames.contains(tag.name) {
                item.state = .on
            }
            menu.addItem(item)
        }
        if !allTags.isEmpty {
            menu.addItem(.separator())
        }
        let createItem = NSMenuItem(title: "新建标签...", action: #selector(showCreateTagDialog(_:)), keyEquivalent: "")
        createItem.target = self
        createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
        menu.addItem(createItem)
    }

    /// 创建带颜色的圆点 NSImage
    private func makeDotImage(colorHex: String) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let color = NSColor(hex: colorHex) ?? .systemBlue
        let circle = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        color.setFill()
        circle.fill()
        image.unlockFocus()
        return image
    }

    /// 加载所有侧边栏标签（从 UserDefaults 读取，与 SidebarView 共享存储）
private func loadAllSidebarTags() -> [Tag] {
    guard let data = UserDefaults.standard.data(forKey: "SidebarTags"),
          let tags = try? JSONDecoder().decode([Tag].self, from: data) else {
        return []
    }
    return tags
}

    /// 切换文件标签
    @objc private func toggleTagOnFile(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagId = info["tagId"],
              let tagName = info["tagName"],
              let path = info["path"] else { return }
        let tagColor = info["tagColor"] ?? "#007AFF"

        let currentTags = TagBridge.shared.getTags(path: path)
        if currentTags.contains(where: { $0.id == tagId || $0.name == tagName }) {
            _ = TagBridge.shared.removeTag(tagId, path: path)
        } else {
            let tag = Tag(id: tagId, name: tagName, color: tagColor)
            _ = TagBridge.shared.addTag(tag, path: path)
        }
        // 刷新网格以更新标签药丸
        reloadData()
        // 通知侧边栏刷新标签列表，携带文件当前标签以同步侧边栏
        let updatedTags = TagBridge.shared.getTags(path: path)
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": updatedTags])
    }

    /// 显示新建标签对话框
    @objc private func showCreateTagDialog(_ sender: Any?) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "输入标签名称并选择颜色："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let containerWidth: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 64))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 36, width: containerWidth, height: 24))
        nameField.placeholderString = "标签名称"
        container.addSubview(nameField)

        let presetColors: [String] = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#5856D6"]
        let dotSize: CGFloat = 22
        let spacing: CGFloat = 8
        let totalDotsWidth = CGFloat(presetColors.count) * dotSize + CGFloat(presetColors.count - 1) * spacing
        let startX = (containerWidth - totalDotsWidth) / 2

        let colorHolder = FFCreateTagColorHolder(colors: presetColors)

        for (i, hex) in presetColors.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            let btn = NSButton(frame: NSRect(x: x, y: 4, width: dotSize, height: dotSize))
            btn.bezelStyle = .circular
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = (NSColor(hex: hex) ?? .systemBlue).cgColor
            btn.layer?.cornerRadius = dotSize / 2
            btn.layer?.borderColor = NSColor.labelColor.cgColor
            btn.layer?.borderWidth = (i == 0) ? 2 : 0
            btn.target = colorHolder
            btn.action = #selector(FFCreateTagColorHolder.selectColor(_:))
            btn.tag = i
            container.addSubview(btn)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        let targetPath = clickedEntry?.path ?? viewModel?.selectedFiles.first?.path

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let tag = Tag(name: name, color: colorHolder.selectedHex)

            var allTags = self?.loadAllSidebarTags() ?? []
            if !allTags.contains(where: { $0.name == tag.name }) {
                allTags.append(tag)
                if let data = try? JSONEncoder().encode(allTags) {
                    UserDefaults.standard.set(data, forKey: "SidebarTags")
                }
            }

            if let path = targetPath {
                _ = TagBridge.shared.addTag(tag, path: path)
            }

            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": allTags])
        }
    }

    /// 查重扫描
    @objc private func duplicateScan(_ sender: Any?) {
        DuplicateScanWindowController.shared.showWindow()
    }
}

// MARK: - Drag and Drop（拖入目标）

extension FileGridView {
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return isMoveOperation(sender) ? .move : .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return isMoveOperation(sender) ? .move : .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return false
        }

        let destPath = viewModel?.currentPath ?? ""
        guard !destPath.isEmpty else { return false }

        let isMove = isMoveOperation(sender)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let srcs = urls.map { $0.path }
            let total = srcs.count
            do {
                let success: Int
                if isMove {
                    success = try CoreBridge.shared.parallelMove(srcs: srcs, dstDir: destPath)
                } else {
                    success = try CoreBridge.shared.parallelCopy(srcs: srcs, dstDir: destPath)
                }

                // I2: invalidate cache so the refresh reflects the new state.
                // Destination always changes; for a move each source parent
                // directory also changes (items left those dirs). Best-effort.
                try? CoreBridge.shared.invalidateCache(path: destPath)
                if isMove {
                    let sourceDirs = Set(srcs.map { ($0 as NSString).deletingLastPathComponent })
                    for dir in sourceDirs where !dir.isEmpty {
                        try? CoreBridge.shared.invalidateCache(path: dir)
                    }
                }

                // I3: capture the detailed partial-failure message now
                // (getLastError is read-once) before the async UI refresh.
                let partialDetail = (success < total) ? CoreBridge.shared.getLastError() : ""

                // 计算 dst 路径用于撤销注册（best-effort：假设 srcs 都成功）
                let dstPaths = srcs.map { src -> String in
                    let name = (src as NSString).lastPathComponent
                    return (destPath as NSString).appendingPathComponent(name)
                }

                DispatchQueue.main.async {
                    self?.viewModel?.refresh()

                    // Bug 3 修复：跨面板拖拽时，若源文件来自对侧面板的当前目录，需刷新对侧面板
                    // （仅 move 操作会改变源目录；copy 不改变源，但为安全起见也刷新对侧）
                    if let counterpartPath = self?.counterpartViewModel?.currentPath,
                       !counterpartPath.isEmpty,
                       srcs.contains(where: { ($0 as NSString).deletingLastPathComponent == counterpartPath }) {
                        self?.counterpartViewModel?.refresh()
                    }

                    // 注册撤销（通过 viewModel?.undoManager 访问 per-window UndoManager）
                    if success > 0, let vm = self?.viewModel, let undoManager = vm.undoManager {
                        let counterpart = self?.counterpartViewModel
                        if isMove {
                            let pairs = zip(srcs, dstPaths).map { (src: $0, dst: $1) }
                            undoManager.registerUndo(withTarget: vm) { [weak counterpart] targetVM in
                                // undo: 移回原位
                                for (src, dst) in pairs {
                                    try? CoreBridge.shared.moveFile(src: dst, dst: src)
                                }
                                // 注册 redo：再次移动
                                targetVM.undoManager?.registerUndo(withTarget: targetVM) { [weak counterpart] vm2 in
                                    for (src, dst) in pairs {
                                        try? CoreBridge.shared.moveFile(src: src, dst: dst)
                                    }
                                    vm2.refresh()
                                    counterpart?.refresh()
                                }
                                targetVM.undoManager?.setActionName("移动 \(success) 个项目")
                                // I1: 刷新双面板（跨面板移动 undo 后源面板需同步）
                                targetVM.refresh()
                                counterpart?.refresh()
                            }
                            undoManager.setActionName("移动 \(success) 个项目")
                        } else {
                            let pairs = zip(srcs, dstPaths).map { (src: $0, dst: $1) }
                            undoManager.registerUndo(withTarget: vm) { [weak counterpart] targetVM in
                                // undo: 删除复制项
                                for (_, dst) in pairs {
                                    try? CoreBridge.shared.deleteFile(path: dst)
                                }
                                // 注册 redo：重新复制
                                targetVM.undoManager?.registerUndo(withTarget: targetVM) { [weak counterpart] vm2 in
                                    for (src, dst) in pairs {
                                        try? CoreBridge.shared.copyFile(src: src, dst: dst)
                                    }
                                    vm2.refresh()
                                    counterpart?.refresh()
                                }
                                targetVM.undoManager?.setActionName("复制 \(success) 个项目")
                                // I1: 刷新双面板
                                targetVM.refresh()
                                counterpart?.refresh()
                            }
                            undoManager.setActionName("复制 \(success) 个项目")
                        }
                    }

                    if success < total {
                        self?.showError(error: NSError(
                            domain: "FlowFinder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "\(total - success) 个项目操作失败：\(partialDetail)"])
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error: error)
                }
            }
        }

        return true
    }

    /// 判断是否为移动操作（同卷 + 未按 Cmd）
    private func isMoveOperation(_ sender: NSDraggingInfo) -> Bool {
        // Cmd 键切换为复制
        if sender.draggingSourceOperationMask.contains(.copy) &&
           !sender.draggingSourceOperationMask.contains(.move) {
            return false
        }

        // 检查源和目标是否在同一卷
        guard let destPath = viewModel?.currentPath else { return false }

        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let srcPath = urls.first?.path {
            return isSameVolume(srcPath: srcPath, destPath: destPath)
        }

        return false
    }

    /// 检查两个路径是否在同一卷（通过 statfs）
    private func isSameVolume(srcPath: String, destPath: String) -> Bool {
        var srcStat = statfs()
        var dstStat = statfs()

        let srcResult = srcPath.withCString { statfs($0, &srcStat) }
        let dstResult = destPath.withCString { statfs($0, &dstStat) }

        guard srcResult == 0 && dstResult == 0 else { return false }

        // 比较设备 ID (使用 memcmp 比较 fsid_t 原始字节)
        var srcFsid = srcStat.f_fsid
        var dstFsid = dstStat.f_fsid
        return withUnsafeBytes(of: &srcFsid) { srcBytes in
            withUnsafeBytes(of: &dstFsid) { dstBytes in
                srcBytes.elementsEqual(dstBytes)
            }
        }
    }
}
