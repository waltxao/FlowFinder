import Cocoa

/// 设置页视觉 A（2026-10-21 用户确认）：12pt 卡片 / 40pt 行 / 24–28 控件 / 13·11 字。
enum FFSettingsMetrics {
    static let cardRadius: CGFloat = 12
    static let rowHeight: CGFloat = 40
    static let controlHeight: CGFloat = 26
    static let cardPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 2
    static let titleFontSize: CGFloat = 13
    static let descFontSize: CGFloat = 11
}

// MARK: - SettingsRowView

/// 设置行视图：左侧标题+描述，右侧控件（toggle/popup/segmented/input/button/slider/color）
/// 液态玻璃卡片内行样式：行高 36pt，无分隔线（用 spacing 替代），悬停时微弱背景高亮
class SettingsRowView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let descLabel = NSTextField(labelWithString: "")
    /// 右侧控件容器
    private let controlContainer = NSView()
    /// 全宽内容模式标志（setFullWidthContent 设置；true 时 controlContainer 撑满整行）
    private var isFullWidthContent = false
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
        hoverBackground.layer?.cornerRadius = 8
        hoverBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverBackground)

        titleLabel.font = NSFont.systemFont(ofSize: FFSettingsMetrics.titleFontSize)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        descLabel.font = NSFont.systemFont(ofSize: FFSettingsMetrics.descFontSize)
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
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlContainer.leadingAnchor, constant: -12),

            // 右侧控件区
            controlContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            controlContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 7),
            controlContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),
        ])

        // 行高 40pt（无描述时），有描述时自适应
        bottomAnchor.constraint(greaterThanOrEqualTo: descLabel.bottomAnchor, constant: 9).isActive = true
        bottomAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 9).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: FFSettingsMetrics.rowHeight).isActive = true
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
            ctx.duration = FFMotion.animationDuration(0.15)
            hoverBackground.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        })
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = FFMotion.animationDuration(0.15)
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

    /// 全宽内容模式：内容视图铺满整行（不挤在右侧控件区）。
    /// 用于自带完整布局的内容块（标签列表/关于信息/外观选择器）——
    /// 旧实现 setControl 把内容塞进右侧 controlContainer（窄、靠右），
    /// 导致"内容靠右挤/只占右半边"。
    func setFullWidthContent(_ view: NSView) {
        isFullWidthContent = true
        titleLabel.isHidden = true
        descLabel.isHidden = true
        controlContainer.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(view)
        // 全宽模式：控件区从行左 16 延伸到行右 -16（内容铺满整行，不挤右侧）
        NSLayoutConstraint.activate([
            controlContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            controlContainer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            controlContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            view.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: controlContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: controlContainer.bottomAnchor),
        ])
    }

    /// 禁用整行（占位项标注"即将支持"）
    func setDisabled(tooltip: String = "即将支持") {
        titleLabel.textColor = FFVisualTokens.hint
        descLabel.textColor = FFVisualTokens.hint
        controlContainer.subviews.forEach { ($0 as? NSControl)?.isEnabled = false }
        self.toolTip = tooltip
    }
}

// MARK: - SettingsSectionView

/// 设置分区视图：独立实心底卡片，sectionTitle(15pt semibold + 前导图标) + 多个 SettingsRowView
/// 卡片背景为 solidBackground 实心底（Wave4 Task 3：颜色统一走 FFDesign.operationAreaBackground
/// 令牌，日间 #F5F5F5 / 夜间 #2D2D2D，与主窗操作区并排时灰度一致），16pt 内边距，行间用 spacing 替代分隔线
class SettingsSectionView: NSView {

    enum Style {
        case card
        case plain
    }

    private let style: Style
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    /// 实心卡片背景（问题 6：改用 macOS 系统设置风格实心卡片，
    /// controlBackgroundColor 深浅色自适应 + 明显边框 + 圆角，文字清晰、整页不透）
    private let solidBackground = NSView()
    /// 内容容器（在背景之上，提供 16pt 内边距）
    private let contentContainer = NSView()

    init(title: String, icon: FFIconName? = nil, style: Style = .card) {
        self.style = style
        super.init(frame: .zero)
        setupUI()
        titleLabel.stringValue = title
        if style == .plain {
            titleLabel.font = NSFont.systemFont(ofSize: FFSettingsMetrics.titleFontSize, weight: .semibold)
            solidBackground.isHidden = true
        }
        if let icon = icon {
            iconView.image = FFIcon.template(icon, size: 16)
            iconView.contentTintColor = NSColor.secondaryLabelColor
            iconView.isHidden = false
        }
    }

