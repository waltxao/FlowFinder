import AppKit
import XCTest
@testable import FlowFinder

// MARK: - 工具页目录（R19-2 D-05/D-06）

final class FFToolPageCatalogTests: XCTestCase {

    private func context(path: String, selection: [FileEntry] = []) -> FFToolContext {
        FFToolContext(activePane: .left, currentPath: path, selection: selection, window: nil)
    }

    override func setUp() {
        super.setUp()
        FFToolRegistry.registerBuiltInsIfNeeded()
    }

    /// 只列用户批准的 5 个工具，AI「即将推出」不进页面
    func testCatalogListsFiveApprovedToolsInOrder() {
        XCTAssertEqual(FFToolPageCatalog.entries(context: context(path: "/tmp")).map { $0.tool.id },
                       ["duplicate-scan", "batch-rename", "task-center", "settings", "about"])
    }

    /// 可用性按进入页面时的上下文计算
    func testCatalogAvailabilityFollowsContext() {
        let empty = FFToolPageCatalog.entries(context: context(path: ""))
        XCTAssertEqual(empty.first { $0.tool.id == "duplicate-scan" }?.availability, .needsFolder)
        XCTAssertEqual(empty.first { $0.tool.id == "batch-rename" }?.availability, .needsSelection)
        XCTAssertEqual(empty.first { $0.tool.id == "task-center" }?.availability, .available)

        let two = FFToolPageCatalog.entries(context: context(
            path: "/tmp",
            selection: [FileEntry(path: "/tmp/a", name: "a", isDirectory: false),
                        FileEntry(path: "/tmp/b", name: "b", isDirectory: false)]))
        XCTAssertEqual(two.first { $0.tool.id == "duplicate-scan" }?.availability, .available)
        XCTAssertEqual(two.first { $0.tool.id == "batch-rename" }?.availability, .available)
    }

    /// 分组纵向列表：整理 → 任务 → 系统
    func testCatalogGroupsInApprovedOrder() {
        let groups = FFToolPageCatalog.grouped(context: context(path: "/tmp"))
        XCTAssertEqual(groups.map { $0.group }, [.organize, .task, .system])
        XCTAssertEqual(groups.map { $0.entries.count }, [2, 1, 2])
    }
}

// MARK: - 工具页视图（R19-2 D-03/D-04）

final class SidebarToolPageViewTests: XCTestCase {

    private func context(path: String = "/Users/test/Documents/私密目录",
                         selection: [FileEntry] = [FileEntry(path: "/tmp/a", name: "a.txt",
                                                             isDirectory: false)]) -> FFToolContext {
        FFToolContext(activePane: .left, currentPath: path, selection: selection, window: nil)
    }

    /// D-04：页面头部不显示路径、选中数量或当前面板，那些归右键菜单
    func testHeaderOmitsPathSelectionAndPane() {
        let page = SidebarToolPageView(context: context())
        let header = page.headerTextsForTesting.joined(separator: " ")
        XCTAssertEqual(header, "工具 返回收藏")
    }

    /// 行集合必须与目录一致（含不可用行）
    func testRowsMatchCatalog() {
        let page = SidebarToolPageView(context: context())
        XCTAssertEqual(page.rowViewsForTesting().map { $0.tool.id },
                       FFToolPageCatalog.entries(context: context()).map { $0.tool.id })
    }

    /// 不可用行不可点击
    func testDisabledRowIgnoresClick() {
        let page = SidebarToolPageView(context: context(path: ""))
        let scan = try? XCTUnwrap(page.rowViewsForTesting().first { $0.tool.id == "duplicate-scan" })
        var fired = false
        scan?.onClick = { fired = true }
        scan?.mouseUp(with: NSEvent())
        XCTAssertFalse(fired, "needsFolder 的行不应响应点击")
    }
}

// MARK: - 品牌旁工具胶囊与侧栏页面切换（R19-2 D-02/D-03）

final class FFToolPageAccessibilityTests: XCTestCase {

    /// 批次 1 B1-10：工具胶囊必须是可读可点的按钮
    func testToolPillExposesButtonAccessibility() {
        let pill = FFPillButton(title: "工具", icon: .wrench, height: 24)
        XCTAssertEqual(pill.accessibilityRole(), .button)
        XCTAssertEqual(pill.accessibilityLabel(), "工具")
        XCTAssertTrue(pill.acceptsFirstResponder)
        pill.isSelected = true
        XCTAssertEqual(pill.accessibilityValue() as? String, "已打开")
    }

    /// 可用行可接键盘焦点，禁用行不抢焦点
    func testToolPageRowsAreFocusable() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        let empty = FFToolContext(activePane: .left, currentPath: "/tmp", selection: [], window: nil)
        let page = SidebarToolPageView(context: empty)
        let views = page.focusableViewsForTesting()
        XCTAssertEqual(views.count, 5)
        // 批量重命名在无选中时禁用，不应进入焦点链
        XCTAssertEqual(views.filter { $0.acceptsFirstResponder }.count, 4)

        let two = FFToolContext(activePane: .left, currentPath: "/tmp",
                                selection: [FileEntry(path: "/tmp/a", name: "a", isDirectory: false),
                                            FileEntry(path: "/tmp/b", name: "b", isDirectory: false)],
                                window: nil)
        let full = SidebarToolPageView(context: two)
        XCTAssertEqual(full.focusableViewsForTesting().filter { $0.acceptsFirstResponder }.count, 5)
    }
}

final class SidebarToolPageToggleTests: XCTestCase {

    private func makeSidebar(width: CGFloat = 240) -> SidebarView {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        sidebar.toolContextProvider = {
            FFToolContext(activePane: .left, currentPath: "/tmp", selection: [], window: nil)
        }
        sidebar.layoutSubtreeIfNeeded()
        return sidebar
    }

    func testPillTogglesToolPageAndRestoresFavorites() {
        let sidebar = makeSidebar()
        XCTAssertFalse(sidebar.isToolPageShown)
        XCTAssertTrue(sidebar.sidebarContentVisibleForTesting)

        sidebar.toolPillForTesting.onClick?()
        XCTAssertTrue(sidebar.isToolPageShown)
        XCTAssertFalse(sidebar.sidebarContentVisibleForTesting)
        XCTAssertTrue(sidebar.toolPillForTesting.isSelected)

        sidebar.toolPageForTesting?.backButtonForTesting.performClick(nil)
        XCTAssertFalse(sidebar.isToolPageShown)
        XCTAssertTrue(sidebar.sidebarContentVisibleForTesting)
        XCTAssertFalse(sidebar.toolPillForTesting.isSelected)
    }

    /// 再次点胶囊同样退出（D-03）
    func testSecondPillTapExitsToolPage() {
        let sidebar = makeSidebar()
        sidebar.toolPillForTesting.onClick?()
        sidebar.toolPillForTesting.onClick?()
        XCTAssertFalse(sidebar.isToolPageShown)
    }

    /// D-02 响应式：≥200pt 胶囊与名称同行；<200pt 移到版本号所在行
    func testPillFollowsBrandRowBySidebarWidth() {
        let wide = makeSidebar(width: 240)
        let wideBrand = wide.brandViewsForTesting
        XCTAssertEqual(wide.toolPillForTesting.frame.midY,
                       wideBrand.name.frame.midY, accuracy: 1.0)

        let narrow = makeSidebar(width: 180)
        let narrowBrand = narrow.brandViewsForTesting
        XCTAssertEqual(narrow.toolPillForTesting.frame.midY,
                       narrowBrand.version.frame.midY, accuracy: 1.0)
    }
}
