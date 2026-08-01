import Cocoa

// MARK: - SearchFilterConfig

/// 搜索筛选配置（由侧边栏维护，外部读取以驱动搜索）
struct SearchFilterConfig {
    /// 搜索条件
    var matchFileName: Bool = true       // 文件名包含
    var matchContent: Bool = false       // 内容包含
    var caseSensitive: Bool = false      // 区分大小写
    /// 文件类型筛选（选中的类型，空集合表示全部）
    var enabledTypes: Set<FileTypeFilter> = []
    /// 标签筛选（选中的标签名，空集合表示全部）
    var enabledTags: Set<String> = []
}

/// 文件类型筛选枚举
enum FileTypeFilter: String, CaseIterable {
    case pdf = "PDF"
    case image = "图片"
    case video = "视频"
    case document = "文档"
    case audio = "音频"
    case other = "其他"

    var iconName: String {
        switch self {
        case .pdf:      return "doc.richtext"
        case .image:    return "photo"
        case .video:    return "film"
        case .document: return "doc.text"
        case .audio:    return "music.note"
        case .other:    return "doc"
        }
    }
}

// MARK: - SearchFilterSidebar

/// 搜索筛选侧边栏：搜索条件 + 文件类型 + 标签 三个 section
/// 容器背景由外部实体背景提供，section header 用实体背景 chip
class SearchFilterSidebar: NSView {

    /// 当前筛选配置（外部读取）
    private(set) var config = SearchFilterConfig()

    /// 配置变更回调（触发重新搜索）
    var onConfigChanged: ((SearchFilterConfig) -> Void)?

    private let mainStack = NSStackView()

