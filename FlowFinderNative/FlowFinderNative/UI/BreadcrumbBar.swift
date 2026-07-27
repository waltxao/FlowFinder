import AppKit

protocol BreadcrumbBarDelegate: AnyObject {
    func breadcrumbBar(_ bar: BreadcrumbBar, didSelectPath path: String)
}

/// 路径面包屑导航栏
/// 显示当前路径，每段可点击跳转
class BreadcrumbBar: NSView {

    weak var delegate: BreadcrumbBarDelegate?

    private(set) var path: String = "" {
        didSet { updateBreadcrumbs() }
    }

    private let scrollView = NSScrollView()
    private let containerStackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        containerStackView.orientation = .horizontal
        containerStackView.spacing = 4
        containerStackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = containerStackView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    func setPath(_ path: String) {
        self.path = path
    }

    // 任务 B2: 重写面包屑渲染，分隔符为 chevron.right 可点击弹出同级目录
    private func updateBreadcrumbs() {
        containerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let components = path.split(separator: "/").map(String.init)
        var currentPath = ""
        let lastIndex = components.count - 1

        for (index, component) in components.enumerated() {
            if index > 0 {
                currentPath += "/"
            }
            currentPath += component

            // 分隔符 chevron.right（可点击，弹出该层级同级目录下拉菜单）
            if index > 0 {
                let separator = BreadcrumbSeparatorButton()
                separator.target = self
                separator.action = #selector(siblingMenuClicked(_:))
                // separator 的 identifier 设为**当前分段路径**，点击时弹出此层级的同级目录
                separator.identifier = NSUserInterfaceItemIdentifier(currentPath)
                containerStackView.addArrangedSubview(separator)
            }

            let isCurrent = (index == lastIndex)
            let button = BreadcrumbSegmentButton(title: component, isCurrent: isCurrent)
            button.target = self
            button.action = #selector(pathClicked(_:))
            button.identifier = NSUserInterfaceItemIdentifier(currentPath)
            containerStackView.addArrangedSubview(button)
        }
    }

    @objc private func pathClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }

    // 任务 B2: 同级目录下拉菜单（点击 chevron.right 分隔符触发）
    @objc private func siblingMenuClicked(_ sender: NSView) {
        guard let segmentPath = sender.identifier?.rawValue else { return }

        // 获取父目录
        let url = URL(fileURLWithPath: segmentPath)
        let parentPath = url.deletingLastPathComponent().path
        let standardizedParent = (parentPath as NSString).standardizingPath

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: standardizedParent) else {
            return
        }

        let menu = NSMenu()

        for item in contents.sorted() {
            let fullPath = (standardizedParent as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                let menuItem = NSMenuItem(title: item, action: #selector(siblingItemClicked(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = fullPath
                if fullPath == segmentPath {
                    menuItem.state = .on
                }
                menu.addItem(menuItem)
            }
        }

        if menu.items.isEmpty {
            let emptyItem = NSMenuItem(title: "无同级目录", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        // 在分隔符下方弹出菜单
        let location = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    @objc private func siblingItemClicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }

    // MARK: - 任务 B3: 右键菜单（复制路径/粘贴路径跳转/在访达中打开/在终端中打开）

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "复制路径", action: #selector(copyPathToClipboard), keyEquivalent: "")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyItem.target = self
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "粘贴路径跳转", action: #selector(pastePathAndNavigate), keyEquivalent: "")
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        pasteItem.target = self
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let finderItem = NSMenuItem(title: "在访达中打开", action: #selector(openInFinder), keyEquivalent: "")
        finderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        finderItem.target = self
        menu.addItem(finderItem)

        let terminalItem = NSMenuItem(title: "在终端中打开", action: #selector(openInTerminal), keyEquivalent: "")
        terminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        terminalItem.target = self
        menu.addItem(terminalItem)

        return menu
    }

    @objc private func copyPathToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }

    @objc private func pastePathAndNavigate() {
        guard let clipped = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = clipped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 验证路径存在
        if FileManager.default.fileExists(atPath: trimmed) {
            delegate?.breadcrumbBar(self, didSelectPath: trimmed)
        }
    }

    @objc private func openInFinder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openInTerminal() {
        // 使用 osascript 在 Terminal 中 cd 到当前目录
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"cd \\\"\(escaped)\\\"\"\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - 任务 A2b: 面包屑分段按钮

/// 面包屑分段按钮：透明背景，悬停时显示 controlBackgroundColor 圆角背景
/// - 字体 12pt，普通分段 secondaryLabelColor，当前分段 labelColor + semibold
/// - 圆角 4pt，padding 2x4
private class BreadcrumbSegmentButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private let isCurrent: Bool

    init(title: String, isCurrent: Bool) {
        self.isCurrent = isCurrent
        super.init(frame: .zero)
        self.isBordered = false
        self.bezelStyle = .inline
        self.imagePosition = .imageOnly
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 4
        self.focusRingType = .none

        let color = isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor
        let weight: NSFont.Weight = isCurrent ? .semibold : .regular
        let font = NSFont.systemFont(ofSize: 12, weight: weight)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font,
            .paragraphStyle: paragraph,
        ]
        self.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        self.toolTip = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 增加 padding：水平 4pt 左右，垂直 2pt 上下
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 8
        size.height = max(size.height, 16)
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea {
            removeTrackingArea(area)
        }
        let newArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        hoverTrackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if isHovering && !isCurrent {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

// MARK: - 任务 B2: 路径分隔符按钮（chevron.right 可点击）

/// 路径分段间的 chevron.right 分隔符按钮
/// 点击弹出该层级同级目录下拉菜单（仅显示文件夹）
/// 悬停时显示 controlBackgroundColor 圆角背景
private class BreadcrumbSeparatorButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isBordered = false
        self.bezelStyle = .inline
        self.imagePosition = .imageOnly
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 3
        self.focusRingType = .none
        self.contentTintColor = NSColor.tertiaryLabelColor
        self.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "同级目录")
        self.toolTip = "点击查看同级目录"

        // 固定尺寸（10x10）
        self.widthAnchor.constraint(equalToConstant: 12).isActive = true
        self.heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea {
            removeTrackingArea(area)
        }
        let newArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        hoverTrackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        // 悬停时加深图标颜色
        contentTintColor = NSColor.secondaryLabelColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        contentTintColor = NSColor.tertiaryLabelColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if isHovering {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