    /// 布局诊断：记录卡片实际 frame 与内容容器宽度（定位"卡片占半边/内容溢出"）
    /// 每次 layout 都记录（节流：仅当 frame 变化时打印，避免刷屏）
    private var lastLoggedFrame: NSRect = .zero
    public override func layout() {
        super.layout()
        if frame != lastLoggedFrame {
            lastLoggedFrame = frame
            FFDebug.log("[LAYOUT-DIAG] SettingsSectionView '\(titleLabel.stringValue)' frame=\(frame) width=\(frame.width) rowsStack.w=\(rowsStack.frame.width) contentContainer.w=\(contentContainer.frame.width)")
        }
    }

    required init?(coder: NSCoder) {
        self.style = .card
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .appearanceChanged, object: nil)
    }

    /// 主题切换时刷新卡片实心底色 + 边框（cgColor 是快照，不自动跟随）
    @objc private func refreshThemeColors() {
        // Wave4 Task 3：卡片底色改读 FFDesign.operationAreaBackground 统一令牌
        // （此前手动 calibratedWhite 1.0/0.16，与主窗操作区 #F5F5F5/#2D2D2D 并排时灰度有可感知差异）
        let cardBG: NSColor = FFDesign.operationAreaBackground
        let cardBorder: NSColor = isDarkCardTheme ? NSColor(calibratedWhite: 0.30, alpha: 1.0) : NSColor(calibratedWhite: 0.80, alpha: 1.0)
        FFDebug.log("SettingsSection.refreshThemeColors: effective=\(effectiveAppearance.name) isDark=\(isDarkCardTheme) cardBG=\(cardBG)")
        solidBackground.layer?.backgroundColor = cardBG.cgColor
        solidBackground.layer?.borderColor = cardBorder.cgColor
        solidBackground.needsDisplay = true
    }

    /// 当前是否深色主题（供边框色选择；底色已由 FFDesign 令牌双值承担）
    private var isDarkCardTheme: Bool {
        ThemeManager.shared.resolvedIsDark
    }

    private func setupUI() {
        wantsLayer = true
        // 监听主题变更，刷新卡片底色与边框（修复深色模式设置页卡片不跟随）
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshThemeColors),
            name: .appearanceChanged, object: nil
        )

        // 实心卡片背景：底色读 FFDesign.operationAreaBackground 统一令牌（主窗与设置卡片色调一致）
        // + 明显边框 + 圆角。深浅色由 refreshThemeColors 在主题变更时刷新。
        solidBackground.translatesAutoresizingMaskIntoConstraints = false
        solidBackground.wantsLayer = true
        solidBackground.layer?.backgroundColor = FFDesign.operationAreaBackground.cgColor
        solidBackground.layer?.cornerRadius = FFSettingsMetrics.cardRadius
        solidBackground.layer?.cornerCurve = .continuous
        solidBackground.layer?.borderWidth = 1
        solidBackground.layer?.borderColor = (ThemeManager.shared.resolvedIsDark ? NSColor(calibratedWhite: 0.30, alpha: 1.0) : NSColor(calibratedWhite: 0.80, alpha: 1.0)).cgColor
        addSubview(solidBackground, positioned: .below, relativeTo: nil)

        // 内容容器（提供 16pt 内边距）
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        // 分区标题图标
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isHidden = true

        // 分区标题（13pt semibold，视觉 A）
        titleLabel.font = NSFont.systemFont(ofSize: FFSettingsMetrics.titleFontSize, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 行堆叠（垂直，spacing 替代分隔线）
        rowsStack.orientation = .vertical
        rowsStack.spacing = FFSettingsMetrics.rowSpacing
        rowsStack.detachesHiddenViews = false
        // v0.7.4 根因修复：不再设 rowsStack.alignment = .width！
        // 运行时证据（LAYOUT-DIAG）：.width alignment 与 addRow/addContentView 的
        // 显式 leading/trailing 约束冲突，导致含 setFullWidthContent 的卡片右对齐塌缩。
        // 行的全宽由 addRow/addContentView 的显式约束保证，不依赖 alignment。
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(iconView)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(rowsStack)

        NSLayoutConstraint.activate([
            // 实心背景填满（圆角卡片）
            solidBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackground.topAnchor.constraint(equalTo: topAnchor),
            solidBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 内容容器 16pt 内边距
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: FFSettingsMetrics.cardPadding),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -FFSettingsMetrics.cardPadding),
            contentContainer.topAnchor.constraint(equalTo: topAnchor, constant: FFSettingsMetrics.cardPadding),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -FFSettingsMetrics.cardPadding),

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

    /// 添加一行（全宽嵌入卡片内容区）
    /// v0.7.4 彻底修复：显式加 leading/trailing 约束钉到 rowsStack 边缘，
    /// 不依赖 rowsStack.alignment=.width 的隐式行为。
    /// 运行时证据（LAYOUT-DIAG）：.width alignment 对部分视图不可靠
    /// （主题卡片塌缩为 286pt 而非全宽 531），显式约束彻底解决。
    func addRow(_ row: SettingsRowView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor),
        ])
    }

    /// 添加一个任意内容视图（全宽嵌入，与 addRow 行为一致）
    func addContentView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.addArrangedSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor),
        ])
    }

    /// R4-13：脚注——只对「说明一件事、但没有开关」的内容使用。
    /// 之前这类说明排成一行设置项（标题加粗、右侧空），用户会去找根本不存在的控件。
    func addFootnote(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: FFSettingsMetrics.descFontSize)
        label.textColor = NSColor.secondaryLabelColor
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.addArrangedSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor),
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
        toggle.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
        popup.heightAnchor.constraint(equalToConstant: FFSettingsMetrics.controlHeight).isActive = true
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
        segmented.heightAnchor.constraint(equalToConstant: FFSettingsMetrics.controlHeight).isActive = true
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
        slider.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
        textField.heightAnchor.constraint(equalToConstant: FFSettingsMetrics.controlHeight).isActive = true
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
        button.heightAnchor.constraint(equalToConstant: FFSettingsMetrics.controlHeight).isActive = true
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
/// C1: internal（非 private）——SettingsWindowController 在分区切换时调用 removeAll 清理
class SettingsActionTarget: NSObject {
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

