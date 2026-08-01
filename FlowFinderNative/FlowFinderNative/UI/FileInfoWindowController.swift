import Cocoa
import UniformTypeIdentifiers

/// 仿 macOS 访达"显示简介"独立窗口
///
/// 显示文件的图标、名称、种类、大小、位置、创建/修改日期、标签和权限信息。
/// 文件夹大小异步计算，避免阻塞主线程。
/// 任务 F11-2: 窗口实体背景（windowBackgroundColor），移除透明玻璃架构（v0.6.7）。
public class FileInfoWindowController: NSWindowController {

    // MARK: - State

    private var filePath: String

    // MARK: - UI Elements

    private var iconImageView: NSImageView!
    private var nameLabel: NSTextField!
    private var kindValueLabel: NSTextField!
    private var sizeValueLabel: NSTextField!
    private var locationValueLabel: NSTextField!
    private var createdValueLabel: NSTextField!
    private var modifiedValueLabel: NSTextField!
    private var tagsContainerView: TagPillsContainerView!
    private var permissionLabel: NSTextField!

    // MARK: - Init

    public init(filePath: String) {
        self.filePath = filePath
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = (filePath as NSString).lastPathComponent
        window.center()
        window.isReleasedWhenClosed = true
        // 任务 F11-2: 实体窗口背景（v0.6.7）
        // 移除透明窗口配置（isOpaque=false + backgroundColor=.clear），改为实体窗口背景。
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.minSize = NSSize(width: 280, height: 360)
        super.init(window: window)
        setupUI()
        loadFileInfo(filePath: filePath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// 更新内容并显示窗口
    public func showInfoWindow(filePath: String) {
        self.filePath = filePath
        window?.title = (filePath as NSString).lastPathComponent
        loadFileInfo(filePath: filePath)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let window = window else { return }
        let contentView = window.contentView!

        // 任务 F11-2: 实体背景容器（替代 NSVisualEffectView .underWindowBackground，v0.6.7）
        // 使用系统动态 windowBackgroundColor，与窗口背景一致。
        let backgroundContainer = NSView()
        backgroundContainer.translatesAutoresizingMaskIntoConstraints = false
        backgroundContainer.wantsLayer = true
        backgroundContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.addSubview(backgroundContainer)

        // 内容容器（垂直堆叠）
        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundContainer.addSubview(contentStack)

        // 顶部图标（用 wrapper 实现居中）
        let iconWrapper = NSView()
        iconWrapper.translatesAutoresizingMaskIntoConstraints = false

        iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconWrapper.addSubview(iconImageView)

        // 文件名（居中粗体 14pt）
        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 14)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textColor = NSColor.labelColor
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.cell?.wraps = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // 元信息容器
        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 8
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        // 构建各元信息行
        kindValueLabel = makeValueLabel()
        sizeValueLabel = makeValueLabel()
        locationValueLabel = makeValueLabel()
        createdValueLabel = makeValueLabel()
        modifiedValueLabel = makeValueLabel()
        tagsContainerView = TagPillsContainerView()

        let kindRow = makeInfoRow(title: "种类：", valueView: kindValueLabel)
        let sizeRow = makeInfoRow(title: "大小：", valueView: sizeValueLabel)
        let locationRow = makeInfoRow(title: "位置：", valueView: locationValueLabel)
        let createdRow = makeInfoRow(title: "创建日期：", valueView: createdValueLabel)
        let modifiedRow = makeInfoRow(title: "修改日期：", valueView: modifiedValueLabel)
        let tagsRow = makeInfoRow(title: "标签：", valueView: tagsContainerView)

        for row in [kindRow, sizeRow, locationRow, createdRow, modifiedRow, tagsRow] {
            infoStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: infoStack.widthAnchor).isActive = true
        }

        // 权限信息
        permissionLabel = NSTextField(labelWithString: "")
        permissionLabel.font = NSFont.systemFont(ofSize: 11)
        permissionLabel.textColor = NSColor.secondaryLabelColor
        permissionLabel.lineBreakMode = .byTruncatingTail
        permissionLabel.cell?.truncatesLastVisibleLine = true
        permissionLabel.cell?.wraps = false
        permissionLabel.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(iconWrapper)
        contentStack.addArrangedSubview(nameLabel)
        contentStack.addArrangedSubview(separator)
        contentStack.addArrangedSubview(infoStack)
        contentStack.addArrangedSubview(permissionLabel)

        // 让需要占满宽度的子视图与 contentStack 等宽
        iconWrapper.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        nameLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        infoStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        permissionLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            backgroundContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: backgroundContainer.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: backgroundContainer.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: backgroundContainer.trailingAnchor, constant: -16),

