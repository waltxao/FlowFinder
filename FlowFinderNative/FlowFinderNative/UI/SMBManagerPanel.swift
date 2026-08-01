import Cocoa
import Combine

// MARK: - SMBManagerPanel

/// SMB 管理面板（重写版）：服务器列表行（状态圆点+名称+IP+状态标签+连接/断开按钮）+ 底部"添加服务器"按钮
/// 每行用 FFGlassView(level: .component, cornerRadius: 6) 作为卡片背景
public class SMBManagerPanel: NSView {

    private var serverStack: NSStackView!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var addButton: NSButton!
    private var refreshButton: NSButton!

    /// 已挂载的共享列表
    private var volumes: [SMBVolume] = []

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        refreshList()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        refreshList()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 标题
        let titleLabel = NSTextField(labelWithString: "SMB 网络共享")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 副标题
        let subtitleLabel = NSTextField(labelWithString: "连接到局域网或 VPN 内的 SMB/NAS 共享")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 状态行（进度指示器 + 状态标签 + 刷新按钮）
        let statusRow = NSView()
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshButton = NSButton()
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.isBordered = false
        refreshButton.toolTip = "刷新列表"
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        statusRow.addSubview(progressIndicator)
        statusRow.addSubview(statusLabel)
        statusRow.addSubview(refreshButton)

