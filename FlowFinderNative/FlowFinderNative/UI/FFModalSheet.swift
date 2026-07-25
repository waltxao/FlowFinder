import AppKit

/// 闭包持有盒：用于在 super.init 前构造占位闭包，super.init 后再注入依赖 self 的逻辑。
/// 解决 Swift 6 严格模式禁止在 super.init 前向 escaping 闭包捕获 self 的问题。
final class FFClosureBox {
    var closure: (() -> Void)?
}

/// 模态对话框主按钮样式
enum FFModalSheetButtonStyle {
    case `default`    // accent 色
    case destructive  // 红色
    case plain        // 普通次要按钮
}

/// 模态对话框基类
///
/// 设计稿中所有对话框共用 macOS sheet 风格（圆角 12pt、阴影、header/body/footer 三段式）。
/// 基于 `FFGlassView(level: .panel, material: .sheet, cornerRadius: 12)` 提供液态玻璃增强背景。
///
/// 用法：
/// ```swift
/// let bodyView = NSView()  // 自定义 body 内容
/// let sheet = FFModalSheet(
///     title: "选择标签",
///     bodyView: bodyView,
///     primaryButton: ("确定", .default),
///     secondaryButton: "取消",
///     primaryAction: { /* 点击确定 */ }
/// )
/// sheet.beginSheetModal(for: parentWindow)
/// ```
class FFModalSheet: NSWindow {

    // MARK: - 配置

    let primaryButtonTitle: String
    let primaryButtonStyle: FFModalSheetButtonStyle
    let secondaryButtonTitle: String?
    let primaryAction: () -> Void

    // MARK: - UI 元素

    private var headerView: NSView!
    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var bodyContainer: NSView!
    private var footerView: NSView!
    private var primaryButton: NSButton!
    private var secondaryButton: NSButton?

    /// 对话框默认宽度
    private let defaultWidth: CGFloat = 420
    /// header 高度
    private let headerHeight: CGFloat = 40
    /// footer 高度
    private let footerHeight: CGFloat = 56
    /// body 上下边距
    private let bodyVerticalPadding: CGFloat = 12
    /// body 左右边距
    private let horizontalPadding: CGFloat = 20

    // MARK: - 初始化

    init(title: String,
         bodyView: NSView,
         primaryButton: (title: String, style: FFModalSheetButtonStyle),
         secondaryButton: String?,
         primaryAction: @escaping () -> Void) {
        self.primaryButtonTitle = primaryButton.title
        self.primaryButtonStyle = primaryButton.style
        self.secondaryButtonTitle = secondaryButton
        self.primaryAction = primaryAction

        // 初始 frame 临时值，后续根据 body 计算
        let initialRect = NSRect(x: 0, y: 0, width: defaultWidth, height: 400)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        self.title = title
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.hasShadow = true
        self.isReleasedWhenClosed = false

        // 玻璃背景
        let glass = FFGlassView(level: .panel,
                                cornerRadius: 12,
                                material: .sheet)
        glass.translatesAutoresizingMaskIntoConstraints = false
        self.contentView = glass

        setupHeader(title: title)
        setupBody(bodyView: bodyView)
        setupFooter()

        // 计算并设置最终大小
        layoutAndResize()
    }

    // MARK: - Header

    private func setupHeader(title: String) {
        headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(headerView)

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        closeButton = NSButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.image = NSImage(systemSymbolName: "xmark",
                                    accessibilityDescription: "关闭")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        headerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor,
                                                constant: horizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor,
                                                  constant: -horizontalPadding),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Body

    private func setupBody(bodyView: NSView) {
        bodyContainer = NSView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(bodyContainer)
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyView)

        NSLayoutConstraint.activate([
            bodyContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor,
                                                  constant: horizontalPadding),
            bodyContainer.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor,
                                                   constant: -horizontalPadding),

