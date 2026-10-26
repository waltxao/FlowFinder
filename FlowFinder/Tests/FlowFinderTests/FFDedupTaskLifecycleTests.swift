import AppKit
import XCTest
@testable import FlowFinder

/// R4-02（docs/AUDIT-2026-10-23-UIUX-R4.md）：任务面板里「重复文件扫描」停在
/// 进行中 + 100%，点「刷新」也不变。
///
/// 真实时序：SearchBridge 的 C 回调跳板已经把进度/分组回调切到主线程，控制器又在
/// 里面多套了一层 `DispatchQueue.main.async`。这一跳把进度与分组更新排到了
/// completion 之后——`finishScanTask(.finished)` 先落账，迟到的进度再把任务改回
/// .running；同一竞态也让状态栏读到还没落账的分组数（谎报 0 个）。
final class FFDedupTaskLifecycleTests: XCTestCase {

    private var dirs: [URL] = []

    private func makeDir(name: String, files: Int, duplicate: Bool) throws -> URL {
        let dir = URL(fileURLWithPath: "/tmp/ff_dedup_task_\(name)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirs.append(dir)
        if duplicate {
            let payload = Data(repeating: 0x41, count: 4096)
            try payload.write(to: dir.appendingPathComponent("a1.bin"))
            try payload.write(to: dir.appendingPathComponent("a2.bin"))
        }
        for i in 0..<files {
            try Data([UInt8(i % 251), UInt8((i / 251) % 251)])
                .write(to: dir.appendingPathComponent("f\(i).bin"))
        }
        return dir
    }

    private func spin(_ condition: () -> Bool, timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func scanTasks(excluding ids: Set<String>) -> [FFTask] {
        FFTaskService.shared.tasks.filter { $0.title == "重复文件扫描" && !ids.contains($0.id) }
    }

    private func runScan(_ wc: DuplicateScanWindowController, files: Int, tag: String) throws {
        wc.selectedURL = try makeDir(name: tag, files: files, duplicate: true)
        wc.perform(NSSelectorFromString("startScan"))
    }

    override func tearDown() {
        for dir in dirs { try? FileManager.default.removeItem(at: dir) }
        dirs.removeAll()
        super.tearDown()
    }

    /// 单次扫描：迟到的进度不得把已收尾的任务改回「进行中」。
    func testSingleScanReachesTerminalState() throws {
        let preexisting = Set(FFTaskService.shared.tasks.map(\.id))
        let wc = DuplicateScanWindowController.shared
        wc.showWindow()
        defer { wc.window?.orderOut(nil) }

        try runScan(wc, files: 40, tag: "single")
        spin { !wc.isScanning }
        spin { !self.scanTasks(excluding: preexisting).contains { $0.isActive } }

        let tasks = scanTasks(excluding: preexisting)
        XCTAssertEqual(tasks.count, 1, "一次扫描应产生一条任务")
        let task = try XCTUnwrap(tasks.first)
        XCTAssertFalse(task.isActive, "扫描结束后任务仍是 \(task.statusText)")
    }

    /// 收尾时分组回调必须已经落账，否则状态栏谎报「找到 0 个重复组」。
    func testCompletionReportsGroupsFoundByScan() throws {
        let preexisting = Set(FFTaskService.shared.tasks.map(\.id))
        let wc = DuplicateScanWindowController.shared
        wc.showWindow()
        defer { wc.window?.orderOut(nil) }

        try runScan(wc, files: 20, tag: "status")
        spin { !self.scanTasks(excluding: preexisting).contains { $0.isActive } }

        XCTAssertEqual(wc.groupCountForTesting, 1, "扫描应产出 1 个重复组")
        XCTAssertEqual(wc.statusTextForTesting, "完成，找到 1 个重复组",
                       "收尾文案与实际分组不一致：\(wc.statusTextForTesting)")
    }

    /// 扫描进行中再次请求扫描：不接受，也不留下第二条永远进行中的任务。
    func testScanRequestWhileScanningIsRejected() throws {
        let preexisting = Set(FFTaskService.shared.tasks.map(\.id))
        let wc = DuplicateScanWindowController.shared
        wc.showWindow()
        defer { wc.window?.orderOut(nil) }

        try runScan(wc, files: 200, tag: "busyA")
        XCTAssertTrue(wc.isScanning, "A 扫描应已进入进行中")

        try runScan(wc, files: 20, tag: "busyB")
        XCTAssertEqual(scanTasks(excluding: preexisting).count, 1, "扫描中不应再登记第二条任务")

        spin { !self.scanTasks(excluding: preexisting).contains { $0.isActive } }
        XCTAssertTrue(scanTasks(excluding: preexisting).allSatisfy { !$0.isActive },
                      "二次请求让首条任务停在「进行中」")
    }
}
