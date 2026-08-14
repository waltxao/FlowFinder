import Cocoa

// MARK: - DeleteConfirmDialog

/// 删除确认对话框：警告图标 + 主消息 + 副消息 + "不再询问"复选框
/// "不再询问"勾选 → 写入 UserDefaults `delete_confirm_disabled`
class DeleteConfirmDialog: FFModalSheet {

    /// "不再询问"复选框
    private var dontAskAgainCheckbox: NSButton!
    /// 文件数（用于显示消息）
    private let fileCount: Int

    /// 初始化
    /// - Parameters:
    ///   - fileCount: 待删除文件数
    ///   - message: 主消息（nil 时使用默认"确定要将 N 个项目移到废纸篓吗？"）
    ///   - confirmButtonTitle: 确认按钮标题（默认"移到废纸篓"；永久删除场景传"永久删除"）
    ///   - deleteAction: 确认删除回调
    init(fileCount: Int,
         message: String? = nil,
         confirmButtonTitle: String = "移到废纸篓",
         deleteAction: @escaping () -> Void) {
        self.fileCount = fileCount

        let bodyView = NSView()
        // 先创建 checkbox 引用，供闭包捕获（避免在 super.init 前引用 self）
        let checkbox = NSButton(checkboxWithTitle: "不再询问", target: nil, action: nil)
        self.dontAskAgainCheckbox = checkbox
        // 捕获局部 deleteAction，避免闭包中引用 self
        let capturedDeleteAction = deleteAction

        super.init(title: "确认删除",
                   bodyView: bodyView,
                   primaryButton: (confirmButtonTitle, .destructive),
                   secondaryButton: "取消",
                   primaryAction: {
                       if checkbox.state == .on {
                           UserDefaults.standard.set(true, forKey: FFUserDefaultsKeys.deleteConfirmDisabled)
                       }
                       capturedDeleteAction()
                   })

        setupBody(bodyView: bodyView, checkbox: checkbox, message: message)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody(bodyView: NSView, checkbox: NSButton, message: String?) {
        // 警告图标（黄色三角）
        let warningIcon = NSImageView()
        warningIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                    accessibilityDescription: "警告")
        warningIcon.contentTintColor = .systemYellow
        warningIcon.imageScaling = .scaleProportionallyDown
        warningIcon.translatesAutoresizingMaskIntoConstraints = false

        // 主消息
        let mainMessage = NSTextField(labelWithString: message ?? "确定要将 \(fileCount) 个项目移到废纸篓吗？")
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

// MARK: - 统一删除确认入口（任务 T12）

extension DeleteConfirmDialog {

    /// 是否需要弹确认框（纯决策函数，供测试与统一入口共用）。
    /// - 0 个条目：无需确认（直接执行空操作）
    /// - 用户已勾选"不再询问"：跳过
    /// - 无宿主窗口：跳过（无法展示 sheet，直接执行，与既有回退行为一致）
    static func shouldConfirm(fileCount: Int, confirmDisabled: Bool, windowAvailable: Bool) -> Bool {
        guard fileCount > 0 else { return false }
        if confirmDisabled { return false }
        if !windowAvailable { return false }
        return true
    }

    /// 全应用唯一的破坏性删除确认入口。
    /// 所有调用方（主菜单 / 右键菜单 / 键盘 Del / 重复扫描批量删除）统一经此入口，
    /// "不再询问"语义与 UserDefaults key 全入口一致。
    /// - Parameters:
    ///   - fileCount: 待删除条目数（0 时直接执行）
    ///   - window: 宿主窗口（nil 时直接执行 action，与既有无窗口回退行为一致）
    ///   - message: 主消息覆盖（重复扫描永久删除等业务差异）
    ///   - confirmButtonTitle: 确认按钮标题覆盖
    ///   - action: 确认后执行的实际删除动作
    static func confirmDelete(fileCount: Int,
                              window: NSWindow?,
                              message: String? = nil,
                              confirmButtonTitle: String = "移到废纸篓",
                              action: @escaping () -> Void) {
        let disabled = UserDefaults.standard.bool(forKey: FFUserDefaultsKeys.deleteConfirmDisabled)
        guard shouldConfirm(fileCount: fileCount, confirmDisabled: disabled, windowAvailable: window != nil) else {
            action()
            return
        }
        let dialog = DeleteConfirmDialog(fileCount: fileCount,
                                         message: message,
                                         confirmButtonTitle: confirmButtonTitle,
                                         deleteAction: action)
        dialog.beginSheetModal(for: window!)
    }
}
