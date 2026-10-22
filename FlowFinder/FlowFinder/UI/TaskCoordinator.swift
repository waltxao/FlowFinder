import Foundation

/// 任务协调器：窗口只通过这里启停轮询，并读取统一任务服务。
final class TaskCoordinator {

    let service: FFTaskService
    let scheduler: TaskSchedulerManager
    private var pollingStarted = false

    init(service: FFTaskService = .shared,
         scheduler: TaskSchedulerManager = .shared) {
        self.service = service
        self.scheduler = scheduler
    }

    func start() {
        guard !pollingStarted else { return }
        pollingStarted = true
        scheduler.startPolling()
    }

    func stop() {
        guard pollingStarted else { return }
        pollingStarted = false
        scheduler.stopPolling()
    }

    var activeTaskCount: Int {
        service.tasks.filter(\.isActive).count + scheduler.allTasks.filter { $0.isActive }.count
    }
}
