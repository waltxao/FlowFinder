import Cocoa

/// R4-04：主题卡需要持续可见的选中态。
///
/// 普通 momentary `NSButton` 的 `state` 不产生持续视觉（按下弹起后外观不变），
/// 用户点「深色」后界面变黑了，但三张卡看起来一模一样，认不出当前生效项。
/// 这里自建卡片：选中态用强调色描边 + 淡底 + 图标着色三者共同表达。
final class FFThemeCardButton: NSButton {

    var isSelectedCard: Bool = false {
        didSet { guard oldValue != isSelectedCard else { return } ; refreshChrome() }
    }

    init(title: String, icon: FFIconName, tag: Int) {
        super.init(frame: .zero)
        self.tag = tag
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageAbove
        imageScaling = .scaleNone
        font = NSFont.systemFont(ofSize: 12, weight: .medium)
        image = FFIcon.template(icon, size: 28)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                         .foregroundColor: NSColor.labelColor]
        )
        toolTip = title
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        refreshChrome()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshChrome),
            name: .appearanceChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshChrome),
            name: .accentColorChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    @objc private func refreshChrome() {
        let accent = FFAccent.current
        let selected = isSelectedCard
        // layer 只吃 CGColor 快照：动态色必须在视图自身的外观里解析，
        // 否则深色模式下 controlBackgroundColor 会按 Aqua 解析成纯白（实测）。
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.cornerRadius = 10
            self.layer?.cornerCurve = .continuous
            self.layer?.borderWidth = selected ? 2 : 1
            self.layer?.borderColor = (selected ? accent : NSColor.separatorColor).cgColor
            self.layer?.backgroundColor = (selected
                                           ? accent.withAlphaComponent(0.10)
                                           : NSColor.controlBackgroundColor).cgColor
        }
        contentTintColor = selected ? accent : NSColor.secondaryLabelColor
    }
}

/// 外观设置视图：主题三卡（浅色/深色/自动跟随系统）+ 界面尺寸
/// R4-04/R4-26：卡片改为等宽铺满整行（原 100×100 左对齐、右侧大片死白），
/// 带持续选中态；删掉视图内重复的「外观」标题（分区标题已经是「主题」）。
public class AppearanceSettingsView: NSView {

    private var cardStack: NSStackView!
    private var themeCards: [FFThemeCardButton] = []
    private var descriptionLabel: NSTextField!
    private var sizeTitleLabel: NSTextField!
    private var sizeControl: NSSegmentedControl!
    private var sizeHintLabel: NSTextField!

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
        cardStack = NSStackView()
        cardStack.orientation = .horizontal
        cardStack.distribution = .fillEqually
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        themeCards = AppearanceMode.allCases.map { mode in
            let card = FFThemeCardButton(title: mode.title, icon: mode.icon, tag: mode.rawValue)
            card.target = self
            card.action = #selector(themeButtonClicked(_:))
            cardStack.addArrangedSubview(card)
            return card
        }

        descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.textColor = NSColor.secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        sizeTitleLabel = NSTextField(labelWithString: "界面尺寸")
        sizeTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        sizeTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        sizeControl = NSSegmentedControl(
            labels: FFSizeLevel.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(sizeLevelChanged(_:))
        )
        sizeControl.segmentStyle = .rounded
        sizeControl.translatesAutoresizingMaskIntoConstraints = false

        sizeHintLabel = NSTextField(labelWithString: "影响正文与图标尺寸；顶栏保持 44pt 高度。")
        sizeHintLabel.font = NSFont.systemFont(ofSize: 11)
        sizeHintLabel.textColor = NSColor.secondaryLabelColor
        sizeHintLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardStack)
        addSubview(descriptionLabel)
        addSubview(sizeTitleLabel)
        addSubview(sizeControl)
        addSubview(sizeHintLabel)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            cardStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardStack.heightAnchor.constraint(equalToConstant: 92),

            descriptionLabel.topAnchor.constraint(equalTo: cardStack.bottomAnchor, constant: 10),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            sizeTitleLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 16),
            sizeTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            sizeControl.topAnchor.constraint(equalTo: sizeTitleLabel.bottomAnchor, constant: 8),
            sizeControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            sizeControl.widthAnchor.constraint(equalToConstant: 240),
            sizeControl.heightAnchor.constraint(equalToConstant: 24),

            sizeHintLabel.topAnchor.constraint(equalTo: sizeControl.bottomAnchor, constant: 8),
            sizeHintLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            sizeHintLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Bug #17 修复：约束链必须闭合到底部，否则视图在 NSStackView 中高度歧义、塌缩为 0。
            sizeHintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        updateSelection()
    }

    // MARK: - Bindings

    private func setupBindings() {
        // onModeChanged 是单回调，保留前一个回调链避免覆盖其他组件已注册的监听
        let previousCallback = ThemeManager.shared.onModeChanged
        ThemeManager.shared.onModeChanged = { [weak self] mode in
            previousCallback?(mode)
            DispatchQueue.main.async {
                self?.updateSelection()
            }
        }
    }

    private func updateSelection() {
        let currentMode = ThemeManager.shared.currentMode
        for card in themeCards {
            card.isSelectedCard = card.tag == currentMode.rawValue
        }

        let sizeIndex = FFSizeLevel.allCases.firstIndex(of: FFSizePreference.current) ?? 1
        sizeControl.selectedSegment = sizeIndex

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

    @objc private func sizeLevelChanged(_ sender: NSSegmentedControl) {
        guard FFSizeLevel.allCases.indices.contains(sender.selectedSegment) else { return }
        let level = FFSizeLevel.allCases[sender.selectedSegment]
        FFSizePreference.current = level
        FFDebug.log("AppearanceSettingsView.sizeLevelChanged: \(level.rawValue)")
    }
}
