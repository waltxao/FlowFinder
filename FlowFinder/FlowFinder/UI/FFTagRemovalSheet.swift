import AppKit

/// 「从所有文件移除标签」的确认 + 进度窗口。
///
/// 由侧栏删除标签触发。流程分三步，都在同一个 sheet 里完成：
/// 1. 后台收集受影响路径（本地索引 ∪ Spotlight）
/// 2. 弹确认：显示文件数，主按钮「移除」为破坏性样式
/// 3. 点确认后原地切成进度态，可随时取消；已完成的部分不回滚
///
/// 为什么不用 `NSAlert`：确认后要跑可能持续数秒的批量 xattr 写入，
/// 需要进度与取消入口，而 modal alert 无法承载。
final class FFTagRemovalSheet: NSWindow {

    // MARK: - 输入

    private let tagName: String
    private let paths: [String]
    /// 结束后回调：已完成数、失败数、是否被取消
    private let onFinished: (_ removed: Int, _ failed: Int, _ cancelled: Bool) -> Void

    // MARK: - 视图

    private var progressIndicator: NSProgressIndicator!
    private var descriptionLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var primaryButton: NSButton!
    private var cancelButton: NSButton!

    // MARK: - 状态

    private let task = TagRemovalTask()
    private var hasStarted = false
    private weak var hostWindow: NSWindow?

    private let contentWidth: CGFloat = 420
    private let horizontalPadding: CGFloat = 20

    // MARK: - 初始化

    init(tagName: String,
         paths: [String],
         onFinished: @escaping (_ removed: Int, _ failed: Int, _ cancelled: Bool) -> Void) {
        self.tagName = tagName
        self.paths = paths
        self.onFinished = onFinished

        super.init(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 190),
                   styleMask: [.titled, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        self.title = "移除标签"
        self.isOpaque = true
        self.backgroundColor = .windowBackgroundColor
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.isMovableByWindowBackground = true
        setAccessibilityTitle("移除标签")

        buildUI()
    }

    // MARK: - 呈现

    func present(in parent: NSWindow) {
        hostWindow = parent
        parent.beginSheet(self)
    }

    // MARK: - UI

    private func buildUI() {
        // R4-32: 动态色要在外观切换时重新解析，不能构建时钉死在 layer 上。
        let container = FFDynamicBackgroundView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 190))
        container.fillCornerRadius = 12
        contentView = container

        // 标题
        let titleLabel = NSTextField(labelWithString: "移除标签")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // 说明：确认态讲后果，进度态讲正在做什么
        descriptionLabel = NSTextField(wrappingLabelWithString: confirmText)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(descriptionLabel)

        // 进度条（确认态隐藏）
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(max(paths.count, 1))
        progressIndicator.doubleValue = 0
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressIndicator)

        // 进度文字
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        // 按钮
        primaryButton = NSButton(title: "移除", target: self, action: #selector(primaryClicked))
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.contentTintColor = .systemRed
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(primaryButton)

        cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),

            progressIndicator.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 14),
            progressIndicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            progressIndicator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),

            statusLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),

            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            primaryButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    private var confirmText: String {
        if paths.isEmpty {
            return "没有找到带「\(tagName)」标签的文件。继续将只删除侧栏中的这个标签。"
        }
        return "将从 \(paths.count) 个文件中移除「\(tagName)」标签。\n"
            + "文件本身不会被删除，此操作不可撤销。"
    }

    // MARK: - 动作

    @objc private func primaryClicked() {
        guard !hasStarted else { return }
        hasStarted = true

        // 切到进度态
        descriptionLabel.stringValue = "正在从文件中移除「\(tagName)」…"
        progressIndicator.isHidden = false
        statusLabel.isHidden = false
        statusLabel.stringValue = "0 / \(paths.count)"
        primaryButton.isHidden = true
        cancelButton.title = "停止"

        runRemoval()
    }

    @objc private func cancelClicked() {
        if hasStarted {
            // 进度中：只置取消标记，让后台循环在下一个文件处退出
            task.cancel()
            cancelButton.isEnabled = false
            statusLabel.stringValue = "正在停止…"
        } else {
            finish(removed: 0, failed: 0, cancelled: true)
        }
    }

    // MARK: - 后台执行

    private func runRemoval() {
        let name = tagName
        let paths = self.paths
        let task = self.task

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var removed = 0
            var failed = 0
            let fm = FileManager.default
            let batchSize = 10

            for (index, path) in paths.enumerated() {
                if task.isCancelled { break }
                // 路径可能已被删除/改名，跳过不计失败
                if fm.fileExists(atPath: path) {
                    if TagBridge.shared.removeTagByName(name, path: path) {
                        removed += 1
                    } else {
                        failed += 1
                    }
                }
                // 每 10 个回报一次，避免主线程被高频刷新拖慢
                if index % batchSize == 0 || index == paths.count - 1 {
                    let done = index + 1
                    DispatchQueue.main.async {
                        self?.progressIndicator.doubleValue = Double(done)
                        self?.statusLabel.stringValue = "\(done) / \(paths.count)"
                    }
                }
            }

            let cancelled = task.isCancelled
            DispatchQueue.main.async {
                self?.progressIndicator.doubleValue = Double(cancelled ? 0 : paths.count)
                self?.finish(removed: removed, failed: failed, cancelled: cancelled)
            }
        }
    }

    private func finish(removed: Int, failed: Int, cancelled: Bool) {
        let parent = hostWindow
        onFinished(removed, failed, cancelled)
        if let parent {
            parent.endSheet(self)
        } else {
            close()
        }
    }
}

// MARK: - 编排

/// 删除标签的统一入口：查数量 → 弹确认与进度 → 完成后清理侧栏条目。
enum TagRemovalCoordinator {

    /// 请求移除某标签。
    /// - Parameters:
    ///   - tag: 要删除的标签
    ///   - window: 宿主窗口，用于挂 sheet
    ///   - onFinished: 流程结束（含取消）后回调，参数为实际移除的文件数
    static func begin(tag: Tag, in window: NSWindow, onFinished: @escaping (Int) -> Void) {
        TagIndexStore.shared.collectPaths(forTagNamed: tag.name, includeSpotlight: true) { paths in
            DispatchQueue.main.async {
                let sheet = FFTagRemovalSheet(tagName: tag.name, paths: paths.sorted()) { removed, _, cancelled in
                    // 只有在真正执行过（或被部分执行）时才清理侧栏，
                    // 用户在确认页点取消不该丢标签。
                    if !cancelled || removed > 0 {
                        removeFromSidebar(tag: tag)
                    }
                    onFinished(removed)
                }
                sheet.present(in: window)
            }
        }
    }

    /// 从 SidebarTags 存储与侧栏界面移除标签，并广播刷新。
    private static func removeFromSidebar(tag: Tag) {
        TagCatalog.shared.removeDefinition(id: tag.id, name: tag.name)

        // 活动面板若正在按该标签筛选，解除筛选（否则列表空着且无从恢复）
        NotificationCenter.default.post(name: .sidebarTagsDidRemoveTag,
                                        object: nil,
                                        userInfo: ["name": tag.name])
        NotificationCenter.default.post(name: .fileTagsDidChange, object: nil,
                                        userInfo: ["tags": TagCatalog.shared.tags])
    }
}

// MARK: - 通知名
// 通知名常量定义在 TagIndexStore.swift（模型层），
// 供删除/改色流程在不依赖 UI 层的情况下广播。
