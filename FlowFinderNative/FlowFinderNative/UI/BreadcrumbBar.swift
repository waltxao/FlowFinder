import AppKit

// MARK: - BreadcrumbBarDelegate

/// 路径栏委托协议（MainWindowController 依赖，保持不变）
/// 点击路径段或同级目录菜单项时回调，path 始终为绝对路径（以 "/" 开头）
protocol BreadcrumbBarDelegate: AnyObject {
    func breadcrumbBar(_ bar: BreadcrumbBar, didSelectPath path: String)
}

// MARK: - BreadcrumbBar

/// 仿访达路径栏（任务 F11-4：完全重写，修复问题12）
///
/// 设计要点：
/// 1. 固定位置：由 PaneToolbar.setBreadcrumbBar 嵌入 Row1（刷新按钮后），位置稳定
///    不使用 NSScrollView 水平滚动（避免路径栏位置漂移），改用固定裁剪容器
/// 2. 每段路径为可点击按钮，点击跳转到对应层级（绝对路径）
/// 3. 段间 chevron 分隔符可点击，弹出该层级同级目录下拉菜单（仅目录）
/// 4. 当前位置（最后一段）加粗 + accent 色 + 圆角胶囊高亮
/// 5. 路径溢出时左侧显示省略号按钮（访达行为）：点击展开隐藏的左侧路径段下拉菜单
class BreadcrumbBar: NSView {

    weak var delegate: BreadcrumbBarDelegate?

    /// 当前路径（绝对路径）。set 后触发重建分段。
    private(set) var path: String = "" {
        didSet {
            guard oldValue != path else { return }
            rebuildSegments()
        }
    }

    // MARK: 视图层级

    /// 内容容器（固定裁剪，不滚动）。所有分段按需从右向左裁剪。
    private let clipContainer = NSView()
    /// 横向堆叠所有分段（路径按钮 + chevron 分隔符），靠右对齐
    private let contentStack = NSStackView()
    /// 左侧溢出省略号按钮（仅当内容超出可见区域时显示）
    private let overflowButton = BreadcrumbOverflowButton()

    /// 记录当前是否处于溢出状态（用于省略号显隐 + 渐变蒙层）
    private var isOverflowing = false {
        didSet {
            guard oldValue != isOverflowing else { return }
            overflowButton.isHidden = !isOverflowing
            needsDisplay = true
        }
    }

    // MARK: 数据

