import Foundation
import Combine

struct FFTask: Identifiable, Equatable {
    let id: String
    var title: String
    var detail: String
    var completedBytes: Int64
    var totalBytes: Int64
    var state: FFTaskState
    let startedAt: Date
    /// 任务作用的对象（R4-24）：任务中心据此提供「定位」。nil = 这条任务没有可跳转的东西。
    var locationPath: String? = nil

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }

    var isActive: Bool {
        switch state {
        case .queued, .running, .paused: return true
        case .finished, .failed, .cancelled: return false
        }
    }

    var statusText: String {
        switch state {
        case .queued: return "等待中"
        case .running: return "进行中"
        case .paused: return "已暂停"
        case .finished: return "已完成"
        case .failed(let reason): return "失败：\(reason)"
        case .cancelled: return "已取消"
        }
    }
}

enum FFTaskState: Equatable {
    case queued
    case running
    case paused
    case finished
    case failed(String)
    case cancelled
}

/// 应用任务真值：复制/移动/查重等操作写入进度，任务中心只读订阅。
/// 服务本身不执行文件操作；取消/重试由任务拥有者注入闭包。
final class FFTaskService: ObservableObject {

    static let shared = FFTaskService()

    @Published private(set) var tasks: [FFTask] = []

    private var cancelHandlers: [String: () -> Void] = [:]
    private var retryHandlers: [String: () -> Void] = [:]

    init() {}

    func upsert(_ task: FFTask) {
        let signpost = FFPerf.begin("Task.publish")
        defer { FFPerf.end("Task.publish", signpost) }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            // 终态是事实的终点：迟到的进度不能把已结束的任务改回「进行中」（R4-02）。
            // 重新激活只走 retry()。
            guard tasks[index].isActive || !task.isActive else { return }
            guard tasks[index] != task else { return }
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    func setCancelHandler(for id: String, handler: @escaping () -> Void) {
        cancelHandlers[id] = handler
    }

    func setRetryHandler(for id: String, handler: @escaping () -> Void) {
        retryHandlers[id] = handler
    }

    func canCancel(_ id: String) -> Bool {
        cancelHandlers[id] != nil && tasks.first(where: { $0.id == id })?.isActive == true
    }

    func canRetry(_ id: String) -> Bool {
        retryHandlers[id] != nil && tasks.first(where: { $0.id == id })?.isActive == false
    }

    func cancel(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        cancelHandlers[id]?()
        tasks[index].state = .cancelled
        cancelHandlers.removeValue(forKey: id)
    }

    func retry(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = .queued
        tasks[index].completedBytes = 0
        retryHandlers[id]?()
    }

    func removeFinished() {
        let removed = tasks.filter { !$0.isActive }.map(\.id)
        tasks.removeAll { !$0.isActive }
        for id in removed {
            cancelHandlers.removeValue(forKey: id)
            retryHandlers.removeValue(forKey: id)
        }
    }
}

// MARK: - 任务存在与聚合进度（底栏任务按钮）

/// 底栏任务按钮需要的只读快照：
/// - `hasTasks`：有任何任务记录（含已完成/失败/取消，直到清除）
/// - `progress`：活动任务（排队/进行中/暂停）的平均进度；无活动但有记录 = 1
struct FFTaskSummary: Equatable {
    let hasTasks: Bool
    let activeCount: Int
    let progress: Double

    static let empty = FFTaskSummary(hasTasks: false, activeCount: 0, progress: 0)
}

enum FFTaskPresence {

    /// 合并 App 任务（复制/整理等）与 Rust 系统任务。
    static func summary(appTasks: [FFTask] = FFTaskService.shared.tasks,
                        systemTasks: [TaskInfo] = TaskSchedulerManager.shared.allTasks) -> FFTaskSummary {
        let total = appTasks.count + systemTasks.count
        guard total > 0 else { return .empty }

        let activeApp = appTasks.filter(\.isActive)
        let activeSystem = systemTasks.filter { $0.isActive }
        let activeCount = activeApp.count + activeSystem.count

        // 没有活动任务时注满：历史记录只用于保持入口存在，不再计算平均。
        guard activeCount > 0 else {
            return FFTaskSummary(hasTasks: true, activeCount: 0, progress: 1)
        }

        let values = activeApp.map { $0.progress } + activeSystem.map { $0.progress }
        let average = values.reduce(0, +) / Double(values.count)
        return FFTaskSummary(hasTasks: true,
                             activeCount: activeCount,
                             progress: min(1, max(0, average)))
    }
}