    // MARK: - Init

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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        mainStack.orientation = .vertical
        mainStack.spacing = 16
        mainStack.detachesHiddenViews = false
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        scrollView.documentView = mainStack

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            // mainStack 宽度跟随 clipView
            mainStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            mainStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        rebuildConditionsSection()
        rebuildFileTypesSection()
        rebuildTagsSection()
    }

    // MARK: - Section: 搜索条件

    private func rebuildConditionsSection() {
        let section = makeSection(title: "搜索条件")
        section.addRow(makeCheckRow(title: "文件名包含", state: config.matchFileName) { [weak self] on in
            self?.config.matchFileName = on
            self?.fireChange()
        })
        section.addRow(makeCheckRow(title: "内容包含", state: config.matchContent) { [weak self] on in
            self?.config.matchContent = on
            self?.fireChange()
        })
        section.addRow(makeCheckRow(title: "区分大小写", state: config.caseSensitive) { [weak self] on in
            self?.config.caseSensitive = on
            self?.fireChange()
        })
        mainStack.addArrangedSubview(section)
    }

    // MARK: - Section: 文件类型

    private var fileTypesSection: SettingsSectionView?

    private func rebuildFileTypesSection() {
        if let existing = fileTypesSection {
            mainStack.removeArrangedSubview(existing)
            existing.removeFromSuperview()
        }
        let section = makeSection(title: "文件类型")
        for type in FileTypeFilter.allCases {
            let row = makeCheckRow(
                title: type.rawValue,
                icon: type.iconName,
                state: config.enabledTypes.contains(type)
            ) { [weak self] on in
                if on {
                    self?.config.enabledTypes.insert(type)
                } else {
                    self?.config.enabledTypes.remove(type)
                }
                self?.fireChange()
            }
            section.addRow(row)
        }
        fileTypesSection = section
        // 插入到主 stack 的第二个位置（搜索条件之后）
        if mainStack.arrangedSubviews.count > 1 {
            mainStack.insertArrangedSubview(section, at: 1)
        } else {
            mainStack.addArrangedSubview(section)
        }
    }

    // MARK: - Section: 标签

    private var tagsSection: SettingsSectionView?

    private func rebuildTagsSection() {
        if let existing = tagsSection {
            mainStack.removeArrangedSubview(existing)
            existing.removeFromSuperview()
        }
        let section = makeSection(title: "标签")
        let emptyRow = SettingsRowView(title: "暂无标签")
        section.addRow(emptyRow)
        tagsSection = section
        mainStack.addArrangedSubview(section)
    }

    // MARK: - 组件工厂

    /// 创建 section 容器（标题用 FFGlassView(.component) chip 背景）
    private func makeSection(title: String) -> SettingsSectionView {
        let section = SettingsSectionView(title: title)
        section.translatesAutoresizingMaskIntoConstraints = false
        return section
    }

    /// 创建复选框行（26pt 高，圆角 6pt，左侧 14x14 复选框 + 标签 + 可选计数药丸）
    private func makeCheckRow(title: String,
                              icon: String? = nil,
                              colorHex: String? = nil,
                              count: Int? = nil,
                              state: Bool,
                              action: @escaping (Bool) -> Void) -> SettingsRowView {
        // 左侧图标区（可选：SF Symbol 或彩色圆点）
        var leftView: NSView?
        if let iconName = icon {
            let iconView = NSImageView()
            iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: title)
            iconView.contentTintColor = NSColor.secondaryLabelColor
            iconView.imageScaling = .scaleProportionallyDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 14).isActive = true
            leftView = iconView
        } else if let hex = colorHex {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = (NSColor(hex: hex) ?? .systemBlue).cgColor
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            leftView = dot
        }

        // 复选框（NSSwitch 紧凑型，14x14 视觉）
        let toggle = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        toggle.state = state ? .on : .off
        toggle.font = NSFont.systemFont(ofSize: 12)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = SearchFilterActionTarget.shared
        toggle.action = #selector(SearchFilterActionTarget.toggleChanged(_:))
        SearchFilterActionTarget.shared.register(toggle: toggle, handler: action)

        // 计数药丸（可选）
        if let count = count {
            let pill = NSTextField(labelWithString: "\(count)")
            pill.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            pill.textColor = NSColor.secondaryLabelColor
            pill.alignment = .center
            pill.wantsLayer = true
            pill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
            pill.layer?.cornerRadius = 7
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
            pill.heightAnchor.constraint(equalToConstant: 14).isActive = true

            // 组装：复选框 + 弹性间距 + 药丸
            let row = SettingsRowView(title: "")
            // 清除默认控件，使用自定义布局
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(toggle)
            container.addSubview(pill)
            if let left = leftView {
                container.addSubview(left)
                NSLayoutConstraint.activate([
                    left.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    left.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    toggle.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 6),
                ])
            } else {
                NSLayoutConstraint.activate([
                    toggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                ])
            }
            NSLayoutConstraint.activate([
                toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                pill.leadingAnchor.constraint(greaterThanOrEqualTo: toggle.trailingAnchor, constant: 4),
                pill.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                pill.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.heightAnchor.constraint(equalToConstant: 22),
            ])
            row.setControl(container)
            return row
        } else {
            let row = SettingsRowView(title: "")
            // 清除默认控件，使用复选框
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(toggle)
            if let left = leftView {
                container.addSubview(left)
                NSLayoutConstraint.activate([
                    left.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    left.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    toggle.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 6),
                ])
            } else {
                NSLayoutConstraint.activate([
                    toggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                ])
            }
            NSLayoutConstraint.activate([
                toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                toggle.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                container.heightAnchor.constraint(equalToConstant: 22),
            ])
            row.setControl(container)
            return row
        }
    }

    // MARK: - 通知

    private func fireChange() {
        onConfigChanged?(config)
    }
}

// MARK: - SearchFilterActionTarget

/// 闭包桥接目标对象（避免每行单独创建 NSObject 子类）
private class SearchFilterActionTarget: NSObject {
    static let shared = SearchFilterActionTarget()
    private var handlers: [ObjectIdentifier: (Bool) -> Void] = [:]

    func register(toggle: NSButton, handler: @escaping (Bool) -> Void) {
        handlers[ObjectIdentifier(toggle)] = handler
    }

    @objc func toggleChanged(_ sender: NSButton) {
        handlers[ObjectIdentifier(sender)]?(sender.state == .on)
    }
}
