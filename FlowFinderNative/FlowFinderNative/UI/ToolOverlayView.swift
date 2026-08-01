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

        // 关闭按钮
        let closeButton = NSButton()
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.title = "❌"
        closeButton.font = NSFont.systemFont(ofSize: 18)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(closeButton)

        // 工具方块网格容器（2列）
        let gridContainer = NSGridView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.rowSpacing = 16
        gridContainer.columnSpacing = 16
        backgroundView.addSubview(gridContainer)

        // 添加工具方块（每行 2 列）
        var rowViews: [NSView] = []
        for tool in tools {
            let toolCard = ToolCardView(tool: tool) { [weak self] in
                tool.action?()
                self?.onClose?()
            }
            rowViews.append(toolCard)
            if rowViews.count >= 2 {
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
