import Cocoa

// MARK: - ProgressDialog

/// 文件操作进度对话框：当前文件名 + 源/目标路径 + 进度条 + 文件计数 + 字节计数 + ETA
/// 绑定 TaskSchedulerManager.shared.$activeTask 的进度数据
/// "后台运行"关闭模态但保持 TaskProgressBar 可见
class ProgressDialog: FFModalSheet {

    // UI 引用
    private var fileNameLabel: NSTextField!
    private var sourceLabel: NSTextField!
    private var destLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var fileCountLabel: NSTextField!
    private var byteCountLabel: NSTextField!
    private var etaLabel: NSTextField!

    /// 完成回调（用于清理）
    private var onComplete: (() -> Void)?

    /// 任务起始时间戳（用于基于实际耗时计算 ETA）
    private var startTime: Date?

    /// 当前对话框绑定的后台任务 ID（用于「取消」按钮真正中止任务）。
    /// 由调用方在展示对话框前通过 `setTaskId(_:)` 注入，或在 init 时传入。
    private var taskId: String?

    /// 初始化
    /// - Parameters:
    ///   - title: 标题（例: "正在复制文件"）
    ///   - taskId: 关联的后台任务 ID；若非空，「取消」按钮会调用 `TaskSchedulerManager.shared.cancelTask(taskId:)` 真正中止任务
    ///   - onComplete: 操作完成回调
    init(title: String = "正在处理文件",
         taskId: String? = nil,
         onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.taskId = taskId

        let bodyView = NSView()
        // 使用闭包持有盒延迟注入 self 依赖（Swift 6 严格模式禁止 super.init 前捕获 self）
        let box = FFClosureBox()
        // ProgressDialog 用独立窗口，不需要 secondary button
        super.init(title: title,
                   bodyView: bodyView,
                   primaryButton: ("后台运行", .default),
                   secondaryButton: "取消",
                   primaryAction: { box.closure?() })

        box.closure = { [weak self] in
            // 后台运行：关闭模态窗口，TaskProgressBar 保持可见
            self?.close()
        }

        // 接线「取消」按钮：在 FFModalSheet 关闭窗口前，先真正取消后台任务。
        // 之前「取消」仅 close()，后台文件操作继续执行（P0#8）。
        secondaryAction = { [weak self] in
            guard let self = self, let taskId = self.taskId else { return }
            TaskSchedulerManager.shared.cancelTask(taskId: taskId)
        }

        setupBody(bodyView: bodyView)
        observeTaskProgress()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 注入或更新任务 ID。
    ///
    /// 适用于调用方先展示对话框、再拿到任务 ID 的场景；若新 ID 与当前不同，则更新引用。
    /// - Parameter taskId: 后台任务 ID（与 `TaskInfo.id` 一致，为 String）
    func setTaskId(_ taskId: String) {
        self.taskId = taskId
    }

    private func setupBody(bodyView: NSView) {
        // 当前文件名
        fileNameLabel = NSTextField(labelWithString: "准备中...")
        fileNameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fileNameLabel.textColor = .labelColor
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.cell?.truncatesLastVisibleLine = true
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false

        // 源路径
        let sourceTitle = NSTextField(labelWithString: "源")
        sourceTitle.font = .systemFont(ofSize: 10)
        sourceTitle.textColor = .tertiaryLabelColor
        sourceTitle.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel = NSTextField(labelWithString: "—")
        sourceLabel.font = .systemFont(ofSize: 10)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.cell?.truncatesLastVisibleLine = true
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false

        // 目标路径
        let destTitle = NSTextField(labelWithString: "目标")
        destTitle.font = .systemFont(ofSize: 10)
        destTitle.textColor = .tertiaryLabelColor
        destTitle.translatesAutoresizingMaskIntoConstraints = false
        destLabel = NSTextField(labelWithString: "—")
        destLabel.font = .systemFont(ofSize: 10)
        destLabel.textColor = .secondaryLabelColor
        destLabel.lineBreakMode = .byTruncatingMiddle
        destLabel.cell?.truncatesLastVisibleLine = true
        destLabel.translatesAutoresizingMaskIntoConstraints = false

        // 进度条
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 计数行（文件数 + 字节数 + ETA）
        fileCountLabel = NSTextField(labelWithString: "0 / 0")
        fileCountLabel.font = .systemFont(ofSize: 10)
        fileCountLabel.textColor = .secondaryLabelColor
        fileCountLabel.translatesAutoresizingMaskIntoConstraints = false

        byteCountLabel = NSTextField(labelWithString: "0 KB / 0 KB")
        byteCountLabel.font = .systemFont(ofSize: 10)
        byteCountLabel.textColor = .secondaryLabelColor
        byteCountLabel.translatesAutoresizingMaskIntoConstraints = false

        etaLabel = NSTextField(labelWithString: "剩余 —")
        etaLabel.font = .systemFont(ofSize: 10)
        etaLabel.textColor = .secondaryLabelColor
        etaLabel.alignment = .right
        etaLabel.translatesAutoresizingMaskIntoConstraints = false

        let countsStack = NSStackView(views: [fileCountLabel, NSView(), byteCountLabel])
        countsStack.orientation = .horizontal
        countsStack.spacing = 8
        countsStack.translatesAutoresizingMaskIntoConstraints = false

        let etaStack = NSStackView(views: [NSView(), etaLabel])
        etaStack.orientation = .horizontal
        etaStack.spacing = 8
        etaStack.translatesAutoresizingMaskIntoConstraints = false

        bodyView.addSubview(fileNameLabel)
        bodyView.addSubview(sourceTitle)
        bodyView.addSubview(sourceLabel)
        bodyView.addSubview(destTitle)
        bodyView.addSubview(destLabel)
        bodyView.addSubview(progressIndicator)
        bodyView.addSubview(countsStack)
        bodyView.addSubview(etaStack)

        NSLayoutConstraint.activate([
            fileNameLabel.topAnchor.constraint(equalTo: bodyView.topAnchor),
            fileNameLabel.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            fileNameLabel.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            sourceTitle.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 8),
            sourceTitle.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            sourceTitle.widthAnchor.constraint(equalToConstant: 32),
            sourceLabel.centerYAnchor.constraint(equalTo: sourceTitle.centerYAnchor),
            sourceLabel.leadingAnchor.constraint(equalTo: sourceTitle.trailingAnchor, constant: 6),
            sourceLabel.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            destTitle.topAnchor.constraint(equalTo: sourceTitle.bottomAnchor, constant: 2),
            destTitle.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            destTitle.widthAnchor.constraint(equalToConstant: 32),
            destLabel.centerYAnchor.constraint(equalTo: destTitle.centerYAnchor),
            destLabel.leadingAnchor.constraint(equalTo: destTitle.trailingAnchor, constant: 6),
            destLabel.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            progressIndicator.topAnchor.constraint(equalTo: destTitle.bottomAnchor, constant: 12),
            progressIndicator.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 12),

            countsStack.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 6),
            countsStack.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            countsStack.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),

