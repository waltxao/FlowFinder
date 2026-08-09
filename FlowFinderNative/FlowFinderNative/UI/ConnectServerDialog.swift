import Cocoa

// MARK: - ConnectServerProtocol

/// 支持的服务器协议
enum ConnectServerProtocol: Int, CaseIterable {
    case smb = 0
    case ftp = 1
    case sftp = 2
    case webdav = 3

    var title: String {
        switch self {
        case .smb: return "SMB"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .webdav: return "WebDAV"
        }
    }

    var defaultPort: String {
        switch self {
        case .smb: return "445"
        case .ftp: return "21"
        case .sftp: return "22"
        case .webdav: return "443"
        }
    }

    /// 当前是否已支持（仅 SMB 已接入 SMBBridge）
    var isSupported: Bool {
        return self == .smb
    }
}

// MARK: - ConnectServerDialog

/// 连接服务器对话框：协议 segmented + 服务器地址 + 端口+共享名 + 用户名 + 密码 + 记住密码/自动连接 toggle
class ConnectServerDialog: FFModalSheet {

    // UI 引用
    private var protocolSegmented: NSSegmentedControl!
    private var serverField: NSTextField!
    private var portField: NSTextField!
    private var shareField: NSTextField!
    private var userField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var rememberToggle: NSButton!
    private var autoConnectToggle: NSButton!

    /// 连接回调
    private let connectAction: (ConnectServerResult) -> Void

