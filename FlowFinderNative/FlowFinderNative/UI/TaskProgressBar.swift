import Cocoa
import Combine

/// 底部固定进度条：设计稿 ff-taskbar，28px 高
/// 布局：[任务文字] [4px 细进度条 flex:1] [百分比文字]
///
/// 任务 F11-9（问题1）：复制/移动底部进度栏
/// - 复用此组件，新增"直接进度 API"（不依赖 TaskSchedulerManager 后台轮询），
///   用于跨面板复制/移动、粘贴等同步批量操作的实时进度展示。
/// - 完成后延迟 2 秒淡出，自动收起高度，避免长期占用操作区底部空间。
public class TaskProgressBar: NSView {

    private var progressIndicator: NSProgressIndicator!
    private var taskLabel: NSTextField!
    private var percentLabel: NSTextField!
    /// 玻璃容器（FFGlassView .component 提供亚克力质感）
    private var containerView: FFGlassView!

    private var cancellables = Set<AnyCancellable>()
    private var currentTaskId: String?

    /// 进度条高度
    public static let height: CGFloat = 28

    /// 当前是否处于"直接进度"模式（跨面板复制/移动/粘贴）
    /// 该模式下不响应 TaskSchedulerManager.activeTask 的更新，避免被后台任务覆盖
    private var isDirectProgressMode = false

    /// 完成态淡出定时器（完成后延迟 2 秒收起）
    private var fadeOutTimer: Timer?

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
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // 设计稿 ff-taskbar：28px 高，FFGlassView(.component) 提供亚克力磨砂质感
        containerView = FFGlassView(level: .component, cornerRadius: 0)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // 任务文字（左侧，11pt secondary）
        taskLabel = NSTextField(labelWithString: "就绪")
        taskLabel.font = NSFont.systemFont(ofSize: 11)
        taskLabel.textColor = NSColor.secondaryLabelColor
        taskLabel.lineBreakMode = .byTruncatingTail
        taskLabel.translatesAutoresizingMaskIntoConstraints = false

        // 进度条（中间，flex:1，4px 高细条）
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 百分比文字（右侧，11pt secondary）
        percentLabel = NSTextField(labelWithString: "")
        percentLabel.font = NSFont.systemFont(ofSize: 11)
        percentLabel.textColor = NSColor.secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(taskLabel)
        containerView.addSubview(progressIndicator)
        containerView.addSubview(percentLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 任务文字：左侧 12px 内边距
            taskLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            taskLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            taskLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260),

            // 进度条：flex:1，4px 高
            progressIndicator.leadingAnchor.constraint(equalTo: taskLabel.trailingAnchor, constant: 8),
            progressIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 4),

            // 百分比：右侧 12px 内边距，固定宽度 40px
            percentLabel.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 8),
            percentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            percentLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 40),
        ])

        // 任务 F11-9：默认隐藏（高度由外部约束驱动为 0），仅在复制/移动/粘贴等
        // 同步批量操作期间展开显示。设计稿原"常驻空进度条"在 v0.6.7 实体背景下
        // 会占用操作区底部空间，改为按需显示更贴合访达行为。
        isHidden = true
    }

    // MARK: - Bindings

    private func setupBindings() {
        // 仅当未处于"直接进度"模式时响应后台任务（TaskSchedulerManager 轮询的任务）
        TaskSchedulerManager.shared.$activeTask
            .receive(on: DispatchQueue.main)
            .sink { [weak self] task in
                guard let self = self else { return }
                // 直接进度模式下忽略后台任务更新，避免覆盖正在进行的复制/移动进度
                guard !self.isDirectProgressMode else { return }
                if let task = task {
                    self.show(task: task)
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API（后台任务模式，保留兼容）

    /// 显示任务进度（后台任务模式）
    /// - Parameter task: 任务信息
    public func show(task: TaskInfo) {
        cancelFadeOut()
        isDirectProgressMode = false
        isHidden = false
        taskLabel.stringValue = "\(task.name) - \(task.statusDescription)"
        progressIndicator.doubleValue = task.progress * 100
        percentLabel.stringValue = "\(Int(task.progress * 100))%"
        currentTaskId = task.id
    }

    /// 隐藏进度条（设计稿：不隐藏，重置为"就绪"状态）
    public func hide() {
        cancelFadeOut()
        isDirectProgressMode = false
        progressIndicator.doubleValue = 0
        taskLabel.stringValue = "就绪"
        percentLabel.stringValue = ""
        currentTaskId = nil
        isHidden = true
    }

    // MARK: - Public API（直接进度模式 - 任务 F11-9）

    /// 开始一次同步批量操作进度展示（跨面板复制/移动、粘贴等）
    /// - Parameters:
    ///   - operation: 操作名称（如"复制"、"移动"）
    ///   - totalCount: 待处理文件总数
    public func startDirectProgress(operation: String, totalCount: Int) {
        cancelFadeOut()
        isDirectProgressMode = true
        isHidden = false
        progressIndicator.doubleValue = 0
        percentLabel.stringValue = "0%"
        taskLabel.stringValue = "\(operation) \(totalCount) 个项目…"
        currentTaskId = nil
    }

    /// 更新直接进度（在批量操作每完成一项时调用，主线程）
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - currentFileName: 正在处理的文件名（用于展示，可为 nil）
    ///   - completed: 已完成数量
    ///   - total: 总数量
    public func updateDirectProgress(operation: String,
                                     currentFileName: String?,
                                     completed: Int,
                                     total: Int) {
        guard isDirectProgressMode else { return }
        let ratio = total > 0 ? Double(completed) / Double(total) : 0
        progressIndicator.doubleValue = ratio * 100
        percentLabel.stringValue = "\(Int(ratio * 100))%"
        if let name = currentFileName {
            // 截断过长文件名，避免进度条被挤出
            let displayName = name.count > 40 ? String(name.prefix(37)) + "…" : name
            taskLabel.stringValue = "\(operation) \(completed)/\(total)：\(displayName)"
        } else {
            taskLabel.stringValue = "\(operation) \(completed)/\(total)…"
        }
    }

    /// 标记直接进度完成，显示"已完成"状态并延迟 2 秒淡出收起
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - count: 成功处理的项目数
    public func completeDirectProgress(operation: String, count: Int) {
        guard isDirectProgressMode else { return }
        progressIndicator.doubleValue = 100
        percentLabel.stringValue = "100%"
        taskLabel.stringValue = "\(operation)完成：\(count) 个项目"
        // 延迟 2 秒后淡出收起
        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hide()
            }
        }
    }

    /// 取消挂起的淡出定时器
    private func cancelFadeOut() {
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
    }

    // MARK: - Actions
}
