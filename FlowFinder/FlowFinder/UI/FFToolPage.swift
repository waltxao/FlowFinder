import AppKit

// MARK: - 工具页目录（R19-2 D-05/D-06）

/// 工具页只列用户批准的可用工具，并按「整理 / 任务 / 系统」纵向分组。
///
/// AI 两个「即将推出」工具仍注册在全局注册表里（右键菜单等照旧可见），
/// 但不进入工具页——工具页只放现在真能用的东西。
enum FFToolPageCatalog {

    struct Entry {
        let tool: FFTool
        let availability: FFToolAvailability
    }

    static let includedToolIDs = ["duplicate-scan", "batch-rename", "task-center", "settings", "about"]

    static func entries(context: FFToolContext, registry: FFToolRegistry = .shared) -> [Entry] {
        registry.registeredTools
            .filter { includedToolIDs.contains($0.id) }
            .sorted { idIndex($0.id) < idIndex($1.id) }
            .map { Entry(tool: $0, availability: $0.availability(in: context)) }
    }

    static func grouped(context: FFToolContext,
                        registry: FFToolRegistry = .shared) -> [(group: FFToolGroup, entries: [Entry])] {
        let all = entries(context: context, registry: registry)
        return FFToolGroup.allCases.compactMap { group in
            let inGroup = all.filter { $0.tool.group == group }
            return inGroup.isEmpty ? nil : (group, inGroup)
        }
    }

    private static func idIndex(_ id: String) -> Int {
        includedToolIDs.firstIndex(of: id) ?? Int.max
    }
}

// MARK: - 工具行

final class FFToolRowView: NSView {

    /// 桌面 hit target 下限 24pt；这里取 32pt 以留出呼吸感。
    static let preferredHeight: CGFloat = 32
    let tool: FFTool
    var onClick: (() -> Void)?
    private let availability: FFToolAvailability
    private var hovered = false { didSet { needsDisplay = true } }

    init(tool: FFTool, availability: FFToolAvailability) {
        self.tool = tool
        self.availability = availability
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = FFIcon.template(tool.icon, size: 16)
        icon.contentTintColor = availability.isAvailable ? .secondaryLabelColor : .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: tool.title)
        title.font = FFVisualTokens.Font.body
        title.textColor = availability.isAvailable ? .labelColor : .tertiaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let hintText = availability.reason ?? tool.contextHint
        let reason = NSTextField(labelWithString: hintText ?? "")
        reason.font = FFVisualTokens.Font.caption
        reason.textColor = .tertiaryLabelColor
        reason.isHidden = hintText == nil
        reason.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reason)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tool.title)
        setAccessibilityHelp(hintText ?? "")
        setAccessibilityEnabled(availability.isAvailable)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),

            reason.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            reason.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: reason.leadingAnchor, constant: -6),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard availability.isAvailable else { return }
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override var acceptsFirstResponder: Bool { availability.isAvailable }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard availability.isAvailable else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    override func keyDown(with event: NSEvent) {
        if availability.isAvailable,
           event.keyCode == 36 || event.keyCode == 49 {
            onClick?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hovered, availability.isAvailable else { return }
        let rect = bounds.insetBy(dx: 4, dy: 1)
        FFAccent.current.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect,
                     xRadius: FFVisualTokens.Radius.control,
                     yRadius: FFVisualTokens.Radius.control).fill()

        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                    xRadius: FFVisualTokens.Radius.control,
                                    yRadius: FFVisualTokens.Radius.control)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

// MARK: - 侧栏工具页（R19-2 D-03/D-04）

/// 侧栏内的工具页：只替换侧栏内容，文件区与滚动位置都不动。
///
/// D-04：页面头部只有标题与「返回收藏」，不显示当前路径、选中数量或活动面板——
/// 那些是右键菜单的输入，工具页只回答「现在能做什么」。
final class SidebarToolPageView: NSView {

    static let title = "工具"
    static let backTitle = "返回收藏"

    /// 执行完工具 / 点「返回收藏」后通知属主退出工具页
    var onDismiss: (() -> Void)?

    private let context: FFToolContext
    private let backButton = NSButton(title: backTitle, target: nil, action: nil)
    private var rows: [FFToolRowView] = []

    var backButtonForTesting: NSButton { backButton }
    var headerTextsForTesting: [String] { [Self.title, backButton.title] }
    func rowViewsForTesting() -> [FFToolRowView] { rows }

    /// 批次 1 B1-10：工具页打开时接入窗口 keyViewLoop
    func focusableViewsForTesting() -> [NSView] { rows }

    init(context: FFToolContext) {
        self.context = context
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: Self.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        backButton.target = self
        backButton.action = #selector(backClicked)
        backButton.isBordered = false
        backButton.font = FFVisualTokens.Font.caption
        backButton.contentTintColor = FFAccent.current
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setAccessibilityLabel(Self.backTitle)

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)
        header.addSubview(backButton)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedToolPageContainer()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document

        addSubview(header)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            header.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
        ])

        for (group, entries) in FFToolPageCatalog.grouped(context: context) {
            let groupTitle = NSTextField(labelWithString: group.title)
            groupTitle.font = FFVisualTokens.Font.captionMedium
            groupTitle.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(groupTitle)
            stack.setCustomSpacing(2, after: groupTitle)

            var lastRow: NSView?
            for entry in entries {
                let row = FFToolRowView(tool: entry.tool, availability: entry.availability)
                row.onClick = { [weak self] in
                    guard let self else { return }
                    entry.tool.run(in: self.context)
                    self.onDismiss?()
                }
                stack.addArrangedSubview(row)
                rows.append(row)
                lastRow = row
            }
            if let lastRow {
                stack.setCustomSpacing(10, after: lastRow)
            }
        }

        // 行必须铺满栈宽，否则右侧可用性提示贴不到边缘（.leading 对齐只保证左缘）
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func backClicked() {
        onDismiss?()
    }
}

/// 工具页滚动文档：flipped，内容贴顶（与非 flipped 的侧栏滚动容器同理）
private final class FlippedToolPageContainer: NSView {
    override var isFlipped: Bool { true }
}
