import AppKit
import XCTest
@testable import FlowFinder

// MARK: - 工具页目录（R19-2 D-05/D-06）

final class FFToolPageCatalogTests: XCTestCase {

    private func context(path: String, selection: [FileEntry] = [],
                         hasTasks: Bool = false) -> FFToolContext {
        FFToolContext(activePane: .left, currentPath: path, selection: selection,
                      window: nil, hasTasks: hasTasks)
    }

    override func setUp() {
        super.setUp()
        FFToolRegistry.registerBuiltInsIfNeeded()
    }

    /// 只列用户批准的文件工具；设置与关于是应用命令，不属于工具簇
    func testCatalogListsApprovedToolsInOrder() {
        XCTAssertEqual(FFToolPageCatalog.entries(context: context(path: "/tmp")).map { $0.tool.id },
                       ["duplicate-scan", "batch-rename", "batch-organize", "task-center"])
    }

    /// 可用性按进入页面时的上下文计算
    func testCatalogAvailabilityFollowsContext() {
        let empty = FFToolPageCatalog.entries(context: context(path: ""))
        XCTAssertEqual(empty.first { $0.tool.id == "duplicate-scan" }?.availability, .needsFolder)
        XCTAssertEqual(empty.first { $0.tool.id == "batch-rename" }?.availability, .needsSelection)
        XCTAssertEqual(empty.first { $0.tool.id == "task-center" }?.availability, .disabled("暂无任务"))

        let withTasks = FFToolPageCatalog.entries(context: context(path: "", hasTasks: true))
        XCTAssertEqual(withTasks.first { $0.tool.id == "task-center" }?.availability, .available)

        let two = FFToolPageCatalog.entries(context: context(
            path: "/tmp",
            selection: [FileEntry(path: "/tmp/a", name: "a", isDirectory: false),
                        FileEntry(path: "/tmp/b", name: "b", isDirectory: false)]))
        XCTAssertEqual(two.first { $0.tool.id == "duplicate-scan" }?.availability, .available)
        XCTAssertEqual(two.first { $0.tool.id == "batch-rename" }?.availability, .available)
        XCTAssertEqual(two.first { $0.tool.id == "task-center" }?.availability, .disabled("暂无任务"))
    }

    /// 分组纵向列表：整理 → 任务（系统组已无工具，不再显示）
    func testCatalogGroupsInApprovedOrder() {
        let groups = FFToolPageCatalog.grouped(context: context(path: "/tmp"))
        XCTAssertEqual(groups.map { $0.group }, [.organize, .task])
        XCTAssertEqual(groups.map { $0.entries.count }, [3, 1])
    }
}
