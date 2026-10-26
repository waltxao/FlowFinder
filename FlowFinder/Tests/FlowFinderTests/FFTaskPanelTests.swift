import AppKit
import XCTest
@testable import FlowFinder

/// R4-22 / R4-23 / R4-01 残留：任务面板的空行条纹、始终可点的「取消任务」
/// 与英文 AM/PM 时间列（docs/AUDIT-2026-10-23-UIUX-R4.md）。
final class FFTaskPanelTests: XCTestCase {

    private var panel: TaskPanelWindowController { TaskPanelWindowController.shared }
    private var ids: [String] = []

    private func spin(_ condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    @discardableResult
    private func addTask(title: String,
                         state: FFTaskState,
                         cancellable: Bool = false,
                         location: String? = nil) -> String {
        let id = "panel-\(UUID().uuidString)"
        ids.append(id)
        let task = FFTask(id: id, title: title, detail: "d", completedBytes: 1,
                          totalBytes: 10, state: state, startedAt: Date(),
                          locationPath: location)
        FFTaskService.shared.upsert(task)
        if cancellable {
            FFTaskService.shared.setCancelHandler(for: id) {}
        }
        spin { self.panel.rowTaskIDs.contains(id) }
        return id
    }

    private func selectRow(_ id: String) {
        guard let index = panel.rowTaskIDs.firstIndex(of: id),
              let table = panel.tableViewForTesting else {
            XCTFail("任务 \(id) 未出现在面板行中")
            return
        }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        spin { table.selectedRow == index }
    }

    override func setUp() {
        super.setUp()
        panel.showWindow()
    }

    override func tearDown() {
        for task in FFTaskService.shared.tasks where ids.contains(task.id) {
            var settled = task
            settled.state = .cancelled
            FFTaskService.shared.upsert(settled)
        }
        FFTaskService.shared.removeFinished()
        ids.removeAll()
        super.tearDown()
    }

    /// R4-22：表格下方不得出现交替色的空行条纹。
    func testPanelHasNoPhantomRowStripes() throws {
        let table = try XCTUnwrap(panel.tableViewForTesting)
        XCTAssertFalse(table.usesAlternatingRowBackgroundColors,
                       "开启交替行底色后，空行区域照样画出条纹")
        XCTAssertTrue(table.gridStyleMask.contains(.solidHorizontalGridLineMask),
                      "取消条纹后要用横向分隔线保持可读性")
    }

    /// R4-23：取消按钮跟随选中行的可取消性，不再点击静默无效。
    func testCancelButtonFollowsSelection() throws {
        let running = addTask(title: "复制", state: .running, cancellable: true)
        let done = addTask(title: "整理", state: .finished)

        panel.tableViewForTesting?.deselectAll(nil)
        spin { (self.panel.tableViewForTesting?.selectedRow ?? 0) < 0 }
        XCTAssertFalse(panel.cancelButtonForTesting?.isEnabled ?? true, "未选中时取消按钮应禁用")

        selectRow(running)
        XCTAssertTrue(panel.cancelButtonForTesting?.isEnabled ?? false, "选中可取消任务后应可用")

        selectRow(done)
        XCTAssertFalse(panel.cancelButtonForTesting?.isEnabled ?? true, "已结束的任务不可取消")
    }

    /// R4-02 的另一半：扫描任务在面板里也要真的可取消。
    func testRunningScanRegistersCancelHandler() throws {
        let wc = DuplicateScanWindowController.shared
        wc.showWindow()
        defer { wc.window?.orderOut(nil) }

        let dir = URL(fileURLWithPath: "/tmp/ff_dedup_panel_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<30 {
            try Data([UInt8(i)]).write(to: dir.appendingPathComponent("f\(i).bin"))
        }

        wc.selectedURL = dir
        wc.perform(NSSelectorFromString("startScan"))
        XCTAssertTrue(wc.isScanning)
        defer { wc.perform(NSSelectorFromString("cancelScan")) }

        let taskID = try XCTUnwrap(wc.scanTaskIDForTesting)
        XCTAssertTrue(FFTaskService.shared.canCancel(taskID),
                      "扫描进行中，任务面板的「取消任务」应能取消它")
    }

    /// R4-01 残留：创建时间列不得使用英文 AM/PM。
    func testCreatedColumnUsesChineseDateTime() throws {
        let id = addTask(title: "复制", state: .running)
        guard let index = panel.rowTaskIDs.firstIndex(of: id),
              let table = panel.tableViewForTesting,
              let column = table.tableColumns.first(where: { $0.identifier.rawValue == "created" })
        else { return XCTFail("缺少 created 列") }

        let cell = panel.tableView(table, viewFor: column, row: index)
        let text = try XCTUnwrap((cell as? NSTableCellView)?.textField?.stringValue)
        XCTAssertFalse(text.contains("AM") || text.contains("PM"), "时间列仍是英文：\(text)")
        XCTAssertTrue(text.contains("月") && text.contains("日"), "时间列缺少中文日期：\(text)")
    }

    // MARK: - R4-24 定位到任务对象

    /// 任务面板只有「取消 / 清除」，用户看到一条扫描或复制记录后没法跳到它作用的东西上。
    /// 「定位」按钮的可用性与「取消任务」同一套规则：未选中、或任务本身没有可定位对象时禁用并说明原因。
    func testRevealButtonFollowsSelection() throws {
        let located = addTask(title: "重复文件扫描", state: .finished,
                              location: NSTemporaryDirectory())
        let blind = addTask(title: "批量整理", state: .finished)

        panel.tableViewForTesting?.deselectAll(nil)
        spin { (self.panel.tableViewForTesting?.selectedRow ?? 0) < 0 }
        XCTAssertFalse(panel.revealButtonForTesting?.isEnabled ?? true, "未选中任务时「定位」应禁用")

        selectRow(located)
        XCTAssertTrue(panel.revealButtonForTesting?.isEnabled ?? false, "选中带路径的任务后「定位」应可用")

        selectRow(blind)
        XCTAssertFalse(panel.revealButtonForTesting?.isEnabled ?? true, "任务没有可定位对象时「定位」应禁用")
        XCTAssertFalse((panel.revealButtonForTesting?.toolTip ?? "").isEmpty, "禁用原因要写进 tooltip，否则又是一次静默无效")

        let stale = addTask(title: "重复文件扫描", state: .finished,
                            location: (NSTemporaryDirectory() as NSString)
                                .appendingPathComponent("ff-r424-已删除-\(UUID().uuidString)"))
        selectRow(stale)
        XCTAssertFalse(panel.revealButtonForTesting?.isEnabled ?? true, "对象已从磁盘消失时不应给出可用的「定位」")
    }

    /// 定位落到主窗口的活动面板：目录直接进入，文件进入父目录并选中它。
    @MainActor
    func testRevealNavigatesActivePane() throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("ff-r424-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = (dir as NSString).appendingPathComponent("目标文件.txt")
        try Data("x".utf8).write(to: URL(fileURLWithPath: file))
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // 临时目录在 /var/folders 下，属于 rust-core 的系统保护区，默认筛选会把条目整片滤掉。
        let key = FFUserDefaultsKeys.showSystemFiles
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let vm = controller.leftPaneViewModel
        spin { !vm.isLoading }
        // 启动后还有一拍按「上次打开的位置」恢复活动面板；每次定位前重新钉住左栏，
        // 否则断言可能读到另一块面板（真实使用时定位跟着用户当前面板走，是对的）。
        func pinLeftPane() { controller.activePane = .left }

        pinLeftPane()
        controller.revealTaskLocation(path: dir)
        spin { vm.state.path == dir && !vm.isLoading }
        XCTAssertEqual(vm.state.path, dir, "定位到目录：活动面板要切到该目录")

        pinLeftPane()
        controller.revealTaskLocation(path: file)
        spin { vm.state.selectedFiles.map(\.path) == [file] }
        XCTAssertEqual(vm.state.path, dir, "定位到文件：进入的是它的父目录")
        XCTAssertEqual(vm.state.selectedFiles.map(\.path), [file],
                       "定位到文件：该文件必须处于选中态，否则只是换了个目录而已")

        // 复制/下载这类任务，对象往往在面板最后一次列表之后才出现：
        // 定位不能因为当前列表里没有它就静默失败，要重读再选中。
        let lateFile = (dir as NSString).appendingPathComponent("任务新建的文件.txt")
        try Data("y".utf8).write(to: URL(fileURLWithPath: lateFile))
        pinLeftPane()
        controller.revealTaskLocation(path: lateFile)
        spin { vm.state.selectedFiles.map(\.path) == [lateFile] }
        XCTAssertEqual(vm.state.selectedFiles.map(\.path), [lateFile],
                       "对象晚于当前列表出现时，定位仍要把它选中")
    }
}
