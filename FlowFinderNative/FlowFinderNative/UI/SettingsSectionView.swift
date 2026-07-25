import Cocoa

// MARK: - SettingsRowView

/// 设置行视图：左侧标题+描述，右侧控件（toggle/popup/segmented/input/button/slider）
/// 匹配设计稿 `ff-set-row` 样式，行高自适应，行间 0.5pt 分隔线
class SettingsRowView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let descLabel = NSTextField(labelWithString: "")
    /// 右侧控件容器
    private let controlContainer = NSView()
    /// 底部分隔线
    private let separator = NSBox()

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

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(descLabel)
        addSubview(controlContainer)
        addSubview(separator)

        NSLayoutConstraint.activate([
            // 左侧文本区
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlContainer.leadingAnchor, constant: -12),

            // 右侧控件区
            controlContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            controlContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            controlContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            // 底部分隔线
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // 描述行存在时增加底部间距
        bottomAnchor.constraint(greaterThanOrEqualTo: descLabel.bottomAnchor, constant: 10).isActive = true
        // 无描述时确保最小行高
        bottomAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 10).isActive = true
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

/// 设置分区视图：sectionTitle(15pt bold) + 多个 SettingsRowView，容器背景为 FFGlassView(.component)
class SettingsSectionView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    /// 玻璃背景（卡片质感）
    private let glassBackground: FFGlassView

    init(title: String) {
        glassBackground = FFGlassView(level: .component, cornerRadius: 8)
        super.init(frame: .zero)
        setupUI()
        titleLabel.stringValue = title
    }

    required init?(coder: NSCoder) {
        glassBackground = FFGlassView(level: .component, cornerRadius: 8)
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)

        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.spacing = 0
        rowsStack.detachesHiddenViews = false
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            // 玻璃背景填满
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -6),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 标题
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            // 行堆叠（在玻璃背景内）
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
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
}

// MARK: - SettingsActionTarget

/// 闭包桥接目标对象：避免每行单独创建 NSObject 子类
private class SettingsActionTarget: NSObject {
    static let shared = SettingsActionTarget()
    private var toggleHandlers: [ObjectIdentifier: (Bool) -> Void] = [:]
    private var popupHandlers: [ObjectIdentifier: (Int) -> Void] = [:]
    private var segmentedHandlers: [ObjectIdentifier: (Int) -> Void] = [:]

    func register(toggle: NSSwitch, handler: @escaping (Bool) -> Void) {
        toggleHandlers[ObjectIdentifier(toggle)] = handler
    }
    func register(popup: NSPopUpButton, handler: @escaping (Int) -> Void) {
        popupHandlers[ObjectIdentifier(popup)] = handler
    }
    func register(segmented: NSSegmentedControl, handler: @escaping (Int) -> Void) {
        segmentedHandlers[ObjectIdentifier(segmented)] = handler
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
}