            bodyView.topAnchor.constraint(equalTo: bodyContainer.topAnchor,
                                          constant: bodyVerticalPadding),
            bodyView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor,
                                             constant: -bodyVerticalPadding),
        ])
    }

    // MARK: - Footer

    private func setupFooter() {
        footerView = NSView()
        footerView.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(footerView)

        // 主按钮
        primaryButton = makeButton(title: primaryButtonTitle,
                                   style: primaryButtonStyle,
                                   isPrimary: true,
                                   action: #selector(primaryButtonClicked))
        footerView.addSubview(primaryButton)

        // 次按钮（可选）
        var constraints = [
            footerView.topAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            footerView.heightAnchor.constraint(equalToConstant: footerHeight),

            primaryButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor,
                                                    constant: -horizontalPadding),
            primaryButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            primaryButton.heightAnchor.constraint(equalToConstant: 24),
        ]

        if let secondaryTitle = secondaryButtonTitle {
            let secondary = makeButton(title: secondaryTitle,
                                       style: .plain,
                                       isPrimary: false,
                                       action: #selector(secondaryButtonClicked))
            footerView.addSubview(secondary)
            secondaryButton = secondary
            constraints.append(contentsOf: [
                secondary.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor,
                                                    constant: -8),
                secondary.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
                secondary.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
                secondary.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    /// 创建按钮
    private func makeButton(title: String,
                            style: FFModalSheetButtonStyle,
                            isPrimary: Bool,
                            action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: isPrimary ? .semibold : .regular)

        // 用 FFGlassView(level: .component) 包裹提供玻璃质感
        let glassBg = FFGlassView(level: .component, cornerRadius: 4)
        glassBg.translatesAutoresizingMaskIntoConstraints = false
        glassBg.wantsLayer = true
        button.addSubview(glassBg, positioned: .below, relativeTo: nil)  // 放到最底层
        NSLayoutConstraint.activate([
            glassBg.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            glassBg.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            glassBg.topAnchor.constraint(equalTo: button.topAnchor),
            glassBg.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        // 主按钮文字色按样式
        switch style {
        case .default:
            button.contentTintColor = .white
            // 叠加 accent 色 tint
            let accentOverlay = CALayer()
            accentOverlay.backgroundColor = NSColor.controlAccentColor.cgColor
            accentOverlay.opacity = 0.85
            glassBg.layer?.addSublayer(accentOverlay)
            // 让文字白色更清晰
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.white,
                             .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
            )
        case .destructive:
            button.contentTintColor = .white
            let accentOverlay = CALayer()
            accentOverlay.backgroundColor = NSColor.systemRed.cgColor
            accentOverlay.opacity = 0.85
            glassBg.layer?.addSublayer(accentOverlay)
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.white,
                             .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
            )
        case .plain:
            button.contentTintColor = .controlAccentColor
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.labelColor,
                             .font: NSFont.systemFont(ofSize: 12)]
            )
        }

        return button
    }

    // MARK: - 布局计算

    /// 根据 body 内容计算并设置窗口最终大小
    private func layoutAndResize() {
        contentView?.layoutSubtreeIfNeeded()

        // 计算 body 内容所需高度（fittingSize 包含所有约束的最小尺寸）
        let bodyHeight = bodyContainer.fittingSize.height
        let totalHeight = headerHeight + bodyHeight + footerHeight

        let frame = NSRect(x: 0, y: 0, width: defaultWidth, height: totalHeight)
        self.setFrame(frame, display: true)
    }

    // MARK: - 按钮事件

    @objc private func closeButtonClicked() {
        cancel()
    }

    @objc private func primaryButtonClicked() {
        primaryAction()
        close()
    }

    @objc private func secondaryButtonClicked() {
        cancel()
    }

    /// 取消关闭
    private func cancel() {
        close()
    }

    // MARK: - 显示

    /// 以 sheet 形式附加到目标窗口
    func beginSheetModal(for parentWindow: NSWindow) {
        parentWindow.beginSheet(self, completionHandler: nil)
    }

    /// 作为独立模态窗口显示（阻塞当前线程）
    func runModal() -> NSApplication.ModalResponse {
        return NSApp.runModal(for: self)
    }
}