    /// 清空全部已注册 handler。
    /// 设置分区切换时调用：每次切换都会整页重建控件，旧控件的注册项永不再被触发，
    /// 不清空会导致字典无界增长。SettingsActionTarget 是单例（static let shared），
    /// 进程生命周期内不会 deinit，故只能靠分区切换时显式清理。
    /// 保留"同一控件重复注册时后者覆盖前者"的语义：一次分区构建内每个控件只注册一次，
    /// 重复注册同一控件的场景仍按字典赋值覆盖。
    func removeAll() {
        toggleHandlers.removeAll()
        popupHandlers.removeAll()
        segmentedHandlers.removeAll()
        sliderHandlers.removeAll()
        textFieldHandlers.removeAll()
        buttonHandlers.removeAll()
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
/// 注意：色圆点用纯 NSView + 点击手势实现（不用 NSButton）——
/// macOS 26 上 20×20 无边框 NSButton 可能渲染出系统占位文字（如"BU"缩写），
/// 纯视图 + 手势彻底杜绝此问题。
class FFColorPickerView: NSView {

    private let colors: [String]
    private(set) var selectedHex: String
    private var colorDots: [NSView] = []
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
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 11
            dot.layer?.backgroundColor = NSColor(hex: hex)?.cgColor ?? NSColor.gray.cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 22).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 22).isActive = true
            // 选中态边框
            if hex.lowercased() == selectedHex.lowercased() {
                dot.layer?.borderWidth = 2
                dot.layer?.borderColor = NSColor.labelColor.cgColor
            }
            // 点击手势（纯视图，不用 NSButton，避免系统占位文字）
            let click = NSClickGestureRecognizer(target: self, action: #selector(dotClicked(_:)))
            dot.addGestureRecognizer(click)
            stack.addArrangedSubview(dot)
            colorDots.append(dot)
        }
    }

    @objc private func dotClicked(_ sender: NSClickGestureRecognizer) {
        guard let dot = sender.view, let idx = colorDots.firstIndex(of: dot), idx < colors.count else { return }
        FFDebug.log("FFColorPicker.dotClicked: idx=\(idx) hex=\(colors[idx])")
        selectedHex = colors[idx]
        // 更新边框
        for d in colorDots {
            d.layer?.borderWidth = 0
        }
        dot.layer?.borderWidth = 2
        dot.layer?.borderColor = NSColor.labelColor.cgColor
        onSelected(selectedHex)
    }
}

// MARK: - NSColor hex 扩展已在 SidebarView.swift 中定义，此处不再重复