            etaStack.topAnchor.constraint(equalTo: countsStack.bottomAnchor, constant: 2),
            etaStack.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            etaStack.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            etaStack.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
        ])
    }

    // MARK: - 进度观察

    private func observeTaskProgress() {
        // 监听 TaskSchedulerManager.shared.activeTask 变更
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(taskProgressUpdated),
                                               name: .taskProgressUpdated,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(taskCompleted),
                                               name: .taskCompleted,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func taskProgressUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let progress = userInfo["progress"] as? Double,
              let currentFile = userInfo["currentFile"] as? String,
              let sourcePath = userInfo["sourcePath"] as? String,
              let destPath = userInfo["destPath"] as? String,
              let processedFiles = userInfo["processedFiles"] as? Int,
              let totalFiles = userInfo["totalFiles"] as? Int,
              let processedBytes = userInfo["processedBytes"] as? Int64,
              let totalBytes = userInfo["totalBytes"] as? Int64 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fileNameLabel.stringValue = currentFile
            self.sourceLabel.stringValue = sourcePath
            self.destLabel.stringValue = destPath
            self.progressIndicator.doubleValue = progress
            self.fileCountLabel.stringValue = "\(processedFiles) / \(totalFiles)"

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            self.byteCountLabel.stringValue = "\(formatter.string(fromByteCount: processedBytes)) / \(formatter.string(fromByteCount: totalBytes))"

            // ETA 计算：基于实际耗时（已耗时 / 进度 * 剩余进度）
            if progress > 0 {
                if self.startTime == nil {
                    self.startTime = Date()
                }
                if let start = self.startTime {
                    let elapsed = Date().timeIntervalSince(start)
                    // progress 范围 0-100，总预估 = 已耗时 / (progress/100)
                    let totalEstimated = elapsed / (progress / 100.0)
                    let remaining = max(0, totalEstimated - elapsed)
                    self.etaLabel.stringValue = "剩余 \(self.formatDuration(remaining))"
                }
            }
        }
    }

    /// 格式化剩余时间
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "< 1 秒"
        } else if seconds < 60 {
            return String(format: "%.0f 秒", seconds)
        } else if seconds < 3600 {
            let m = Int(seconds / 60)
            let s = Int(seconds) % 60
            return "\(m) 分 \(s) 秒"
        } else {
            let h = Int(seconds / 3600)
            let m = (Int(seconds) % 3600) / 60
            return "\(h) 小时 \(m) 分"
        }
    }

    @objc private func taskCompleted(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.progressIndicator.doubleValue = 100
            self?.etaLabel.stringValue = "已完成"
            // 延迟关闭，让用户看到完成状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.close()
                self?.onComplete?()
            }
        }
    }

}
