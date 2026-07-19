import Cocoa
import Combine

// MARK: - DetailsBar

class DetailsBar: NSView {
    private var file: FileEntry?
    private var selectedCount: Int = 0
    private var collapsed: Bool = false

    private var iconView: NSImageView!
    private var nameField: NSTextField!
    private var typeField: NSTextField!
    private var sizeField: NSTextField!
    private var modifiedField: NSTextField!
    private var createdField: NSTextField!
    private var tagsField: NSTextField!
    private var collapseButton: NSButton!

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
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        // Icon
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Collapse button
        collapseButton = NSButton()
        collapseButton.title = ""
        collapseButton.bezelStyle = .texturedRounded
        collapseButton.target = self
        collapseButton.action = #selector(collapseClicked)
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collapseButton)

        // Details grid
        let detailsStack = NSStackView()
        detailsStack.orientation = .vertical
        detailsStack.spacing = 4
        detailsStack.translatesAutoresizingMaskIntoConstraints = false

        nameField = createDetailField(label: "名称:")
        typeField = createDetailField(label: "类型:")
        sizeField = createDetailField(label: "大小:")
        modifiedField = createDetailField(label: "修改:")
        createdField = createDetailField(label: "创建:")
        tagsField = createDetailField(label: "标签:")

        detailsStack.addArrangedSubview(nameField)
        detailsStack.addArrangedSubview(typeField)
        detailsStack.addArrangedSubview(sizeField)
        detailsStack.addArrangedSubview(modifiedField)
        detailsStack.addArrangedSubview(createdField)
        detailsStack.addArrangedSubview(tagsField)

        addSubview(detailsStack)

        // Constraints
        NSLayoutConstraint.activate([
            collapseButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            collapseButton.widthAnchor.constraint(equalToConstant: 24),
            collapseButton.heightAnchor.constraint(equalToConstant: 24),

            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            detailsStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            detailsStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            detailsStack.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -8),
            detailsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func createDetailField(label: String) -> NSTextField {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        labelView.textColor = NSColor.secondaryLabelColor

        let valueView = NSTextField(labelWithString: "")
        valueView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        valueView.textColor = NSColor.labelColor
        valueView.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [labelView, valueView])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY

        // Store reference to value view for updates
        objc_setAssociatedObject(stack, "valueField", valueView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let container = NSView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Return the value field directly so we can update it
        return valueView
    }

    // MARK: - Public API

    func setFile(_ file: FileEntry?) {
        self.file = file
        updateDetails()
    }

    func setSelectedCount(_ count: Int) {
        self.selectedCount = count
        updateDetails()
    }

    // MARK: - Private

    private func updateDetails() {
        if selectedCount > 1 {
            nameField.stringValue = "已选中 \(selectedCount) 项"
            typeField.stringValue = ""
            sizeField.stringValue = ""
            modifiedField.stringValue = ""
            createdField.stringValue = ""
            tagsField.stringValue = ""
            iconView.image = nil
            return
        }

        guard let file = file else {
            nameField.stringValue = "未选择文件"
            typeField.stringValue = ""
            sizeField.stringValue = ""
            modifiedField.stringValue = ""
            createdField.stringValue = ""
            tagsField.stringValue = ""
            iconView.image = nil
            return
        }

        nameField.stringValue = file.name
        typeField.stringValue = file.isDirectory ? "文件夹" : (file.fileExtension.isEmpty ? "文件" : file.fileExtension)
        sizeField.stringValue = file.isDirectory ? "-" : formatBytes(file.size)
        modifiedField.stringValue = formatDate(file.modificationDate)

        // Tags (placeholder for now)
        tagsField.stringValue = "无"

        // Icon
        if file.isDirectory {
            iconView.image = NSImage(named: NSImage.folderName)
        } else {
            if let fileIcon = NSImage(systemSymbolName: "doc", accessibilityDescription: nil) {
                iconView.image = fileIcon
            } else {
                iconView.image = NSImage(named: NSImage.folderName)
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @objc private func collapseClicked() {
        collapsed.toggle()
        if collapsed {
            // Show collapsed state
            for subview in subviews {
                subview.isHidden = subview == iconView || subview == collapseButton
            }
            frame.size.height = 24
        } else {
            // Show expanded state
            for subview in subviews {
                subview.isHidden = false
            }
            frame.size.height = 120
        }
    }
}