    init(connectAction: @escaping (ConnectServerResult) -> Void) {
        self.connectAction = connectAction

        let bodyView = NSView()
        // 使用闭包持有盒延迟注入 self 依赖（Swift 6 严格模式禁止 super.init 前捕获 self）
        let box = FFClosureBox()
        super.init(title: "连接到服务器",
                   bodyView: bodyView,
                   primaryButton: ("连接", .default),
                   secondaryButton: "取消",
                   primaryAction: { box.closure?() })

        box.closure = { [weak self] in
            guard let self = self else { return }
            let result = ConnectServerResult(
                protocol: ConnectServerProtocol(rawValue: self.protocolSegmented.selectedSegment) ?? .smb,
                server: self.serverField.stringValue,
                port: self.portField.stringValue,
                share: self.shareField.stringValue,
                user: self.userField.stringValue,
                password: self.passwordField.stringValue,
                rememberPassword: self.rememberToggle.state == .on,
                autoConnect: self.autoConnectToggle.state == .on
            )
            self.connectAction(result)
        }

        setupBody(bodyView: bodyView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody(bodyView: NSView) {
        // 协议 segmented
        let protocolLabel = makeFieldLabel("协议")
        protocolSegmented = NSSegmentedControl(labels: ConnectServerProtocol.allCases.map { $0.title },
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(protocolChanged))
        protocolSegmented.selectedSegment = 0
        protocolSegmented.controlSize = .small
        protocolSegmented.translatesAutoresizingMaskIntoConstraints = false

        // 服务器地址
        let serverLabel = makeFieldLabel("服务器地址")
        serverField = NSTextField()
        serverField.placeholderString = "例: 192.168.1.100 或 server.local"
        serverField.translatesAutoresizingMaskIntoConstraints = false

        // 端口 + 共享名（同行）
        let portLabel = makeFieldLabel("端口")
        portField = NSTextField()
        portField.stringValue = "445"
        portField.translatesAutoresizingMaskIntoConstraints = false

        let shareLabel = makeFieldLabel("共享名")
        shareField = NSTextField()
        shareField.placeholderString = "可选"
        shareField.translatesAutoresizingMaskIntoConstraints = false

        let portShareStack = NSStackView(views: [portField, shareField])
        portShareStack.orientation = .horizontal
        portShareStack.spacing = 8
        portShareStack.distribution = .fill
        portShareStack.translatesAutoresizingMaskIntoConstraints = false

        let portShareLabels = NSStackView(views: [portLabel, shareLabel])
        portShareLabels.orientation = .horizontal
        portShareLabels.spacing = 8
        portShareLabels.distribution = .fillEqually
        portShareLabels.translatesAutoresizingMaskIntoConstraints = false

        // 用户名
        let userLabel = makeFieldLabel("用户名")
        userField = NSTextField()
        userField.placeholderString = "可选（匿名访问留空）"
        userField.translatesAutoresizingMaskIntoConstraints = false

        // 密码
        let passwordLabel = makeFieldLabel("密码")
        passwordField = NSSecureTextField()
        passwordField.placeholderString = "可选"
        passwordField.translatesAutoresizingMaskIntoConstraints = false

        // 选项 toggles
        rememberToggle = NSButton(checkboxWithTitle: "记住密码", target: nil, action: nil)
        rememberToggle.font = .systemFont(ofSize: 11)
        rememberToggle.translatesAutoresizingMaskIntoConstraints = false

        autoConnectToggle = NSButton(checkboxWithTitle: "下次自动连接", target: nil, action: nil)
        autoConnectToggle.font = .systemFont(ofSize: 11)
        autoConnectToggle.translatesAutoresizingMaskIntoConstraints = false

        let togglesStack = NSStackView(views: [rememberToggle, autoConnectToggle])
        togglesStack.orientation = .horizontal
        togglesStack.spacing = 16
        togglesStack.translatesAutoresizingMaskIntoConstraints = false

        // 布局
        bodyView.addSubview(protocolLabel)
        bodyView.addSubview(protocolSegmented)
        bodyView.addSubview(serverLabel)
        bodyView.addSubview(serverField)
        bodyView.addSubview(portShareLabels)
        bodyView.addSubview(portShareStack)
        bodyView.addSubview(userLabel)
        bodyView.addSubview(userField)
        bodyView.addSubview(passwordLabel)
        bodyView.addSubview(passwordField)
        bodyView.addSubview(togglesStack)

        let labelHeight: CGFloat = 14
        let fieldHeight: CGFloat = 22
        let spacing: CGFloat = 6

        NSLayoutConstraint.activate([
            // 协议
            protocolLabel.topAnchor.constraint(equalTo: bodyView.topAnchor),
            protocolLabel.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            protocolLabel.heightAnchor.constraint(equalToConstant: labelHeight),

            protocolSegmented.topAnchor.constraint(equalTo: protocolLabel.bottomAnchor, constant: 2),
            protocolSegmented.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            protocolSegmented.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            // 服务器地址
            serverLabel.topAnchor.constraint(equalTo: protocolSegmented.bottomAnchor, constant: spacing),
            serverLabel.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            serverLabel.heightAnchor.constraint(equalToConstant: labelHeight),

            serverField.topAnchor.constraint(equalTo: serverLabel.bottomAnchor, constant: 2),
            serverField.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            serverField.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            serverField.heightAnchor.constraint(equalToConstant: fieldHeight),

            // 端口+共享名
            portShareLabels.topAnchor.constraint(equalTo: serverField.bottomAnchor, constant: spacing),
            portShareLabels.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            portShareLabels.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            portShareLabels.heightAnchor.constraint(equalToConstant: labelHeight),

            portShareStack.topAnchor.constraint(equalTo: portShareLabels.bottomAnchor, constant: 2),
            portShareStack.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            portShareStack.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            portShareStack.heightAnchor.constraint(equalToConstant: fieldHeight),

            // 用户名
            userLabel.topAnchor.constraint(equalTo: portShareStack.bottomAnchor, constant: spacing),
            userLabel.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            userLabel.heightAnchor.constraint(equalToConstant: labelHeight),

            userField.topAnchor.constraint(equalTo: userLabel.bottomAnchor, constant: 2),
            userField.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            userField.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            userField.heightAnchor.constraint(equalToConstant: fieldHeight),

            // 密码
            passwordLabel.topAnchor.constraint(equalTo: userField.bottomAnchor, constant: spacing),
            passwordLabel.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            passwordLabel.heightAnchor.constraint(equalToConstant: labelHeight),

            passwordField.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 2),
            passwordField.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: fieldHeight),

            // 选项
            togglesStack.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: spacing),
            togglesStack.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            togglesStack.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),

            // 端口与共享名宽度比例
            portField.widthAnchor.constraint(equalTo: portShareStack.widthAnchor, multiplier: 0.3),
        ])
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @objc private func protocolChanged() {
        let proto = ConnectServerProtocol(rawValue: protocolSegmented.selectedSegment) ?? .smb
        portField.stringValue = proto.defaultPort
        // 非支持协议禁用连接（F2: 同时禁用「连接」按钮，避免点击后静默无效果）
        if !proto.isSupported {
            // 仅 SMB 已支持，其他协议禁用用户名/密码输入
            userField.isEnabled = false
            passwordField.isEnabled = false
            shareField.isEnabled = false
            setPrimaryButtonEnabled(false)
            // 提示
            userField.placeholderString = "（\(proto.title) 暂不支持）"
        } else {
            userField.isEnabled = true
            passwordField.isEnabled = true
            shareField.isEnabled = true
            setPrimaryButtonEnabled(true)
            userField.placeholderString = "可选（匿名访问留空）"
        }
    }
}

// MARK: - ConnectServerResult

/// 连接服务器对话框结果
struct ConnectServerResult {
    let `protocol`: ConnectServerProtocol
    let server: String
    let port: String
    let share: String
    let user: String
    let password: String
    let rememberPassword: Bool
    let autoConnect: Bool

    /// 生成 SMB URL（仅 SMB 协议有效）
    /// F2: user/password 需 URL 编码（含 @、:、/ 等字符时否则 URL 解析错误）
    func smbURL() -> URL? {
        guard `protocol` == .smb, !server.isEmpty else { return nil }
        var urlString = "smb://"
        if !user.isEmpty {
            let encodedUser = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
            urlString += encodedUser
            if !password.isEmpty {
                let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
                urlString += ":" + encodedPassword
            }
            urlString += "@"
        }
        urlString += server
        if !share.isEmpty {
            let encodedShare = share.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? share
            urlString += "/\(encodedShare)"
        }
        return URL(string: urlString)
    }
}
