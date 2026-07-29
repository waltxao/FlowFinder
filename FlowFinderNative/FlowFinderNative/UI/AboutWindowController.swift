import AppKit

/// 关于 FlowFinder 独立窗口（仿 Finder 关于对话框）
/// 任务 R3: 点击侧边栏顶部应用图标弹出此窗口
/// 任务 F11-2: 窗口实体背景（windowBackgroundColor），确保内容清晰可读（v0.6.7）。
class AboutWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 FlowFinder"
        // 任务 F11-2: 实体窗口背景（v0.6.7）
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        // 任务 F11-2: 容器实体背景（v0.6.7）
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "FlowFinder")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 17)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // 动态读取 Bundle 版本号，与 SettingsWindowController 写法保持一致，避免升级后版本号脱钩
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "版本 \(shortVersion) (\(buildVersion))")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyrightLabel = NSTextField(labelWithString: "© 2026 FlowFinder")
        copyrightLabel.font = NSFont.systemFont(ofSize: 10)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(versionLabel)
        container.addSubview(copyrightLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            copyrightLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 4),
            copyrightLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        window?.contentView = container
    }
}