            iconImageView.topAnchor.constraint(equalTo: iconWrapper.topAnchor),
            iconImageView.bottomAnchor.constraint(equalTo: iconWrapper.bottomAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: iconWrapper.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),
        ])

        // bottom 用低优先级约束，允许内容多于可见区域时扩展（用户可拉伸窗口）
        let bottomConstraint = contentStack.bottomAnchor.constraint(
            equalTo: backgroundContainer.bottomAnchor, constant: -16
        )
        bottomConstraint.priority = .defaultLow
        bottomConstraint.isActive = true
    }

    /// 创建元信息值文本标签（单行、中间截断）
    private func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.wraps = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// 创建一行元信息：标题（固定宽度右对齐）+ 值视图（占满剩余宽度）
    private func makeInfoRow(title: String, valueView: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.cell?.wraps = false
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        valueView.translatesAutoresizingMaskIntoConstraints = false
        valueView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, valueView])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    // MARK: - Load File Info

    private func loadFileInfo(filePath: String) {
        let fm = FileManager.default

        // 1. 图标
        iconImageView.image = NSWorkspace.shared.icon(forFile: filePath)

        // 2. 文件名
        nameLabel.stringValue = (filePath as NSString).lastPathComponent

        // 3. 是否为文件夹
        var isDir: ObjCBool = false
        let fileExists = fm.fileExists(atPath: filePath, isDirectory: &isDir)
        let isDirectory = fileExists && isDir.boolValue

        // 4. 种类
        kindValueLabel.stringValue = kindString(for: filePath, isDirectory: isDirectory)

        // 5. 位置（目录完整路径，tooltip 显示完整路径）
        let dir = (filePath as NSString).deletingLastPathComponent
        locationValueLabel.stringValue = dir
        locationValueLabel.toolTip = dir

        // 6. 元信息（大小、日期）
        if let attrs = try? fm.attributesOfItem(atPath: filePath) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            if let created = attrs[.creationDate] as? Date {
                createdValueLabel.stringValue = dateFormatter.string(from: created)
            } else {
                createdValueLabel.stringValue = "—"
            }

            if let modified = attrs[.modificationDate] as? Date {
                modifiedValueLabel.stringValue = dateFormatter.string(from: modified)
            } else {
                modifiedValueLabel.stringValue = "—"
            }

            // 大小：文件直接显示，文件夹异步计算
            if isDirectory {
                sizeValueLabel.stringValue = "计算中…"
                calculateDirectorySizeAsync(at: filePath)
            } else if let size = attrs[.size] as? NSNumber {
                sizeValueLabel.stringValue = FileInfoWindowController.formatFileSize(size.int64Value)
            } else {
                sizeValueLabel.stringValue = "—"
            }
        } else {
            sizeValueLabel.stringValue = "—"
            createdValueLabel.stringValue = "—"
            modifiedValueLabel.stringValue = "—"
        }

        // 7. 权限
        permissionLabel.stringValue = permissionString(for: filePath)

        // 8. 标签
        let tags = TagBridge.shared.getTags(path: filePath)
        tagsContainerView.updateTags(tags)
    }

    /// 异步计算文件夹大小与项目数，主线程更新 UI
    private func calculateDirectorySizeAsync(at path: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let size = FileInfoWindowController.directorySize(at: path)
            let count = FileInfoWindowController.directoryItemCount(at: path)
            let sizeString = FileInfoWindowController.formatFileSize(size)
            let display = "\(sizeString)（\(count) 项）"
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 仅当仍指向同一路径时更新，避免竞态
                if path == self.filePath {
                    self.sizeValueLabel.stringValue = display
                }
            }
        }
    }

    // MARK: - Helpers

    /// 递归计算目录总大小（字节）
    private static func directorySize(at path: String) -> Int64 {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            ) else { continue }
            if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// 顶层子项数量
    private static func directoryItemCount(at path: String) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return 0
        }
        return contents.count
    }

    /// 格式化字节大小为 "X MB" / "X KB" / "X GB"
    private static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: bytes)
    }

    /// 文件种类描述
    private func kindString(for path: String, isDirectory: Bool) -> String {
        if isDirectory {
            return "文件夹"
        }
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty {
            if let type = UTType(filenameExtension: ext),
               let desc = type.localizedDescription {
                return desc
            }
            return "\(ext.uppercased()) 文件"
        }
        return "文件"
    }

    /// 当前用户对该文件的访问权限描述
    private func permissionString(for path: String) -> String {
        let fm = FileManager.default
        let readable = fm.isReadableFile(atPath: path)
        let writable = fm.isWritableFile(atPath: path)
        if readable && writable {
            return "您拥有：读写"
        } else if readable {
            return "您拥有：只读"
        } else if writable {
            return "您拥有：只写"
        } else {
            return "您拥有：无访问权限"
        }
    }
}

