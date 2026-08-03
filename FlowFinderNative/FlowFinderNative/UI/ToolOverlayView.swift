import Cocoa

/// v0.6.9: 工具选择覆盖页
/// 点击侧边栏工具按钮后在当前激活操作区覆盖显示，大方块布局
/// 每个工具包含大图图标 + 名称 + 介绍，右上角关闭按钮
public class ToolOverlayView: NSView {

    /// 工具项定义
    public struct ToolItem {
        let icon: String          // SF Symbol 名称
        let title: String         // 工具名称
        let description: String   // 简短介绍
        let isEnabled: Bool       // 是否可用
        let action: (() -> Void)? // 点击回调
    }

    /// 关闭回调
    public var onClose: (() -> Void)?

    /// 工具项列表
    private let tools: [ToolItem]

    /// 初始化
    /// - Parameter tools: 工具项列表
    public init(tools: [ToolItem]) {
        self.tools = tools
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // 背景视图（操作区背景色 + 超椭圆圆角 16pt）
        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        // 标题
        let titleLabel = NSTextField(labelWithString: "工具")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(titleLabel)

        // 关闭按钮（灰色 × 图标）
        let closeButton = NSButton()
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(closeButton)

        // 工具方块网格容器（3列）
        let gridContainer = NSGridView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.rowSpacing = 16
        gridContainer.columnSpacing = 16
        backgroundView.addSubview(gridContainer)

        // 添加工具方块（每行 3 列）
        var rowViews: [NSView] = []
        for tool in tools {
            let toolCard = ToolCardView(tool: tool) { [weak self] in
                tool.action?()
                self?.onClose?()
            }
            rowViews.append(toolCard)
            if rowViews.count >= 3 {
                gridContainer.addRow(with: rowViews)
                rowViews = []
            }
        }
        if !rowViews.isEmpty {
            gridContainer.addRow(with: rowViews)
        }

        // 设置行高和列宽
        for i in 0..<gridContainer.numberOfRows {
            gridContainer.row(at: i).height = 120
        }
        for i in 0..<gridContainer.numberOfColumns {
            gridContainer.column(at: i).width = 200
        }

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 24),

            closeButton.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            gridContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            gridContainer.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 24),
            gridContainer.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -24),
            gridContainer.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -24),
        ])
    }

    /// 关闭按钮点击
    @objc private func closeClicked() {
        onClose?()
    }

    /// Escape 键关闭
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            closeClicked()
            return
        }
        super.keyDown(with: event)
    }
}

/// v0.6.9: 工具卡片视图子类，存储 action 闭包（替代 objc_setAssociatedObject 反模式）
private class ToolCardView: NSView {

    /// 点击回调
    private let onTap: (() -> Void)?

    init(tool: ToolOverlayView.ToolItem, onTap: @escaping () -> Void) {
        self.onTap = tool.isEnabled ? onTap : nil
        super.init(frame: .zero)
        setupUI(tool: tool)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(tool: ToolOverlayView.ToolItem) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        // 图标
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: tool.icon, accessibilityDescription: tool.title)
        iconView.contentTintColor = tool.isEnabled ? .controlAccentColor : .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // 标题
        let titleLabel = NSTextField(labelWithString: tool.title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = tool.isEnabled ? .labelColor : .tertiaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // 介绍
        let descLabel = NSTextField(labelWithString: tool.description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            descLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        // 点击手势（仅可用工具响应）
        if onTap != nil {
            let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
            addGestureRecognizer(click)
        }
    }

    @objc private func clicked() {
        onTap?()
    }
}

// MARK: - v0.7.0: 工具浮动面板（替代设备栏位置显示）

/// 工具浮动面板视图
/// 点击侧边栏工具按钮后，隐藏设备栏，在设备栏原位显示此面板
/// 3×3 网格大方块布局（末行不足 3 个补灰色占位方块），每个工具包含大图标 + 名称，右上角关闭按钮
/// 宽度 = 侧边栏宽度，高度根据工具数量自适应
public class ToolPanelView: NSView {

    /// 关闭回调（点击 ❌ 或工具卡片时触发）
    public var onClose: (() -> Void)?

    /// 工具项列表
    private let tools: [ToolOverlayView.ToolItem]

    /// 网格容器（3×N 布局；提升为存储属性以便 layout() 中设置列宽）
    private var gridContainer: NSGridView!

