import AppKit

// MARK: - 面板框（ZCode 独立面板模型）
//
// ZCode 的布局立场：每块内容是一个独立框（背景 + 1px 弱边框 + 圆角），
// 框与框之间留 4pt 透明间隙，靠背景对比与边框分层，不用投影。
// 本类是该模型在 AppKit 的最小实现。
//
// 与旧做法的区别：
//   - 旧：FFSplitView(dividerThickness=0) 切分 + FFGlassView 叠液态玻璃
//   - 新：面板各自成框，边框承担分层，间隙承担拖拽热区
final class FFPanelView: NSView {

    /// 面板背景层级
    enum Tone {
        /// 侧栏（比面板略深一档）
        case sidebar
        /// 常规内容面板
        case panel
        /// 头部/工具栏（比面板亮一档）
        case header
        /// 卡片/弹层
        case card
    }

    private let tone: Tone
    private let cornerRadius: CGFloat

    init(tone: Tone = .panel, cornerRadius: CGFloat = FFDesign.Radius.xl) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = FFDesign.Layout.borderWidth
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 是否绘制边框（嵌套面板可关掉，避免双线）
    var showsBorder: Bool = true {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer = layer else { return }
        let appearance = effectiveAppearance
        let bg: NSColor
        switch tone {
        case .sidebar: bg = FFDesign.Color.sidebar
        case .panel:   bg = FFDesign.Color.panel
        case .header:  bg = FFDesign.Color.header
        case .card:    bg = FFDesign.Color.card
        }
        var bgColor = NSColor.clear.cgColor
        var borderColor = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance {
            bgColor = bg.cgColor
            borderColor = FFDesign.Color.border.cgColor
        }
        layer.backgroundColor = bgColor
        layer.borderWidth = showsBorder ? FFDesign.Layout.borderWidth : 0
        layer.borderColor = borderColor
        layer.cornerRadius = cornerRadius
    }

    /// 主题/外观变化时刷新（NSView 默认会在 appearance 变化时重新 updateLayer，
    /// 此处显式提供入口供无法自动触发的场景调用）
    func refreshAppearance() {
        needsDisplay = true
    }
}

// MARK: - 分区标题（ZCode text-ui-sm + fgSubtle）

/// 侧栏/设置页的分区标题。12pt 次级色，与内容行左对齐。
final class FFSectionHeaderView: NSView {

    private let label = NSTextField(labelWithString: "")
    private let trailingButton = NSButton()

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    /// 右侧操作按钮（如「+」新建）。传 nil 隐藏。
    var accessory: (image: NSImage?, action: Selector?, target: AnyObject?)? {
        didSet {
            guard let accessory = accessory else {
                trailingButton.isHidden = true
                return
            }
            trailingButton.isHidden = false
            trailingButton.image = accessory.image
            trailingButton.action = accessory.action
            trailingButton.target = accessory.target
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        label.stringValue = title
        label.font = FFDesign.Text.sm
        label.textColor = FFDesign.Color.textSecondary
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        trailingButton.isBordered = false
        trailingButton.imagePosition = .imageOnly
        trailingButton.contentTintColor = FFDesign.Color.textTertiary
        trailingButton.isHidden = true
        trailingButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trailingButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: FFDesign.Spacing.x2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -FFDesign.Spacing.x2),
            trailingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: 16),
            trailingButton.heightAnchor.constraint(equalToConstant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingButton.leadingAnchor, constant: -FFDesign.Spacing.x1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: FFDesign.Spacing.x6)
    }
}

// MARK: - 空态（ZCode：居中图标 + 一行说明 + 一个主操作）

/// 统一空态视图。用于「收藏为空」「目录为空」「搜索无结果」等场景。
///
/// 设计依据：ZCode 空态不使用插画，只用图标 + 一句话 + 一个可执行动作，
/// 避免「营销式留白」。
final class FFEmptyStateView: NSView {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()

    private var action: (() -> Void)?

    init(symbolName: String, title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        iconView.contentTintColor = FFDesign.Color.textTertiary
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = FFDesign.Text.base
        titleLabel.textColor = FFDesign.Color.textSecondary
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.font = FFDesign.Text.sm
        subtitleLabel.textColor = FFDesign.Color.textTertiary
        subtitleLabel.alignment = .center
        subtitleLabel.isHidden = (subtitle == nil)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        actionButton.title = actionTitle ?? ""
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.isHidden = (actionTitle == nil || action == nil)
        actionButton.target = self
        actionButton.action = #selector(handleAction)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: FFDesign.Spacing.x3),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: FFDesign.Spacing.x2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -FFDesign.Spacing.x2),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: FFDesign.Spacing.x1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: FFDesign.Spacing.x3),
            actionButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleAction() {
        action?()
    }
}

// MARK: - 分隔线（1px 边框色，不用阴影）

final class FFSeparatorView: NSView {

    enum Orientation { case horizontal, vertical }

    private let orientation: Orientation

    init(orientation: Orientation = .horizontal) {
        self.orientation = orientation
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = FFDesign.Color.border.cgColor
        }
        layer?.backgroundColor = color
    }

    override var intrinsicContentSize: NSSize {
        switch orientation {
        case .horizontal: return NSSize(width: NSView.noIntrinsicMetric, height: 1)
        case .vertical:   return NSSize(width: 1, height: NSView.noIntrinsicMetric)
        }
    }
}
