import AppKit

// MARK: - 底栏工具目录（R19-2 D-05/D-06）

/// 底栏工具簇只列文件工具，并按「整理 / 任务」顺序排列。
///
/// 设置与关于是应用命令（菜单/侧栏入口），不属于文件工具，不进入底栏圆钮。
/// AI 两个「即将推出」工具仍注册在全局注册表里（右键菜单等照旧可见）。
enum FFToolPageCatalog {

    struct Entry {
        let tool: FFTool
        let availability: FFToolAvailability
    }

    static let includedToolIDs = ["duplicate-scan", "batch-rename", "batch-organize", "task-center"]

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
        // 不可用的工具靠图标变淡 + 右侧原因表达；名称本身仍要读得清（R4-27）
        title.textColor = availability.isAvailable ? .labelColor : FFVisualTokens.hint
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let hintText = availability.reason ?? tool.contextHint
        let reason = NSTextField(labelWithString: hintText ?? "")
        reason.font = FFVisualTokens.Font.caption
        reason.textColor = FFVisualTokens.hint
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

    /// VoiceOver / AX 按压激活（实机验证发现 AXPress 此前无效）
    override func accessibilityPerformPress() -> Bool {
        guard availability.isAvailable else { return false }
        onClick?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if hovered, availability.isAvailable {
            let rect = bounds.insetBy(dx: 4, dy: 1)
            FFAccent.current.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: rect,
                         xRadius: FFVisualTokens.Radius.control,
                         yRadius: FFVisualTokens.Radius.control).fill()
        }

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

    private var context: FFToolContext
    private let backButton = NSButton(title: backTitle, target: nil, action: nil)
    private let contentStack = NSStackView()
    private var rows: [FFToolRowView] = []
    private var availabilitySignature = ""

    var backButtonForTesting: NSButton { backButton }
    var headerTextsForTesting: [String] { [Self.title, backButton.title] }
    func rowViewsForTesting() -> [FFToolRowView] { rows }

    /// 批次 1 B1-10：工具页打开时接入窗口 keyViewLoop
    func focusableViewsForTesting() -> [NSView] { [backButton] + rows }

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

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 2
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedToolPageContainer()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)
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
            contentStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
        ])

        populateRows()
    }

    /// 选择/目录变化时更新可用性，不重建头部与滚动位置。
    func updateContext(_ newContext: FFToolContext) {
        let signature = FFToolPageCatalog.entries(context: newContext)
            .map { "\($0.tool.id):\(String(describing: $0.availability))" }
            .joined(separator: "|")
        context = newContext
        guard signature != availabilitySignature else { return }
        populateRows()
    }

    private func populateRows() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll()

        let grouped = FFToolPageCatalog.grouped(context: context)
        availabilitySignature = grouped
            .flatMap { $0.entries }
            .map { "\($0.tool.id):\(String(describing: $0.availability))" }
            .joined(separator: "|")

        for (group, entries) in grouped {
            let groupTitle = NSTextField(labelWithString: group.title)
            groupTitle.font = FFVisualTokens.Font.captionMedium
            groupTitle.textColor = FFVisualTokens.hint
            contentStack.addArrangedSubview(groupTitle)
            contentStack.setCustomSpacing(2, after: groupTitle)

            var lastRow: NSView?
            for entry in entries {
                let row = FFToolRowView(tool: entry.tool, availability: entry.availability)
                row.onClick = { [weak self] in
                    guard let self else { return }
                    entry.tool.run(in: self.context)
                    self.onDismiss?()
                }
                contentStack.addArrangedSubview(row)
                rows.append(row)
                lastRow = row
            }
            if let lastRow {
                contentStack.setCustomSpacing(10, after: lastRow)
            }
        }

        // 行必须铺满栈宽，否则右侧可用性提示贴不到边缘（.leading 对齐只保证左缘）
        for subview in contentStack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
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
