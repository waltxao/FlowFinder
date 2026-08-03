import Cocoa

// MARK: - SettingsRowView

/// 设置行视图：左侧标题+描述，右侧控件（toggle/popup/segmented/input/button/slider/color）
/// 液态玻璃卡片内行样式：行高 36pt，无分隔线（用 spacing 替代），悬停时微弱背景高亮
class SettingsRowView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let descLabel = NSTextField(labelWithString: "")
    /// 右侧控件容器
    private let controlContainer = NSView()
    /// 悬停背景层（微弱高亮）
    private let hoverBackground = NSView()
    /// 悬停追踪区域
    private var trackingArea: NSTrackingArea?

    /// 标题
    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    /// 描述（可选，留空则隐藏）
    var desc: String {
        get { descLabel.stringValue }
        set {
            descLabel.stringValue = newValue
            descLabel.isHidden = newValue.isEmpty
        }
    }

    init(title: String, desc: String = "", control: NSView? = nil) {
        super.init(frame: .zero)
        setupUI()
        self.title = title
        self.desc = desc
        if let control = control {
            setControl(control)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // 悬停背景层（默认透明，悬停时显示微弱高亮）
        hoverBackground.wantsLayer = true
        hoverBackground.layer?.backgroundColor = NSColor.clear.cgColor
        hoverBackground.layer?.cornerRadius = 6
        hoverBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverBackground)

        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.isHidden = true
        descLabel.setContentHuggingPriority(.required, for: .vertical)

        controlContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(descLabel)
        addSubview(controlContainer)

        NSLayoutConstraint.activate([
            // 悬停背景填满行
            hoverBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hoverBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hoverBackground.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            hoverBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            // 左侧文本区
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlContainer.leadingAnchor, constant: -12),

            // 右侧控件区
            controlContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            controlContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            controlContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])

        // 行高 36pt（无描述时），有描述时自适应
        bottomAnchor.constraint(greaterThanOrEqualTo: descLabel.bottomAnchor, constant: 8).isActive = true
        bottomAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 8).isActive = true
        // 最小行高 36pt
        heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
    }

    // MARK: - 悬停效果

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            hoverBackground.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        })
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            hoverBackground.layer?.backgroundColor = NSColor.clear.cgColor
        })
    }

    /// 设置右侧控件（替换旧控件）
    func setControl(_ control: NSView) {
        controlContainer.subviews.forEach { $0.removeFromSuperview() }
        control.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor),
            control.topAnchor.constraint(equalTo: controlContainer.topAnchor),
            control.bottomAnchor.constraint(equalTo: controlContainer.bottomAnchor),
        ])
    }

    /// 禁用整行（占位项标注"即将支持"）
    func setDisabled(tooltip: String = "即将支持") {
        titleLabel.textColor = NSColor.tertiaryLabelColor
        descLabel.textColor = NSColor.tertiaryLabelColor
        controlContainer.subviews.forEach { ($0 as? NSControl)?.isEnabled = false }
        self.toolTip = tooltip
    }
}

// MARK: - SettingsSectionView

/// 设置分区视图：独立液态玻璃卡片，sectionTitle(15pt semibold + 前导图标) + 多个 SettingsRowView
/// 卡片背景为 FFGlassView(.component, cornerRadius: 12)，16pt 内边距，行间用 spacing 替代分隔线
class SettingsSectionView: NSView {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    /// 玻璃背景（卡片质感）
    private let glassBackground: FFGlassView
    /// 实心背景（问题 6：半透明玻璃在实体窗口背景上文字不清，
    /// 叠一层 controlBackgroundColor 实心底保证可读性，深浅色自动适配）
    private let solidBackground = NSView()
    /// 内容容器（在背景之上，提供 16pt 内边距）
    private let contentContainer = NSView()

