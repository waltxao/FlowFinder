import Cocoa
import Combine

// MARK: - FileGridCollectionViewItem

class FileGridCollectionViewItem: NSCollectionViewItem {
    private var thumbnailImageView: NSImageView!
    /// 缩略图宽/高约束（动态重建：按图片原始比例，最长边 64pt——Finder 风格，替代固定方形）
    private var thumbWidthConstraint: NSLayoutConstraint!
    private var thumbHeightConstraint: NSLayoutConstraint!
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
                    setThumbnail(cached)
                } else {
                    let placeholder = NSImage(systemSymbolName: "folder", accessibilityDescription: "文件夹")
                        ?? NSImage(named: NSImage.folderName)
                    setThumbnail(placeholder)
                    ThumbnailManager.shared.fetchWorkspaceIcon(for: entry.path, pointSize: 48) { [weak self] image in
                        guard let self = self, self.currentPath == nil else { return }
                        if let image = image { self.setThumbnail(image) }
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
                    setThumbnail(cachedIcon)
                } else {
                    setThumbnail(NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
                        ?? NSImage(named: NSImage.multipleDocumentsName))
                    // 后台异步获取真实工作区图标作为过渡（缩略图返回前先显示真实类型图标）
                    ThumbnailManager.shared.fetchWorkspaceIcon(for: path, pointSize: placeholderPointSize) { [weak self] image in
                        guard let self = self, self.currentPath == path else { return }
                        if let image = image {
                            // 缩略图优先级更高：若缩略图已返回则不覆盖
                            guard !self.didReceiveThumbnail else { return }
                            self.setThumbnail(image)
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
                        self.setThumbnail(image)
                    } else {
                        self.setThumbnail(NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
                            ?? NSImage(named: NSImage.multipleDocumentsName))
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
        setThumbnail(nil)
        // 重置选中背景（防止复用 item 残留选中样式）
        view.layer?.backgroundColor = NSColor.clear.cgColor
        // squircle 圆角：0 时自动移除 mask（SquircleMaskedView）
        (view as? SquircleMaskedView)?.squircleRadius = 0
        // 清除旧标签药丸
        tagPillContainer?.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    /// 设置缩略图/图标并同步宽高比（Finder 风格：最长边 64pt，保持原始比例）。
    /// 所有 image 赋值统一走此方法，替代直接改 thumbnailImageView.image。
    private func setThumbnail(_ image: NSImage?) {
        thumbnailImageView.image = image
        // 移除旧尺寸约束
        thumbWidthConstraint?.isActive = false
        thumbHeightConstraint?.isActive = false
        guard let image = image, image.size.width > 0, image.size.height > 0 else {
            // 无图片/占位：回退 64×64 方形
            thumbWidthConstraint = thumbnailImageView.widthAnchor.constraint(equalToConstant: 64)
            thumbHeightConstraint = thumbnailImageView.heightAnchor.constraint(equalToConstant: 64)
            thumbWidthConstraint.isActive = true
            thumbHeightConstraint.isActive = true
            return
        }
        let w = image.size.width
        let h = image.size.height
        if w >= h {
            // 宽图（含方形）：宽 64，高按比例
            thumbWidthConstraint = thumbnailImageView.widthAnchor.constraint(equalToConstant: 64)
            thumbHeightConstraint = thumbnailImageView.heightAnchor.constraint(equalToConstant: max(64 * h / w, 1))
        } else {
            // 高图：高 64，宽按比例
            thumbHeightConstraint = thumbnailImageView.heightAnchor.constraint(equalToConstant: 64)
            thumbWidthConstraint = thumbnailImageView.widthAnchor.constraint(equalToConstant: max(64 * w / h, 1))
        }
        thumbWidthConstraint.isActive = true
        thumbHeightConstraint.isActive = true
        thumbnailImageView.needsLayout = true
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
        // 缩略图尺寸约束动态管理（setThumbnail 时按图片比例重建）：
        // 初始 64×64 占位，图片到达后按原始宽高比（最长边 64）重建，Finder 风格。
        thumbWidthConstraint = thumbnailImageView.widthAnchor.constraint(equalToConstant: 64)
        thumbHeightConstraint = thumbnailImageView.heightAnchor.constraint(equalToConstant: 64)
        thumbWidthConstraint.isActive = true
        thumbHeightConstraint.isActive = true

        self.view = view
    }

    override var isSelected: Bool {
        didSet {
            // 任务 F10-9: 访达风格实心蓝半透明选中（v0.6.6）
            // alpha 0.15->0.25 增强可见性（问题10），圆角 6->8 与访达网格一致
            view.layer?.backgroundColor = isSelected
                ? FFAccent.current.withAlphaComponent(0.25).cgColor
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
// 非 private（internal）：MainWindowController 的 isFilePaneResponder 需用类型判断
// 文件面板焦点（全局键盘 monitor），private 类跨文件不可见。
class DraggingCollectionView: NSCollectionView {
    /// 空格键触发 QuickLook 通知（collectionView 为 first responder 时，空格被 NSCollectionView
    /// 默认 keyDown/interpretKeyEvents 消耗，需在此拦截转发给 FileGridView.keyDown 同款逻辑）
    var onSpaceKey: (() -> Void)?
    /// Enter 键触发内联重命名（collectionView 为 firstResponder 时 Enter 被其 keyDown 消耗，
    /// 不冒泡到 FileGridView.keyDown，需在此拦截转发）
    var onEnterKey: (() -> Void)?
    /// Del 键触发删除（移到废纸篓，访达语义）
    var onDeleteKey: (() -> Void)?

    /// 修复网格视图空格预览不可用：NSCollectionView 默认 acceptsFirstResponder=false，
    /// 点击网格项不成为 firstResponder——performKeyEquivalent 只沿 responder chain 分发，
    /// 列表 tableView（有 firstResponder 守卫）不拦、本视图也不在链上 → 空格无响应。
    /// 设为 true 后点击网格项即成为 firstResponder，空格事件沿链到达本视图被拦截。
    override var acceptsFirstResponder: Bool { true }

    /// 点击网格项时显式转移 firstResponder 到本视图（acceptsFirstResponder 只允许，
    /// NSCollectionView 点击默认不自动抢焦点——不转移则空格/Enter 事件沿旧链分发无效）
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move, .delete]
    }

    /// 拦截空格键触发 QuickLook。
    /// 用 performKeyEquivalent 而非 keyDown：NSCollectionView 的字符键先经 interpretKeyEvents
    /// 处理，keyDown 可能收不到（问题 5 根因）。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        if event.keyCode == 49 && !modifiers.contains(.command) && !modifiers.contains(.option) && !modifiers.contains(.control) {
            FFDebug.log("DraggingCollectionView.performKeyEquivalent: space intercepted")
            onSpaceKey?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags
        // 修复：不能用 isEmpty——Enter 自带 .numericPad 标志，改为不含 Cmd/Opt/Ctrl/Shift
        let hasRealModifier = !modifiers.intersection([.command, .option, .control, .shift]).isEmpty
        if !hasRealModifier {
            if event.keyCode == 49 {
                onSpaceKey?()
                return
            }
            // 修复网格 Enter 重命名：拦截 Enter 转发给 FileGridView.beginInlineRename
            if event.keyCode == 36 || event.keyCode == 76 {
                onEnterKey?()
                return
            }
            // Del 删除（访达语义：keyCode 51 = backspace/Del）
            if event.keyCode == 51 {
                onDeleteKey?()
                return
            }
        }
        super.keyDown(with: event)
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

    // 问题 7 根因修复：拖拽过程中持续捕获修饰键（用于 ⌘ 判断，访达语义）。
    // 在 draggingEntered/draggingUpdated 中持续写入，draggingEnded 复位。
    private var lastDragModifierFlags: NSEvent.ModifierFlags = []

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
            // 重命名等"数量不变"操作：state sink 只比较数量不刷新，需强制 reloadData
            NotificationCenter.default.addObserver(
                self, selector: #selector(forceReload),
                name: .fileListContentChanged, object: nil
            )
        }
    }

    @objc private func forceReload() {
        FFDebug.log("FileGridView.forceReload")
        reloadData()
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

    /// 统一操作控制器：所有右键菜单操作、键盘操作、内联重命名由控制器统一处理。
    /// 视图只需实现 FFPaneViewHost 协议提供视图特有信息，新增视图零重复、零重测。
    private(set) lazy var actionsController: FFPaneActionsController = FFPaneActionsController(host: self)

    /// 标签二级菜单（动态构建：每次显示前由 actionsController 的 NSMenuDelegate 重建内容）
    private(set) lazy var tagsSubmenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = actionsController
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
        // 任务 T5: QuickLook 空格键修复（网格视图）。collectionView 是 first responder 时空格被
        // NSCollectionView 消耗，不会冒泡到 FileGridView.keyDown → 在 DraggingCollectionView 拦截转发。
        // side 动态取 self.getSide()（identifier 由 MainWindowController 在 init 之后设置）。
        (collectionView as? DraggingCollectionView)?.onSpaceKey = { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": self.getSide()])
        }
        // Enter 键 → 内联重命名（与 Finder 一致，委托给 actionsController）
        (collectionView as? DraggingCollectionView)?.onEnterKey = { [weak self] in
            FFDebug.log("DraggingCollectionView.onEnterKey 触发")
            self?.actionsController.beginInlineRename()
        }
        // Del 键 → 移到废纸篓（与 Finder 一致，委托给 actionsController）
        (collectionView as? DraggingCollectionView)?.onDeleteKey = { [weak self] in
            FFDebug.log("DraggingCollectionView.onDeleteKey 触发")
            self?.actionsController.deleteSelected(nil)
        }
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
        // 统一由 FFPaneMenuBuilder 构建，target 为 actionsController（操作逻辑由控制器统一处理）
        let menu = FFPaneMenuBuilder.buildMenu(for: actionsController, isLeft: effectiveSide == .left, tagsSubmenu: tagsSubmenu)
        // 启用动态菜单：右键菜单显示前由 actionsController 的 menuNeedsUpdate 更新图标/可见性/标签二级子菜单
        menu.delegate = actionsController
        collectionView.menu = menu
    }

    // MARK: - Context Menu Helpers

    var clickedEntry: FileEntry? {
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
        // 与 FileListView 一致：优先用注入的 panelSide（identifier 在 setup 时尚未设置）
        if let panelSide = panelSide {
            return panelSide == .right ? "right" : "left"
        }
        return identifier?.rawValue ?? "left"
    }

    // MARK: - 拖拽撤销辅助（无限撤销/重做闭环）

    /// 撤销"拖拽移动"：把文件移回源位置，并同步注册 redo（redoDragMove）。
    /// redoDragMove 处理器内又会注册反向 undo（= undoDragMove），从而形成无限撤销/重做闭环：
    /// 撤销→重做→撤销→重做…可无限进行。文件操作经 undoRedoQueue 串行化，排队在上一操作之后，避免竞态。
    func undoDragMove(pairs: [(src: String, dst: String)], counterpart: PaneViewModel?, actionName: String) {
        // 必须先注册 redo 再排队文件操作：registerUndo 在撤销会话内（isUndoing）会路由到 redo 栈，
        // 而文件操作异步执行，需先建立 redo 栈再排队，否则重做栈可能为空。
        undoManager?.registerUndo(withTarget: self) { [weak counterpart] view in
            view.redoDragMove(pairs: pairs, counterpart: counterpart, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        MainWindowController.undoRedoQueue.async { [weak self, weak counterpart] in
            for (src, dst) in pairs {
                try? CoreBridge.shared.moveFile(src: dst, dst: src)
            }
            DispatchQueue.main.async {
                self?.viewModel?.refresh()
                counterpart?.refresh()
            }
        }
    }

    /// 重做"拖拽移动"：把文件再次移动到目标位置（与初始移动相同）。
    /// 处理器内同步注册反向 undo（undoDragMove，路由到 undo 栈，isRedoing == true），
    /// 从而形成无限撤销/重做闭环。
    func redoDragMove(pairs: [(src: String, dst: String)], counterpart: PaneViewModel?, actionName: String) {
        // 先注册反向 undo 再排队文件操作：registerUndo 在重做会话内（isRedoing）路由到 undo 栈。
        undoManager?.registerUndo(withTarget: self) { [weak counterpart] view in
            view.undoDragMove(pairs: pairs, counterpart: counterpart, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        MainWindowController.undoRedoQueue.async { [weak self, weak counterpart] in
            for (src, dst) in pairs {
                try? CoreBridge.shared.moveFile(src: src, dst: dst)
            }
            DispatchQueue.main.async {
                self?.viewModel?.refresh()
                counterpart?.refresh()
            }
        }
    }

    /// 撤销"拖拽复制"：删除复制项，并同步注册 redo（redoDragCopy）。
    /// redoDragCopy 处理器内又会注册反向 undo（= undoDragCopy），从而形成无限撤销/重做闭环：
    /// 撤销→重做→撤销→重做…可无限进行。文件操作经 undoRedoQueue 串行化，排队在上一操作之后，避免竞态。
    func undoDragCopy(pairs: [(src: String, dst: String)], counterpart: PaneViewModel?, actionName: String) {
        // 必须先注册 redo 再排队文件操作：registerUndo 在撤销会话内（isUndoing）会路由到 redo 栈，
        // 而文件操作异步执行，需先建立 redo 栈再排队，否则重做栈可能为空。
        undoManager?.registerUndo(withTarget: self) { [weak counterpart] view in
            view.redoDragCopy(pairs: pairs, counterpart: counterpart, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        MainWindowController.undoRedoQueue.async { [weak self, weak counterpart] in
            for (_, dst) in pairs {
                try? CoreBridge.shared.deleteFile(path: dst)
            }
            DispatchQueue.main.async {
                self?.viewModel?.refresh()
                counterpart?.refresh()
            }
        }
    }

    /// 重做"拖拽复制"：重新复制目标文件（与初始复制相同）。
    /// 处理器内同步注册反向 undo（undoDragCopy，路由到 undo 栈，isRedoing == true），
    /// 从而形成无限撤销/重做闭环。
    func redoDragCopy(pairs: [(src: String, dst: String)], counterpart: PaneViewModel?, actionName: String) {
        // 先注册反向 undo 再排队文件操作：registerUndo 在重做会话内（isRedoing）路由到 undo 栈。
        undoManager?.registerUndo(withTarget: self) { [weak counterpart] view in
            view.undoDragCopy(pairs: pairs, counterpart: counterpart, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        MainWindowController.undoRedoQueue.async { [weak self, weak counterpart] in
            for (src, dst) in pairs {
                try? CoreBridge.shared.copyFile(src: src, dst: dst)
            }
            DispatchQueue.main.async {
                self?.viewModel?.refresh()
                counterpart?.refresh()
            }
        }
    }

    private func showError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        if let window = window { alert.beginSheetModal(for: window) { _ in } }
    }

    // MARK: - Keyboard（委托给 actionsController）

    /// 重写 keyDown：Enter/Return 触发内联重命名，空格触发 QuickLook 预览，
    /// Cmd+Down/Cmd+O 打开选中项，Cmd+Up 上级目录（macOS Finder 风格）。
    /// 空格/Enter/Del 由 actionsController 统一处理，其他快捷键保留视图内兜底。
    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // Space / Enter / Del：委托给 actionsController 统一处理
        if modifiers.isEmpty && (event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 51) {
            if actionsController.handlePaneKey(event.keyCode) {
                return
            }
        }

        // Cmd+Down (keyCode 125) / Cmd+O (keyCode 31) 打开选中项（Finder 风格）
        let isPureCommand = modifiers.contains(.command)
            && !modifiers.contains(.shift)
            && !modifiers.contains(.option)
            && !modifiers.contains(.control)
        if isPureCommand && (event.keyCode == 125 || event.keyCode == 31) {
            actionsController.openSelectedEntry()
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

    /// 统一键盘入口（MainWindowController 全局 keyDown monitor 调用）：
    /// 空格 → QuickLook，Enter → 内联重命名，Del → 移到废纸篓。
    /// 委托给 actionsController 统一处理。
    func handlePaneKey(_ keyCode: UInt16) -> Bool {
        return actionsController.handlePaneKey(keyCode)
    }

    // MARK: - Context Menu Actions（已迁移至 FFPaneActionsController）
    // 所有 @objc 方法（openSelected/copySelected/cutSelected/pasteSelected/renameSelected/
    // deleteSelected/createDirectory/addToFavorites/generateAITags/triggerAITagGeneration/
    // addTagMenu/showInfoMenu/copyToOtherPane/moveToOtherPane/openInOtherPane/duplicateScan）
    // 已迁移至 FFPaneActionsController。菜单 target 设为 actionsController，无需在此重复实现。

    /// AI 自动打标签公共入口（供 MainWindowController 外部调用）。
    /// 委托给 actionsController 统一处理。
    public func triggerAITagGeneration() {
        actionsController.triggerAITagGeneration()
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

// MARK: - NSTextFieldDelegate / NSMenuDelegate（已迁移至 FFPaneActionsController）
// 内联重命名编辑事件和右键菜单动态更新逻辑已由 actionsController 统一实现。

// MARK: - FFPaneViewHost 协议实现

extension FileGridView: FFPaneViewHost {
    var hostWindow: NSWindow? { window }
    var doubleClickHandler: ((FileEntry) -> Void)? { onDoubleClick }
    var selectedEntries: [FileEntry] { viewModel?.selectedFiles ?? [] }

    func renameTextFieldForSelection() -> NSTextField? {
        let selectedIndexPaths = collectionView.selectionIndexPaths
        guard selectedIndexPaths.count == 1, let indexPath = selectedIndexPaths.first else { return nil }
        guard let gridItem = collectionView.item(at: indexPath) as? FileGridCollectionViewItem else { return nil }
        return gridItem.nameLabel
    }

    func selectClickedItemForRename() {
        guard let event = NSApp.currentEvent else { return }
        let point = collectionView.convert(event.locationInWindow, from: nil)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            collectionView.deselectAll(nil)
            collectionView.selectItems(at: [indexPath], scrollPosition: [])
        }
    }

    var focusRestoreTarget: NSResponder? { collectionView }
    func reloadPaneData() { reloadData() }
}

// MARK: - Drag and Drop（拖入目标）

extension FileGridView {
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // 捕获当前修饰键（问题 7 根因修复：回调中直接读 NSApp.currentEvent 不可靠）
        if let event = NSApp.currentEvent {
            lastDragModifierFlags = event.modifierFlags
        }
        return isMoveOperation(sender, destPath: viewModel?.currentPath) ? .move : .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // 持续捕获修饰键，支持拖拽过程中实时切换 ⌘
        if let event = NSApp.currentEvent {
            lastDragModifierFlags = event.modifierFlags
        }
        return isMoveOperation(sender, destPath: viewModel?.currentPath) ? .move : .copy
    }

    public override func draggingEnded(_ sender: NSDraggingInfo) {
        lastDragModifierFlags = []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // 双保险：落下前再捕获一次最新修饰键
        if let event = NSApp.currentEvent {
            lastDragModifierFlags = event.modifierFlags
        }
        let pasteboard = sender.draggingPasteboard

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return false
        }

        let destPath = viewModel?.currentPath ?? ""
        guard !destPath.isEmpty else { return false }

        let isMove = isMoveOperation(sender, destPath: destPath)

        // 任务 10：冲突预检与解决（替换/保留两者/跳过）
        let conflictPlan = ConflictResolver.resolveConflicts(
            srcPaths: urls.map { $0.path },
            destDir: destPath,
            window: window
        )
        guard !conflictPlan.isEmpty else { return true }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let srcs = conflictPlan.normalSrcs
            let allSrcs = srcs + conflictPlan.keepBoth.map { $0.src }
            let total = allSrcs.count
            do {
                var success: Int
                if isMove {
                    success = try CoreBridge.shared.parallelMove(srcs: srcs, dstDir: destPath)
                } else {
                    success = try CoreBridge.shared.parallelCopy(srcs: srcs, dstDir: destPath)
                }

                // 保留两者：逐项以改名后的目标名复制/移动（批量接口目标名取 lastPathComponent，无法表达改名）
                // 仅记录成功项为 (src, dst) 对，保持 src/dst 严格对齐，避免部分失败时 zip 静默截断
                var keepBothPairs: [(src: String, dst: String)] = []
                for pair in conflictPlan.keepBoth {
                    let dstFull = (destPath as NSString).appendingPathComponent(pair.dstName)
                    do {
                        if isMove {
                            try CoreBridge.shared.moveFile(src: pair.src, dst: dstFull)
                        } else {
                            try CoreBridge.shared.copyFile(src: pair.src, dst: dstFull)
                        }
                        success += 1
                        keepBothPairs.append((src: pair.src, dst: dstFull))
                    } catch {
                        // 单项失败：不计入 success，下方按 partial failure 统一提示
                    }
                }

                // I2: invalidate cache so the refresh reflects the new state.
                // Destination always changes; for a move each source parent
                // directory also changes (items left those dirs). Best-effort.
                try? CoreBridge.shared.invalidateCache(path: destPath)
                if isMove {
                    let sourceDirs = Set(allSrcs.map { ($0 as NSString).deletingLastPathComponent })
                    for dir in sourceDirs where !dir.isEmpty {
                        try? CoreBridge.shared.invalidateCache(path: dir)
                    }
                }

                // I3: capture the detailed partial-failure message now
                // (getLastError is read-once) before the async UI refresh.
                let partialDetail = (success < total) ? CoreBridge.shared.getLastError() : ""

                // 计算 dst 路径用于撤销注册（best-effort：假设都成功）。
                // 保留两者项仅计入成功者，normalDstPaths 与 keepBothPairs 顺序对齐，
                // undoPairs 由 src 列表 + 成功项组成，避免单项失败时 zip 错配 src↔dst
                let normalDstPaths = srcs.map { src -> String in
                    let name = (src as NSString).lastPathComponent
                    return (destPath as NSString).appendingPathComponent(name)
                }
                let undoPairs = zip(srcs, normalDstPaths).map { (src: $0, dst: $1) } + keepBothPairs

                DispatchQueue.main.async {
                    self?.viewModel?.refresh()

                    // Bug 3 修复：跨面板拖拽时，若源文件来自对侧面板的当前目录，需刷新对侧面板
                    // （仅 move 操作会改变源目录；copy 不改变源，但为安全起见也刷新对侧）
                    if let counterpartPath = self?.counterpartViewModel?.currentPath,
                       !counterpartPath.isEmpty,
                       allSrcs.contains(where: { ($0 as NSString).deletingLastPathComponent == counterpartPath }) {
                        self?.counterpartViewModel?.refresh()
                    }

                    // 注册撤销（通过 viewModel?.undoManager 访问 per-window UndoManager）
                    if success > 0, let view = self, let vm = view.viewModel, let undoManager = vm.undoManager {
                        let counterpart = view.counterpartViewModel
                        if isMove {
                            let pairs = undoPairs
                            let actionName = "移动 \(success) 个项目"
                            // 注册撤销：移回原位。undoDragMove 会同步注册 redo（redoDragMove），
                            // 而 redoDragMove 处理器内又会注册反向 undo（= undoDragMove），
                            // 从而形成无限撤销/重做闭环。
                            undoManager.registerUndo(withTarget: view) { [weak counterpart] targetView in
                                targetView.undoDragMove(pairs: pairs, counterpart: counterpart, actionName: actionName)
                            }
                            undoManager.setActionName(actionName)
                        } else {
                            let pairs = undoPairs
                            let actionName = "复制 \(success) 个项目"
                            // 注册撤销：删除复制项。undoDragCopy 会同步注册 redo（redoDragCopy），
                            // 而 redoDragCopy 处理器内又会注册反向 undo（= undoDragCopy），
                            // 从而形成无限撤销/重做闭环。
                            undoManager.registerUndo(withTarget: view) { [weak counterpart] targetView in
                                targetView.undoDragCopy(pairs: pairs, counterpart: counterpart, actionName: actionName)
                            }
                            undoManager.setActionName(actionName)
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

    /// 判断是否为移动操作（访达语义）：
    /// 同盘 + 无修饰键 = 移动；同盘 + ⌘ = 复制
    /// 跨盘 + 无修饰键 = 复制；跨盘 + ⌘ = 移动
    /// - Parameter destPath: 真实拖放目标路径（网格目标即当前目录，默认取 viewModel?.currentPath）
    private func isMoveOperation(_ sender: NSDraggingInfo, destPath: String? = nil) -> Bool {
        // 读取拖拽过程中捕获的修饰键（比 NSApp.currentEvent 在回调中可靠）
        let commandPressed = lastDragModifierFlags.contains(.command)

        // 源与目标卷判定
        let dest = destPath ?? viewModel?.currentPath
        guard let dest = dest, !dest.isEmpty else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let srcPath = urls.first?.path else { return false }
        let sameVolume = isSameVolume(srcPath: srcPath, destPath: dest)

        // ⌘ 按下时反转默认行为（复制↔移动切换，访达语义）
        return commandPressed ? !sameVolume : sameVolume
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
