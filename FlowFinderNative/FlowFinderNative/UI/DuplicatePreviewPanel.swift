import Cocoa

// MARK: - DuplicatePreviewPanel

/// 重复文件预览面板（右侧 240pt）
/// 选中组的首个文件大图标 + 元数据网格 + 重复文件对比列表
class DuplicatePreviewPanel: NSView {

    /// 当前选中的组
    private var currentGroup: FFDuplicateGroup?

    // UI 引用
    private let previewBox = NSImageView()
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let metaStack = NSStackView()
    private let divider = NSBox()
    private let compareScrollView = NSScrollView()
    private let compareStack = NSStackView()

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

        // 大图标（56x56）
        previewBox.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        previewBox.contentTintColor = NSColor.secondaryLabelColor
        previewBox.imageScaling = .scaleProportionallyDown
        previewBox.translatesAutoresizingMaskIntoConstraints = false

        // 文件名
        fileNameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        fileNameLabel.textColor = NSColor.labelColor
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.cell?.truncatesLastVisibleLine = true
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false

        // 元数据网格
        metaStack.orientation = .vertical
        metaStack.spacing = 4
        metaStack.translatesAutoresizingMaskIntoConstraints = false

        // 分隔线
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        // 对比列表（滚动）
        compareScrollView.hasVerticalScroller = true
        compareScrollView.autohidesScrollers = true
        compareScrollView.drawsBackground = false
        compareScrollView.translatesAutoresizingMaskIntoConstraints = false

        compareStack.orientation = .vertical
        compareStack.spacing = 6
        compareStack.detachesHiddenViews = false
        compareStack.translatesAutoresizingMaskIntoConstraints = false
        compareScrollView.documentView = compareStack

        // 容器
        let container = NSStackView(views: [previewBox, fileNameLabel, metaStack, divider, compareScrollView])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.detachesHiddenViews = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            previewBox.widthAnchor.constraint(equalToConstant: 56),
            previewBox.heightAnchor.constraint(equalToConstant: 56),
            previewBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            fileNameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            fileNameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            metaStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            metaStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            compareScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            compareScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            compareStack.leadingAnchor.constraint(equalTo: compareScrollView.contentView.leadingAnchor),
            compareStack.trailingAnchor.constraint(equalTo: compareScrollView.contentView.trailingAnchor),
            compareStack.topAnchor.constraint(equalTo: compareScrollView.contentView.topAnchor),
            compareStack.widthAnchor.constraint(equalTo: compareScrollView.contentView.widthAnchor),
        ])
    }

    /// 更新预览面板内容
    /// - Parameter group: 选中的重复组
    func update(with group: FFDuplicateGroup) {
        currentGroup = group
        guard let firstFile = group.files.first else { return }

        // 大图标 + 文件名
        previewBox.image = NSImage(systemSymbolName: iconForFile(firstFile.name), accessibilityDescription: firstFile.name)
        fileNameLabel.stringValue = firstFile.name

        // 元数据网格
        metaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        metaStack.addArrangedSubview(makeMetaRow(label: "格式", value: extOf(firstFile.name).uppercased()))
        metaStack.addArrangedSubview(makeMetaRow(label: "大小", value: formatSize(firstFile.size)))
        if firstFile.modified > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(firstFile.modified))
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            metaStack.addArrangedSubview(makeMetaRow(label: "修改", value: formatter.string(from: date)))
        }
        metaStack.addArrangedSubview(makeMetaRow(label: "重复数", value: "\(group.files.count) 个"))

        // 对比列表
        compareStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for file in group.files {
            compareStack.addArrangedSubview(makeCompareItem(file: file, isFirst: file.path == firstFile.path))
        }
    }

    /// 创建元数据行
    private func makeMetaRow(label: String, value: String) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 10)
        labelField.textColor = NSColor.tertiaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false

        let valueField = NSTextField(labelWithString: value)
        valueField.font = NSFont.systemFont(ofSize: 11)
        valueField.textColor = NSColor.labelColor
        valueField.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(labelField)
        row.addSubview(valueField)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueField.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 16),
        ])
        return row
    }

    /// 创建对比列表项（卡片样式，FFGlassView .component 背景）
    private func makeCompareItem(file: FFDuplicateFile, isFirst: Bool) -> NSView {
        let card = FFGlassView(level: .component, cornerRadius: 4)
        card.translatesAutoresizingMaskIntoConstraints = false

        // 色块缩略图（16x16，按文件类型着色）
        let thumb = NSView()
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = colorForFile(file.name).cgColor
        thumb.layer?.cornerRadius = 3
        thumb.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: file.path)
        pathLabel.font = NSFont.systemFont(ofSize: 10)
        pathLabel.textColor = NSColor.labelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.cell?.truncatesLastVisibleLine = true
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSTextField(labelWithString: isFirst ? "保留" : "删除")
        badge.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        badge.textColor = isFirst ? NSColor.systemGreen : NSColor.systemRed
        badge.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [thumb, pathLabel, badge])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
            thumb.widthAnchor.constraint(equalToConstant: 16),
            thumb.heightAnchor.constraint(equalToConstant: 16),
            card.heightAnchor.constraint(equalToConstant: 28),
        ])
        return card
    }

    // MARK: - 辅助

    private func extOf(_ name: String) -> String {
        return (name as NSString).pathExtension
    }

    private func iconForFile(_ name: String) -> String {
        let ext = extOf(name).lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp", "svg"]
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v"]
        if ext == "pdf" { return "doc.richtext" }
        if imageExts.contains(ext) { return "photo" }
        if videoExts.contains(ext) { return "film" }
        return "doc"
    }

    private func colorForFile(_ name: String) -> NSColor {
        let ext = extOf(name).lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp", "svg"]
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v"]
        if ext == "pdf" { return .systemRed }
        if imageExts.contains(ext) { return .systemGreen }
        if videoExts.contains(ext) { return .systemPurple }
        return .systemGray
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