    init(title: String, iconName: String? = nil) {
        glassBackground = FFGlassView(level: .component, cornerRadius: 12)
        super.init(frame: .zero)
        setupUI()
        titleLabel.stringValue = title
        if let iconName = iconName {
            iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: title)
            iconView.contentTintColor = NSColor.secondaryLabelColor
            iconView.isHidden = false
        }
    }

    required init?(coder: NSCoder) {
        glassBackground = FFGlassView(level: .component, cornerRadius: 12)
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // 实心背景（最底层）：controlBackgroundColor 动态色，圆角与卡片一致，保证文字可读
        solidBackground.translatesAutoresizingMaskIntoConstraints = false
        solidBackground.wantsLayer = true
        solidBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        solidBackground.layer?.cornerRadius = 12
        addSubview(solidBackground, positioned: .below, relativeTo: nil)

        // 玻璃背景填满整个卡片（叠在实心背景之上，保留玻璃质感边缘）
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)

        // 内容容器（提供 16pt 内边距）
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        // 分区标题图标
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isHidden = true

        // 分区标题（15pt semibold）
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 行堆叠（垂直，spacing 替代分隔线）
        rowsStack.orientation = .vertical
        rowsStack.spacing = 4
        rowsStack.detachesHiddenViews = false
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(iconView)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(rowsStack)

        NSLayoutConstraint.activate([
            // 实心背景填满（圆角与玻璃一致）
            solidBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackground.topAnchor.constraint(equalTo: topAnchor),
            solidBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 玻璃背景填满
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 内容容器 16pt 内边距
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentContainer.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            // 图标
            iconView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            // 标题
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor),

            // 行堆叠
            rowsStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            rowsStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    /// 添加一行（自动填充宽度到 stack）
    func addRow(_ row: SettingsRowView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor),
        ])
    }

    /// 添加一个任意内容视图（全宽嵌入，与 addRow 行为一致）
    /// 用于自带完整布局的内容块（如 AppearanceSettingsView 三态主题切换器），
    /// 避免塞入 SettingsRowView.controlContainer（无宽度约束）导致塌缩。
    func addContentView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.addArrangedSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor),
        ])
    }
}

// MARK: - 控件工厂便捷方法

extension SettingsRowView {

    /// 创建带 NSSwitch 的设置行
    static func toggleRow(title: String, desc: String = "", state: Bool, action: ((Bool) -> Void)? = nil) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let toggle = NSSwitch()
        toggle.state = state ? .on : .off
        if let action = action {
            toggle.target = SettingsActionTarget.shared
            toggle.action = #selector(SettingsActionTarget.toggleChanged(_:))
            SettingsActionTarget.shared.register(toggle: toggle) { newState in action(newState) }
        }
        row.setControl(toggle)
        return row
    }

    /// 创建带 NSPopUpButton 的设置行
    static func popupRow(title: String, desc: String = "", items: [String], selectedIndex: Int = 0, action: ((Int) -> Void)? = nil) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let popup = NSPopUpButton()
        popup.addItems(withTitles: items)
        popup.selectItem(at: selectedIndex)
        if let action = action {
            popup.target = SettingsActionTarget.shared
            popup.action = #selector(SettingsActionTarget.popupChanged(_:))
            SettingsActionTarget.shared.register(popup: popup) { idx in action(idx) }
        }
        row.setControl(popup)
        return row
    }

    /// 创建带 NSSegmentedControl 的设置行
    static func segmentedRow(title: String, desc: String = "", labels: [String], selected: Int = 0, action: ((Int) -> Void)? = nil) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let segmented = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        segmented.selectedSegment = selected
        if let action = action {
            segmented.target = SettingsActionTarget.shared
            segmented.action = #selector(SettingsActionTarget.segmentChanged(_:))
            SettingsActionTarget.shared.register(segmented: segmented) { idx in action(idx) }
        }
        row.setControl(segmented)
        return row
    }

    /// 创建带 NSSlider 的设置行（离散档位）
    static func sliderRow(title: String, desc: String = "", minValue: Double, maxValue: Double, value: Double, action: ((Double) -> Void)? = nil) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let slider = NSSlider(value: value, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        slider.controlSize = .regular
        if let action = action {
            slider.target = SettingsActionTarget.shared
            slider.action = #selector(SettingsActionTarget.sliderChanged(_:))
            SettingsActionTarget.shared.register(slider: slider) { val in action(val) }
        }
        row.setControl(slider)
        return row
    }

    /// 创建带颜色选择按钮的设置行
    static func colorRow(title: String, desc: String = "", colors: [String], selectedHex: String, action: ((String) -> Void)? = nil) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let picker = FFColorPickerView(colors: colors, selectedHex: selectedHex) { hex in
            action?(hex)
        }
        row.setControl(picker)
        return row
    }

    /// 创建带 NSTextField 的设置行（可输入文本）
    static func textFieldRow(title: String, desc: String = "", placeholder: String = "", value: String = "", action: ((String) -> Void)? = nil) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = value
        textField.controlSize = .small
        textField.preferredMaxLayoutWidth = 160
        // 修复 T8：值为空时 NSTextField 的 intrinsic width 塌缩到接近 0，
        // 嵌入无宽度约束的 controlContainer 后输入框窄到无法使用。
        // 给一个可用的最小宽度。
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        if let action = action {
            textField.target = SettingsActionTarget.shared
            textField.action = #selector(SettingsActionTarget.textFieldChanged(_:))
            SettingsActionTarget.shared.register(textField: textField) { val in action(val) }
        }
        row.setControl(textField)
        return row
    }

    /// 创建带 NSButton 的设置行
    static func buttonRow(title: String, desc: String = "", buttonTitle: String, action: @escaping () -> Void) -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        let button = NSButton(title: buttonTitle, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = SettingsActionTarget.shared
        button.action = #selector(SettingsActionTarget.buttonClicked(_:))
        SettingsActionTarget.shared.register(button: button, handler: action)
        row.setControl(button)
        return row
    }

    /// 创建纯标签行（用于显示信息，无控件）
    static func labelRow(title: String, desc: String = "") -> SettingsRowView {
        let row = SettingsRowView(title: title, desc: desc)
        return row
    }
}

