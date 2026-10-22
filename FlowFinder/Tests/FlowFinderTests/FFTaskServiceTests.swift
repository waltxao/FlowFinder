import XCTest
@testable import FlowFinder

final class FFTaskServiceTests: XCTestCase {

    private func task(id: String = "1",
                      completed: Int64 = 0,
                      total: Int64 = 100,
                      state: FFTaskState = .running) -> FFTask {
        FFTask(id: id, title: "Copy", detail: "a.txt",
               completedBytes: completed, totalBytes: total,
               state: state, startedAt: Date())
    }

    func testProgressPublishesAndCompletes() {
        let service = FFTaskService()
        var item = task()
        service.upsert(item)
        XCTAssertEqual(service.tasks.count, 1)

        item.completedBytes = 100
        item.state = .finished
        service.upsert(item)
        XCTAssertEqual(service.tasks.count, 1)
        XCTAssertEqual(service.tasks.first?.state, .finished)
        XCTAssertEqual(service.tasks.first?.progress, 1)
    }

    func testCancelMarksStateAndInvokesHandler() {
        let service = FFTaskService()
        service.upsert(task())
        var cancelled = false
        service.setCancelHandler(for: "1") { cancelled = true }

        service.cancel("1")

        XCTAssertEqual(service.tasks.first?.state, .cancelled)
        XCTAssertTrue(cancelled)
    }

    func testRetryResetsProgressAndInvokesHandler() {
        let service = FFTaskService()
        service.upsert(task(completed: 100, state: .failed("disk full")))
        var retried = false
        service.setRetryHandler(for: "1") { retried = true }

        service.retry("1")

        XCTAssertEqual(service.tasks.first?.state, .queued)
        XCTAssertEqual(service.tasks.first?.completedBytes, 0)
        XCTAssertTrue(retried)
    }

    func testRemoveFinishedKeepsActiveTasks() {
        let service = FFTaskService()
        service.upsert(task(id: "done", state: .finished))
        service.upsert(task(id: "run", state: .running))
        service.removeFinished()
        XCTAssertEqual(service.tasks.map(\.id), ["run"])
    }
}
