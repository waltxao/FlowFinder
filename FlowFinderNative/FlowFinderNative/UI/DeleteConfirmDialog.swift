import Cocoa

// MARK: - DeleteConfirmDialog

/// 删除确认对话框：警告图标 + 主消息 + 副消息 + "不再询问"复选框
/// "不再询问"勾选 → 写入 UserDefaults `delete_confirm_disabled`
class DeleteConfirmDialog: FFModalSheet {

    /// "不再询问"复选框
    private var dontAskAgainCheckbox: NSButton!
    /// 文件数（用于显示消息）
    private let fileCount: Int
    /// 删除执行回调
    private let deleteAction: () -> Void

    /// 初始化
    /// - Parameters:
    ///   - fileCount: 待删除文件数
    ///   - deleteAction: 确认删除回调
    init(fileCount: Int, deleteAction: @escaping () -> Void) {
        self.fileCount = fileCount
        self.deleteAction = deleteAction

        let bodyView = NSView()
        // 先创建 checkbox 引用，供闭包捕获（避免在 super.init 前引用 self）
        let checkbox = NSButton(checkboxWithTitle: "不再询问", target: nil, action: nil)
        self.dontAskAgainCheckbox = checkbox
        // 捕获局部 deleteAction（与 self.deleteAction 同值），避免闭包中引用 self
        let capturedDeleteAction = deleteAction

        super.init(title: "确认删除",
                   bodyView: bodyView,
                   primaryButton: ("移到废纸篓", .destructive),
                   secondaryButton: "取消",
                   primaryAction: {
                       if checkbox.state == .on {
                           UserDefaults.standard.set(true, forKey: "delete_confirm_disabled")
                       }
                       capturedDeleteAction()
                   })

        setupBody(bodyView: bodyView, checkbox: checkbox)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody(bodyView: NSView, checkbox: NSButton) {
        // 警告图标（黄色三角）
        let warningIcon = NSImageView()
        warningIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                    accessibilityDescription: "警告")
        warningIcon.contentTintColor = .systemYellow
        warningIcon.imageScaling = .scaleProportionallyDown
        warningIcon.translatesAutoresizingMaskIntoConstraints = false

        // 主消息
        let mainMessage = NSTextField(labelWithString: "确定要将 \(fileCount) 个项目移到废纸篓吗？")
        mainMessage.font = .systemFont(ofSize: 13, weight: .medium)
        mainMessage.textColor = .labelColor
        mainMessage.lineBreakMode = .byWordWrapping
        mainMessage.maximumNumberOfLines = 0
        mainMessage.translatesAutoresizingMaskIntoConstraints = false

        // 副消息
        let subMessage = NSTextField(labelWithString: "此操作可以通过 Finder 的「放回原处」或应用的撤销功能恢复。")
        subMessage.font = .systemFont(ofSize: 11)
        subMessage.textColor = .secondaryLabelColor
        subMessage.lineBreakMode = .byWordWrapping
        subMessage.maximumNumberOfLines = 0
        subMessage.translatesAutoresizingMaskIntoConstraints = false

        // "不再询问"复选框：使用 init 中创建的同一实例（与闭包捕获的 checkbox 是同一对象）
        checkbox.font = .systemFont(ofSize: 11)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        bodyView.addSubview(warningIcon)
        bodyView.addSubview(mainMessage)
        bodyView.addSubview(subMessage)
        bodyView.addSubview(checkbox)

        NSLayoutConstraint.activate([
            warningIcon.topAnchor.constraint(equalTo: bodyView.topAnchor),
            warningIcon.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            warningIcon.widthAnchor.constraint(equalToConstant: 28),
            warningIcon.heightAnchor.constraint(equalToConstant: 28),

            mainMessage.topAnchor.constraint(equalTo: bodyView.topAnchor, constant: 2),
            mainMessage.leadingAnchor.constraint(equalTo: warningIcon.trailingAnchor, constant: 10),
            mainMessage.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            subMessage.topAnchor.constraint(equalTo: mainMessage.bottomAnchor, constant: 6),
            subMessage.leadingAnchor.constraint(equalTo: mainMessage.leadingAnchor),
            subMessage.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            checkbox.topAnchor.constraint(equalTo: subMessage.bottomAnchor, constant: 12),
            checkbox.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            checkbox.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
        ])
    }
}