// MARK: - SettingsActionTarget

/// 闭包桥接目标对象：避免每行单独创建 NSObject 子类
private class SettingsActionTarget: NSObject {
    static let shared = SettingsActionTarget()
    private var toggleHandlers: [ObjectIdentifier: (Bool) -> Void] = [:]
    private var popupHandlers: [ObjectIdentifier: (Int) -> Void] = [:]
    private var segmentedHandlers: [ObjectIdentifier: (Int) -> Void] = [:]
    private var sliderHandlers: [ObjectIdentifier: (Double) -> Void] = [:]
    private var textFieldHandlers: [ObjectIdentifier: (String) -> Void] = [:]
    private var buttonHandlers: [ObjectIdentifier: () -> Void] = [:]

    func register(toggle: NSSwitch, handler: @escaping (Bool) -> Void) {
        toggleHandlers[ObjectIdentifier(toggle)] = handler
    }
    func register(popup: NSPopUpButton, handler: @escaping (Int) -> Void) {
        popupHandlers[ObjectIdentifier(popup)] = handler
    }
    func register(segmented: NSSegmentedControl, handler: @escaping (Int) -> Void) {
        segmentedHandlers[ObjectIdentifier(segmented)] = handler
    }
    func register(slider: NSSlider, handler: @escaping (Double) -> Void) {
        sliderHandlers[ObjectIdentifier(slider)] = handler
    }
    func register(textField: NSTextField, handler: @escaping (String) -> Void) {
        textFieldHandlers[ObjectIdentifier(textField)] = handler
    }
    func register(button: NSButton, handler: @escaping () -> Void) {
        buttonHandlers[ObjectIdentifier(button)] = handler
    }

    @objc func toggleChanged(_ sender: NSSwitch) {
        toggleHandlers[ObjectIdentifier(sender)]?(sender.state == .on)
    }
    @objc func popupChanged(_ sender: NSPopUpButton) {
        popupHandlers[ObjectIdentifier(sender)]?(sender.indexOfSelectedItem)
    }
    @objc func segmentChanged(_ sender: NSSegmentedControl) {
        segmentedHandlers[ObjectIdentifier(sender)]?(sender.selectedSegment)
    }
    @objc func sliderChanged(_ sender: NSSlider) {
        sliderHandlers[ObjectIdentifier(sender)]?(sender.doubleValue)
    }
    @objc func textFieldChanged(_ sender: NSTextField) {
        textFieldHandlers[ObjectIdentifier(sender)]?(sender.stringValue)
    }
    @objc func buttonClicked(_ sender: NSButton) {
        buttonHandlers[ObjectIdentifier(sender)]?()
    }
}

// MARK: - FFColorPickerView

/// 颜色选择器视图：水平排列的颜色圆点，点击选择
class FFColorPickerView: NSView {

    private let colors: [String]
    private(set) var selectedHex: String
    private var colorButtons: [NSButton] = []
    private let onSelected: (String) -> Void

    init(colors: [String], selectedHex: String, onSelected: @escaping (String) -> Void) {
        self.colors = colors
        self.selectedHex = selectedHex
        self.onSelected = onSelected
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for (idx, hex) in colors.enumerated() {
            let btn = NSButton()
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 10
            btn.layer?.backgroundColor = NSColor(hex: hex)?.cgColor ?? NSColor.gray.cgColor
            btn.tag = idx
            btn.target = self
            btn.action = #selector(colorSelected(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 20).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 20).isActive = true
            // 选中态边框
            if hex.lowercased() == selectedHex.lowercased() {
                btn.layer?.borderWidth = 2
                btn.layer?.borderColor = NSColor.labelColor.cgColor
            }
            stack.addArrangedSubview(btn)
            colorButtons.append(btn)
        }
    }

    @objc private func colorSelected(_ sender: NSButton) {
        guard sender.tag < colors.count else { return }
        selectedHex = colors[sender.tag]
        // 更新边框
        for btn in colorButtons {
            btn.layer?.borderWidth = 0
        }
        sender.layer?.borderWidth = 2
        sender.layer?.borderColor = NSColor.labelColor.cgColor
        onSelected(selectedHex)
    }
}

// MARK: - NSColor hex 扩展已在 SidebarView.swift 中定义，此处不再重复
