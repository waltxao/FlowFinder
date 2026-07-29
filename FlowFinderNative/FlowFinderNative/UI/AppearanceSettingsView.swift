import Cocoa

/// 外观设置视图：主题切换（浅色/深色/自动跟随系统 三态）
/// 任务 F11-3: 恢复 .system 三态（v0.6.7），修正 v0.6.5 T2 错误移除
public class AppearanceSettingsView: NSView {

    private var titleLabel: NSTextField!
    private var buttonContainer: NSView!
    private var lightButton: NSButton!
    private var darkButton: NSButton!
    private var systemButton: NSButton!
    private var descriptionLabel: NSTextField!

    private var onModeChangedToken: ((AppearanceMode) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupBindings()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupBindings()
    }

    deinit {
        // 解绑 ThemeManager 回调
        if let token = ThemeManager.shared.onModeChanged, let myToken = onModeChangedToken {
            _ = myToken  // 防止 unused warning
            _ = token
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 标题
        titleLabel = NSTextField(labelWithString: "外观")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 按钮容器
        buttonContainer = NSView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false

        // 浅色按钮
        lightButton = createThemeButton(
            title: AppearanceMode.light.title,
            icon: AppearanceMode.light.iconName,
            mode: .light
        )

        // 深色按钮
        darkButton = createThemeButton(
            title: AppearanceMode.dark.title,
            icon: AppearanceMode.dark.iconName,
            mode: .dark
        )

        // 自动跟随系统按钮（任务 F11-3: 恢复三态）
        systemButton = createThemeButton(
            title: AppearanceMode.system.title,
            icon: AppearanceMode.system.iconName,
            mode: .system
        )

        buttonContainer.addSubview(lightButton)
        buttonContainer.addSubview(darkButton)
        buttonContainer.addSubview(systemButton)

        // 描述标签
        descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.textColor = NSColor.secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(buttonContainer)
        addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            buttonContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            buttonContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            buttonContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            buttonContainer.heightAnchor.constraint(equalToConstant: 100),

            lightButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            lightButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            lightButton.widthAnchor.constraint(equalToConstant: 100),
            lightButton.heightAnchor.constraint(equalToConstant: 100),

            darkButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            darkButton.leadingAnchor.constraint(equalTo: lightButton.trailingAnchor, constant: 16),
            darkButton.widthAnchor.constraint(equalToConstant: 100),
            darkButton.heightAnchor.constraint(equalToConstant: 100),

            systemButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            systemButton.leadingAnchor.constraint(equalTo: darkButton.trailingAnchor, constant: 16),
            systemButton.widthAnchor.constraint(equalToConstant: 100),
            systemButton.heightAnchor.constraint(equalToConstant: 100),

            descriptionLabel.topAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            // Bug #17 修复：原约束链仅自顶向下，未闭合到底部，视图在 NSStackView 中高度歧义、塌缩为 0。
            // 增加底部约束闭合高度链，使视图依据内容获得确定高度。
            // 修复：lessThanOrEqualTo 只设最小高度约束，在 NSStackView 中视图可能被压缩到 0 高度。
            // 改为 equalTo 闭合高度链，使视图获得确定高度。
            descriptionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])

        updateSelection()
    }

    private func createThemeButton(title: String, icon: String, mode: AppearanceMode) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = true
        button.title = ""
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.imagePosition = .imageAbove
        button.font = NSFont.systemFont(ofSize: 12)
        button.toolTip = title
        button.tag = mode.rawValue
        button.target = self
        button.action = #selector(themeButtonClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        // 使用副标题显示文字
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        )
        button.image?.size = NSSize(width: 40, height: 40)
        return button
    }

    // MARK: - Bindings

    private func setupBindings() {
        // 任务 T2: 移除 @Published，改用 onModeChanged 回调
        // 注意：onModeChanged 是单回调，需保留前一个回调链
        let previousCallback = ThemeManager.shared.onModeChanged
        onModeChangedToken = { [weak self] mode in
            DispatchQueue.main.async {
                self?.updateSelection()
            }
        }
        ThemeManager.shared.onModeChanged = { [weak self] mode in
            previousCallback?(mode)
            self?.onModeChangedToken?(mode)
        }
    }

    private func updateSelection() {
        let currentMode = ThemeManager.shared.currentMode

        lightButton.state = currentMode == .light ? .on : .off
        darkButton.state = currentMode == .dark ? .on : .off
        systemButton.state = currentMode == .system ? .on : .off

        switch currentMode {
        case .light:
            descriptionLabel.stringValue = "应用始终使用浅色外观，不受系统设置影响。"
        case .dark:
            descriptionLabel.stringValue = "应用始终使用深色外观，不受系统设置影响。"
        case .system:
            descriptionLabel.stringValue = "应用自动跟随系统外观，系统切换浅/深色时即时生效。"
        }
    }

    // MARK: - Actions

    @objc private func themeButtonClicked(_ sender: NSButton) {
        guard let mode = AppearanceMode(rawValue: sender.tag) else { return }
        ThemeManager.shared.applyMode(mode)
    }
}