    /// 初始化
    /// - Parameter tools: 工具项列表
    public init(tools: [ToolOverlayView.ToolItem]) {
        self.tools = tools
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // 任务 4: 液态玻璃背景：FFGlassView 统一提供玻璃质感、圆角与主题刷新
        let glassBackground = FFGlassView(level: .panel, cornerRadius: 8)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 关闭按钮（右上角，灰色 × 图标）
        let closeButton = NSButton()
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        // 网格容器：NSGridView 3×N 布局，每行 3 列（末行不足补占位）
        gridContainer = NSGridView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.rowSpacing = 12
        gridContainer.columnSpacing = 12
        addSubview(gridContainer)

        // 构建工具卡片，每行 3 列，不足 3 个补灰色占位方块
        var rowViews: [NSView] = []
        for tool in tools {
            let card = ToolPanelCardView(tool: tool) { [weak self] in
                tool.action?()
                // 延迟关闭面板：确保工具窗口先弹出（同步 showWindow 在 onClose 前执行，
                // 但面板收起动画与窗口弹出竞争时可能打断窗口显示，改为下一轮 runloop 关闭）
                DispatchQueue.main.async {
                    self?.onClose?()
                }
            }
            rowViews.append(card)
            if rowViews.count >= 3 {
                gridContainer.addRow(with: rowViews)
                rowViews = []
            }
        }
        // 末行不足 3 个时补占位（灰色方块，无交互）
        if !rowViews.isEmpty {
            while rowViews.count < 3 {
                rowViews.append(makePlaceholderCard())
            }
            gridContainer.addRow(with: rowViews)
        }

        // 设置行高（80pt 大方块）和列宽（自适应填充）
        for i in 0..<gridContainer.numberOfRows {
            gridContainer.row(at: i).height = 80
        }
        // NSGridCell.Placement 只有 .center, .leading, .trailing, .fill, .none（旧SDK）
        // 使用 .center 即可，列宽由内容自适应

        NSLayoutConstraint.activate([
            // 关闭按钮：右上角 8pt 内边距
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            // 网格：关闭按钮下方 4pt，左右 12pt 内边距，底部 12pt
            gridContainer.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            gridContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            gridContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            gridContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    /// 关闭按钮点击
    @objc private func closeClicked() {
        onClose?()
    }

    /// 灰色占位方块（3×3 网格末行补齐，无交互）
    private func makePlaceholderCard() -> NSView {
        let placeholder = NSView()
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        placeholder.layer?.cornerRadius = 8
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        return placeholder
    }

    /// 3 列等分网格宽度：NSGridView 默认列宽由内容自适应，卡片无 intrinsic size 会塌缩到 0，
    /// 导致点击区域不可命中（问题 6/7 根因）。每次布局时显式设置列宽。
    public override func layout() {
        super.layout()
        let availableWidth = bounds.width - 24  // 左右内边距各 12
        let colWidth = max((availableWidth - 2 * 12) / 3, 40)  // 列间距 12
        for i in 0..<gridContainer.numberOfColumns {
            gridContainer.column(at: i).width = colWidth
        }
    }
}

/// v0.7.0: 工具面板卡片视图（紧凑大方块布局）
/// 每个卡片：大图标（28pt SF Symbol）+ 名称（11pt），居中排列
private class ToolPanelCardView: NSView {

    /// 点击回调
    private let onTap: (() -> Void)?

    init(tool: ToolOverlayView.ToolItem, onTap: @escaping () -> Void) {
        self.onTap = tool.isEnabled ? onTap : nil
        super.init(frame: .zero)
        setupUI(tool: tool)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(tool: ToolOverlayView.ToolItem) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        // 图标（28pt SF Symbol）
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: tool.icon, accessibilityDescription: tool.title)
        iconView.contentTintColor = tool.isEnabled ? .controlAccentColor : .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // 名称/描述（11pt）
        let descLabel = NSTextField(labelWithString: tool.title)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = tool.isEnabled ? .labelColor : .tertiaryLabelColor
        descLabel.alignment = .center
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descLabel)

        NSLayoutConstraint.activate([
            // 图标：顶部 10pt 内边距，水平居中，28×28pt
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            // 名称：图标下方 6pt，左右 4pt 内边距
            descLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        // 点击手势（仅可用工具响应）
        // 点击视觉反馈：按下时卡片背景变深，松开恢复（解决"点了没反馈"）
        if onTap != nil {
            let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
            addGestureRecognizer(click)
            let hover = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(hover)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // 仅可用工具响应悬停（禁用卡片不添加 tracking area）
        guard onTap != nil else { return }
        let hover = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(hover)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        layer?.cornerRadius = 8
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @objc private func clicked() {
        onTap?()
    }
}
