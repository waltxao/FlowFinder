import XCTest
@testable import FlowFinder

// MARK: - J3-10 批量整理（按日期/按类型，预览 + 撤销）

final class FFOrganizePlannerTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func entry(_ name: String, year: Int, month: Int, day: Int, directory: String = "/tmp/fforg") -> FileEntry {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        let date = calendar.date(from: comps)!
        return FileEntry(path: (directory as NSString).appendingPathComponent(name),
                         name: name, isDirectory: false, modificationDate: date)
    }

    // MARK: 日期分组

    func testDatePlanGroupsByYearMonth() {
        let entries = [
            entry("报告终稿.pdf", year: 2025, month: 11, day: 2),
            entry("照片 0231.jpg", year: 2025, month: 11, day: 2),
            entry("笔记.md", year: 2024, month: 12, day: 30),
        ]
        let plan = FFOrganizePlanner.plan(mode: .date(.ym), directory: "/tmp/fforg",
                                          entries: entries, calendar: calendar) { _ in false }
        XCTAssertEqual(plan.conflicts, [])
        XCTAssertEqual(Set(plan.moves.map { $0.targetDirectory }),
                       Set(["/tmp/fforg/2025/11", "/tmp/fforg/2024/12"]))
        XCTAssertEqual(plan.moves.count, 3)
        let pdf = try! XCTUnwrap(plan.moves.first { $0.fileName == "报告终稿.pdf" })
        XCTAssertEqual(pdf.targetPath, "/tmp/fforg/2025/11/报告终稿.pdf")
    }

    func testDatePlanFormatsChangeDepth() {
        let entries = [entry("a.txt", year: 2025, month: 3, day: 7)]
        let y = FFOrganizePlanner.plan(mode: .date(.year), directory: "/tmp/fforg",
                                       entries: entries, calendar: calendar) { _ in false }
        XCTAssertEqual(y.moves.first?.targetDirectory, "/tmp/fforg/2025")
        let ymd = FFOrganizePlanner.plan(mode: .date(.ymd), directory: "/tmp/fforg",
                                         entries: entries, calendar: calendar) { _ in false }
        XCTAssertEqual(ymd.moves.first?.targetDirectory, "/tmp/fforg/2025/03/07")
    }

    func testDatePlanZeroPadsComponents() {
        let entries = [entry("a.txt", year: 2025, month: 3, day: 7)]
        let plan = FFOrganizePlanner.plan(mode: .date(.ymd), directory: "/tmp/fforg",
                                          entries: entries, calendar: calendar) { _ in false }
        XCTAssertEqual(plan.moves.first?.targetDirectory, "/tmp/fforg/2025/03/07")
    }

    // MARK: 类别映射（中文 9 类）

    func testTypePlanMapsChineseCategories() {
        let cases: [(String, String)] = [
            ("photo.jpg", "图片"), ("doc.pdf", "文档"), ("sheet.xlsx", "表格"),
            ("deck.key", "演示"), ("song.mp3", "音频"), ("clip.mp4", "视频"),
            ("bundle.zip", "压缩包"), ("installer.dmg", "应用"), ("README", "其他"),
        ]
        for (name, folder) in cases {
            let e = FileEntry(path: "/tmp/fforg/\(name)", name: name, isDirectory: false)
            let plan = FFOrganizePlanner.plan(mode: .type, directory: "/tmp/fforg",
                                              entries: [e], calendar: calendar) { _ in false }
            XCTAssertEqual(plan.moves.first?.targetDirectory, "/tmp/fforg/\(folder)",
                           "\(name) 应归入 \(folder)")
        }
    }

    // MARK: 重名跳过

    func testConflictsSkippedAndReported() {
        let entries = [
            entry("a.txt", year: 2025, month: 11, day: 2),
            entry("b.txt", year: 2025, month: 11, day: 2),
        ]
        let plan = FFOrganizePlanner.plan(mode: .date(.ym), directory: "/tmp/fforg",
                                          entries: entries, calendar: calendar) { path in
            path == "/tmp/fforg/2025/11/a.txt"
        }
        XCTAssertEqual(plan.moves.map { $0.fileName }, ["b.txt"], "重名文件不进入移动计划")
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertEqual(plan.conflicts.first?.fileName, "a.txt")
        XCTAssertEqual(plan.conflicts.first?.targetDirectory, "/tmp/fforg/2025/11")
    }

    func testPlanEmptyWhenNoFiles() {
        let plan = FFOrganizePlanner.plan(mode: .type, directory: "/tmp/fforg",
                                          entries: [], calendar: calendar) { _ in false }
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertTrue(plan.conflicts.isEmpty)
    }

    // MARK: 候选收集（顶层可见文件）

    func testCandidatesTopLevelVisibleFilesOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff_org_cand_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("子文件夹"), withIntermediateDirectories: true)

        let candidates = try FFOrganizePlanner.candidates(inDirectory: dir.path)
        XCTAssertEqual(candidates.map { $0.name }, ["a.txt"], "只收集顶层可见文件，排除子文件夹与隐藏文件")
        XCTAssertFalse(candidates.first!.isDirectory)
    }

    func testCandidatesThrowsForMissingDirectory() {
        XCTAssertThrowsError(try FFOrganizePlanner.candidates(inDirectory: "/nonexistent/ff_org_missing"))
    }
}