        NSLayoutConstraint.activate([
            progressIndicator.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 14),
            progressIndicator.heightAnchor.constraint(equalToConstant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor),
            refreshButton.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 20),
            refreshButton.heightAnchor.constraint(equalToConstant: 20),
            statusRow.heightAnchor.constraint(equalToConstant: 20),
        ])

        // 服务器列表（卡片样式）
        let listLabel = NSTextField(labelWithString: "已连接的服务器")
        listLabel.font = .systemFont(ofSize: 11, weight: .medium)
        listLabel.textColor = .secondaryLabelColor
        listLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        serverStack = NSStackView()
        serverStack.orientation = .vertical
        serverStack.spacing = 6
        serverStack.detachesHiddenViews = false
        serverStack.translatesAutoresizingMaskIntoConstraints = false
        serverStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scrollView.documentView = serverStack

        // 添加服务器按钮
        addButton = NSButton(title: "+ 添加服务器...", target: self, action: #selector(addServerClicked))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .regular
        addButton.translatesAutoresizingMaskIntoConstraints = false

        // 组装
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(statusRow)
        addSubview(listLabel)
        addSubview(scrollView)
        addSubview(addButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            statusRow.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            statusRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            statusRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            listLabel.topAnchor.constraint(equalTo: statusRow.bottomAnchor, constant: 12),
            listLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: listLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),

            addButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            addButton.heightAnchor.constraint(equalToConstant: 28),

            serverStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            serverStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            serverStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            serverStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    // MARK: - 列表渲染

    private func rebuildServerList() {
        serverStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if volumes.isEmpty {
            let empty = makeEmptyState()
            serverStack.addArrangedSubview(empty)
            NSLayoutConstraint.activate([
                empty.leadingAnchor.constraint(equalTo: serverStack.leadingAnchor),
                empty.trailingAnchor.constraint(equalTo: serverStack.trailingAnchor),
            ])
            return
        }

        for volume in volumes {
            let card = makeServerCard(volume: volume)
            serverStack.addArrangedSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: serverStack.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: serverStack.trailingAnchor),
            ])
        }
    }

    /// 空状态视图
    private func makeEmptyState() -> NSView {
        let container = SquircleMaskedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3).cgColor
        container.squircleRadius = 8

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: nil)
        icon.contentTintColor = .tertiaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "暂无已连接的服务器")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "点击下方「添加服务器」按钮连接到 SMB 共享")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            hint.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            hint.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            container.heightAnchor.constraint(equalToConstant: 110),
        ])
        return container
    }

    /// 创建服务器卡片（FFGlassView .component 背景）
    private func makeServerCard(volume: SMBVolume) -> NSView {
        let card = FFGlassView(level: .component, cornerRadius: 6)
        card.translatesAutoresizingMaskIntoConstraints = false

        // 状态圆点（8x8，绿=已连接）
        let statusDot = NSView()
        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        // 服务器图标
        let serverIcon = NSImageView()
        serverIcon.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: volume.name)
        serverIcon.contentTintColor = .secondaryLabelColor
        serverIcon.imageScaling = .scaleProportionallyDown
        serverIcon.translatesAutoresizingMaskIntoConstraints = false

        // 名称 + IP（双行）
        let nameLabel = NSTextField(labelWithString: volume.name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let ipLabel = NSTextField(labelWithString: volume.url)
        ipLabel.font = .systemFont(ofSize: 10)
        ipLabel.textColor = .tertiaryLabelColor
        ipLabel.lineBreakMode = .byTruncatingTail
        ipLabel.cell?.truncatesLastVisibleLine = true
        ipLabel.translatesAutoresizingMaskIntoConstraints = false

        // 状态药丸（"已连接"）
        let statusPill = NSTextField(labelWithString: "已连接")
        statusPill.font = .systemFont(ofSize: 10, weight: .medium)
        statusPill.textColor = NSColor.systemGreen
        statusPill.alignment = .center
        statusPill.wantsLayer = true
        statusPill.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        statusPill.applySquircleCornerRadius(7)
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        statusPill.widthAnchor.constraint(equalToConstant: 48).isActive = true
        statusPill.heightAnchor.constraint(equalToConstant: 14).isActive = true

        // 断开按钮
        let disconnectButton = NSButton(title: "断开", target: self, action: #selector(disconnectClicked(_:)))
        disconnectButton.bezelStyle = .rounded
        disconnectButton.controlSize = .small
        disconnectButton.font = .systemFont(ofSize: 11)
        disconnectButton.contentTintColor = .systemRed
        disconnectButton.translatesAutoresizingMaskIntoConstraints = false
        disconnectButton.toolTip = volume.path

        // 组装卡片
        let infoStack = NSStackView(views: [nameLabel, ipLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 1
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [statusDot, serverIcon, infoStack, NSView(), statusPill, disconnectButton])
        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            mainStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            mainStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),

            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            serverIcon.widthAnchor.constraint(equalToConstant: 18),
            serverIcon.heightAnchor.constraint(equalToConstant: 18),
            card.heightAnchor.constraint(equalToConstant: 52),
        ])
        return card
    }

    // MARK: - Actions

    @objc private func addServerClicked() {
        guard let parentWindow = self.window else { return }
        let dialog = ConnectServerDialog { [weak self] result in
            guard let self = self else { return }
            guard let url = result.smbURL() else {
                self.statusLabel.stringValue = "无效的服务器地址"
                return
            }
            self.connectToServer(url: url, parentWindow: parentWindow)
        }
        dialog.beginSheetModal(for: parentWindow)
    }

    /// 连接到服务器
    private func connectToServer(url: URL, parentWindow: NSWindow) {
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在连接..."
        addButton.isEnabled = false

        SMBBridge.shared.mount(url: url.absoluteString) { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)
                self?.addButton.isEnabled = true

                switch result {
                case .success(let path):
                    self?.statusLabel.stringValue = "已连接：\(path)"
                    self?.refreshList()
                case .failure(let error):
                    self?.statusLabel.stringValue = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func refreshClicked() {
        refreshList()
    }

    @objc private func disconnectClicked(_ sender: NSButton) {
        let mountPoint = sender.toolTip ?? ""
        guard !mountPoint.isEmpty else { return }

        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在断开..."
        sender.isEnabled = false

        SMBBridge.shared.unmount(mountPoint: mountPoint) { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)
                switch result {
                case .success:
                    self?.statusLabel.stringValue = "已断开"
                    self?.refreshList()
                case .failure(let error):
                    self?.statusLabel.stringValue = "断开失败：\(error.localizedDescription)"
                    sender.isEnabled = true
                }
            }
        }
    }

    // MARK: - 列表刷新

    private func refreshList() {
        SMBBridge.shared.refreshMountedVolumes()
        volumes = SMBBridge.shared.listMounted()
        rebuildServerList()
        if statusLabel.stringValue == "就绪" || statusLabel.stringValue.contains("已断开") || statusLabel.stringValue.contains("已连接") {
            statusLabel.stringValue = "共 \(volumes.count) 个已连接服务器"
        }
    }
}
