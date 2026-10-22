import XCTest
@testable import FlowFinder

final class FFPerformancePolicyTests: XCTestCase {

    private func file(_ name: String) -> FileEntry {
        FileEntry(path: "/tmp/\(name)", name: name, isDirectory: false, size: 1)
    }

    func testTagCountsOnlyRefreshOnPathOrFilesChange() {
        var a = PaneState(path: "/tmp")
        a.files = [file("a")]
        var b = a
        b.selectedFiles = a.files
        b.isLoading = true
        XCTAssertFalse(FFPerformancePolicy.shouldRefreshTagCounts(previous: a, current: b))

        b.files.append(file("b"))
        XCTAssertTrue(FFPerformancePolicy.shouldRefreshTagCounts(previous: a, current: b))

        var c = a
        c.path = "/tmp/other"
        XCTAssertTrue(FFPerformancePolicy.shouldRefreshTagCounts(previous: a, current: c))
    }

    func testTaskPublishOnlyOnChange() {
        let base = Date(timeIntervalSince1970: 1_000)
        let a = [TaskInfo(id: "1", name: "Copy", description: "", priority: .normal,
                          status: .running, progress: 0.5, createdAt: base)]
        XCTAssertFalse(FFPerformancePolicy.shouldPublishTasks(previous: a, next: a))

        let b = [TaskInfo(id: "1", name: "Copy", description: "", priority: .normal,
                          status: .running, progress: 0.6, createdAt: base)]
        XCTAssertTrue(FFPerformancePolicy.shouldPublishTasks(previous: a, next: b))

        XCTAssertTrue(FFPerformancePolicy.shouldPublishTasks(previous: a, next: []))
    }
}