// MARK: - TagPillsContainerView

/// 标签药丸容器：横向 wrap 自动换行布局
/// 样式参考 ff-pill-tag：24pt 高、胶囊形圆角、8x8 圆点、12pt 文字
private final class TagPillsContainerView: NSView {

    // MARK: - Layout Constants

    private let pillHeight: CGFloat = 24
    private let pillGap: CGFloat = 6          // 药丸之间水平+垂直间距
    private let dotSize: CGFloat = 8
    private let pillHPadding: CGFloat = 10
    private let pillGapIconText: CGFloat = 6

    // MARK: - State

    private var tags: [Tag] = []
    private var heightConstraint: NSLayoutConstraint!

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        heightConstraint = heightAnchor.constraint(equalToConstant: 18)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    func updateTags(_ newTags: [Tag]) {
        self.tags = newTags
        rebuildPills()
        needsLayout = true
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutPills()
    }

    // MARK: - Pill Building

    private func rebuildPills() {
        subviews.forEach { $0.removeFromSuperview() }

        if tags.isEmpty {
            let none = NSTextField(labelWithString: "无标签")
            none.font = NSFont.systemFont(ofSize: 12)
            none.textColor = NSColor.tertiaryLabelColor
            none.translatesAutoresizingMaskIntoConstraints = false
            addSubview(none)
            NSLayoutConstraint.activate([
                none.leadingAnchor.constraint(equalTo: leadingAnchor),
                none.topAnchor.constraint(equalTo: topAnchor),
                none.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            heightConstraint.constant = 18
            return
        }

        for tag in tags {
            let pill = makePill(tag: tag)
            addSubview(pill)
        }
    }

    /// 计算每个药丸的 frame 并设置，同时更新容器高度
    private func layoutPills() {
        guard !tags.isEmpty else { return }
        let width = bounds.width
        guard width > 0 else { return }

        var rows: [[NSRect]] = []
        var currentRow: [NSRect] = []
        var currentX: CGFloat = 0
        let gap = pillGap

        for tag in tags {
            let pillW = pillWidth(for: tag)
            if currentX + pillW > width && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                currentX = 0
            }
            currentRow.append(NSRect(x: currentX, y: 0, width: pillW, height: pillHeight))
            currentX += pillW + gap
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        let totalHeight: CGFloat
        if rows.isEmpty {
            totalHeight = 0
        } else {
            totalHeight = CGFloat(rows.count) * pillHeight
                + CGFloat(max(rows.count - 1, 0)) * pillGap
        }
        heightConstraint.constant = totalHeight

        var idx = 0
        for (rowIdx, row) in rows.enumerated() {
            let y = CGFloat(rowIdx) * (pillHeight + pillGap)
            for frame in row {
                guard idx < subviews.count else { break }
                subviews[idx].frame = NSRect(
                    x: frame.origin.x,
                    y: y,
                    width: frame.size.width,
                    height: pillHeight
                )
                idx += 1
            }
        }
    }

    /// 计算单个药丸宽度：左 padding + dot + gap + text + 右 padding
    private func pillWidth(for tag: Tag) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let textWidth = (tag.name as NSString).size(withAttributes: [.font: font]).width
        return pillHPadding + dotSize + pillGapIconText + ceil(textWidth) + pillHPadding
    }

    private func makePill(tag: Tag) -> NSView {
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        pill.squircleRadius = pillHeight / 2  // 胶囊圆角

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = dotSize / 2

        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail

        pill.addSubview(dot)
        pill.addSubview(label)

        let pillW = pillWidth(for: tag)
        dot.frame = NSRect(
            x: pillHPadding,
            y: (pillHeight - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        label.frame = NSRect(
            x: pillHPadding + dotSize + pillGapIconText,
            y: (pillHeight - 16) / 2,
            width: pillW - pillHPadding * 2 - dotSize - pillGapIconText,
            height: 16
        )
        return pill
    }
}
