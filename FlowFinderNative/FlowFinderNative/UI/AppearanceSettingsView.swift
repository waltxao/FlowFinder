import Cocoa
import Combine

/// 外观设置视图：主题切换（浅色/深色/跟随系统）
public class AppearanceSettingsView: NSView {

    private var titleLabel: NSTextField!
    private var buttonContainer: NSView!
    private var systemButton: NSButton!
    private var lightButton: NSButton!
    private var darkButton: NSButton!
    private var descriptionLabel: NSTextField!

    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - UI Setup

    private func setupUI() {
        // 标题
        titleLabel = NSTextField(labelWithString: "外观")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 按钮容器
        buttonContainer = NSView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false

        // 系统跟随按钮
        systemButton = createThemeButton(
            title: AppearanceMode.system.title,
            icon: AppearanceMode.system.iconName,
            mode: .system
        )

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

        buttonContainer.addSubview(systemButton)
        buttonContainer.addSubview(lightButton)
        buttonContainer.addSubview(darkButton)

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

            systemButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            systemButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            systemButton.widthAnchor.constraint(equalToConstant: 100),
            systemButton.heightAnchor.constraint(equalToConstant: 100),

            lightButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            lightButton.leadingAnchor.constraint(equalTo: systemButton.trailingAnchor, constant: 16),
            lightButton.widthAnchor.constraint(equalToConstant: 100),
            lightButton.heightAnchor.constraint(equalToConstant: 100),

            darkButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            darkButton.leadingAnchor.constraint(equalTo: lightButton.trailingAnchor, constant: 16),
            darkButton.widthAnchor.constraint(equalToConstant: 100),
            darkButton.heightAnchor.constraint(equalToConstant: 100),

            descriptionLabel.topAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
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
        ThemeManager.shared.$currentMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSelection()
            }
            .store(in: &cancellables)
    }

    private func updateSelection() {
        let currentMode = ThemeManager.shared.currentMode

        systemButton.state = currentMode == .system ? .on : .off
        lightButton.state = currentMode == .light ? .on : .off
        darkButton.state = currentMode == .dark ? .on : .off

        switch currentMode {
        case .system:
            descriptionLabel.stringValue = "应用将跟随系统的外观设置自动切换。"
        case .light:
            descriptionLabel.stringValue = "应用始终使用浅色外观，不受系统设置影响。"
        case .dark:
            descriptionLabel.stringValue = "应用始终使用深色外观，不受系统设置影响。"
        }
    }

    // MARK: - Actions

    @objc private func themeButtonClicked(_ sender: NSButton) {
        guard let mode = AppearanceMode(rawValue: sender.tag) else { return }
        ThemeManager.shared.applyMode(mode)
    }
}