// MARK: - 执行 + 撤销

final class FFOrganizeExecutionTests: XCTestCase {

    private var dir: URL!
    private var undoManager: UndoManager!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff_org_exec_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        undoManager = UndoManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeFile(_ name: String) throws {
        try "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testPerformOrganizeMovesFilesAndSingleUndoRestores() throws {
        try makeFile("a.txt")
        try makeFile("b.txt")
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.year = 2025; comps.month = 11; comps.day = 2; comps.hour = 12
        let date = calendar.date(from: comps)!
        let entries = try FFOrganizePlanner.candidates(inDirectory: dir.path)
            .map { e in FileEntry(path: e.path, name: e.name, isDirectory: false, modificationDate: date) }
        let plan = FFOrganizePlanner.plan(mode: .date(.ym), directory: dir.path,
                                          entries: entries, calendar: calendar) { _ in false }
        XCTAssertEqual(plan.moves.count, 2)

        let vm = PaneViewModel()
        vm.undoManager = undoManager

        let organizeExp = expectation(forNotification: .paneFileOperationChanged, object: nil) { _ in true }
        vm.performOrganize(plan: plan, directory: dir.path)
        wait(for: [organizeExp], timeout: 10.0)

        // 文件已移动到日期子目录
        for move in plan.moves {
            XCTAssertFalse(FileManager.default.fileExists(atPath: move.sourcePath),
                           "原路径应已不存在：\(move.sourcePath)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: move.targetPath),
                          "目标路径应存在：\(move.targetPath)")
        }

        // 整批一次撤销：全部回到原位置
        let undoExp = expectation(forNotification: .paneFileOperationChanged, object: nil) { _ in true }
        undoManager.undo()
        wait(for: [undoExp], timeout: 10.0)

        for move in plan.moves {
            XCTAssertTrue(FileManager.default.fileExists(atPath: move.sourcePath),
                          "撤销后应恢复原路径：\(move.sourcePath)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: move.targetPath),
                           "撤销后目标路径不应有文件：\(move.targetPath)")
        }
    }

    // MARK: 入口结构

    func testToolPageIncludesBatchOrganize() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        XCTAssertTrue(FFToolPageCatalog.includedToolIDs.contains("batch-organize"),
                      "工具页应包含「批量整理」行")
        let registryTool = FFToolRegistry.shared.registeredTools.first { $0.id == "batch-organize" }
        XCTAssertNotNil(registryTool, "注册表应注册 batch-organize 工具")
        XCTAssertEqual(registryTool?.group, .organize)
    }

    func testBatchOrganizeAvailabilityRequiresFolder() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        let tool = FFToolRegistry.shared.registeredTools.first { $0.id == "batch-organize" }!
        let empty = FFToolContext(activePane: .left, currentPath: "", selection: [], window: nil)
        let ready = FFToolContext(activePane: .left, currentPath: "/tmp", selection: [], window: nil)
        XCTAssertEqual(tool.availability(in: empty), .needsFolder)
        XCTAssertEqual(tool.availability(in: ready), .available)
    }

    func testContextMenuIncludesOrganizeCurrentDirectory() {
        final class FakeHost: NSObject, FFPaneViewHost {
            var viewModel: PaneViewModel? = nil
            var hostWindow: NSWindow? = nil
            var panelSide: PaneSide? = .left
            var doubleClickHandler: ((FileEntry) -> Void)? = nil
            var selectedEntries: [FileEntry] = []
            var clickedEntry: FileEntry? = nil
            func renameTextFieldForSelection() -> NSTextField? { nil }
            func selectClickedItemForRename() {}
            func revealSelection() {}
            var focusRestoreTarget: NSResponder? { nil }
            func reloadPaneData() {}
            var tagsSubmenu: NSMenu { NSMenu() }
        }
        let host = FakeHost()
        let controller = FFPaneActionsController(host: host)
        let menu = FFPaneMenuBuilder.buildMenu(for: controller, isLeft: true, tagsSubmenu: nil)
        let item = menu.items.first { $0.title == FFNaming.batchOrganizeBase }
        XCTAssertNotNil(item, "右键菜单应包含「\(FFNaming.batchOrganizeBase)」")
        XCTAssertEqual(item?.action, #selector(FFPaneActionsController.organizeCurrentDirectory(_:)))
        XCTAssertEqual(item?.target as? FFPaneActionsController, controller)
        XCTAssertEqual(menu.items.first { $0.action == #selector(FFPaneActionsController.generateAITags(_:)) }?.title,
                       "按类型自动打标签",
                       "右键菜单不应再出现 AI 字样")
    }
}
