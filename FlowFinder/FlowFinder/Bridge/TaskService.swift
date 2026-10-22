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
