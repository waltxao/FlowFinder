import Foundation
import Combine
import os.log

/// 任务调度管理器：单例轮询 CoreBridge.listTasks() 更新进度
public final class TaskSchedulerManager: ObservableObject {

    public static let shared = TaskSchedulerManager()

    @Published public private(set) var activeTask: TaskInfo?
    @Published public private(set) var allTasks: [TaskInfo] = []

    private var pollingTimer: DispatchSourceTimer?
    private let pollingQueue = DispatchQueue(label: "com.flowfinder.taskpolling", qos: .utility)
    private var pollingInterval: TimeInterval = 0.5
    /// 当前定时器实际间隔；无任务时降频到 idleInterval，避免空转。
    private var scheduledInterval: TimeInterval = 0.5
    private let idleInterval: TimeInterval = 2.0

    private init() {}

    // MARK: - Polling

    /// Wave2 P0-4（多窗口）：轮询引用计数。每个 MainWindowController 在 setupUI 启动、
    /// deinit 停止——多窗口并存时关闭其中一个窗口不应终止全局轮询（非引用计数的
    /// 直接 stop 会把其他窗口仍在依赖的轮询一并停掉）。
    private var pollingRefCount = 0

    /// 启动任务轮询（引用计数 +1；首次调用时真正创建定时器）
    /// - Parameter interval: 轮询间隔（默认 0.5 秒）
    public func startPolling(interval: TimeInterval = 0.5) {
        pollingInterval = interval
        pollingRefCount += 1
        guard pollingRefCount == 1, pollingTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        scheduledInterval = pollingInterval
        timer.schedule(deadline: .now(), repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshTasks()
        }
        timer.resume()
        pollingTimer = timer
    }

    /// 停止任务轮询（引用计数 -1；计数归零时才真正取消定时器）
    public func stopPolling() {
        pollingRefCount = max(0, pollingRefCount - 1)
        guard pollingRefCount == 0 else { return }
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    /// 立即刷新任务列表
    public func refreshTasks() {
        let tasks = CoreBridge.shared.listTasks()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // @Published 每次赋值都会触发订阅者重建；只有任务真正变化时才发布。
            if FFPerformancePolicy.shouldPublishTasks(previous: self.allTasks, next: tasks) {
                self.allTasks = tasks
                self.activeTask = tasks.first(where: { $0.isActive })
            }
            self.updatePollingCadence(hasTasks: !tasks.isEmpty)
        }
    }

    /// 有任务时 0.5s 轮询；空闲时降到 2s，保留发现后台新任务的能力。
    private func updatePollingCadence(hasTasks: Bool) {
        let desired = hasTasks ? pollingInterval : idleInterval
        guard abs(desired - scheduledInterval) > 0.01, let timer = pollingTimer else { return }
        scheduledInterval = desired
        timer.schedule(deadline: .now() + desired, repeating: desired)
    }

    // MARK: - Task Operations

    /// 取消指定任务
    /// - Parameter taskId: 任务 ID 字符串
    public func cancelTask(taskId: String) {
        do {
            try CoreBridge.shared.cancelTask(taskId: taskId)
            refreshTasks()
        } catch {
            FFLog.error("TaskSchedulerManager: 取消任务失败: \(error.localizedDescription)", log: FFLog.task)
        }
    }

    /// 清除已完成/失败的任务历史（保留正在执行及取消的任务）
    public func clearCompletedTasks() {
        do {
            try CoreBridge.shared.clearCompletedTasks()
            refreshTasks()
        } catch {
            FFLog.error("TaskSchedulerManager: 清除已完成任务失败: \(error.localizedDescription)", log: FFLog.task)
        }
    }
}
