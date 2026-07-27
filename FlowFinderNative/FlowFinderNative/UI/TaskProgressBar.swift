import Cocoa
import Combine

/// 底部固定进度条：设计稿 ff-taskbar，28px 高
/// 布局：[任务文字] [4px 细进度条 flex:1] [百分比文字]
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
            taskLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220),

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

        // 设计稿：TaskBar 常驻显示（即使无任务也显示空进度条）
        isHidden = false
    }

    // MARK: - Bindings

    private func setupBindings() {
        TaskSchedulerManager.shared.$activeTask
            .receive(on: DispatchQueue.main)
            .sink { [weak self] task in
                if let task = task {
                    self?.show(task: task)
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// 显示任务进度
    /// - Parameter task: 任务信息
    public func show(task: TaskInfo) {
        isHidden = false
        taskLabel.stringValue = "\(task.name) - \(task.statusDescription)"
        progressIndicator.doubleValue = task.progress * 100
        percentLabel.stringValue = "\(Int(task.progress * 100))%"
        currentTaskId = task.id
    }

    /// 隐藏进度条（设计稿：不隐藏，重置为"就绪"状态）
    public func hide() {
        progressIndicator.doubleValue = 0
        taskLabel.stringValue = "就绪"
        percentLabel.stringValue = ""
        currentTaskId = nil
    }

    // MARK: - Actions
}