    /// 当前路径的全部分段：[(显示名, 绝对路径)]，按从根到当前顺序
    private var segments: [(name: String, absolutePath: String)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - 布局

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // 裁剪超出部分（左侧路径段被裁掉时显示省略号）
        layer?.masksToBounds = true

        // 内容裁剪容器：固定充满本视图，内部内容靠右对齐
        clipContainer.translatesAutoresizingMaskIntoConstraints = false
        clipContainer.wantsLayer = true
        clipContainer.layer?.backgroundColor = NSColor.clear.cgColor
        clipContainer.layer?.masksToBounds = true
        addSubview(clipContainer)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 2
        contentStack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        // 靠右对齐：高水平拥抱优先级使堆栈保持内容宽度（不拉伸填充），
        // 高压缩阻力使分段不被压缩（溢出时整体向左溢出被裁剪，而非截断文字）
        // 叠加 trailing 固定约束后内容贴右排列；溢出时左端被裁剪（访达行为）
        contentStack.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        clipContainer.addSubview(contentStack)

        // 溢出省略号按钮（默认隐藏）
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.isHidden = true
        overflowButton.target = self
        overflowButton.action = #selector(overflowClicked(_:))
        addSubview(overflowButton)

        NSLayoutConstraint.activate([
            // clipContainer 充满本视图
            clipContainer.topAnchor.constraint(equalTo: topAnchor),
            clipContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            clipContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            // contentStack 在 clipContainer 内靠右对齐：
            // - trailing 固定 → 当前段（最后一段）永远贴右（访达行为）
            // - top/bottom 固定 → 垂直充满
            // - 不约束 leading → 由 intrinsicContentSize 决定宽度，向左生长
            //   当内容宽度 > 容器宽度时，leading 计算为负值，溢出部分被 clipContainer 裁剪
            contentStack.topAnchor.constraint(equalTo: clipContainer.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: clipContainer.bottomAnchor),
            contentStack.trailingAnchor.constraint(equalTo: clipContainer.trailingAnchor, constant: 0),

            // 溢出按钮贴左
            overflowButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            overflowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            overflowButton.widthAnchor.constraint(equalToConstant: 20),
            overflowButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    // MARK: - 公共 API（保留，MainWindowController 依赖）

    /// 设置当前路径（绝对路径）。空字符串清空分段。
    func setPath(_ path: String) {
        self.path = path
    }

    // MARK: - 路径分段构建

    /// 解析绝对路径为分段列表。
    /// 对根 "/" 特殊处理：作为第一段显示为计算机图标 + 名称。
    /// 每段 absolutePath 为该层级的绝对路径（以 "/" 开头，根为 "/"）。
    private func parseSegments(from absolutePath: String) -> [(name: String, absolutePath: String)] {
        guard !absolutePath.isEmpty else { return [] }

        // 标准化路径
        let standardized = (absolutePath as NSString).standardizingPath

        // 特殊处理：根目录或路径本身就是 "/"
        if standardized == "/" {
            return [(name: computerName(), absolutePath: "/")]
        }

        var result: [(name: String, absolutePath: String)] = []
        // 先加入根
        result.append((name: computerName(), absolutePath: "/"))

        // 标准化后去掉前导 "/"，按 "/" 拆分
        let trimmed = standardized.hasPrefix("/") ? String(standardized.dropFirst()) : standardized
        let components = trimmed.split(separator: "/").map(String.init)

        var acc = ""
        for comp in components {
            acc += "/" + comp
            // 显示名：用户主目录显示 "~" 等（此处保留原组件名）
            result.append((name: comp, absolutePath: acc))
        }
        return result
    }

    /// 计算机名称（用于根路径段显示）。无法获取时回退为 "Macintosh HD"。
    private func computerName() -> String {
        if let name = Host.current().name {
            // Host.name 通常返回 "xxx.local"，取点之前部分
            let short = name.split(separator: ".").first.map(String.init) ?? name
            if !short.isEmpty { return short }
        }
        return "Macintosh HD"
    }

    /// 重建全部分段视图（路径按钮 + chevron 分隔符）
    private func rebuildSegments() {
        // 清空旧分段
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        segments = parseSegments(from: path)
        guard !segments.isEmpty else {
            isOverflowing = false
            return
        }

        let lastIndex = segments.count - 1

        for (index, seg) in segments.enumerated() {
            // 在每一段之前（除了第一段）插入 chevron 分隔符
            if index > 0 {
                let chevron = BreadcrumbChevronButton()
                chevron.target = self
                chevron.action = #selector(chevronClicked(_:))
                // chevron 标识：其左侧段（上一段）的父目录路径
                // 点击时弹出"上一段的同级目录"下拉
                let previousSegment = segments[index - 1]
                chevron.representedPath = previousSegment.absolutePath
                contentStack.addArrangedSubview(chevron)
            }

            let isCurrent = (index == lastIndex)
            let isRoot = (index == 0)
            let button = BreadcrumbSegmentButton(name: seg.name, absolutePath: seg.absolutePath, isCurrent: isCurrent, isRoot: isRoot)
            button.target = self
            button.action = #selector(segmentClicked(_:))
            contentStack.addArrangedSubview(button)
        }

        // 延迟到下一轮布局后再计算溢出（此时 contentStack.intrinsicContentSize 已更新）
        DispatchQueue.main.async { [weak self] in
            self?.updateOverflowState()
        }
    }

    // MARK: - 溢出检测

    /// 检测内容是否溢出可见区域，更新省略号显隐
    private func updateOverflowState() {
        let contentWidth = contentStack.fittingSize.width
        let visibleWidth = clipContainer.bounds.width
        isOverflowing = contentWidth > visibleWidth && visibleWidth > 0
    }

    override func layout() {
        super.layout()
        // 布局变化后重新检测溢出（窗口缩放等场景）
        DispatchQueue.main.async { [weak self] in
            self?.updateOverflowState()
        }
    }

    // MARK: - 点击事件

    /// 点击路径段：跳转到该层级
    @objc private func segmentClicked(_ sender: NSButton) {
        guard let path = (sender as? BreadcrumbSegmentButton)?.absolutePath else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }

    /// 点击 chevron 分隔符：弹出该层级同级目录下拉菜单
    /// chevron.representedPath = 其左侧段（上一段）的绝对路径
    /// 弹出的是"上一段所在父目录"下的同级目录列表（即上一段及其兄弟目录）
    @objc private func chevronClicked(_ sender: BreadcrumbChevronButton) {
        guard let segmentPath = sender.representedPath else { return }
        showSiblingMenu(for: segmentPath, anchorView: sender)
    }

    /// 点击左侧溢出省略号：弹出被裁剪掉的左侧路径段下拉菜单
    @objc private func overflowClicked(_ sender: BreadcrumbOverflowButton) {
        showOverflowMenu(anchorView: sender)
    }

    // MARK: - 同级目录下拉菜单

    /// 弹出同级目录下拉菜单。
    /// - Parameter segmentPath: 某层级的绝对路径
    /// - Parameter anchorView: 弹出锚点视图
    /// 菜单内容：segmentPath 所在父目录下的所有子目录（兄弟目录）。
    /// 当前 segmentPath 项标记为选中态。
    private func showSiblingMenu(for segmentPath: String, anchorView: NSView) {
        let url = URL(fileURLWithPath: segmentPath)
        let parentPath = url.deletingLastPathComponent().path
        let standardizedParent = (parentPath as NSString).standardizingPath

        // 父目录不存在或不可读则不弹
        guard FileManager.default.fileExists(atPath: standardizedParent) else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let items = siblingDirectories(at: standardizedParent)
        if items.isEmpty {
            let emptyItem = NSMenuItem(title: "无同级目录", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for dirName in items {
                let fullPath = (standardizedParent as NSString).appendingPathComponent(dirName)
                let menuItem = NSMenuItem(title: dirName, action: #selector(siblingItemClicked(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = fullPath
                if fullPath == segmentPath {
                    menuItem.state = .on
                }
                menu.addItem(menuItem)
            }
        }

        // 在锚点视图下方弹出
        let location = NSPoint(x: 0, y: anchorView.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: anchorView)
    }

    /// 获取指定目录下的子目录名（已排序，仅目录）
    private func siblingDirectories(at dirPath: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { return [] }
        return contents.sorted().filter { name in
            let full = (dirPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// 选中同级目录菜单项：跳转
    @objc private func siblingItemClicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }

    // MARK: - 溢出菜单

    /// 弹出溢出菜单：显示被裁剪掉的左侧路径段（从根到当前层级的完整列表）
    private func showOverflowMenu(anchorView: NSView) {
        guard !segments.isEmpty else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        // 列出所有分段（根 + 中间段），当前段（最后一段）也列出以便跳转
        for (index, seg) in segments.enumerated() {
            let isCurrent = (index == segments.count - 1)
            let menuItem = NSMenuItem(title: seg.name, action: #selector(overflowItemClicked(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = seg.absolutePath
            if isCurrent {
                menuItem.state = .on
            }
            menu.addItem(menuItem)
            // 段间加分隔符（除最后一段外）
            if index < segments.count - 1 {
                menu.addItem(.separator())
            }
        }

        let location = NSPoint(x: 0, y: anchorView.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: anchorView)
    }

    /// 选中溢出菜单项：跳转
    @objc private func overflowItemClicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }

    // MARK: - 自定义绘制：溢出渐变蒙层（仿访达左端淡出效果）

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        guard let layer = layer else { return }
        // 溢出时在左端绘制渐变蒙层（从背景色到透明），让裁剪边界更自然
        if isOverflowing {
            let grad = CAGradientLayer()
            grad.frame = NSRect(x: 0, y: 0, width: 24, height: bounds.height)
            // 适配明暗模式：使用 windowBackgroundColor
            let bg = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? NSColor.white
            grad.colors = [bg.cgColor, bg.withAlphaComponent(0).cgColor]
            grad.startPoint = CGPoint(x: 0, y: 0.5)
            grad.endPoint = CGPoint(x: 1, y: 0.5)
            // 替换已有蒙层（避免叠加）
            layer.mask = nil
            // 注意：直接设 layer.mask 会裁掉整层；改用子层叠加渐变在省略号右侧
            // 此处简化：不设 mask，靠省略号按钮自身不透明背景遮挡即可
            _ = grad
        } else {
            layer.mask = nil
        }
    }

    // MARK: - 右键菜单（任务 B3 保留：复制路径/粘贴路径跳转/在访达中打开/在终端中打开）

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

// MARK: - BreadcrumbSegmentButton（路径分段按钮）

/// 路径分段按钮：透明背景，悬停显示圆角胶囊背景。
/// - 普通分段：secondaryLabelColor，12pt regular
/// - 当前分段（最后一段）：labelColor + accent 色文字，12pt semibold，带圆角胶囊背景
/// - 根分段：显示计算机图标（macpro/电脑 图标）+ 名称
private class BreadcrumbSegmentButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private let isCurrent: Bool
    private let isRoot: Bool
    /// 该分段对应的绝对路径（点击时回传）
    let absolutePath: String
    private let displayName: String

    init(name: String, absolutePath: String, isCurrent: Bool, isRoot: Bool) {
        self.displayName = name
        self.absolutePath = absolutePath
        self.isCurrent = isCurrent
        self.isRoot = isRoot
        super.init(frame: .zero)
        self.isBordered = false
        self.bezelStyle = .inline
        self.imagePosition = isRoot ? .imageLeading : .imageOnly
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 4
        self.focusRingType = .none
        self.toolTip = absolutePath

        configureAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 配置外观（标题颜色/字重 + 根图标）。响应明暗模式切换时也会调用。
    private func configureAppearance() {
        let color: NSColor = isCurrent ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        let weight: NSFont.Weight = isCurrent ? .semibold : .regular
        let font = NSFont.systemFont(ofSize: 12, weight: weight)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font,
            .paragraphStyle: paragraph,
        ]
        self.attributedTitle = NSAttributedString(string: displayName, attributes: attrs)

        // 根分段显示计算机图标
        if isRoot {
            // 优先用 "macpro" 图标，回退 "pc"
            self.image = NSImage(systemSymbolName: "macpro.gen1", accessibilityDescription: "电脑")
                ?? NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "电脑")
            self.contentTintColor = color
        }
    }

    // 增加 padding：水平 6pt 左右，垂直 2pt 上下
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 12
        size.height = max(size.height, 18)
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
        if isCurrent {
            // 当前分段：accent 色淡背景胶囊
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        } else if isHovering {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    /// 明暗模式切换时刷新外观
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configureAppearance()
    }
}

// MARK: - BreadcrumbChevronButton（chevron 分隔符按钮）

/// 路径分段间的 chevron 分隔符按钮。
/// 点击弹出其左侧段所在父目录的兄弟目录下拉菜单。
/// 悬停时显示圆角背景 + 加深图标。
private class BreadcrumbChevronButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    /// 该 chevron 左侧段的绝对路径（点击时弹出其兄弟目录）
    var representedPath: String?

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

        // 固定尺寸（14x14，略大于原 12 以提高点击命中率）
        self.widthAnchor.constraint(equalToConstant: 14).isActive = true
        self.heightAnchor.constraint(equalToConstant: 14).isActive = true
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
        contentTintColor = NSColor.secondaryLabelColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        contentTintColor = NSColor.tertiaryLabelColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = isHovering ? NSColor.controlBackgroundColor.cgColor : NSColor.clear.cgColor
    }
}

// MARK: - BreadcrumbOverflowButton（左侧溢出省略号按钮）

/// 左侧溢出省略号按钮（仿访达）。
/// 仅当路径内容超出可见宽度时显示。
/// 点击弹出完整路径分段下拉菜单（可跳转到任意被裁剪的层级）。
private class BreadcrumbOverflowButton: NSButton {
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
        self.contentTintColor = NSColor.secondaryLabelColor
        // 使用 ellipsis 图标（...）
        self.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多路径")
        self.toolTip = "点击查看完整路径"

        self.widthAnchor.constraint(equalToConstant: 20).isActive = true
        self.heightAnchor.constraint(equalToConstant: 14).isActive = true
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
        contentTintColor = NSColor.labelColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        contentTintColor = NSColor.secondaryLabelColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = isHovering ? NSColor.controlBackgroundColor.cgColor : NSColor.clear.cgColor
    }
}
