import AppKit

/// 批次 4：首次启动引导策略（纯函数，供测试）。
enum OnboardingPolicy {
    static func shouldShow(completed: Bool, isRunningTests: Bool, selfTest: Bool) -> Bool {
        !completed && !isRunningTests && !selfTest
    }

    static func permissionTitle(denied: Bool) -> String {
        denied ? "待授权" : "已授权"
    }
}

/// 首次启动欢迎窗口：双栏用法 + 权限状态 + 三个快捷键。
/// 「开始使用」写入完成标记；「稍后再看」只关闭本次。
final class OnboardingWindowController: NSWindowController {

    static let shared = OnboardingWindowController()
    static let completedKey = "onboarding_completed"

    private let defaults: UserDefaults
    private var permissionLabels: [String: NSTextField] = [:]
    private var settingsButton: NSButton!

    init(defaults: UserDefaults = .standard, center: Bool = true) {
        self.defaults = defaults
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "欢迎使用 FlowFinder"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        if center { window.center() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showIfNeeded() {
        guard OnboardingPolicy.shouldShow(
            completed: defaults.bool(forKey: Self.completedKey),
            isRunningTests: MainWindowController.isRunningTests,
            selfTest: ProcessInfo.processInfo.environment["FF_SELFTEST"] == "1") else { return }
        show(force: true)
    }

    func show(force: Bool = false) {
        if !force, defaults.bool(forKey: Self.completedKey) { return }
        refreshPermissions()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func startUsing() {
        defaults.set(true, forKey: Self.completedKey)
        close()
    }

    @objc func later() {
        close()
    }

    @objc private func openPrivacySettings() {
        FFPermissionGate.openPrivacySettings(pane: "Privacy_AllFiles")
    }

    // MARK: - UI

    private func label(_ text: String, size: CGFloat, color: NSColor = .labelColor,
                       weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let brand = FFGradientLabelView(text: "FlowFinder",
                                        font: NSFont.systemFont(ofSize: 22, weight: .bold))
        let version = label(FFBuildInfo.displayVersion, size: 11, color: .secondaryLabelColor)
        let lead = label("左右两栏各看一个位置，拖拽或按 ⌘⇧C / ⌘⇧X 把文件搬到另一栏。先确认下面三项权限，体验最完整。",
                         size: 13, color: .secondaryLabelColor)
        lead.lineBreakMode = .byWordWrapping
        lead.maximumNumberOfLines = 2

        // 双栏示意图
        let leftPane = miniPane()
        let arrow = label("⇄", size: 18, color: .controlAccentColor, weight: .semibold)
        let rightPane = miniPane()
        let panes = NSStackView(views: [leftPane, arrow, rightPane])
        panes.orientation = .horizontal
        panes.alignment = .centerY
        panes.spacing = 8
        leftPane.widthAnchor.constraint(equalToConstant: 96).isActive = true
        rightPane.widthAnchor.constraint(equalToConstant: 96).isActive = true
        let paneCaption = label("双栏：拖到另一栏即搬运", size: 11, color: .secondaryLabelColor)

        let illustration = NSStackView(views: [panes, paneCaption])
        illustration.orientation = .vertical
        illustration.alignment = .centerX
        illustration.spacing = 8

        // 权限 + 快捷键
        let info = NSStackView()
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 5
        for title in ["桌面", "文稿", "下载"] {
            let status = label("已授权", size: 12, color: .systemGreen, weight: .semibold)
            permissionLabels[title] = status
            let row = NSStackView(views: [label(title, size: 12), status])
            row.orientation = .horizontal
            row.distribution = .equalSpacing
            row.widthAnchor.constraint(equalToConstant: 180).isActive = true
            info.addArrangedSubview(row)
        }
        info.setCustomSpacing(10, after: info.arrangedSubviews.last!)
        for (key, text) in [("⌘⇧C", "复制到另一栏"), ("⌘F", "搜索当前面板"), ("Space", "预览选中文件")] {
            let keyLabel = label(key, size: 11, color: .labelColor)
            keyLabel.alignment = .center
            keyLabel.wantsLayer = true
            keyLabel.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            keyLabel.layer?.cornerRadius = 4
            keyLabel.layer?.borderWidth = 1
            keyLabel.layer?.borderColor = NSColor.separatorColor.cgColor
            keyLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true
            let row = NSStackView(views: [keyLabel, label(text, size: 12)])
            row.orientation = .horizontal
            row.spacing = 8
            info.addArrangedSubview(row)
        }

        settingsButton = NSButton(title: "打开系统设置授权", target: self,
                                  action: #selector(openPrivacySettings))
        settingsButton.bezelStyle = .inline
        settingsButton.controlSize = .small
        settingsButton.font = NSFont.systemFont(ofSize: 11)
        settingsButton.isHidden = true
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        let columns = NSStackView(views: [illustration, info])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 28

        let later = NSButton(title: "稍后再看", target: self, action: #selector(later))
        later.bezelStyle = .inline
        later.isBordered = false
        later.font = NSFont.systemFont(ofSize: 12)
        later.contentTintColor = .secondaryLabelColor
        let start = NSButton(title: "开始使用", target: self, action: #selector(startUsing))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        start.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(later)
        footer.addSubview(start)
        later.translatesAutoresizingMaskIntoConstraints = false
        start.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: 30),
            later.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            later.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            start.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            start.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        let stack = NSStackView(views: [brand, version, lead, columns, settingsButton, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: brand)
        stack.setCustomSpacing(16, after: lead)
        stack.setCustomSpacing(14, after: columns)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            lead.widthAnchor.constraint(equalTo: stack.widthAnchor),
            columns.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        content.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        window?.setContentSize(NSSize(width: 560, height: fitting.height + 48))
        window?.center()
    }

    private func miniPane() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 70).isActive = true
        return view
    }

    private func refreshPermissions() {
        FFPermissionGate.shared.recheck { [weak self] report in
            guard let self else { return }
            let denied = Set(report.denied.map(\.title))
            for (title, label) in self.permissionLabels {
                let isDenied = denied.contains(title)
                label.stringValue = OnboardingPolicy.permissionTitle(denied: isDenied)
                label.textColor = isDenied ? .systemOrange : .systemGreen
            }
            self.settingsButton.isHidden = !report.needsAttention
        }
    }
}
